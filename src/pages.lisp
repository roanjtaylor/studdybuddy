;;;; L5b — Pages. A directory: / (what this is for) → /fields → /computers →
;;;; /computers/switches → /computers/switches/ram. Every page is live:
;;;; re-evaluate the form, refresh the browser.

(in-package :studybuddy)

;;; ---- Small components --------------------------------------------------

(defcomponent level-badge (id)
  (let ((n (node-level id)))
    (html (:span :class (str "lvl lvl-" n) :title (str "level " n) (level-name n)))))

(defcomponent node-link (id)
  (let ((n (find-node id)))
    (html (:a :class "nodelink" :href (node-url id) (if n (getf n :title) id)) " " (level-badge id))))

(defcomponent group-tag (group-id)
  (html (:a :class "tag" :href (group-url group-id) group-id)))

(defcomponent string-list (items &key (class "plain"))
  (when items
    (html (:ul :class class (dolist (s items) (html (:li s)))))))

(defcomponent hidden (name value)
  (html (:input :type "hidden" :name name :value value)))

(defcomponent markdown (text)
  (html (:div :class "md" (:raw (markdown->html text)))))

;;; ---- The ask box: the one way to talk to the field ------------------------
;;; `here` is the focus the ask is made from: "" for the field, a group id, an
;;; idea id. Chips are canned asks; they post to the same action as the free text.

(defcomponent chip (label text here)
  (html (:form :method "post" :action "/action/ask" :class "inline ask-form"
          (hidden "map-name" (map-id)) (hidden "here" here) (hidden "text" text)
          (:button :type "submit" :class "chip" label))))

(defcomponent ask-box (placeholder chips &optional (here "") (view ""))
  (html (:section :class "ask" :id "ask"
          (:form :method "post" :action "/action/ask" :class "ask-form"
            (hidden "map-name" (map-id)) (hidden "here" here) (hidden "view" view)
            (:textarea :name "text" :rows 2 :placeholder placeholder :required t :spellcheck "false")
            (:div :class "ask-row"
              (:label :class "check" (:input :type "checkbox" :name "search" :value "1") " search the web")
              (:button :type "submit" :class "primary" "Ask")))
          (:div :class "chips"
            (loop for (label text) in chips do (chip label text here))))))

(defcomponent message-view (m)
  (let ((role (getf m :role)))
    (html (:article :class (str "msg msg-" role)
            (:p :class "quiet small who"
                (cond ((equal role "you") "you") ((equal role "error") "error") (t "buddy"))
                (when (getf m :node)
                  (html " · " (:a :href (node-url (getf m :node))
                                 (let ((n (find-node (getf m :node)))) (if n (getf n :title) (getf m :node))))))
                " · " (getf m :at))
            (if (equal role "you")
                (html (:p (getf m :text)))
                (markdown (getf m :text)))
            (when (getf m :changes)
              (html (:p :class "changes" "map changed: " (getf m :changes))))))))

(defcomponent transcript (messages &key (limit 12) all-href)
  (let* ((n (length messages))
         (shown (if (and limit (> n limit)) (last messages limit) messages)))
    (html (:section :class "transcript"
            (when (and all-href (> n (length shown)))
              (html (:p :class "quiet small" (:a :href all-href "show all " n " messages"))))
            (dolist (m shown) (message-view m))))))

;;; ---- Views of a field -----------------------------------------------------
;;; Two things are chosen in the URL: the tab (?view=map|timeline|interact) and how
;;; far in you look (?depth=breadth|depth). Breadth is the groups; depth is every idea.

(defparameter *views* '("map" "timeline" "interact"))
(defparameter *depths* '("breadth" "depth"))

(defparameter *col-w* 220)
(defparameter *row-h* 76)
(defparameter *box-w* 190)
(defparameter *box-h* 56)

(defun nodes-in-group (nodes group-id)
  (stable-sort (remove group-id nodes :key (lambda (n) (getf n :group)) :test-not #'equal)
               #'< :key (lambda (n) (node-depth (getf n :id)))))

;; (wrap-words "a long title here" 8) → ("a long" "title" "here…") at most 2 lines
(defun wrap-words (s width &optional (max-lines 2))
  (let ((lines '()) (line ""))
    (dolist (w (split #\Space s))
      (if (and (> (length line) 0) (> (+ (length line) 1 (length w)) width))
          (progn (push line lines) (setf line w))
          (setf line (if (string= line "") w (str line " " w)))))
    (push line lines)
    (setf lines (nreverse lines))
    (if (> (length lines) max-lines)
        (append (subseq lines 0 (1- max-lines))
                (list (truncate-string (join " " (nthcdr (1- max-lines) lines)) width)))
        lines)))

;; The svg every picture is drawn in; map.js pans and zooms it.
(defmacro with-canvas ((w h &optional height) &body body)
  `(html (:div :id "map-wrap"
           (:svg :id "map" :xmlns "http://www.w3.org/2000/svg"
                 :viewBox (str "0 0 " ,w " " ,h) :width "100%" :height ,height
             (:g :id "viewport" ,@body)))))

;;; -- Depth map: every idea, a column per group, prerequisites as lines --------

;; → hash id → (x y), total width, total height. Rows are prerequisite depth in the group.
(defun map-positions (nodes groups)
  (let ((pos (make-hash-table :test #'equal)) (col 0) (maxrows 0))
    (dolist (g groups)
      (let ((gn (nodes-in-group nodes (getf g :id))))
        (loop for n in gn for row from 0
              do (setf (gethash (getf n :id) pos)
                       (list (+ 20 (* col *col-w*)) (+ 76 (* row *row-h*)))))
        (setf maxrows (max maxrows (length gn))))
      (incf col))
    (values pos (+ 40 (* col *col-w*)) (+ 96 (* maxrows *row-h*)))))

(defcomponent depth-map (nodes)
  (let ((groups (visible-groups nodes)))
    (multiple-value-bind (pos w h) (map-positions nodes groups)
      (with-canvas (w h)
        (loop for g in groups for col from 0
              do (let ((x (+ 20 (* col *col-w*))))
                   (html (:a :href (group-url (getf g :id))
                           (:text :x x :y 30 :class "group-title" (getf g :id)))
                         (:text :x x :y 50 :class "group-comp"
                                (truncate-string (getf* g :compression "") 34)))))
        (dolist (n nodes)
          (let ((to (gethash (getf n :id) pos)))
            (dolist (p (getf n :prereqs))
              (let ((from (gethash p pos)))
                (when (and from to)
                  (html (:line :class "edge"
                               :x1 (+ (first from) (/ *box-w* 2)) :y1 (+ (second from) *box-h*)
                               :x2 (+ (first to) (/ *box-w* 2)) :y2 (second to))))))))
        (dolist (n nodes)
          (let* ((id (getf n :id)) (p (gethash id pos)) (x (first p)) (y (second p)))
            (html (:a :href (node-url id)
                    (:rect :x x :y y :width *box-w* :height *box-h* :rx 6
                           :class (str "box lvl-" (node-level id)))
                    (:title (getf n :title) " — " (getf n :compression))
                    (:text :x (+ x 10) :y (+ y 23) :class "box-title"
                      (loop for line in (wrap-words (getf n :title) 27) for i from 0
                            do (html (:tspan :x (+ x 10) :dy (if (= i 0) 0 16) line))))))))))))

;;; -- Breadth map: one box per group, left to right in prerequisite order -------

(defparameter *gbox-w* 230)
(defparameter *gbox-h* 104)
(defparameter *gap* 40)

;; The groups a group's ideas build on, other than itself.
(defun group-prereqs (nodes group-id)
  (remove group-id
          (remove-duplicates
           (loop for n in nodes
                 when (equal (getf n :group) group-id)
                   append (loop for p in (getf n :prereqs)
                                for pn = (find-node p)
                                when pn collect (getf pn :group)))
           :test #'equal)
          :test #'equal))

;; Column of a group: 0 with nothing before it, else one past its latest prerequisite group.
(defun group-layer (nodes group-id &optional seen)
  (let ((ps (remove-if (lambda (g) (member g seen :test #'equal)) (group-prereqs nodes group-id))))
    (if ps
        (1+ (reduce #'max (mapcar (lambda (g) (group-layer nodes g (cons group-id seen))) ps)))
        0)))

;; Prerequisites run left to right, or top to bottom when `vertical` (a narrow pane).
(defcomponent breadth-map (nodes &optional vertical)
  (let* ((groups (visible-groups nodes))
         (pos (make-hash-table :test #'equal))
         (fill (make-hash-table)) (layers 0) (rows 0)
         (bw *gbox-w*) (bh *gbox-h*))
    (dolist (g groups)
      (let* ((layer (group-layer nodes (getf g :id))) (row (gethash layer fill 0)))
        (setf (gethash (getf g :id) pos) (list layer row)
              (gethash layer fill) (1+ row)
              layers (max layers (1+ layer))
              rows (max rows (1+ row)))))
    (flet ((px (g) (destructuring-bind (layer row) (gethash (getf g :id) pos)
                     (+ 20 (* (if vertical row layer) (+ bw *gap*)))))
           (py (g) (destructuring-bind (layer row) (gethash (getf g :id) pos)
                     (+ 20 (* (if vertical layer row) (+ bh *gap*))))))
      (with-canvas ((+ 40 (* (if vertical rows layers) (+ bw *gap*)))
                    (+ 40 (* (if vertical layers rows) (+ bh *gap*))))
        (dolist (g groups)
          (dolist (p (group-prereqs nodes (getf g :id)))
            (let ((from (find p groups :key (lambda (x) (getf x :id)) :test #'equal)))
              (when from
                (html (:line :class "edge"
                             :x1 (+ (px from) (if vertical (/ bw 2) bw))
                             :y1 (+ (py from) (if vertical bh (/ bh 2)))
                             :x2 (+ (px g) (if vertical (/ bw 2) 0))
                             :y2 (+ (py g) (if vertical 0 (/ bh 2)))))))))
        (dolist (g groups)
          (let* ((id (getf g :id)) (x (px g)) (y (py g))
                 (mine (nodes-in-group nodes id))
                 (done (count-if (lambda (n) (>= (node-level (getf n :id)) 2)) mine)))
            (html (:a :href (group-url id)
                    (:rect :x x :y y :width bw :height bh :rx 8 :class "box group-box")
                    (:text :x (+ x 14) :y (+ y 26) :class "group-title gb-text" id)
                    (:text :x (+ x 14) :y (+ y 46) :class "box-title gb-text"
                      (loop for line in (wrap-words (getf* g :compression "") 32 3) for i from 0
                            do (html (:tspan :x (+ x 14) :dy (if (= i 0) 0 15) line))))
                    (:text :x (+ x 14) :y (+ y bh -12) :class "group-comp gb-meta"
                           (length mine) " ideas · " done " explained")))))))))

;;; -- Timeline: years along the x axis, a lane per group -----------------------

(defparameter *tl-left* 170)
(defparameter *tl-right* 1150)
(defparameter *tl-top* 44)

;; A tick every 10 years, or wider when the span is long.
(defun tick-step (span) (cond ((<= span 150) 10) ((<= span 600) 50) (t 500)))

;; Greedy rows for labels along a line: each item takes the first row whose last label
;; has ended before it starts. → list of (item x row), and the number of rows used.
(defun pack-rows (items x-of width-of)
  (let ((ends '()) (placed '()))
    (dolist (it items)
      (let* ((x (funcall x-of it))
             (row (or (position-if (lambda (e) (<= e x)) ends) (length ends)))
             (end (+ x (funcall width-of it))))
        (if (< row (length ends))
            (setf (nth row ends) end)
            (setf ends (append ends (list end))))
        (push (list it x row) placed)))
    (values (nreverse placed) (max 1 (length ends)))))

(defcomponent timeline (nodes depth)
  (let* ((dated (remove-if-not (lambda (n) (getf n :era)) nodes))
         (groups (remove-if-not (lambda (g) (some (lambda (n) (equal (getf n :group) (getf g :id))) dated))
                                (visible-groups nodes)))
         (eras (mapcar (lambda (n) (getf n :era)) dated)))
    (if (null dated)
        (html (:p :class "quiet" "No ideas here have a date yet."))
        (let* ((step (tick-step (- (reduce #'max eras) (reduce #'min eras))))
               (lo (* step (floor (reduce #'min eras) step)))
               (hi (let ((h (* step (ceiling (reduce #'max eras) step)))) (if (= h lo) (+ lo step) h)))
               (deep (equal depth "depth"))
               (lanes '()) (y *tl-top*))
          (flet ((x (year) (round (+ *tl-left* (* (- *tl-right* *tl-left*) (/ (- year lo) (- hi lo)))))))
            ;; Lane = (group nodes-by-year placed-items height top).
            (dolist (g groups)
              (let ((gn (stable-sort (remove (getf g :id) dated :key (lambda (n) (getf n :group)) :test-not #'equal)
                                     #'< :key (lambda (n) (getf n :era)))))
                (multiple-value-bind (placed rows)
                    (if deep
                        (pack-rows gn (lambda (n) (x (getf n :era)))
                                   (lambda (n) (+ 16 (* 6.5 (length (getf n :title))))))
                        (values nil 0))
                  (let ((height (if deep (+ 16 (* 22 rows)) 62)))
                    (push (list g gn placed height y) lanes)
                    (incf y height)))))
            (setf lanes (nreverse lanes))
            (html
              (with-canvas (1200 (+ y 16))
                (loop for year from lo to hi by step
                      do (html (:line :class "gridline" :x1 (x year) :y1 (- *tl-top* 8) :x2 (x year) :y2 y)
                               (:text :x (x year) :y (- *tl-top* 16) :class "tick" :text-anchor "middle" year)))
                (dolist (lane lanes)
                  (destructuring-bind (g gn placed height ly) lane
                    (declare (ignore height))
                    (html (:line :class "lane" :x1 20 :y1 ly :x2 *tl-right* :y2 ly)
                          (:a :href (group-url (getf g :id))
                            (:text :x 20 :y (+ ly 22) :class "group-title" (getf g :id)))
                          (if deep
                              (dolist (it placed)
                                (destructuring-bind (n nx row) it
                                  (html (:a :href (node-url (getf n :id))
                                          (:circle :cx nx :cy (+ ly 18 (* 22 row)) :r 5
                                                   :class (str "dot lvl-" (node-level (getf n :id))))
                                          (:title (getf n :era) " — " (getf n :compression))
                                          (:text :x (+ nx 10) :y (+ ly 22 (* 22 row)) :class "box-title"
                                                 (getf n :title))))))
                              (let* ((first-year (getf (first gn) :era))
                                     (last-year (getf (car (last gn)) :era))
                                     (a (x first-year)) (b (max (x last-year) (+ a 8))))
                                (html (:a :href (group-url (getf g :id))
                                        (:rect :x a :y (+ ly 12) :width (- b a) :height 14 :rx 4 :class "span")
                                        (:title (getf* g :compression ""))
                                        (:text :x a :y (+ ly 46) :class "group-comp"
                                               first-year "–" last-year " · "
                                               (truncate-string (getf* g :compression "") 70)))))))))))
            (let ((undated (- (length nodes) (length dated))))
              (when (> undated 0)
                (html (:p :class "quiet small" undated " ideas have no date and are left out here.")))))))))

;;; -- Tabs ---------------------------------------------------------------------

(defun view-url (self-url view depth) (str self-url "?view=" view "&depth=" depth))

(defun capitalise (s) (str (string-upcase (subseq s 0 1)) (subseq s 1)))

(defcomponent view-button (self-url label view depth on)
  (html (:form :method "get" :action self-url :class "inline"
          (hidden "view" view) (hidden "depth" depth)
          (:button :type "submit" :class (and on "on") label))))

;; An iOS-style switch that is really a GET form: pressing it submits the other
;; state. `on` is a form evaluated once; the hidden fields are (name value) pairs.
;;
;;   (ios-switch (deep "/computers" :off "Breadth" :on "Depth")
;;     ("view" view) ("depth" (if deep "breadth" "depth")))
(defmacro ios-switch ((on action &key (off-label "Off") (on-label "On")) &body hidden-fields)
  (with-gensyms (on?)
    `(let ((,on? ,on))
       (html (:form :method "get" :action ,action :class "inline"
               ,@(loop for (name value) in hidden-fields collect `(hidden ,name ,value))
               (:button :type "submit" :class "switch" :role "switch"
                        :aria-checked (if ,on? "true" "false")
                        :title (str "Show " (if ,on? ,off-label ,on-label))
                 (:span :class (and (not ,on?) "on") ,off-label)
                 (:span :class "track" (:span :class "knob"))
                 (:span :class (and ,on? "on") ,on-label)))))))

;; One switch between the two depths: pressing it goes to the other one.
(defcomponent depth-toggle (self-url view depth)
  (let ((deep (equal depth "depth")))
    (ios-switch (deep self-url :off-label "Breadth" :on-label "Depth")
      ("view" view)
      ("depth" (if deep "breadth" "depth")))))

(defcomponent view-bar (self-url view depth)
  (html (:div :class "viewbar"
          (dolist (v *views*)
            (view-button self-url (capitalise v) v depth (equal v view)))
          (:span :class "gap")
          (depth-toggle self-url view depth))))

(defcomponent map-view (nodes depth &optional vertical)
  (cond ((null nodes) (html (:p :class "quiet" "No ideas here yet.")))
        ((equal depth "depth") (depth-map nodes))
        (t (breadth-map nodes vertical))))

(defcomponent chat (focus view)
  (html (:section :class "chat"
          (:div :class "chat-log"
            (let ((ms (map-messages)))
              (if ms
                  (dolist (m ms) (message-view m))
                  (html (:p :class "quiet" "Ask anything about this field, or tell me how to change the map.")))))
          (ask-box "Ask about this field, or tell me how to change the map…" nil focus view))))

(defcomponent field-view (nodes view depth focus)
  (html (:div :class (str "stage view-" view)
          (cond ((equal view "timeline") (timeline nodes depth))
                ((equal view "interact")
                 (html (:div :class "pane-map" (map-view nodes depth t))
                       (:div :class "pane-chat" (chat focus view))))
                (t (map-view nodes depth))))))

(defcomponent map-warnings ()
  (let ((bad (check-map)))
    (when bad
      (html (:p :class "warn"
              "Dangling prerequisites: "
              (join "; " (mapcar (lambda (b) (str (car b) " → " (cdr b))) bad)))))))

(defcomponent field-list ()
  (html (:ul
          (dolist (m (list-maps))
            (html (:li (:a :href (field-url m) (getf (field-summary m) :title))))))))

;;; ---- Home: what this is for ----------------------------------------------

(defpage home "/" ()
  (layout "StudyBuddy"
    (html (:div :class "home"
            (markdown (about-text))))))

;;; ---- Fields ---------------------------------------------------------------

(defpage fields-page "/fields" (new)
  (let ((*crumbs* '(("fields"))))
    (layout "Fields"
      (html (:div :class "heading"
              (:h1 "Fields")
              (:a :class "round" :href (if new "/fields" "/fields?new=1")
                  :title (if new "Cancel" "New field")
                  (if new "×" "+")))
            (when new
              (html (:form :method "post" :action "/action/seed" :class "ask-form"
                      (:label "Field" (:input :type "text" :name "field" :required t :placeholder "e.g. Thermodynamics"))
                      (:label "What you already know, and why you want it"
                              (:textarea :name "note" :rows 4))
                      (:button :type "submit" :class "primary" "Create field"))))
            (field-list)))))

;;; ---- A field, or one group of it -----------------------------------------

;; Shared by the field page (focus "") and the group page (focus = group id or idea id).
;; A whole field opens at breadth; a group or an idea's neighbourhood opens at depth.
(defun render-field (focus view depth self-url)
  (let* ((view (if (member view *views* :test #'equal) view "map"))
         (depth (cond ((member depth *depths* :test #'equal) depth)
                      ((blankp focus) "breadth")
                      (t "depth")))
         (group (and (not (blankp focus)) (find-group focus)))
         (nodes (visible-nodes focus))
         (*page-class* "field")
         (*crumbs* (append (list (cons "fields" "/fields")
                                 (cons (map-id) (and group (field-url))))
                           (when group (list (list (getf group :id))))))
         (*nav-extra* (html (:span :class "tagline" (if group (getf group :compression) (getf *map* :compression)))
                            (view-bar self-url view depth))))
    (layout (if group (str (getf group :id) " · " (map-title)) (map-title))
      (html (unless group (map-warnings))
            (field-view nodes view depth focus)))))

(defpage field-page "/:name" (name view depth around)
  (unless (select-map name) (return-from field-page (not-found "field")))
  (render-field (if (and around (find-node around)) around "") view depth (field-url)))

;; /computers/switches is the group; /computers/ram forgives a dropped group.
(defpage group-page "/:name/:group" (name group view depth)
  (unless (select-map name) (return-from group-page (not-found "field")))
  (cond ((find-group group) (render-field group view depth (group-url group)))
        ((find-node group) (redirect (node-url group)))
        (t (not-found "group"))))

;;; ---- An idea --------------------------------------------------------------

(defcomponent feedback-view (fb)
  (when fb
    (html (:div :class "feedback"
            (:p :class "verdict" (getf fb :verdict))
            (:div :class "three"
              (:div (:h4 "Right") (string-list (getf fb :right)))
              (:div (:h4 "Missing") (string-list (getf fb :missing)))
              (:div (:h4 "Wrong") (string-list (getf fb :wrong))))
            (when (getf fb :suggested-level)
              (html (:p :class "quiet small" "Model's suggestion: level " (getf fb :suggested-level)
                        " (" (level-name (getf fb :suggested-level)) "). You decide.")))))))

(defcomponent attempt-view (a)
  (html (:article :class "attempt"
          (:p :class "quiet small" (getf a :at))
          (:pre :class "wrote" (getf a :text))
          (feedback-view (getf a :feedback)))))

(defcomponent rate-form (id)
  (let ((current (node-level id)))
    (html (:form :method "post" :action "/action/rate" :class "rate"
            (hidden "map-name" (map-id)) (hidden "node-id" id)
            (:span :class "quiet" "Your level: ")
            (loop for i from 0 to 3
                  do (html (:button :type "submit" :name "level" :value i
                                    :class (str "lvl lvl-" i (when (= i current) " current"))
                                    (level-name i))))))))

(defcomponent write-box (id)
  (html (:form :method "post" :action "/action/attempt" :class "write ask-form"
          (hidden "map-name" (map-id)) (hidden "node-id" id)
          (:textarea :name "text" :rows 8 :required t :spellcheck "false"
                     :placeholder "Explain it cold, in your own words, as if teaching it.")
          (:div :class "ask-row"
            (:span :class "quiet small" "The model names what is right, missing and wrong. It never sets your level.")
            (:button :type "submit" :class "primary" "Check my explanation")))))

(defcomponent edit-node-form (n)
  (html (:details :class "edit"
          (:summary "Edit by hand")
          (:form :method "post" :action "/action/edit-node" :class "ask-form"
            (hidden "map-name" (map-id)) (hidden "node-id" (getf n :id))
            (:label "Title" (:input :type "text" :name "title" :value (getf n :title) :required t))
            (:label "Compression" (:textarea :name "compression" :rows 2 (getf n :compression)))
            (:label "Why it matters" (:textarea :name "why" :rows 2 (getf n :why)))
            (:label "Notes (markdown)" (:textarea :name "notes" :rows 8 (getf n :notes)))
            (:label "Group" (:input :type "text" :name "group" :value (getf n :group)))
            (:label "Builds on (ids, comma separated)" (:input :type "text" :name "prereqs" :value (join ", " (getf n :prereqs))))
            (:label "Era (year)" (:input :type "text" :name "era" :value (getf n :era)))
            (:div :class "ask-row"
              (:button :type "submit" :class "primary" "Save")))
          (:form :method "post" :action "/action/remove-node" :class "inline"
            (hidden "map-name" (map-id)) (hidden "node-id" (getf n :id))
            (:button :type "submit" :class "danger" "Remove this idea from the map")))))

(defparameter *node-chips*
  '(("Explain it to me" "Explain this idea to me from first principles, mechanism first. Then record the explanation in its notes.")
    ("Go deeper" "Expand this idea into the sub-ideas I would need to write out to own it, one level down.")
    ("Quiz me" "Quiz me on this idea and its neighbours: five questions, answers hidden at the end.")
    ("Questions to answer" "Give me five questions about mechanism that I should be able to answer in a paragraph each, hardest gap first given my attempts.")
    ("Why does it matter?" "Why does this idea matter for the rest of the field? What does it unlock, and what breaks without it?")))

(defpage node-page "/:name/:group/:id" (name group id)
  (unless (select-map name) (return-from node-page (not-found "field")))
  (let ((n (find-node id)))
    (cond ((null n) (not-found "idea"))
          ;; The idea moved group: follow it.
          ((not (equal group (getf n :group))) (redirect (node-url id)))
          (t
           (let ((*ask-href* "#ask")
                 (*crumbs* (list (cons "fields" "/fields") (cons (map-id) (field-url))
                                 (cons (getf n :group) (group-url (getf n :group))) (list id))))
             (layout (getf n :title)
               (html (:div :class "node-grid"
                       (:section :class "node-main"
                         (:p :class "crumb"
                             (when (getf n :era) (html (getf n :era) " · "))
                             (:a :href (str (field-url) "?around=" id) "see what it connects to"))
                         (:h1 (getf n :title))
                         (:p :class "compression" (getf n :compression))
                         (:p :class "why" (getf n :why))
                         (when (getf n :prereqs)
                           (html (:p :class "quiet" "Builds on: "
                                     (loop for (p . rest) on (getf n :prereqs)
                                           do (node-link p) (when rest (html ", "))))))
                         (let ((d (dependents id)))
                           (when d
                             (html (:p :class "quiet" "Leads to: "
                                       (loop for (m . rest) on d
                                             do (node-link (getf m :id)) (when rest (html ", ")))))))
                         (unless (blankp (getf n :notes))
                           (html (:section :class "notes" (:h2 "Notes") (markdown (getf n :notes)))))
                         (:h2 "Explain it")
                         (write-box id)
                         (rate-form id)
                         (let ((as (node-attempts id)))
                           (when as
                             (html (:h2 "Attempts" (:span :class "quiet small" " (" (length as) ")"))
                                   (dolist (a as) (attempt-view a)))))
                         (edit-node-form n))
                       (:aside :class "node-side"
                         (ask-box "Ask about this idea, or tell me what to do with it: explain, expand, quiz, record what you've learned…"
                                  *node-chips* id)
                         (transcript (map-messages id) :limit nil))))))))))
