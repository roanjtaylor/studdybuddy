;;;; L5b — Pages. Four screens, each one defpage, each built from defcomponents.
;;;; Every one of these is live: re-evaluate the form, refresh Chrome.

(in-package :studybuddy)

;;; ---- Small components --------------------------------------------------

(defcomponent level-badge (id)
  (let ((n (node-level id)))
    (html (:span :class (str "lvl lvl-" n) :title (str "level " n) (level-name n)))))

(defcomponent node-link (id)
  (let ((n (find-node id)))
    (html (:a :class "nodelink" :href (str "/node/" id) (if n (getf n :title) id)) " " (level-badge id))))

(defcomponent group-tag (group-id)
  (html (:span :class "tag" group-id)))

(defcomponent string-list (items &key (class "plain"))
  (when items
    (html (:ul :class class (dolist (s items) (html (:li s)))))))

(defcomponent hidden (name value)
  (html (:input :type "hidden" :name name :value value)))

(defcomponent post-button (action label &rest hidden-pairs)
  (html (:form :method "post" :action action :class "inline"
          (loop for (k v) on hidden-pairs by #'cddr do (hidden k v))
          (:button :type "submit" label))))

;;; ---- Proposed nodes (from Gaps, Expand) -------------------------------

(defcomponent proposal-view (p)
  (let ((n (normalise-node p)))
    (html (:li :class "proposal"
            (:strong (getf n :title)) " " (group-tag (getf n :group))
            (:p :class "compression small" (getf n :compression))
            (:p :class "quiet small" (getf n :why))
            (:p :class "quiet small" "Builds on: " (join ", " (getf n :prereqs))
                (when (getf n :era) (str " · " (getf n :era))))
            (if (find-node (getf n :id))
                (html (:span :class "quiet small" "already in the map"))
                (post-button "/action/accept-node" "Accept into map"
                             "id" (getf n :id) "title" (getf n :title)
                             "compression" (getf n :compression) "why" (getf n :why)
                             "group" (getf n :group) "prereqs" (join ", " (getf n :prereqs))
                             "era" (getf n :era)))))))

(defcomponent proposals-view (proposals)
  (when proposals
    (html (:ul :class "proposals" (dolist (p proposals) (proposal-view p))))))

;;; ---- The map ----------------------------------------------------------

(defparameter *col-w* 220)
(defparameter *row-h* 76)
(defparameter *box-w* 190)
(defparameter *box-h* 56)

;; Groups in map order, plus any group a node names that the file never declared.
(defun layout-groups ()
  (let ((declared (map-groups)))
    (append declared
            (loop for n in (map-nodes)
                  for g = (getf n :group)
                  unless (or (find-group g) (member g extra :test #'equal))
                    collect g into extra and collect (list :id g :compression "") into undeclared
                  finally (return undeclared)))))

;; → hash id → (x y), total width, total height. Columns are groups; rows are
;; prerequisite depth within the group (ties keep map order).
(defun map-positions ()
  (let ((pos (make-hash-table :test #'equal)) (col 0) (maxrows 0))
    (dolist (g (layout-groups))
      (let ((nodes (stable-sort (copy-list (group-nodes (getf g :id))) #'<
                                :key (lambda (n) (node-depth (getf n :id))))))
        (loop for n in nodes for row from 0
              do (setf (gethash (getf n :id) pos)
                       (list (+ 20 (* col *col-w*)) (+ 76 (* row *row-h*)))))
        (setf maxrows (max maxrows (length nodes))))
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

(defcomponent map-svg ()
  (multiple-value-bind (pos w h) (map-positions)
    (let ((frontier (mapcar (lambda (n) (getf n :id)) (grey-frontier))))
      (html
        (:div :id "map-wrap"
          (:svg :id "map" :xmlns "http://www.w3.org/2000/svg"
                :viewBox (str "0 0 " w " " h) :width "100%" :height "72vh"
            (:g :id "viewport"
              ;; Group headings
              (loop for g in (layout-groups) for col from 0
                    do (let ((x (+ 20 (* col *col-w*))))
                         (html (:text :x x :y 30 :class "group-title" (getf g :id))
                               (:text :x x :y 50 :class "group-comp"
                                      (truncate-string (getf* g :compression "") 34)))))
              ;; Edges first so boxes paint over them
              (dolist (n (map-nodes))
                (let ((to (gethash (getf n :id) pos)))
                  (dolist (p (getf n :prereqs))
                    (let ((from (gethash p pos)))
                      (when (and from to)
                        (html (:line :class "edge"
                                     :x1 (+ (first from) (/ *box-w* 2)) :y1 (+ (second from) *box-h*)
                                     :x2 (+ (first to) (/ *box-w* 2)) :y2 (second to))))))))
              ;; Boxes
              (dolist (n (map-nodes))
                (let* ((id (getf n :id)) (p (gethash id pos)) (x (first p)) (y (second p))
                       (lvl (node-level id)))
                  (html (:a :href (str "/node/" id)
                          (:rect :x x :y y :width *box-w* :height *box-h* :rx 6
                                 :class (str "box lvl-" lvl (when (member id frontier :test #'equal) " frontier")))
                          (:title (getf n :title) " — " (getf n :compression))
                          (:text :x (+ x 10) :y (+ y 23) :class "box-title"
                            (loop for line in (wrap-words (getf n :title) 27) for i from 0
                                  do (html (:tspan :x (+ x 10) :dy (if (= i 0) 0 16) line)))))))))))))))

(defcomponent legend ()
  (html (:p :class "legend"
          (loop for i from 0 to 3
                do (html (:span :class (str "lvl lvl-" i) (level-name i)) " "))
          (:span :class "quiet" "thick border = frontier: prerequisites met, not yet written up. Drag to pan, wheel to zoom."))))

(defcomponent frontier-list ()
  (let ((f (grey-frontier)))
    (html (:section :class "panel"
            (:h2 "Frontier")
            (if f
                (html (:ul :class "plain" (dolist (n f) (html (:li (node-link (getf n :id)))))))
                (html (:p :class "quiet" "Nothing waiting: every reachable node has been attempted.")))))))

(defcomponent gaps-panel ()
  (let ((gaps (scratch (map-id) :gaps)))
    (html (:section :class "panel"
            (:h2 "Gaps")
            (:p :class "quiet small" "Asks the model to read the whole map with your levels and latest verdicts, and to say where you are weak and what the map is missing. Proposals are shown here until you accept them or restart.")
            (post-button "/action/gaps" "Find gaps" "map-name" (map-id))
            (when gaps
              (html (:h3 "Weak nodes")
                    (:ul :class "plain"
                      (dolist (w (getf gaps :weak-nodes))
                        (html (:li (node-link (getf w :id)) " — " (getf w :reason)))))
                    (:h3 "Missing ideas")
                    (proposals-view (getf gaps :missing-nodes))))))))

(defcomponent map-warnings ()
  (let ((bad (check-map)))
    (when bad
      (html (:p :class "warn"
              "Dangling prerequisites: "
              (join "; " (mapcar (lambda (b) (str (car b) " → " (cdr b))) bad)))))))

(defpage map-page "/" ()
  (ensure-map)
  (unless (setting "intro-seen") (redirect "/intro"))
  (layout (map-title)
    (html (:header :class "titlebar"
            (:div (:h1 (map-title))
                  (:p :class "tagline" (getf *map* :compression)))
            (:p :class "quiet small" (length (map-nodes)) " ideas · "
                (count-if (lambda (n) (>= (node-level (getf n :id)) 2)) (map-nodes)) " explained"))
          (map-warnings)
          (map-svg)
          (legend)
          (:div :class "two-col" (frontier-list) (gaps-panel)))))

(defpage map-switch "/map/:name" (name)
  (if (map-exists-p name)
      (progn (load-map name) (redirect "/"))
      (not-found "map")))

;;; ---- Timeline ---------------------------------------------------------

(defpage timeline-page "/timeline" ()
  (ensure-map)
  (let ((nodes (stable-sort (copy-list (map-nodes)) #'<
                            :key (lambda (n) (or (getf n :era) most-positive-fixnum)))))
    (layout "Timeline"
      (html (:h1 "Timeline")
            (:p :class "tagline" "The same ideas in the order they were had.")
            (:table :class "timeline"
              (dolist (n nodes)
                (html (:tr
                        (:td :class "era" (or (getf n :era) "—"))
                        (:td (node-link (getf n :id))
                             (:div :class "quiet small" (getf n :compression)))
                        (:td (group-tag (getf n :group)))))))))))

;;; ---- Node -------------------------------------------------------------

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
            (hidden "node-id" id)
            (:span :class "quiet" "Your level: ")
            (loop for i from 0 to 3
                  do (html (:button :type "submit" :name "level" :value i
                                    :class (str "lvl lvl-" i (when (= i current) " current"))
                                    (level-name i))))))))

(defcomponent write-box (id)
  (html (:form :method "post" :action "/action/attempt" :class "write"
          (hidden "node-id" id)
          (:textarea :name "text" :rows 10 :required t :spellcheck "false")
          (:p :class "quiet small" "Write it cold, in your own words, as if teaching it. The model names what is right, missing and wrong. It never sets your level.")
          (:button :type "submit" :class "primary" "Check my explanation"))))

(defcomponent card-view (card id)
  (html (:section :class "panel"
          (:h2 "Sources")
          (if card
              (html (:h4 "First principles")
                    (string-list (getf card :principles))
                    (:h4 "Read the originator")
                    (:ul :class "sources"
                      (dolist (s (getf card :sources))
                        (html (:li (:a :href (getf s :url) :target "_blank" :rel "noopener" (getf s :title))
                                   (when (or (getf s :author) (getf s :kind))
                                     (html (:span :class "quiet small" " — " (getf s :author)
                                                  (when (getf s :kind) (str " · " (getf s :kind))))))
                                   (:p :class "small" (getf s :blurb))))))
                    (post-button "/action/hunt" "Hunt again" "node-id" id))
              (html (:p :class "quiet small" "No sources yet. Write first; hunt when you want to check yourself against the originator.")
                    (post-button "/action/hunt" "Hunt sources" "node-id" id))))))

(defcomponent study-column (id)
  (let ((questions (scratch (node-ref id) :questions))
        (quiz (scratch (node-ref id) :quiz))
        (children (scratch (node-ref id) :children)))
    (html (:section :class "panel"
            (:h2 "Study")
            (:div :class "buttons"
              (post-button "/action/questions" "Questions to answer" "node-id" id)
              (post-button "/action/quiz" "Quiz me" "node-id" id)
              (post-button "/action/expand" "Expand into sub-ideas" "node-id" id))
            (when questions
              (html (:h4 "Questions") (string-list questions)))
            (when quiz
              (html (:h4 "Quiz")
                    (:ol :class "quiz"
                      (dolist (q quiz)
                        (html (:li (:p (getf q :prompt))
                                   (:ul :class "plain" (dolist (o (getf q :options)) (html (:li o))))
                                   (:details (:summary "Answer")
                                             (:p (:strong (getf q :answer)) " — " (getf q :explanation)))))))))
            (when children
              (html (:h4 "Sub-ideas") (proposals-view children)))))))

(defpage node-page "/node/:id" (id)
  (ensure-map)
  (let ((n (find-node id)))
    (if (null n)
        (not-found "node")
        (layout (getf n :title)
          (html (:div :class "node-grid"
                  (:section :class "node-main"
                    (:p :class "crumb" (:a :href "/" (map-title)) " / " (group-tag (getf n :group))
                        (when (getf n :era) (str " · " (getf n :era))))
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
                    (:h2 "Explain it")
                    (write-box id)
                    (rate-form id)
                    (let ((as (node-attempts id)))
                      (html (:h2 "Attempts" (:span :class "quiet small" " (" (length as) ")"))
                            (if as
                                (dolist (a as) (attempt-view a))
                                (html (:p :class "quiet" "None yet."))))))
                  (:aside :class "node-side"
                    (card-view (node-card id) id)
                    (study-column id))))))))

;;; ---- Maps -------------------------------------------------------------

(defpage maps-page "/maps" ()
  (ensure-map)
  (layout "Maps"
    (html (:h1 "Maps")
          (:ul :class "plain"
            (dolist (m (list-maps))
              (html (:li (:a :href (str "/map/" m) m)
                         (when (equal m (map-id)) (html " " (:span :class "tag" "current")))))))
          (:section :class "panel"
            (:h2 "Seed a new map")
            (:p :class "quiet small" "Names a field; the model researches it with web search and proposes groups and ideas in prerequisite order. Slow (minutes). Edit the resulting file by hand afterwards; it is just a list of forms.")
            (:form :method "post" :action "/action/seed"
              (:label "Field" (:input :type "text" :name "field" :required t :placeholder "e.g. Thermodynamics"))
              (:label "What you already know, and why you want it"
                      (:textarea :name "note" :rows 4))
              (:button :type "submit" :class "primary" "Seed map"))))))

;;; ---- Intro: the Pokémon dialogue from v1, shown on first visit ----------

(defparameter *intro-pages*
  '((:heading "HELLO!"
     :lines ("Welcome to the world of self-directed learning!"
             "My name is STUDYBUDDY."
             (:plain "People call me the " :yellow "SOURCE HUNTER!")))
    (:lines ("This world is filled with IDEAS — and endless remixes of those ideas."
             "The remixes are infinite."
             "The originals are few."))
    (:heading "RULE #1" :accent "yellow"
     :lines ((:plain "THEORY is studied by " :yellow "READING THE SOURCE.")
             "Databases. Transformers. Startups."
             "Codd. Faraday. Paul Graham."
             "Read their words — not the remix."))
    (:heading "RULE #2" :accent "red"
     :lines ((:plain "PRODUCTS are studied by " :red "USING THEM.")
             "Supabase. Stripe. Vercel."
             "No first principles — only docs and decisions."
             "Walk around the Aston Martin."))
    (:heading "RULE #3" :accent "yellow"
     :lines ((:plain "Nothing is understood until " :yellow "WRITTEN OUT AND CHECKED.")
             "Pick an idea on the map. Explain it cold."
             "I say what is right, missing and wrong."
             "You set your own level. Never me."))
    (:heading "BEFORE YOU HUNT"
     :lines ("Ask yourself:"
             (:plain "An " :yellow "IDEA" :plain ", or a " :red "TOOL" :plain "?")
             "Pick the right path."))
    (:heading "READY?"
     :lines ("STUDYBUDDY is waiting."
             "Let the hunt begin!"))))

(defcomponent intro-line (line)
  (if (stringp line)
      (html (:p line))
      (html (:p (loop for (style text) on line by #'cddr
                      do (case style
                           (:yellow (html (:span :class "pk-yellow" text)))
                           (:red (html (:span :class "pk-red" text)))
                           (t (html text))))))))

(defpage intro-page "/intro" (p)
  (let* ((n (max 0 (min (1- (length *intro-pages*)) (or (parse-integer (or p "0") :junk-allowed t) 0))))
         (page (nth n *intro-pages*))
         (last (= n (1- (length *intro-pages*)))))
    (layout "Intro"
      (html (:link :rel "stylesheet" :href "https://fonts.googleapis.com/css2?family=Press+Start+2P&family=VT323&display=swap")
            (:div :class "pk-screen"
              (:div :class "pk-box"
                (when (getf page :heading)
                  (html (:p :class (str "pk-heading " (when (getf page :accent) (str "pk-" (getf page :accent))))
                            (getf page :heading))))
                (:div :class "pk-body" (dolist (l (getf page :lines)) (intro-line l)))
                (:div :class "pk-foot"
                  (:span :class "pk-heading pk-dim" (1+ n) " / " (length *intro-pages*))
                  (if last
                      (post-button "/action/intro-done" "LET'S GO")
                      (html (:a :class "pk-next" :href (str "/intro?p=" (1+ n)) "NEXT ▼")))))
              (:p :class "pk-heading pk-dim pk-skip"
                  (:a :href (str "/intro?p=" (1- (length *intro-pages*))) "skip")))))))
