;;;; L5a — Data. Node, Map, Attempt, Level, Card.
;;;;
;;;; A map is a read-only data file under data/maps/, one form per line:
;;;;   (:map :id "computers" :title "Computers" :compression "…")
;;;;   (:group :id "switches" :compression "A switch can control another switch.")
;;;;   (:node :id "flip-flop" :title "…" :compression "…" :why "…"
;;;;          :group "switches" :prereqs ("logic-gates") :era 1918)
;;;; Levels, attempts and cards live in their own stores so the map stays a clean,
;;;; hand-editable description of the field. They are keyed by :ref = "map/node-id"
;;;; so two maps may reuse a node id.

(in-package :studybuddy)

(defstore attempt (:file "attempts.lisp" :key :id :append t))
(defstore level   (:file "levels.lisp"   :key :ref))
(defstore card    (:file "cards.lisp"    :key :ref))
(defstore setting (:file "settings.lisp" :key :key))   ; (:key "intro-seen" :value t)

(defvar *map* nil "The loaded map: (:id :title :compression :groups :nodes).")
(defvar *default-map* "computers")
(defvar *scratch* (make-hash-table :test #'equal)
  "Results shown but not stored (questions, quizzes, proposals), keyed by ref or map id.")

(defparameter *level-names* #("not yet" "shaky" "can explain" "can teach"))

;;; ---- Maps --------------------------------------------------------------

(defun map-file (name) (data-path (str "maps/" name ".lisp")))

(defun tagged (forms tag)
  (loop for f in forms when (eq (car f) tag) collect (cdr f)))

;; (load-map "computers") → the map plist, now current.
(defun load-map (name)
  (let ((forms (read-file-forms (map-file name))))
    (unless forms (error "No map file ~a" (map-file name)))
    (let ((head (first (tagged forms :map))))
      (setf *map* (list :id name
                        :title (getf* head :title name)
                        :compression (getf head :compression)
                        :groups (tagged forms :group)
                        :nodes (tagged forms :node))))))

(defun ensure-map ()
  (or *map* (load-map *default-map*)))

(defun map-id () (getf (ensure-map) :id))
(defun map-title () (getf (ensure-map) :title))
(defun map-nodes () (getf (ensure-map) :nodes))
(defun map-groups () (getf (ensure-map) :groups))

;; (list-maps) → ("computers" …) from data/maps/*.lisp
(defun list-maps ()
  (sort (mapcar #'pathname-name (directory (data-path "maps/*.lisp"))) #'string<))

(defun map-exists-p (name) (probe-file (map-file name)))

;; Write a whole new map file (seed). Refuses to overwrite.
(defun write-map! (id title compression groups nodes)
  (when (map-exists-p id) (error "Map ~a already exists" id))
  (write-file-forms (map-file id)
                    (append (list (list :map :id id :title title :compression compression))
                            (mapcar (lambda (g) (cons :group g)) groups)
                            (mapcar (lambda (n) (cons :node n)) nodes)))
  id)

;; Append one node to the current map's file and reload.
(defun append-node! (node)
  (when (find-node (getf node :id)) (error "Node ~a already in map" (getf node :id)))
  (append-file-form (map-file (map-id)) (cons :node node))
  (load-map (map-id))
  node)

;; (check-map) → list of (node-id . missing-prereq-id); NIL when every id resolves.
(defun check-map ()
  (loop for n in (map-nodes)
        append (loop for p in (getf n :prereqs)
                     unless (find-node p) collect (cons (getf n :id) p))))

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

(defun node-ref (id) (str (map-id) "/" id))

;;; ---- Levels ------------------------------------------------------------

;; (node-level "ram") → 0..3, 0 when unset.
(defun node-level (id)
  (getf (find-level (node-ref id)) :level 0))

(defun level-name (n) (aref *level-names* (max 0 (min 3 n))))

;; Levels are set by hand after feedback, never by the model.
(defun set-level! (id n)
  (put-level! (list :ref (node-ref id) :map (map-id) :node-id id
                    :level (max 0 (min 3 n)) :at (now-iso))))

(defun prereqs-met-p (id)
  (every (lambda (p) (>= (node-level p) 2)) (getf (find-node id) :prereqs)))

;; Nodes at level 0 whose prereqs are met: what the map should pull you toward.
(defun grey-frontier ()
  (remove-if-not (lambda (n) (and (= 0 (node-level (getf n :id)))
                                  (prereqs-met-p (getf n :id))))
                 (map-nodes)))

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

;;; ---- Cards (v1 study cards) -------------------------------------------

;; (:principles ("…") :sources ((:title "…" :url "…" :blurb "…")))
(defun node-card (id) (find-card (node-ref id)))

(defun set-card! (id principles sources)
  (put-card! (list :ref (node-ref id) :map (map-id) :node-id id
                   :at (now-iso) :principles principles :sources sources)))

;;; ---- Scratch (shown, not stored) ---------------------------------------

(defun scratch (key &optional field)
  (let ((v (gethash key *scratch*)))
    (if field (getf v field) v)))

(defun set-scratch! (key field value)
  (setf (gethash key *scratch*) (plist-update (gethash key *scratch*) field value)))

;;; ---- Normalising model-proposed nodes ---------------------------------

;; Turn a proposal plist (from the model or a form) into a clean node plist.
(defun normalise-node (p)
  (list :id (slugify (getf* p :id (getf p :title)))
        :title (trim (getf* p :title ""))
        :compression (trim (getf* p :compression ""))
        :why (trim (getf* p :why ""))
        :group (slugify (getf* p :group "misc"))
        :prereqs (mapcar #'slugify (remove-if #'blankp (getf p :prereqs)))
        :era (let ((e (getf p :era)))
               (cond ((integerp e) e)
                     ((and (stringp e) (not (blankp e))) (parse-integer e :junk-allowed t))
                     (t nil)))))

;;; ---- Settings ----------------------------------------------------------

(defun setting (key) (getf (find-setting key) :value))
(defun set-setting! (key value) (put-setting! (list :key key :value value :at (now-iso))))

;;; ---- Import the v1 library (data/library.json) ------------------------
;;; Each v1 topic becomes a node in the "library" map with its study card
;;; attached, so the hunted sources show on the node page like any other card.

(defun v1-source->plist (src)
  (list :title (getf src :title) :url (getf src :url) :blurb (getf src :blurb)
        :author (getf src :author) :kind (getf src :kind)))

;; (import-v1-library) → number of topics imported; writes data/maps/library.lisp
;; and the cards store. Re-running replaces the library map and its cards.
(defun import-v1-library (&optional (file (data-path "library.json")))
  (let* ((json (json->lisp (jzon:parse (uiop:read-file-string file))))
         (topics (getf json :cards))
         (nodes (loop for tp in topics
                      collect (list :id (slugify (getf tp :topic))
                                    :title (getf tp :topic)
                                    :compression (or (first (getf tp :firstprinciples)) "")
                                    :why (or (getf (first (getf tp :sources)) :coreidea) "")
                                    :group "hunted" :prereqs '() :era nil))))
    (let ((path (map-file "library")))
      (when (probe-file path) (delete-file path)))
    (write-map! "library" "Library" "Topics hunted with v1: first principles and primary sources, one card each."
                (list (list :id "hunted" :compression "Ideas whose originators have been found."))
                nodes)
    (let ((previous (map-id)))
      (load-map "library")
      (loop for tp in topics for n in nodes
            do (set-card! (getf n :id)
                          (getf tp :firstprinciples)
                          (mapcar #'v1-source->plist (getf tp :sources))))
      (load-map previous))
    (length topics)))
