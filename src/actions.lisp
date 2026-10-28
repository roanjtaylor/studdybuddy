;;;; L5c — Actions. One AI channel (ask) that answers and reshapes the map, one AI
;;;; check of a written explanation, one AI seed of a new field, and the plain
;;;; hand edits. The level is never changed by any action but Rate.

(in-package :studybuddy)

(defparameter *rules*
  "Rules you must obey:
1. Core ideas, not examples. A node is one idea with a one-sentence compression and why it matters. Favour the few ideas that generate the rest; never pad with remixes, tools or trivia.
2. Theory is learned from the originator, products by using them. When you cite, cite primary sources.
3. Nothing is understood until it has been written out and checked. You never set the learner's level; you only give evidence.")

;; Read-time available (#.) so the prompt schemas below can splice it in.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *node-schema*
    '(:object (:id :string "lowercase slug, hyphens only")
              (:title :string "a short name for the idea, five words or fewer")
              (:compression :string "one sentence that compresses the idea")
              (:why :string "one or two sentences on why it matters")
              (:notes :string "deeper notes in markdown, grown over time; empty string when there are none")
              (:group :string "group id this node belongs to")
              (:prereqs (:array :string) "ids of ideas that must be understood first")
              (:era :integer "year the idea was first had; negative for BC; 0 if unknown"))))

;;; ---- URLs ----------------------------------------------------------------

;;; A directory: /computers → /computers/switches → /computers/switches/ram

(defun field-url (&optional (map (map-id))) (str "/" map))
(defun group-url (group &optional (map (map-id))) (str "/" map "/" group))
(defun node-url (id &optional (map (map-id)))
  (let ((n (find-node id)))
    (str "/" map "/" (if n (getf n :group) "misc") "/" id)))
;; Where a focus (group id, idea id, or empty) lives.
(defun focus-url (focus)
  (cond ((blankp focus) (field-url))
        ((find-group focus) (group-url focus))
        ((find-node focus) (node-url focus))
        (t (field-url))))

;;; ---- Context builders --------------------------------------------------

(defun node-context (id)
  (let* ((n (find-node id)) (g (find-group (getf n :group))))
    (str "Idea in focus: " (getf n :title) " (id " id ")" #\Newline
         "Group: " (getf n :group) " — " (getf g :compression) #\Newline
         "Compression: " (getf n :compression) #\Newline
         "Why it matters: " (getf n :why) #\Newline
         (unless (blankp (getf n :notes)) (str "Notes so far:" #\Newline (getf n :notes) #\Newline))
         (when (getf n :prereqs)
           (str "Builds on:" #\Newline
                (join #\Newline
                      (mapcar (lambda (p) (let ((pn (find-node p)))
                                            (str "  - " (if pn (getf pn :title) p) ": "
                                                 (if pn (getf pn :compression) "(not in map)"))))
                              (getf n :prereqs)))
                #\Newline))
         (let ((d (dependents id)))
           (when d
             (str "Leads to:" #\Newline
                  (join #\Newline (mapcar (lambda (m) (str "  - " (getf m :title) ": " (getf m :compression))) d))
                  #\Newline))))))

(defun attempts-context (id &optional (limit 3))
  (let ((as (subseq (node-attempts id) 0 (min limit (length (node-attempts id))))))
    (if as
        (str "Learner's written attempts at this idea, newest first:" #\Newline
             (join #\Newline
                   (mapcar (lambda (a)
                             (str "--- " (getf a :at) #\Newline (getf a :text) #\Newline
                                  "Verdict then: " (getf (getf a :feedback) :verdict)))
                           as)))
        "The learner has not written about this idea yet.")))

(defun map-context ()
  (str "Field: " (map-title) " — " (getf *map* :compression) #\Newline
       "Groups (id: compression):" #\Newline
       (join #\Newline (mapcar (lambda (g) (str "  " (getf g :id) ": " (getf g :compression))) (map-groups)))
       #\Newline "Ideas (id | title | group | learner's level 0-3 | prereqs | era | compression | latest verdict):" #\Newline
       (join #\Newline
             (mapcar (lambda (n)
                       (let ((id (getf n :id)))
                         (str "  " id " | " (getf n :title) " | " (getf n :group) " | " (node-level id) " | "
                              (join "," (getf n :prereqs)) " | " (or (getf n :era) "?") " | "
                              (getf n :compression) " | "
                              (or (getf (getf (latest-attempt id) :feedback) :verdict) "no attempt"))))
                     (map-nodes)))
       #\Newline "Current view: " (view-mode)))

(defun conversation-context (&optional (limit 10))
  (let* ((ms (remove "error" (map-messages) :key (lambda (m) (getf m :role)) :test #'equal))
         (recent (last ms limit)))
    (if recent
        (str "Recent conversation, oldest first:" #\Newline
             (join #\Newline
                   (mapcar (lambda (m)
                             (str (if (equal (getf m :role) "you") "Learner" "You")
                                  (when (getf m :node) (str " (about " (getf m :node) ")")) ": "
                                  (getf m :text)
                                  (when (getf m :changes) (str #\Newline "  [map changed: " (getf m :changes) "]"))))
                           recent)))
        "No conversation yet.")))

;;; ---- Ask: the one channel --------------------------------------------------

(defprompt converse
  :system (str "You are the learner's study buddy, living inside their knowledge map of one field. "
               "The map is the shared object: groups of ideas; each idea has a one-sentence compression, why it matters, prerequisites, optional deeper notes, and the learner's self-rated level 0-3 with the verdict on their latest written explanation."
               #\Newline *rules* #\Newline
               "The learner writes to you to learn and to reshape the map. Do both through the output fields:" #\Newline
               "- reply: markdown, concise, no preamble, no sign-off. Teach mechanism over vocabulary. Quizzes, questions, comparisons, study plans and answers all go here. Refer to ideas by title. "
               "When you changed the map, say what you changed in one line at the end." #\Newline
               "- When the learner asks to change the map, change it: fill gaps, go deeper on one idea (breadth first: three to six sub-ideas one level down, each listing the parent among its prereqs), remove, merge, regroup, rename, or record what they have learned. "
               "Use add-nodes, update-nodes, remove-node-ids and add-groups. Never describe a change you could make." #\Newline
               "- update-nodes replaces a node wholesale, so copy every field you are not changing. Use notes for depth the learner has earned: a longer explanation, the distinctions that matter, what to remember. Keep compression one sentence." #\Newline
               "- When the learner asks to see the field differently, set view.mode: map (groups as columns, prerequisites as lines), outline (groups as reading lists), timeline (by era). "
               "view.focus takes the learner to one group id or one idea id; empty string stays where they are. When no change of view is asked for, mode is keep and focus is empty." #\Newline
               "- Ids are lowercase slugs. Group ids must exist in the map or in add-groups. Prereqs must be ids that exist or that you are adding. Era is a year, 0 if unknown." #\Newline
               "- Never set the learner's level. If asked where they are weak, say so in the reply with reasons.")
  :schema (:object (:reply :string "markdown for the learner")
                   (:add-nodes (:array #.*node-schema*) "new ideas; empty when none")
                   (:update-nodes (:array #.*node-schema*) "full replacements of existing ideas, same id; empty when none")
                   (:remove-node-ids (:array :string) "ids to remove; empty when none")
                   (:add-groups (:array (:object (:id :string) (:compression :string))) "new groups; empty when none")
                   (:view (:object (:mode (:enum "keep" "map" "outline" "timeline"))
                                   (:focus :string "group id, idea id, or empty string")))))

;; Apply what the model asked for → (values one-line-summary-or-NIL focus-or-NIL).
(defun apply-changes! (r)
  (let ((done '()) (focus nil))
    (dolist (g (getf r :add-groups))
      (when (add-group! g) (push (str "group " (getf g :id)) done)))
    (dolist (n (getf r :add-nodes))
      (when (add-node! n) (push (str "+ " (getf n :title)) done)))
    (dolist (n (getf r :update-nodes))
      (when (update-node! n) (push (str "~ " (getf n :title)) done)))
    (dolist (id (getf r :remove-node-ids))
      (when (remove-node! id) (push (str "- " id) done)))
    (let ((v (getf r :view)))
      (when (and v (not (equal (getf v :mode) "keep")) (set-view-mode! (getf v :mode)))
        (push (str "view " (getf v :mode)) done))
      (when (and v (not (blankp (getf v :focus)))
                 (or (find-group (getf v :focus)) (find-node (getf v :focus))))
        (setf focus (getf v :focus))
        (push (str "→ " focus) done)))
    (values (when done (join ", " (nreverse done))) focus)))

;; `here` is the focus the learner asked from: "" (whole field), a group id, or an
;; idea id. The answer lands back there unless the model moved the view.
(defaction ask-buddy "/action/ask" (map-name here text search)
  (unless (select-map map-name) (return-from ask-buddy (not-found "field")))
  (let* ((node (and (not (blankp here)) (find-node here) here))
         (group (and (not (blankp here)) (not node) (find-group here) here))
         (back here))
    (unless (blankp text)
      (add-message! "you" (trim text) :node node)
      (handler-case
          (let* ((context (str (map-context) #\Newline #\Newline
                               (when group (str "The learner is looking at group: " group #\Newline #\Newline))
                               (when node (str (node-context node) #\Newline (attempts-context node) #\Newline #\Newline))
                               (conversation-context) #\Newline #\Newline
                               "Learner says:" #\Newline (trim text)))
                 (r (ask-structured 'converse context :search (not (blankp search)))))
            (multiple-value-bind (changes focus) (apply-changes! r)
              (add-message! "buddy" (strip-quotes (getf r :reply)) :node node :changes changes)
              (when focus (setf back focus))))
        (llm-error (e)
          (add-message! "error" (llm-error-message e) :node node))))
    (redirect (focus-url back))))

;;; ---- Write: check an explanation ---------------------------------------

(defprompt check-explanation
  :system (str "You are checking a learner's written explanation of one idea from a knowledge map." #\Newline
               *rules* #\Newline
               "Judge only what is written. Do not supply what the learner probably meant. "
               "Name the single most important missing idea first in the missing list. "
               "Be concrete and short: each item one sentence. "
               "The verdict is one or two plain sentences on whether this explanation would let the learner rebuild the idea from scratch. "
               "suggested-level: 0 not yet, 1 shaky, 2 can explain, 3 can teach — advisory only.")
  :schema (:object (:right (:array :string) "what the learner got right")
                   (:missing (:array :string) "what a correct explanation needs that is absent; most important first")
                   (:wrong (:array :string) "claims that are false or confused")
                   (:verdict :string)
                   (:suggested-level :integer)))

(defun clean-feedback (fb)
  (list :right (mapcar #'strip-quotes (getf fb :right))
        :missing (mapcar #'strip-quotes (getf fb :missing))
        :wrong (mapcar #'strip-quotes (getf fb :wrong))
        :verdict (strip-quotes (getf fb :verdict))
        :suggested-level (getf fb :suggested-level)))

(defaction attempt "/action/attempt" (map-name node-id text)
  (unless (select-map map-name) (return-from attempt (not-found "field")))
  (unless (blankp text)
    (handler-case
        (let ((feedback (ask-structured 'check-explanation
                                        (str "Field: " (map-title) #\Newline (node-context node-id) #\Newline
                                             "Learner wrote:" #\Newline text))))
          (add-attempt! node-id (trim text) (clean-feedback feedback)))
      (llm-error (e) (add-message! "error" (llm-error-message e) :node node-id))))
  (redirect (node-url node-id)))

;;; ---- Rate (plain) -------------------------------------------------------

(defaction rate "/action/rate" (map-name node-id level)
  (unless (select-map map-name) (return-from rate (not-found "field")))
  (set-level! node-id (parse-integer level))
  (redirect (node-url node-id)))

;;; ---- Hand edits (plain) ---------------------------------------------------

(defaction edit-node "/action/edit-node" (map-name node-id title compression why notes group prereqs era)
  (unless (select-map map-name) (return-from edit-node (not-found "field")))
  (update-node! (list :id node-id :title title :compression compression :why why :notes notes
                      :group group :prereqs prereqs :era era))
  (redirect (node-url node-id)))

(defaction add-node "/action/add-node" (map-name title group)
  (unless (select-map map-name) (return-from add-node (not-found "field")))
  (let ((n (add-node! (list :title title :group (if (blankp group) "misc" group)))))
    (redirect (if n (node-url (getf n :id)) (field-url)))))

(defaction remove-node "/action/remove-node" (map-name node-id)
  (unless (select-map map-name) (return-from remove-node (not-found "field")))
  (let ((group (getf (find-node node-id) :group)))
    (remove-node! node-id)
    (redirect (if group (group-url group) (field-url)))))

(defaction about "/action/about" (text)
  (set-about-text! (or text ""))
  (redirect "/"))

;;; ---- Seed a field: breadth first, with web search ------------------------

(defprompt seed-map
  :system (str "You design a knowledge map of a field for one self-directed learner: the core ideas, in prerequisite order, that let them rebuild the field from first principles." #\Newline
               *rules* #\Newline
               "Breadth first: cover the whole field at one level of depth rather than any part deeply. "
               "Use web search to check the ideas and dates against primary sources. "
               "groups: five to eight, each a lowercase-slug id and a one-sentence compression, ordered so prerequisites flow from the first group to the last. "
               "nodes: twenty-five to forty ideas, four to six per group, each with the schema fields; notes empty; prereqs are ids of other nodes in this map only; era is the year the idea was first had. "
               "title: the field's short title. compression: the field in one sentence.")
  :schema (:object (:title :string)
                   (:compression :string)
                   (:groups (:array (:object (:id :string) (:compression :string))))
                   (:nodes (:array #.*node-schema*))))

(defaction seed "/action/seed" (field note)
  (when (blankp field) (return-from seed (redirect "/fields")))
  (let ((id (slugify field)))
    (when (map-exists-p id) (setf id (str id "-" (get-universal-time))))
    (let ((r (ask-with-search 'seed-map
                              (str "Field: " field #\Newline
                                   "Learner's note (what they already know, and why they want it): " (or note "") #\Newline
                                   "Map id: " id))))
      (write-map! id (getf* r :title field) (getf r :compression)
                  (mapcar (lambda (g) (list :id (slugify (getf g :id)) :compression (getf g :compression)))
                          (getf r :groups))
                  (mapcar #'normalise-node (getf r :nodes)))
      (redirect (field-url id)))))
