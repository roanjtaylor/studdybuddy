;;;; L0 — Utilities. The small operators the layers above wish Lisp had.
;;;; Every definition carries a one-line REPL example above it.

(in-package :studybuddy)

;;; ---- Paths -------------------------------------------------------------

;; Where the system lives on disk; set once at load time.
(defvar *root* (asdf:system-source-directory :studybuddy))

;; All data files live under here. Tests rebind it to a temp folder.
(defvar *data-dir* (merge-pathnames "data/" *root*))

;; (root-path "static/") → #P".../StudyBuddy/static/"
(defun root-path (rel) (merge-pathnames rel *root*))

;; (data-path "attempts.lisp") → #P".../StudyBuddy/data/attempts.lisp"
(defun data-path (rel) (merge-pathnames rel *data-dir*))

;;; ---- Macros ------------------------------------------------------------

;; (with-gensyms (a b) `(let ((,a 1) (,b 2)) ...)) — hygienic temporaries.
(defmacro with-gensyms (names &body body)
  `(let ,(mapcar (lambda (n) `(,n (gensym ,(string n)))) names)
     ,@body))

;;; ---- Strings and symbols ----------------------------------------------

;; (mkstr "a" 1 :b) → "a1B"
(defun mkstr (&rest args)
  (with-output-to-string (s) (dolist (a args) (princ a s))))

;; (symb "foo-" 'bar) → FOO-BAR
(defun symb (&rest args)
  (values (intern (string-upcase (apply #'mkstr args)))))

;; (str "a" 1 :b nil "c") → "a1Bc"   — nil contributes nothing.
(defun str (&rest args)
  (with-output-to-string (s) (dolist (a args) (when a (princ a s)))))

;; (join ", " '("a" "b")) → "a, b"
(defun join (sep list)
  (with-output-to-string (s)
    (loop for (x . rest) on list
          do (princ x s) (when rest (princ sep s)))))

;; (split #\, "a, b,c") → ("a" "b" "c")   — trimmed, empties dropped.
(defun split (char string)
  (loop with start = 0
        for pos = (position char string :start start)
        for piece = (trim (subseq string start pos))
        unless (string= piece "") collect piece
        while pos do (setf start (1+ pos))))

;; (trim "  a ") → "a"
(defun trim (s)
  (string-trim '(#\Space #\Tab #\Newline #\Return) s))

;; (strip-quotes "\"a\"") → "a"   — models sometimes wrap a sentence in quotes.
(defun strip-quotes (s)
  (if (stringp s) (string-trim "\"“”" s) s))

;; (blankp "  ") → T
(defun blankp (s) (or (null s) (string= (trim s) "")))

;; (prefix-p "ab" "abc") → T
(defun prefix-p (prefix s)
  (and (>= (length s) (length prefix))
       (string= prefix s :end2 (length prefix))))

;; (lines "a\r\nb") → ("a" "b")
(defun lines (s)
  (mapcar (lambda (l) (string-right-trim '(#\Return) l))
          (uiop:split-string s :separator '(#\Newline))))

;; (truncate-string "abcdef" 4) → "abc…"
(defun truncate-string (s max)
  (if (<= (length s) max) s (str (subseq s 0 (max 0 (1- max))) "…")))

;; (slugify "Fetch-decode-execute loop!") → "fetch-decode-execute-loop"
(defun slugify (s)
  (let ((out '()) (dash nil))
    (loop for c across (string-downcase s)
          do (cond ((alphanumericp c) (push c out) (setf dash nil))
                   ((not dash) (push #\- out) (setf dash t))))
    (string-trim "-" (coerce (nreverse out) 'string))))

;; (kw "suggested-level") → :SUGGESTED-LEVEL
(defun kw (name) (values (intern (string-upcase name) :keyword)))

;; (lower :suggested-level) → "suggested-level"
(defun lower (sym) (string-downcase (string sym)))

;;; ---- Time --------------------------------------------------------------

;; (now-iso) → "2026-10-28T13:54:00"
(defun now-iso ()
  (multiple-value-bind (sec min hour day mon year) (get-decoded-time)
    (format nil "~4,'0d-~2,'0d-~2,'0dT~2,'0d:~2,'0d:~2,'0d" year mon day hour min sec)))

;;; ---- Plists ------------------------------------------------------------

;; (getf* '(:a nil) :a 3) → 3   — getf with a default that also covers nil.
(defun getf* (plist key &optional default)
  (or (getf plist key) default))

;; (plist-update '(:a 1 :b 2) :b 3) → (:A 1 :B 3)   — non-destructive.
(defun plist-update (plist key value)
  (let ((copy (copy-list plist)))
    (setf (getf copy key) value)
    copy))

;;; ---- Files: the whole persistence layer -------------------------------

;; (read-file-forms #P"data/levels.lisp") → list of forms, or NIL if absent.
(defun read-file-forms (path)
  (when (probe-file path)
    (with-open-file (in path :external-format :utf-8)
      (with-standard-io-syntax
        (let ((*package* (find-package :studybuddy))
              (*read-eval* nil))
          (loop for form = (read in nil :eof)
                until (eq form :eof) collect form))))))

;; (write-file-forms #P"data/levels.lisp" '((:a 1) (:b 2))) — one form per line, readably.
(defun write-file-forms (path forms)
  (ensure-directories-exist path)
  (with-open-file (out path :direction :output :if-exists :supersede
                            :external-format :utf-8)
    (with-standard-io-syntax
      (let ((*package* (find-package :studybuddy))
            (*print-readably* nil)   ; else base-strings print as #A(...) forms
            (*print-pretty* t)
            (*print-right-margin* 100))
        (dolist (f forms) (prin1 f out) (terpri out)))))
  path)

;; (append-file-form #P"data/attempts.lisp" '(:id 1)) — append one form, readably.
(defun append-file-form (path form)
  (ensure-directories-exist path)
  (with-open-file (out path :direction :output :if-exists :append
                            :if-does-not-exist :create :external-format :utf-8)
    (with-standard-io-syntax
      (let ((*package* (find-package :studybuddy))
            (*print-readably* nil)   ; else base-strings print as #A(...) forms
            (*print-pretty* t)
            (*print-right-margin* 100))
        (prin1 form out) (terpri out))))
  path)
