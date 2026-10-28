(asdf:defsystem "studybuddy"
  :description "StudyBuddy: a map of each field's core ideas, with Claude inside it to answer, quiz and reshape the map as you learn."
  :author "Roan Taylor"
  :depends-on ("hunchentoot" "dexador" "com.inuoe.jzon" "uiop")
  :serial t
  :pathname "src/"
  :components ((:file "package")
               (:file "util")
               (:file "html")
               (:file "web")
               (:file "store")
               (:file "llm")
               (:file "nodes")
               (:file "pages")
               (:file "actions")
               (:file "main")))
