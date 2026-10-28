;;;; Entry points. (studybuddy:start) opens http://localhost:8080/ ; (studybuddy:stop).
;;;;
;;;; Bottom-up checkpoints (answer at the end of each weekend; see todo.md §13):
;;;;
;;;; Weekend 1 (build, 28 Oct 2026):
;;;;  1. Which L5 function got shorter because of a lower-layer operator?
;;;;     node-page: the SVG map, the proposals list and every button are
;;;;     defcomponents, and `post-button` replaced six hand-written forms.
;;;;  2. Which three lines were written twice, and what operator removed them?
;;;;     "find a plist by a key in a list" three times → defstore's find-<name>;
;;;;     "join strings with a separator" → join; "slug a model-given id" → normalise-node.
;;;;  3. What did the live image allow that a restart could not?
;;;;     Routes are a table keyed by name, so a defpage re-evaluated in Alive is the
;;;;     page on the next refresh, with the stores and the map still in memory.

(in-package :studybuddy)

(defun start (&key (port *port*) (open t) (map *default-map*))
  "Load data, read the relay settings from the environment, start the server."
  (configure-llm)
  (load-all-stores)
  (load-map map)
  (start-server :port port :open open)
  (format t "~&studybuddy: http://localhost:~a/  map=~a  relay=~a  secret=~a~%"
          port (map-id) *server-url* (if *app-secret* "set" "NOT SET"))
  *server*)

(defun stop ()
  (stop-server))
