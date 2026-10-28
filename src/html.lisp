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

;;; ---- Markdown, the small subset the model and the learner write ----------
;;; Paragraphs, # ## ### headings, - and 1. lists, ``` fences, **bold**, *em*, `code`.
;;; Everything is escaped first, so model output can never inject markup.

;; (wrap-pairs "a **b** c" "**" "<b>" "</b>") → "a <b>b</b> c"   — unpaired delimiters stay.
(defun wrap-pairs (s delim open close)
  (let ((n (length delim)) (start 0))
    (with-output-to-string (out)
      (loop
        (let* ((a (search delim s :start2 start))
               (b (and a (search delim s :start2 (+ a n)))))
          (unless b (write-string s out :start start) (return))
          (write-string s out :start start :end a)
          (write-string open out)
          (write-string s out :start (+ a n) :end b)
          (write-string close out)
          (setf start (+ b n)))))))

(defun md-inline (s)
  (let ((e (escape s)))
    (setf e (wrap-pairs e "`" "<code>" "</code>"))
    (setf e (wrap-pairs e "**" "<strong>" "</strong>"))
    (wrap-pairs e "*" "<em>" "</em>")))

;; "3. text" → "text", else NIL.
(defun ordered-item (line)
  (let ((dot (position #\. line)))
    (when (and dot (> dot 0) (every #'digit-char-p (subseq line 0 dot))
               (< (1+ dot) (length line)) (char= (char line (1+ dot)) #\Space))
      (subseq line (+ dot 2)))))

(defun md-line-kind (line)
  (let ((tl (trim line)))
    (cond ((string= tl "") '(:blank))
          ((prefix-p "```" tl) '(:fence))
          ((prefix-p "### " tl) (list :h 4 (subseq tl 4)))
          ((prefix-p "## " tl) (list :h 3 (subseq tl 3)))
          ((prefix-p "# " tl) (list :h 2 (subseq tl 2)))
          ((or (prefix-p "- " tl) (prefix-p "* " tl)) (list :li "ul" (subseq tl 2)))
          ((ordered-item tl) (list :li "ol" (ordered-item tl)))
          (t (list :text tl)))))

;; (markdown->html "# Hi\n\n- a\n- b") → "<h2>Hi</h2>…<ul><li>a</li><li>b</li></ul>"
(defun markdown->html (text)
  (let ((para '()) (list nil) (fence nil) (code '()))
    (with-output-to-string (out)
      (labels ((end-para () (when para
                              (format out "<p>~a</p>~%" (md-inline (join " " (nreverse para))))
                              (setf para '())))
               (end-list () (when list (format out "</~a>~%" list) (setf list nil)))
               (start-list (tag) (unless (equal list tag) (end-list) (format out "<~a>~%" tag) (setf list tag)))
               (end-fence () (format out "<pre>~a</pre>~%" (escape (join (string #\Newline) (nreverse code))))
                             (setf code '() fence nil)))
        (dolist (line (lines (or text "")))
          (if fence
              (if (prefix-p "```" (trim line)) (end-fence) (push line code))
              (destructuring-bind (kind &rest args) (md-line-kind line)
                (ecase kind
                  (:blank (end-para) (end-list))
                  (:fence (end-para) (end-list) (setf fence t))
                  (:h (end-para) (end-list)
                      (format out "<h~a>~a</h~a>~%" (first args) (md-inline (second args)) (first args)))
                  (:li (end-para) (start-list (first args))
                       (format out "<li>~a</li>~%" (md-inline (second args))))
                  (:text (when list (end-list)) (push (first args) para))))))
        (when fence (end-fence))
        (end-para)
        (end-list)))))
