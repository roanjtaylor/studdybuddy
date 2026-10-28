(asdf:defsystem "studybuddy"
  :description "StudyBuddy v2: a knowledge map where understanding is proven by writing."
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
