(:MAP :ID "library" :TITLE "Library" :COMPRESSION
 "Topics hunted with v1: first principles and primary sources, one card each.")
(:GROUP :ID "hunted" :COMPRESSION "Ideas whose originators have been found.")
(:NODE :ID "claude-code-and-openclaw" :TITLE "Claude Code and OpenClaw" :COMPRESSION
 "The agent loop is the atom: an LLM in a loop that reads state, takes an action via a tool (shell, file edit, message), observes the result, and repeats until a goal is met. Both Claude Code and OpenClaw are this loop wrapped in a 'harness' — strip away the UI and you find the same primitive."
 :WHY
 "Claude Code is an unopinionated agentic harness; you get the most from it by engineering its context (CLAUDE.md), making it plan before coding, and treating it as a teammate you direct rather than an autocomplete."
 :GROUP "hunted" :PREREQS NIL :ERA NIL)
(:NODE :ID "agentic-engineering" :TITLE "Agentic Engineering" :COMPRESSION
 "An agent is a function that maps a percept sequence (observations from an environment) to actions. Intelligence is not magic — it is the disciplined selection of the action that maximizes expected success given what has been perceived. This 'rational agent' formulation (Russell & Norvig) is the bedrock from which every modern LLM agent is just a specific instantiation."
 :WHY
 "Intelligence is rational action: an agent maps perceptions to the action that maximizes expected success, and agent architectures form a ladder from reflex to learning."
 :GROUP "hunted" :PREREQS NIL :ERA NIL)
(:NODE :ID "large-language-models" :TITLE "Large Language Models" :COMPRESSION
 "Language modeling is next-token prediction: an LLM is trained to estimate the probability of the next token given prior tokens. All capabilities — translation, reasoning, coding, dialogue — emerge as side effects of compressing text well enough to predict it. Master this objective and most of the field re-derives from it."
 :WHY
 "Replace recurrence/convolution with self-attention so every token can directly and in parallel attend to every other token, enabling scalable training and long-range context."
 :GROUP "hunted" :PREREQS NIL :ERA NIL)
(:NODE :ID "stripe-payment-processor" :TITLE "Stripe payment processor" :COMPRESSION
 "Networks fail in unpredictable ways, so any API that mutates state with money attached must be idempotent — the same operation invoked any number of times must produce the same side effect exactly once. Idempotency keys are the canonical mechanism: client generates a unique ID, server stores the result and replays it for retries."
 :WHY
 "Networks are unreliable; idempotency keys + safe retries + backoff are the minimum viable kit for building robust APIs that move money."
 :GROUP "hunted" :PREREQS NIL :ERA NIL)
(:NODE :ID "databases" :TITLE "databases" :COMPRESSION
 "Data independence: applications and queries should be insulated from how data is physically stored, indexed, or laid out — change the storage, the queries still work."
 :WHY
 "Separate the logical view of data (sets of tuples in relations) from its physical storage, and query it declaratively via a closed algebra over relations."
 :GROUP "hunted" :PREREQS NIL :ERA NIL)
