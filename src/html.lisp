;;;; L1 — HTML as s-expressions. One macro and you never type an angle bracket.
;;;;
;;;;   (html (:div :class "node" (:h1 title) (:p "a<b")))
;;;;   → "<div class=\"node\"><h1>…</h1><p>a&lt;b</p></div>"
;;;;
;;;; Rules: a form (:tag attrs… children…) is an element; keyword/value pairs
;;;; before the first non-keyword are attributes (nil omits, t is bare); literal
;;;; strings are escaped at macro time; any other form is evaluated and its result
;;;; escaped (nil prints nothing); (:raw x) inserts x unescaped. Output goes to
;;;; *html-out*, a string stream bound by the outermost call, so an inner (html …)
;;;; — inside dolist, a component, anywhere — writes straight into the same page.

(in-package :studybuddy)

(defvar *html-out* nil "The stream the current page is being written to.")

(defparameter *void-elements* '(:br :img :input :meta :link :hr :source))

;; (escape "a<b & \"c\"") → "a&lt;b &amp; &quot;c&quot;"
(defun escape (s)
  (with-output-to-string (out)
    (loop for c across s
          do (case c
               (#\& (write-string "&amp;" out))
               (#\< (write-string "&lt;" out))
               (#\> (write-string "&gt;" out))
               (#\" (write-string "&quot;" out))
               (t (write-char c out))))))

;; Runtime helpers the macro expands into.
(defun emit (x)
  (when x (write-string (escape (if (stringp x) x (princ-to-string x))) *html-out*)))

(defun emit-raw (x)
  (when x (write-string (if (stringp x) x (princ-to-string x)) *html-out*)))

(defun emit-attr (name value)
  (cond ((null value))
        ((eq value t) (format *html-out* " ~a" name))
        (t (format *html-out* " ~a=\"~a\"" name
                   (escape (if (stringp value) value (princ-to-string value)))))))

;; Macro-time: split (:tag :a 1 :b 2 child…) into attrs and children.
(defun split-attrs (forms)
  (loop while (and forms (keywordp (car forms)) (cdr forms))
        collect (list (pop forms) (pop forms)) into attrs
        finally (return (values attrs forms))))

(defun html-form (form)
  (cond ((stringp form) `(write-string ,(escape form) *html-out*))
        ((and (consp form) (eq (car form) :raw))
         `(progn ,@(mapcar (lambda (f) `(emit-raw ,f)) (cdr form))))
        ((and (consp form) (keywordp (car form)))
         (let ((tag (lower (car form))))
           (multiple-value-bind (attrs children) (split-attrs (cdr form))
             `(progn
                (write-string ,(str "<" tag) *html-out*)
                ,@(mapcar (lambda (a) `(emit-attr ,(lower (first a)) ,(second a))) attrs)
                (write-char #\> *html-out*)
                ,@(if (member (car form) *void-elements*)
                      '()
                      `(,@(mapcar #'html-form children)
                        (write-string ,(str "</" tag ">") *html-out*)))))))
        (t `(emit ,form))))

(defmacro html (&body forms)
  (with-gensyms (body)
    `(flet ((,body () ,@(mapcar #'html-form forms) nil))
       (if *html-out*
           (,body)
           (with-output-to-string (*html-out*) (,body))))))

;; (defcomponent button (text &key href) (html (:a :class "btn" :href href text)))
;; Called inside html it splices its output; called alone it returns a string.
(defmacro defcomponent (name args &body body)
  `(defun ,name ,args ,@body))
