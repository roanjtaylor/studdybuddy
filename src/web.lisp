;;;; L2 — Web. Wrap Hunchentoot so a page is one form.
;;;;
;;;;   (defpage node-page "/node/:id" (id) …)        ; GET, :id bound from the path
;;;;   (defaction rate "/action/rate" (node-id level) …)  ; POST, params from the form
;;;;
;;;; Routes live in a table keyed by name, so re-evaluating a defpage form replaces
;;;; the route in the running server. The route's closure calls the page function
;;;; by name, so even the body alone can be redefined live.

(in-package :studybuddy)

(defvar *server* nil)
(defvar *port* 8080)
(defvar *routes* (make-hash-table) "name → route")
(defvar *map* nil "The current field (see nodes.lisp); declared here so the dispatcher can rebind it.")
;; defparameter, not defvar: a reload must replace the nav in a live image.
(defparameter *nav* '(("Fields" . "/fields"))
  "Top-bar links, (label . href).")
(defvar *ask-href* "/fields"
  "Where the nav's Ask button goes. Pages with an ask box bind it to \"#ask\".")
(defvar *nav-extra* nil "Already-rendered HTML for the right of the nav (a field's subtitle and view buttons).")
(defvar *page-class* nil "Class on <body>; \"field\" makes the content fill the window.")
(defvar *crumbs* '()
  "The directory path of the current page, ((label . href) …), shown under the nav.")

(defstruct route name method segments fn)

;;; ---- Routing -----------------------------------------------------------

;; (path-segments "/node/:id") → ("node" (:param "id"))
(defun path-segments (path)
  (mapcar (lambda (s) (if (prefix-p ":" s) (list :param (subseq s 1)) s))
          (remove "" (uiop:split-string path :separator "/") :test #'string=)))

;; (match-path '("node" (:param "id")) "/node/ram") → T, (("id" . "ram"))
(defun match-path (segments path)
  (let ((parts (remove "" (uiop:split-string path :separator "/") :test #'string=)))
    (when (= (length parts) (length segments))
      (let ((bindings '()))
        (loop for seg in segments for part in parts
              do (cond ((consp seg) (push (cons (second seg) part) bindings))
                       ((string/= seg part) (return-from match-path nil))))
        (values t bindings)))))

;; Keyed by name so a re-evaluated defpage replaces itself; a route renamed onto
;; the same method and path evicts the old one, so a live image never keeps a
;; dead handler for a path.
(defun add-route (name method path fn)
  (let ((segments (path-segments path)))
    (loop for r being the hash-values of *routes* using (hash-key k)
          when (and (not (eq k name)) (eq (route-method r) method) (equal (route-segments r) segments))
            do (remhash k *routes*))
    (setf (gethash name *routes*)
          (make-route :name name :method method :segments segments :fn fn))))

;; A Hunchentoot dispatcher: request → handler closure, or NIL to fall through.
(defun route-dispatcher (request)
  (let ((path (ht:script-name request))
        (method (ht:request-method request)))
    ;; Every matching route is a candidate; the one with the fewest :param segments
    ;; wins, so "/fields" beats "/:name" and "/:name/:group" beats nothing by accident.
    (let ((best nil) (best-bindings nil) (best-params most-positive-fixnum))
      (loop for r being the hash-values of *routes*
            do (multiple-value-bind (ok bindings) (match-path (route-segments r) path)
                 (when (and ok (eq method (route-method r)))
                   (let ((params (count-if #'consp (route-segments r))))
                     (when (< params best-params)
                       (setf best r best-bindings bindings best-params params))))))
      (when best
        ;; *map* and the page-shell state are rebound per request so two tabs never clash.
        (let ((fn (route-fn best)) (bindings best-bindings))
          (lambda () (let ((*map* *map*) (*ask-href* *ask-href*) (*crumbs* *crumbs*))
                       (funcall fn bindings))))))))

;; Path bindings win; then query/form parameters of the same name.
(defun route-param (bindings name)
  (or (cdr (assoc name bindings :test #'string=))
      (ht:parameter name)))

(defun param-call-form (name params bindings)
  `(,name ,@(loop for p in params
                  append (list (kw p) `(route-param ,bindings ,(lower p))))))

(defmacro defpage (name path (&rest params) &body body)
  (with-gensyms (b)
    `(progn
       (defun ,name (&key ,@params) (declare (ignorable ,@params)) ,@body)
       (add-route ',name :get ,path (lambda (,b) ,(param-call-form name params b)))
       ',name)))

(defmacro defaction (name path (&rest params) &body body)
  (with-gensyms (b)
    `(progn
       (defun ,name (&key ,@params) (declare (ignorable ,@params)) ,@body)
       (add-route ',name :post ,path (lambda (,b) ,(param-call-form name params b)))
       ',name)))

;;; ---- Request helpers ---------------------------------------------------

(defun param (name) (ht:parameter name))

(defun redirect (url) (ht:redirect url))

(defun not-found (&optional (what "page"))
  (setf (ht:return-code*) ht:+http-not-found+)
  (layout "Not found" (html (:h1 "No such " what) (:p (:a :href "/fields" "Back to your fields")))))

;;; ---- The page shell ----------------------------------------------------

;; (static-url "style.css") → "/static/style.css?v=3969000000" — the file's write time,
;; so a browser never keeps a stale stylesheet after an edit.
(defun static-url (name)
  (let ((path (root-path (str "static/" name))))
    (str "/static/" name "?v=" (or (ignore-errors (file-write-date path)) 0))))

;; (layout "Title" part…) — parts are already-rendered HTML strings.
(defun layout (title &rest parts)
  (html (:raw "<!doctype html>")
    (:html :lang "en"
      (:head (:meta :charset "utf-8")
             (:meta :name "viewport" :content "width=device-width, initial-scale=1")
             (:title title " · StudyBuddy")
             (:link :rel "stylesheet" :href (static-url "style.css")))
      (:body :class *page-class*
        (:nav :class "top"
          (:a :class "brand" :href "/" "StudyBuddy")
          (dolist (link *nav*)
            ;; The "/" is always laid out, just invisible off a crumb path, so links never shift.
            (html (:span :class (if *crumbs* "sep" "sep hidden") "/")
                  (:a :class (and *crumbs* "current") :href (cdr link) (car link))))
          (loop for (label . href) in (cdr *crumbs*)
                do (html (:span :class "sep" "/")
                         (if href (html (:a :href href label)) (html (:span :class "current" label)))))
          (when *nav-extra* (html (:raw *nav-extra*))))
        (:main (dolist (p parts) (html (:raw p))))
        (:script :src (static-url "map.js"))))))

;;; ---- Server ------------------------------------------------------------

(defun open-browser (url)
  #+win32 (sb-ext:run-program "cmd" (list "/c" "start" "" url) :search t :wait nil)
  #+darwin (sb-ext:run-program "open" (list url) :search t :wait nil)
  #-(or win32 darwin) (sb-ext:run-program "xdg-open" (list url) :search t :wait nil))

(defun stop-server ()
  (when *server*
    (ignore-errors (ht:stop *server*))
    (setf *server* nil)))

;; Idempotent: calling it twice restarts cleanly.
(defun start-server (&key (port *port*) (open t))
  (stop-server)
  (setf *port* port
        ht:*show-lisp-errors-p* t
        ht:*default-content-type* "text/html; charset=utf-8"
        ht:*hunchentoot-default-external-format* (flex:make-external-format :utf-8)
        ;; Static first: field names are top-level paths, so "/static/…" must never
        ;; reach the field routes.
        ht:*dispatch-table*
        (list (ht:create-folder-dispatcher-and-handler "/static/" (root-path "static/"))
              'route-dispatcher))
  (setf *server* (ht:start (make-instance 'ht:easy-acceptor
                                          :port port :address "127.0.0.1"
                                          :document-root nil
                                          :access-log-destination nil)))
  (when open (open-browser (format nil "http://localhost:~a/" port)))
  *server*)
