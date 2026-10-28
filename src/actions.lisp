;;;; L5c — Actions. Every AI action is one defprompt and one defaction: build the
;;;; context, call ask-structured, store or show the result, redirect back.
;;;; The level is never changed by any action but Rate.

(in-package :studybuddy)

(defparameter *rules*
  "Rules you must obey:
1. Theory is learned from the originator, products by using them. Sources are primary: the original paper, essay, lecture, or an authoritative textbook chapter. Never a blog post about the blog post.
2. Ideas, not tools. A node is one idea with a one-sentence compression.
3. Nothing is understood until it has been written out and checked. The learner's own written attempt is the core object. You never set the learner's level; you only give evidence.")

;; Read-time available (#.) so the prompt schemas below can splice it in.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *node-schema*
    '(:object (:id :string "lowercase slug, hyphens only")
              (:title :string "a short name for the idea, five words or fewer")
              (:compression :string "one sentence that compresses the idea")
              (:why :string "one or two sentences on why it matters")
              (:group :string "group id this node belongs to")
              (:prereqs (:array :string) "ids of ideas that must be understood first")
              (:era :integer "year the idea was first had; negative for BC"))))

;;; ---- Context builders --------------------------------------------------

(defun node-context (id)
  (let* ((n (find-node id)) (g (find-group (getf n :group))))
    (str "Map: " (map-title) " — " (getf *map* :compression) #\Newline
         "Group: " (getf n :group) " — " (getf g :compression) #\Newline
         "Idea: " (getf n :title) #\Newline
         "Compression: " (getf n :compression) #\Newline
         "Why it matters: " (getf n :why) #\Newline
         (when (getf n :prereqs)
           (str "Prerequisite ideas:" #\Newline
                (join #\Newline
                      (mapcar (lambda (p) (let ((pn (find-node p)))
                                            (str "  - " (if pn (getf pn :title) p) ": "
                                                 (if pn (getf pn :compression) "(not in map)"))))
                              (getf n :prereqs)))
                #\Newline)))))

(defun attempts-context (id &optional (limit 3))
  (let ((as (subseq (node-attempts id) 0 (min limit (length (node-attempts id))))))
    (if as
        (str "Learner's past attempts, newest first:" #\Newline
             (join #\Newline
                   (mapcar (lambda (a)
                             (str "--- " (getf a :at) #\Newline (getf a :text) #\Newline
                                  "Verdict then: " (getf (getf a :feedback) :verdict)))
                           as)))
        "The learner has not written about this idea yet.")))

(defun map-context ()
  (str "Map: " (map-title) " — " (getf *map* :compression) #\Newline
       "Groups:" #\Newline
       (join #\Newline (mapcar (lambda (g) (str "  " (getf g :id) ": " (getf g :compression))) (map-groups)))
       #\Newline "Nodes (id | group | level 0-3 | prereqs | latest verdict):" #\Newline
       (join #\Newline
             (mapcar (lambda (n)
                       (let ((id (getf n :id)))
                         (str "  " id " | " (getf n :group) " | " (node-level id) " | "
                              (join "," (getf n :prereqs)) " | "
                              (or (getf (getf (latest-attempt id) :feedback) :verdict) "no attempt"))))
                     (map-nodes)))))

;;; ---- Rate (plain) -------------------------------------------------------

(defaction rate "/action/rate" (node-id level)
  (set-level! node-id (parse-integer level))
  (redirect (str "/node/" node-id)))

;;; ---- Intro seen (plain) -------------------------------------------------

(defaction intro-done "/action/intro-done" ()
  (set-setting! "intro-seen" t)
  (redirect "/"))

;;; ---- Write --------------------------------------------------------------

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

(defaction attempt "/action/attempt" (node-id text)
  (unless (blankp text)
    (let ((feedback (ask-structured 'check-explanation
                                    (str (node-context node-id) #\Newline
                                         "Learner wrote:" #\Newline text))))
      (add-attempt! node-id (trim text) (clean-feedback feedback))))
  (redirect (str "/node/" node-id)))

;;; ---- Questions ---------------------------------------------------------

(defprompt questions
  :system (str "You set questions that force a learner to write out one idea properly." #\Newline
               *rules* #\Newline
               "Give five questions, each answerable in a paragraph of writing, ordered from the one that exposes the biggest gap in the learner's past attempts to the most refined. "
               "Questions about mechanism, not vocabulary. No yes/no questions.")
  :schema (:object (:questions (:array :string))))

(defaction questions "/action/questions" (node-id)
  (let ((r (ask-structured 'questions (str (node-context node-id) #\Newline (attempts-context node-id)))))
    (set-scratch! (node-ref node-id) :questions (getf r :questions)))
  (redirect (str "/node/" node-id)))

;;; ---- Quiz ----------------------------------------------------------------

(defprompt quiz
  :system (str "You write a short multiple-choice quiz on one idea and its neighbours in a knowledge map." #\Newline
               *rules* #\Newline
               "Five questions. Four options each, exactly one correct; the answer field repeats the correct option's text exactly. "
               "Wrong options must be plausible confusions, not jokes. The explanation says why the right one is right in one sentence.")
  :schema (:object (:questions (:array (:object (:prompt :string)
                                                (:options (:array :string))
                                                (:answer :string)
                                                (:explanation :string))))))

(defun neighbours-context (id)
  (let ((d (dependents id)))
    (when d
      (str "Ideas that build on this one:" #\Newline
           (join #\Newline (mapcar (lambda (m) (str "  - " (getf m :title) ": " (getf m :compression))) d))))))

(defaction quiz "/action/quiz" (node-id)
  (let ((r (ask-structured 'quiz (str (node-context node-id) #\Newline (neighbours-context node-id)))))
    (set-scratch! (node-ref node-id) :quiz (getf r :questions)))
  (redirect (str "/node/" node-id)))

;;; ---- Gaps ----------------------------------------------------------------

(defprompt gaps
  :system (str "You review a learner's whole knowledge map: every idea, their self-rated level and the verdict on their latest written attempt." #\Newline
               *rules* #\Newline
               "weak-nodes: ideas rated 2 or 3 whose verdict or prerequisites suggest the rating is optimistic, or ideas whose low level blocks the most other ideas. Give the node id exactly as listed and a one-sentence reason. At most six. "
               "missing-nodes: ideas the map needs but does not have, each as a full node with a group id from the list and prerequisites from the existing ids. At most six. "
               "Prefer fewer, sharper proposals.")
  :schema (:object (:weak-nodes (:array (:object (:id :string) (:reason :string))))
                   (:missing-nodes (:array #.*node-schema*))))

(defaction gaps "/action/gaps" (map-name)
  (declare (ignore map-name))
  (let ((r (ask-structured 'gaps (map-context))))
    (set-scratch! (map-id) :gaps r))
  (redirect "/"))

;;; ---- Hunt sources (the v1 card) ---------------------------------------

(defprompt hunt-sources
  :system (str "You are a source hunter for a self-directed learner. Given one idea, find the canonical primary sources and the first principles behind it." #\Newline
               *rules* #\Newline
               "Use web search to verify that each source exists and that the URL is the original or the most authoritative copy. "
               "principles: three to five first principles, each one sentence. "
               "sources: three to five canonical sources — the original paper, essay, lecture, or authoritative textbook chapter. "
               "Each source's blurb is three to five sentences giving the gist so the learner has it before clicking through. "
               "Reject listicles, tutorials, marketing, and summaries of summaries.")
  :schema (:object (:principles (:array :string))
                   (:sources (:array (:object (:title :string) (:url :string) (:blurb :string))))))

(defaction hunt "/action/hunt" (node-id)
  (let ((r (ask-with-search 'hunt-sources (node-context node-id))))
    (set-card! node-id (getf r :principles) (getf r :sources)))
  (redirect (str "/node/" node-id)))

;;; ---- Expand a node into sub-ideas -------------------------------------

(defprompt expand
  :system (str "You break one idea in a knowledge map into the three to six sub-ideas a learner must write out to truly own it." #\Newline
               *rules* #\Newline
               "Each child is a node: an idea, not a topic heading; a one-sentence compression; why it matters. "
               "Every child lists the parent id among its prereqs, plus any existing map ids it needs. "
               "Use the parent's group id unless a listed group fits better. "
               "Go one level deeper than the parent, not several; breadth first.")
  :schema (:object (:children (:array #.*node-schema*))))

(defaction expand "/action/expand" (node-id)
  (let ((r (ask-structured 'expand
                           (str (node-context node-id) #\Newline
                                "Parent id: " node-id #\Newline
                                "Existing ids in this map: " (join ", " (mapcar (lambda (n) (getf n :id)) (map-nodes)))
                                #\Newline "Group ids: " (join ", " (mapcar (lambda (g) (getf g :id)) (map-groups)))))))
    (set-scratch! (node-ref node-id) :children (getf r :children)))
  (redirect (str "/node/" node-id)))

;;; ---- Accept a proposed node (plain) ------------------------------------

(defaction accept-node "/action/accept-node" (id title compression why group prereqs era)
  (let ((node (normalise-node (list :id id :title title :compression compression :why why
                                    :group group :prereqs (split #\, (or prereqs "")) :era era))))
    (unless (find-node (getf node :id))
      (append-node! node))
    (redirect (str "/node/" (getf node :id)))))

;;; ---- Seed a map ---------------------------------------------------------

(defprompt seed-map
  :system (str "You design a knowledge map of a field for one self-directed learner: the ideas, in prerequisite order, that let them rebuild the field from first principles." #\Newline
               *rules* #\Newline
               "Use web search to check the ideas and dates against primary sources. "
               "groups: five to eight, each a lowercase-slug id and a one-sentence compression, ordered so prerequisites flow from the first group to the last. "
               "nodes: thirty to fifty ideas, five to eight per group, each with the schema fields; prereqs are ids of other nodes in this map only; era is the year the idea was first had. "
               "title: the map's short title. compression: the field in one sentence.")
  :schema (:object (:title :string)
                   (:compression :string)
                   (:groups (:array (:object (:id :string) (:compression :string))))
                   (:nodes (:array #.*node-schema*))))

(defaction seed "/action/seed" (field note)
  (let* ((id (slugify field))
         (r (ask-with-search 'seed-map
                             (str "Field: " field #\Newline
                                  "Learner's note: " (or note "") #\Newline
                                  "Map id: " id))))
    (when (map-exists-p id) (setf id (str id "-" (get-universal-time))))
    (write-map! id (getf* r :title field) (getf r :compression)
                (mapcar (lambda (g) (list :id (slugify (getf g :id)) :compression (getf g :compression)))
                        (getf r :groups))
                (mapcar #'normalise-node (getf r :nodes)))
    (load-map id)
    (redirect "/")))
