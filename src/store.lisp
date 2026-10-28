;;;; L3 — Store. Persistence is Lisp's reader and printer.
;;;;
;;;;   (defstore attempt (:file "attempts.lisp" :key :id :append t))
;;;;   (defstore level   (:file "levels.lisp"   :key :ref))
;;;;
;;;; defines *attempts* / (attempts), load-attempts, save-attempts, find-attempt,
;;;; put-attempt!. The in-memory list is the truth while the image runs; the file
;;;; is written on every put!. Files are relative to *data-dir* and are plain lists
;;;; of plists you can read and edit by hand.

(in-package :studybuddy)

(defvar *stores* '() "Loader functions registered by defstore; start calls them all.")

(defmacro defstore (name (&key file key append))
  (let ((var    (symb "*" name "S*"))
        (all    (symb name "S"))
        (loader (symb "LOAD-" name "S"))
        (saver  (symb "SAVE-" name "S"))
        (finder (symb "FIND-" name))
        (putter (symb "PUT-" name "!")))
    `(progn
       (defvar ,var '())
       (defun ,all () ,var)
       (defun ,loader () (setf ,var (read-file-forms (data-path ,file))))
       (defun ,saver () (write-file-forms (data-path ,file) ,var))
       (defun ,finder (k)
         (find k ,var :key (lambda (p) (getf p ,key)) :test #'equal))
       (defun ,putter (plist)
         ,(if append
              ;; Append-only: oldest first in memory and in the file; one form is
              ;; appended to the file rather than rewriting it.
              `(progn (setf ,var (append ,var (list plist)))
                      (append-file-form (data-path ,file) plist))
              `(progn (setf ,var (append (remove (getf plist ,key) ,var
                                                 :key (lambda (p) (getf p ,key))
                                                 :test #'equal)
                                         (list plist)))
                      (,saver)))
         plist)
       (pushnew ',loader *stores*)
       ',name)))

(defun load-all-stores ()
  (dolist (loader (reverse *stores*)) (funcall loader)))
