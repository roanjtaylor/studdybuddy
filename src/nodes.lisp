;;;; L5a — Data. Field (a map), Node, Level, Attempt, Message, View.
;;;;
;;;; A field is one file under data/maps/, one form per line:
;;;;   (:map :id "computers" :title "Computers" :compression "…")
;;;;   (:group :id "switches" :compression "A switch can control another switch.")
;;;;   (:node :id "flip-flop" :title "…" :compression "…" :why "…" :notes "…"
;;;;          :group "switches" :prereqs ("logic-gates") :era 1918)
;;;; The map is the shared object the learner and the model both edit. Everything
;;;; the learner does (levels, attempts, conversation) lives in its own store keyed
;;;; by :ref = "map/node-id" so the map file stays a clean description of the field.

(in-package :studybuddy)

(defstore attempt (:file "attempts.lisp" :key :id :append t))
(defstore message (:file "messages.lisp" :key :id :append t))
(defstore level   (:file "levels.lisp"   :key :ref))
(defstore setting (:file "settings.lisp" :key :key))

(defvar *map* nil "The current field: (:id :title :compression :groups :nodes). Bound per request.")
(defvar *default-map* "computers")

(defparameter *level-names* #("not yet" "shaky" "can explain" "can teach"))

;;; ---- Fields (maps) ----------------------------------------------------

(defun map-file (name) (data-path (str "maps/" name ".lisp")))

(defun tagged (forms tag)
  (loop for f in forms when (eq (car f) tag) collect (cdr f)))

;; (read-map "computers") → the map plist, or NIL when there is no such file.
(defun read-map (name)
  (let ((forms (read-file-forms (map-file name))))
    (when forms
      (let ((head (first (tagged forms :map))))
        (list :id name
              :title (getf* head :title name)
              :compression (getf head :compression)
              :groups (tagged forms :group)
              :nodes (mapcar #'normalise-node (tagged forms :node)))))))

;; (load-map "computers") → the map plist, now current.
(defun load-map (name)
  (setf *map* (or (read-map name) (error "No map file ~a" (map-file name)))))

;; (select-map "computers") → the map, or NIL. Pages call this with the URL's name.
(defun select-map (name)
  (and (map-exists-p name) (load-map name)))

(defun ensure-map () (or *map* (load-map *default-map*)))

(defun map-id () (getf (ensure-map) :id))
(defun map-title () (getf (ensure-map) :title))
(defun map-nodes () (getf (ensure-map) :nodes))
(defun map-groups () (getf (ensure-map) :groups))

;; (list-maps) → ("computers" …) from data/maps/*.lisp
(defun list-maps ()
  (sort (mapcar #'pathname-name (directory (data-path "maps/*.lisp"))) #'string<))

(defun map-exists-p (name) (probe-file (map-file name)))

(defun map-forms (map)
  (append (list (list :map :id (getf map :id) :title (getf map :title) :compression (getf map :compression)))
          (mapcar (lambda (g) (cons :group g)) (getf map :groups))
          (mapcar (lambda (n) (cons :node n)) (getf map :nodes))))

;; Write a whole new map file (seed). Refuses to overwrite.
(defun write-map! (id title compression groups nodes)
  (when (map-exists-p id) (error "Map ~a already exists" id))
  (write-file-forms (map-file id)
                    (map-forms (list :id id :title title :compression compression
                                     :groups groups :nodes nodes)))
  id)

;; Mirror the current map to its file after any edit.
(defun save-map! ()
  (write-file-forms (map-file (map-id)) (map-forms *map*))
  *map*)

;; (check-map) → list of (node-id . missing-prereq-id); NIL when every id resolves.
(defun check-map ()
  (loop for n in (map-nodes)
        append (loop for p in (getf n :prereqs)
                     unless (find-node p) collect (cons (getf n :id) p))))

;; How many ideas, and how many explained (level ≥ 2), for a field not yet loaded.
(defun field-summary (name)
  (let* ((m (read-map name)) (nodes (getf m :nodes)))
    (list :id name :title (getf m :title) :compression (getf m :compression)
          :ideas (length nodes)
          :explained (count-if (lambda (n) (>= (node-level (getf n :id) name) 2)) nodes))))

;;; ---- Nodes -------------------------------------------------------------

(defun find-node (id)
  (find id (map-nodes) :key (lambda (n) (getf n :id)) :test #'equal))

(defun find-group (id)
  (find id (map-groups) :key (lambda (g) (getf g :id)) :test #'equal))

(defun group-nodes (group-id)
  (remove group-id (map-nodes) :key (lambda (n) (getf n :group)) :test-not #'equal))

;; Nodes that list ID as a prerequisite.
(defun dependents (id)
  (remove-if-not (lambda (n) (member id (getf n :prereqs) :test #'equal)) (map-nodes)))

;; The node, what it builds on, and what builds on it — in map order.
(defun neighbourhood (id)
  (let ((n (find-node id)))
    (remove-if-not (lambda (m) (or (eq m n)
                                   (member (getf m :id) (getf n :prereqs) :test #'equal)
                                   (member id (getf m :prereqs) :test #'equal)))
                   (map-nodes))))

;; Prerequisite depth within the node's own group: 0 with no same-group prereqs.
(defun node-depth (id &optional seen)
  (let ((n (find-node id)))
    (if (or (null n) (member id seen :test #'equal))
        0
        (let ((same (remove-if-not (lambda (p) (let ((pn (find-node p)))
                                                 (and pn (equal (getf pn :group) (getf n :group)))))
                                   (getf n :prereqs))))
          (if same
              (1+ (reduce #'max (mapcar (lambda (p) (node-depth p (cons id seen))) same)))
              0)))))

(defun node-ref (id &optional (map (map-id))) (str map "/" id))

;;; ---- Editing the map (by hand or by the model) -------------------------

;; Groups in map order, plus any group a node names that was never declared.
(defun ensure-group! (id)
  (unless (or (blankp id) (find-group id))
    (setf (getf *map* :groups) (append (map-groups) (list (list :id id :compression ""))))))

(defun add-group! (g)
  (let ((id (slugify (getf* g :id ""))))
    (unless (or (blankp id) (find-group id))
      (setf (getf *map* :groups) (append (map-groups) (list (list :id id :compression (trim (getf* g :compression ""))))))
      (save-map!)
      id)))

(defun add-node! (node)
  (let ((n (normalise-node node)))
    (unless (or (blankp (getf n :id)) (find-node (getf n :id)))
      (ensure-group! (getf n :group))
      (setf (getf *map* :nodes) (append (map-nodes) (list n)))
      (save-map!)
      n)))

;; Replace the node with the same id, keeping its place in the map.
(defun update-node! (node)
  (let* ((n (normalise-node node)) (old (find-node (getf n :id))))
    (when old
      (ensure-group! (getf n :group))
      (setf (getf *map* :nodes) (substitute n old (map-nodes)))
      (save-map!)
      n)))

;; Drop the node and every reference to it in other nodes' prereqs.
(defun remove-node! (id)
  (when (find-node id)
    (setf (getf *map* :nodes)
          (mapcar (lambda (n) (plist-update n :prereqs (remove id (getf n :prereqs) :test #'equal)))
                  (remove id (map-nodes) :key (lambda (n) (getf n :id)) :test #'equal)))
    (save-map!)
    id))

;; Turn a proposal plist (from the model, a form, or the file) into a clean node plist.
(defun normalise-node (p)
  (list :id (slugify (getf* p :id (getf* p :title "")))
        :title (trim (getf* p :title ""))
        :compression (trim (getf* p :compression ""))
        :why (trim (getf* p :why ""))
        :notes (trim (getf* p :notes ""))
        :group (slugify (getf* p :group "misc"))
        :prereqs (mapcar #'slugify (remove-if #'blankp (let ((pr (getf p :prereqs)))
                                                         (if (stringp pr) (split #\, pr) pr))))
        :era (let ((e (getf p :era)))
               (cond ((and (integerp e) (/= e 0)) e)
                     ((and (stringp e) (not (blankp e))) (parse-integer e :junk-allowed t))
                     (t nil)))))

;;; ---- What is in view ----------------------------------------------------

;; (visible-nodes "switches") → that group; an idea id → its neighbourhood; else all.
(defun visible-nodes (&optional focus)
  (cond ((blankp focus) (map-nodes))
        ((find-group focus) (group-nodes focus))
        ((find-node focus) (neighbourhood focus))
        (t (map-nodes))))

;; Groups, in map order, that have at least one visible node (undeclared ones included).
(defun visible-groups (nodes)
  (let ((ids (remove-duplicates (mapcar (lambda (n) (getf n :group)) nodes) :test #'equal :from-end t)))
    (append (remove-if-not (lambda (g) (member (getf g :id) ids :test #'equal)) (map-groups))
            (loop for id in ids unless (find-group id) collect (list :id id :compression "")))))

;;; ---- Levels ------------------------------------------------------------

;; (node-level "ram") → 0..3, 0 when unset.
(defun node-level (id &optional (map (map-id)))
  (getf (find-level (node-ref id map)) :level 0))

(defun level-name (n) (aref *level-names* (max 0 (min 3 n))))

;; Levels are set by hand after feedback, never by the model.
(defun set-level! (id n)
  (put-level! (list :ref (node-ref id) :map (map-id) :node-id id
                    :level (max 0 (min 3 n)) :at (now-iso))))

;;; ---- Attempts ----------------------------------------------------------

;; Newest first.
(defun node-attempts (id)
  (let ((ref (node-ref id)))
    (reverse (remove ref (attempts) :key (lambda (a) (getf a :ref)) :test-not #'equal))))

(defun latest-attempt (id) (first (node-attempts id)))

(defun add-attempt! (id text feedback)
  (put-attempt! (list :id (str (now-iso) "#" (length (attempts)))
                      :ref (node-ref id) :map (map-id) :node-id id
                      :at (now-iso) :text text :feedback feedback)))

;;; ---- Messages: the conversation with the field -------------------------
;;; One conversation per field, oldest first. A message may be about one node.
;;; :role is "you", "buddy" or "error"; :changes is the one-line summary of what
;;; the model changed in the map, when it did.

(defun map-messages (&optional node)
  (remove-if-not (lambda (m) (and (equal (getf m :map) (map-id))
                                  (or (null node) (equal (getf m :node) node))))
                 (messages)))

(defun add-message! (role text &key node changes)
  (put-message! (list :id (str (now-iso) "#" (length (messages)))
                      :map (map-id) :node node :role role :at (now-iso)
                      :text text :changes changes)))

;;; ---- Settings ----------------------------------------------------------

(defun setting (key) (getf (find-setting key) :value))
(defun set-setting! (key value) (put-setting! (list :key key :value value :at (now-iso))))

;;; ---- About: the articulation on the home page --------------------------

(defun about-file () (data-path "about.md"))

(defun about-text ()
  (if (probe-file (about-file))
      (uiop:read-file-string (about-file) :external-format :utf-8)
      "# studybuddy\n\nWrite here what this product is for."))

(defun set-about-text! (text)
  (ensure-directories-exist (about-file))
  (with-open-file (out (about-file) :direction :output :if-exists :supersede :external-format :utf-8)
    (write-string text out))
  text)
