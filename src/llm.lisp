;;;; L4 — Model. One function talks to the relay; a macro defines prompts as data;
;;;; structured answers come back as plists so the UI never sees free prose.
;;;;
;;;; Calls go through the ClaudeSubscription relay (projects/hf-space), which runs
;;;; the Claude Agent SDK on the owner's subscription rather than metered API
;;;; credit. POST /api/agent, SSE back; with `outputFormat` the validated object
;;;; arrives in a `structured` event.
;;;;
;;;;   (defprompt check-explanation :system "…" :schema (:object (:right (:array :string)) …))
;;;;   (ask-structured 'check-explanation "Idea: … Learner wrote: …")  → plist
;;;;   (ask 'some-prompt "…")                                          → string
;;;;   (ask-with-search 'hunt-sources "…")                             → plist

(in-package :studybuddy)

(defvar *server-url* "https://roanjtaylor-claudesubscription.hf.space"
  "The relay. STUDYBUDDY_SERVER_URL overrides at start.")
(defvar *app-secret* nil
  "Sent as x-app-secret. STUDYBUDDY_APP_SECRET; read at start, never from a file.")
(defvar *model* "claude-opus-4-8"
  "Any model the subscription can use; the relay's /api/models lists them live.")
(defvar *effort* nil
  "nil = reasoning off; or \"low\" \"medium\" \"high\" — passed to the relay.")
(defvar *llm-timeout* 1800 "Seconds to wait for one answer. Web-searched calls are slow.")
(defvar *prompts* (make-hash-table) "name → (:system … :schema …)")
(defvar *last-response* nil "Raw SSE events of the last call, for debugging at the REPL.")

(defun configure-llm ()
  (let ((url (uiop:getenv "STUDYBUDDY_SERVER_URL"))
        (secret (uiop:getenv "STUDYBUDDY_APP_SECRET")))
    (when url (setf *server-url* (string-right-trim "/" url)))
    (when secret (setf *app-secret* secret))))

(define-condition llm-error (error)
  ((message :initarg :message :reader llm-error-message)
   (body :initarg :body :initform nil :reader llm-error-body))
  (:report (lambda (c s)
             (format s "LLM call failed: ~a~@[~%~a~]" (llm-error-message c) (llm-error-body c)))))

(defun llm-fail (message &optional body)
  (error 'llm-error :message message :body body))

;;; ---- Prompts as data ---------------------------------------------------

(defmacro defprompt (name &key system schema)
  `(progn (setf (gethash ',name *prompts*) (list :system ,system :schema ',schema))
          ',name))

(defun prompt (name)
  (or (gethash name *prompts*) (error "No prompt named ~s" name)))

;;; ---- JSON ↔ Lisp -------------------------------------------------------

;; (obj "a" 1 "b" 2) → equal hash-table, which jzon writes as a JSON object.
(defun obj (&rest kvs)
  (let ((h (make-hash-table :test #'equal)))
    (loop for (k v) on kvs by #'cddr do (setf (gethash k h) v))
    h))

;; Convert a parsed JSON value to Lisp data: objects → plists with keyword keys,
;; arrays → lists, null → nil.
(defun json->lisp (x)
  (cond ((hash-table-p x)
         (let ((plist '()))
           (maphash (lambda (k v) (push (json->lisp v) plist) (push (kw k) plist)) x)
           plist))
        ((vectorp x) (if (stringp x) x (map 'list #'json->lisp x)))
        ((eq x 'null) nil)
        (t x)))

;;; ---- Schema ------------------------------------------------------------

;; The small s-expression schema language:
;;   :string :integer :number :boolean
;;   (:array TYPE)
;;   (:object (KEY TYPE [DESCRIPTION]) …)   — every key required
;;   (:enum "a" "b")
;; (schema->json '(:object (:n :integer))) → hash-table ready for jzon.
(defun schema->json (s)
  (cond ((member s '(:string :integer :number :boolean))
         (obj "type" (lower s)))
        ((and (consp s) (eq (car s) :array))
         (obj "type" "array" "items" (schema->json (second s))))
        ((and (consp s) (eq (car s) :enum))
         (obj "type" "string" "enum" (coerce (cdr s) 'vector)))
        ((and (consp s) (eq (car s) :object))
         (let ((props (obj)) (required '()))
           (dolist (p (cdr s))
             (destructuring-bind (key type &optional description) p
               (let ((json (schema->json type)) (name (lower key)))
                 (when description (setf (gethash "description" json) description))
                 (setf (gethash name props) json)
                 (push name required))))
           (obj "type" "object"
                "properties" props
                "required" (coerce (nreverse required) 'vector)
                "additionalProperties" nil)))
        (t (error "Bad schema form: ~s" s))))

;;; ---- SSE ---------------------------------------------------------------

;; (parse-sse "event: a\ndata: {}\n\n") → (("a" . "{}"))
(defun parse-sse (text)
  (let ((events '()) (event nil) (data '()))
    (flet ((flush ()
             (when (or event data)
               (push (cons event (join #\Newline (nreverse data))) events))
             (setf event nil data '())))
      (dolist (line (lines text))
        (cond ((string= line "") (flush))
              ((prefix-p "event:" line) (setf event (trim (subseq line 6))))
              ((prefix-p "data:" line) (push (trim (subseq line 5)) data))))
      (flush))
    (nreverse events)))

(defun sse-events (events name)
  (loop for (e . d) in events when (equal e name) collect (jzon:parse d)))

;;; ---- The one request ---------------------------------------------------

(defun relay-headers ()
  (append '(("content-type" . "application/json"))
          (when *app-secret* `(("x-app-secret" . ,*app-secret*)))))

;; One POST to the relay. Returns the parsed SSE events; signals llm-error with the
;; HTTP body attached on any failure.
(defun relay-request (user-text &key system schema search (max-turns 10))
  (let ((body (obj "messages" (vector (obj "role" "user" "content" user-text))
                   "model" *model*
                   "maxTurns" max-turns
                   "builtinTools" (if search (vector "WebSearch" "WebFetch") (vector))
                   "thinkingDisplay" "omitted")))
    (when system (setf (gethash "systemPrompt" body) system))
    (when *effort* (setf (gethash "effort" body) *effort*))
    (when schema
      (setf (gethash "outputFormat" body)
            (obj "type" "json_schema" "schema" (schema->json schema))))
    (let ((text (handler-case
                    (dex:post (str *server-url* "/api/agent")
                              :headers (relay-headers)
                              :content (jzon:stringify body)
                              :connect-timeout 60
                              :read-timeout *llm-timeout*)
                  (dex:http-request-failed (e)
                    (llm-fail (format nil "HTTP ~a from ~a" (dex:response-status e) *server-url*)
                              (dex:response-body e)))
                  (error (e) (llm-fail (princ-to-string e))))))
      (let ((events (parse-sse text)))
        (setf *last-response* events)
        (let ((err (first (sse-events events "error"))))
          (when err (llm-fail (gethash "error" err))))
        events))))

;;; ---- The three asks ----------------------------------------------------

;; Plain call, returns the model's text.
(defun ask (name user-text &key search)
  (let* ((p (prompt name))
         (events (relay-request user-text :system (getf p :system) :search search
                                          :max-turns (if search 30 10))))
    (join "" (mapcar (lambda (d) (gethash "text" d)) (sse-events events "delta")))))

;; Structured call: the prompt's schema is enforced by the engine and the validated
;; object comes back as a plist. No tool output → error, never prose parsing.
(defun ask-structured (name user-text &key search)
  (let* ((p (prompt name))
         (schema (or (getf p :schema) (error "Prompt ~s has no schema" name)))
         (events (relay-request user-text :system (getf p :system) :schema schema
                                          :search search
                                          :max-turns (if search 30 10)))
         (structured (first (sse-events events "structured"))))
    (unless structured
      (llm-fail "The model returned no structured output"
                (join "" (mapcar (lambda (d) (gethash "text" d)) (sse-events events "delta")))))
    (json->lisp (gethash "output" structured))))

;; Same, with web search on — for source hunting and map seeding.
(defun ask-with-search (name user-text)
  (ask-structured name user-text :search t))
