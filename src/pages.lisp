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

(defcomponent ask-box (placeholder chips &optional (here ""))
  (html (:section :class "ask" :id "ask"
          (:form :method "post" :action "/action/ask" :class "ask-form"
            (hidden "map-name" (map-id)) (hidden "here" here)
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

(defparameter *col-w* 220)
(defparameter *row-h* 76)
(defparameter *box-w* 190)
(defparameter *box-h* 56)

(defun nodes-in-group (nodes group-id)
  (stable-sort (remove group-id nodes :key (lambda (n) (getf n :group)) :test-not #'equal)
               #'< :key (lambda (n) (node-depth (getf n :id)))))

;; → hash id → (x y), total width, total height. Columns are groups; rows are
;; prerequisite depth within the group (ties keep map order).
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

(defcomponent map-view-svg (nodes)
  (let ((groups (visible-groups nodes)))
    (multiple-value-bind (pos w h) (map-positions nodes groups)
      (let ((frontier (mapcar (lambda (n) (getf n :id)) (frontier))))
        (html
          (:div :id "map-wrap"
            (:svg :id "map" :xmlns "http://www.w3.org/2000/svg"
                  :viewBox (str "0 0 " w " " h) :width "100%" :height "70vh"
              (:g :id "viewport"
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
                  (let* ((id (getf n :id)) (p (gethash id pos)) (x (first p)) (y (second p))
                         (lvl (node-level id)))
                    (html (:a :href (node-url id)
                            (:rect :x x :y y :width *box-w* :height *box-h* :rx 6
                                   :class (str "box lvl-" lvl (when (member id frontier :test #'equal) " frontier")))
                            (:title (getf n :title) " — " (getf n :compression))
                            (:text :x (+ x 10) :y (+ y 23) :class "box-title"
                              (loop for line in (wrap-words (getf n :title) 27) for i from 0
                                    do (html (:tspan :x (+ x 10) :dy (if (= i 0) 0 16) line))))))))))
          (:p :class "legend"
            (loop for i from 0 to 3 do (html (:span :class (str "lvl lvl-" i) (level-name i)) " "))
            (:span :class "quiet" "thick border = next: prerequisites met, not yet written up. Drag to pan, wheel to zoom."))))))))

(defcomponent outline-view (nodes)
  (html (:div :class "outline"
          (dolist (g (visible-groups nodes))
            (html (:section :class "outline-group"
                    (:h3 (:a :href (group-url (getf g :id)) (getf g :id))
                         " " (:span :class "quiet small" (getf g :compression)))
                    (:ul :class "plain"
                      (dolist (n (nodes-in-group nodes (getf g :id)))
                        (html (:li (node-link (getf n :id))
                                   (:div :class "quiet small" (getf n :compression))))))))))))

(defcomponent timeline-view (nodes)
  (let ((sorted (stable-sort (copy-list nodes) #'< :key (lambda (n) (or (getf n :era) most-positive-fixnum)))))
    (html (:table :class "timeline"
            (dolist (n sorted)
              (html (:tr
                      (:td :class "era" (or (getf n :era) "—"))
                      (:td (node-link (getf n :id))
                           (:div :class "quiet small" (getf n :compression)))
                      (:td (group-tag (getf n :group))))))))))

;; The toggles keep you on the same URL and change only how it is drawn.
(defcomponent view-bar (self-url)
  (let ((mode (view-mode)))
    (html (:div :class "viewbar"
            (dolist (m *view-modes*)
              (html (:a :class (str "toggle" (when (equal m mode) " on")) :href (str self-url "?view=" m) m)))))))

(defcomponent field-view (nodes)
  (cond ((null nodes) (html (:p :class "quiet" "No ideas here yet. Ask for some below.")))
        ((equal (view-mode) "outline") (outline-view nodes))
        ((equal (view-mode) "timeline") (timeline-view nodes))
        (t (map-view-svg nodes))))

(defcomponent map-warnings ()
  (let ((bad (check-map)))
    (when bad
      (html (:p :class "warn"
              "Dangling prerequisites: "
              (join "; " (mapcar (lambda (b) (str (car b) " → " (cdr b))) bad)))))))

(defcomponent field-list ()
  (html (:ul :class "plain fields"
          (dolist (m (list-maps))
            (let ((f (field-summary m)))
              (html (:li (:a :href (field-url m) (:strong (getf f :title)))
                         (:span :class "quiet small" " · " (getf f :ideas) " ideas, " (getf f :explained) " explained")
                         (:div :class "quiet small" (getf f :compression)))))))))

;;; ---- Home: what this is for ----------------------------------------------

(defpage home "/" ()
  (layout "studybuddy"
    (html (:div :class "home"
            (markdown (about-text))
            (:details :class "edit"
              (:summary "Edit this")
              (:form :method "post" :action "/action/about"
                (:textarea :name "text" :rows 18 :spellcheck "false" (about-text))
                (:p (:button :type "submit" :class "primary" "Save"))))
            (:section :class "panel"
              (:h2 "Fields")
              (field-list)
              (:p (:a :href "/fields" "Start a new field →")))))))

;;; ---- Fields ---------------------------------------------------------------

(defpage fields-page "/fields" ()
  (let ((*crumbs* '(("fields"))))
    (layout "Fields"
      (html (:h1 "Fields")
            (:p :class "tagline" "One map per field. Create it, let the model lay out the breadth, then shape it as you learn.")
            (field-list)
            (:section :class "panel"
              (:h2 "New field")
              (:p :class "quiet small" "Names a field; the model researches it with web search and lays out its core ideas breadth first, in prerequisite order. Slow (minutes). Everything it produces you can then reshape by asking.")
              (:form :method "post" :action "/action/seed" :class "ask-form"
                (:label "Field" (:input :type "text" :name "field" :required t :placeholder "e.g. Thermodynamics"))
                (:label "What you already know, and why you want it"
                        (:textarea :name "note" :rows 4))
                (:button :type "submit" :class "primary" "Create field")))))))

;;; ---- A field, or one group of it -----------------------------------------

(defparameter *field-chips*
  '(("What's missing?" "Read the whole map. What core ideas of this field are missing? Add the ones that matter most, breadth first, and tell me why.")
    ("Where am I weak?" "Looking at my levels and verdicts, where am I weakest, and what should I write out next? Don't change the map.")
    ("What next?" "Given what I can already explain, which one idea should I take on next, and why that one?")
    ("Go deeper here" "Take what I'm looking at and go one level deeper: add the sub-ideas I'd need to write out to own it, breadth first.")
    ("As a timeline" "Show this as a timeline.")
    ("As an outline" "Show this as an outline.")))

;; Shared by the field page (focus "") and the group page (focus = group id).
(defun render-field (focus view all self-url)
  (when view (set-view-mode! view))
  (let ((group (and (not (blankp focus)) (find-group focus)))
        (nodes (visible-nodes focus)))
    (let ((*ask-href* "#ask")
          (*crumbs* (append (list (cons "fields" "/fields")
                                  (cons (map-id) (and group (field-url))))
                            (when group (list (list (getf group :id)))))))
      (layout (if group (str (getf group :id) " · " (map-title)) (map-title))
        (html (:header :class "titlebar"
                (:div (:h1 (if group (getf group :id) (map-title)))
                      (:p :class "tagline" (if group (getf group :compression) (getf *map* :compression))))
                (:p :class "quiet small" (length nodes) " ideas · "
                    (count-if (lambda (n) (>= (node-level (getf n :id)) 2)) nodes) " explained"
                    (when group (html " · " (:a :href (field-url) "whole field")))))
              (unless group (map-warnings))
              (view-bar self-url)
              (field-view nodes)
              (ask-box (if group
                           "Ask about this group, or tell me how to change it: go deeper, add what's missing, split it, rename it…"
                           "Ask anything about this field, or tell me how to change the map: add what's missing, go deeper on a group, regroup, show it differently…")
                       *field-chips* focus)
              (transcript (map-messages) :limit (if all nil 12) :all-href (str self-url "?all=1"))
              (:details :class "edit"
                (:summary "Add an idea by hand")
                (:form :method "post" :action "/action/add-node" :class "ask-form"
                  (hidden "map-name" (map-id))
                  (:label "Title" (:input :type "text" :name "title" :required t))
                  (:label "Group" (:input :type "text" :name "group" :value focus
                                          :placeholder (join ", " (mapcar (lambda (g) (getf g :id)) (map-groups)))))
                  (:button :type "submit" "Add"))))))))

(defpage field-page "/:name" (name view all around)
  (unless (select-map name) (return-from field-page (not-found "field")))
  (render-field (if (and around (find-node around)) around "") view all (field-url)))

;; /computers/switches is the group; /computers/ram forgives a dropped group.
(defpage group-page "/:name/:group" (name group view all)
  (unless (select-map name) (return-from group-page (not-found "field")))
  (cond ((find-group group) (render-field group view all (group-url group)))
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
