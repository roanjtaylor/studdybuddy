;;;; Entry points. (studybuddy:start) opens http://localhost:8080/ ; (studybuddy:stop).

(in-package :studybuddy)

(defun start (&key (port *port*) (open t))
  "Load data, read the relay settings from the environment, start the server."
  (configure-llm)
  (load-all-stores)
  (start-server :port port :open open)
  (format t "~&studybuddy: http://localhost:~a/  fields=~a  relay=~a  secret=~a~%"
          port (list-maps) *server-url* (if *app-secret* "set" "NOT SET"))
  *server*)

(defun stop ()
  (stop-server))
