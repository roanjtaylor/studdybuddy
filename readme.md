# studybuddy

A Common Lisp knowledge map where understanding is proven by writing. Spec and build list in `todo.md`.

v1 was a Next.js source hunter; it is gone from the tree (see git history before the Lisp rewrite). Its five hunted topics live on as the `library` map (`data/maps/library.lisp` plus `data/cards.lisp`), and its Pokémon intro is the `/intro` page.

## The learning loop

Pick an idea on the map, write your explanation of it cold, get feedback naming what is right, missing and wrong, rate yourself by hand, watch the map change colour. Then expand the idea into sub-ideas, quiz yourself, hunt the originator's sources, or ask the model where the whole map is weak.

Built bottom-up, one small language per layer, each live-editable from the REPL:

| Layer | File | Gives |
| --- | --- | --- |
| L0 | `src/util.lisp` | `str`, `join`, `slugify`, `now-iso`, `read-file-forms`/`write-file-forms` (the whole persistence layer) |
| L1 | `src/html.lisp` | the `html` macro: s-expressions in, escaped HTML out; `defcomponent` |
| L2 | `src/web.lisp` | `defpage`, `defaction`, `layout`, `redirect`; routes are a table so a re-evaluated form is live |
| L3 | `src/store.lisp` | `defstore`: a list of plists in memory, mirrored to a file on every `put!` |
| L4 | `src/llm.lisp` | `defprompt`, `ask`, `ask-structured`, `ask-with-search` — structured answers as plists, never prose |
| L5 | `src/nodes.lisp`, `src/pages.lisp`, `src/actions.lisp` | Node, Map, Attempt, Level, Card; Map / Timeline / Node / Maps screens; the actions |

Actions: Rate, Write (check an explanation), Questions, Quiz, Gaps (weak and missing nodes for the map), Hunt sources (v1 card, with web search), Expand (sub-ideas of one node), Accept node, Seed map (a new field, with web search).

Data is Lisp data in files you can read and edit by hand: `data/maps/<field>.lisp` (the map), `data/attempts.lisp` (append-only), `data/levels.lisp`, `data/cards.lisp`, `data/settings.lisp`. Back it up by copying the folder. `data/library.json` is the v1 export; `(import-v1-library)` rebuilds the library map from it.

### Claude via the subscription relay

The app never holds an API key. Every model call is a POST to the ClaudeSubscription relay (`../hf-space`, deployed on Hugging Face Spaces), which runs the Claude Agent SDK on the Claude Code subscription. Structured output is enforced by the engine (`outputFormat: json_schema`) and comes back in a `structured` SSE event. Set in the environment SBCL starts from:

```
STUDYBUDDY_SERVER_URL=https://roanjtaylor-claudesubscription.hf.space   # default; or http://localhost:5174 when running hf-space locally
STUDYBUDDY_APP_SECRET=<the value of the Space secret studybuddySecretKey>
```

The Space sleeps when idle, so the first call after a pause is slow. Web-searched actions (Hunt, Seed) take minutes; the browser tab just waits.

### Run it

```lisp
;; ~/.sbclrc already pushes this folder onto asdf:*central-registry*
(ql:quickload :studybuddy)
(studybuddy:start)              ; opens http://localhost:8080/
(in-package :studybuddy)        ; then edit any defpage / defaction / defprompt, re-evaluate, refresh
(studybuddy:stop)
```

Other maps: `(load-map "thermodynamics")` or visit `/maps`. Check a hand-edited map with `(check-map)`.
