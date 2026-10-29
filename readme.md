# studybuddy

Study the core ideas of a field, not the infinite examples of them. A map of each field, a study buddy (Claude) living inside the map, and one loop: create a field, see its breadth, go deep where it matters, hone it over time. The full articulation lives on the home page (`data/about.md`) and is edited there.

## The workflow

1. **Create a field** (`/fields`). Name it, say what you know and why you want it. The model researches it with web search and lays out the core ideas breadth first, in prerequisite order.
2. **See the whole field** (`/computers`), or one group of it (`/computers/switches`). Three tabs: **Map** (groups as boxes in prerequisite order), **Timeline** (years along the x axis, a lane per group) and **Interact** (the map in the left half, a chat with the model in the right). A **Breadth / Depth** switch sets how far in you look: breadth is the groups, depth is every idea. It is in the URL (`?view=timeline&depth=depth`); a whole field opens at breadth, a group at depth. Your levels colour the ideas.
3. **Interact** — the one channel to the model. Your words go with the map, where you are, your attempts and the recent conversation. The model answers in markdown *and* may change the map: add ideas, replace them (notes grow here), remove, regroup. What it changed is shown under its reply. Idea pages have their own ask box.
4. **Go deep** (`/computers/switches/ram`). Write your explanation cold, get right / missing / wrong, rate yourself by hand. Edit or remove the idea by hand if you prefer.

URLs are a directory, shown as a path under the nav: `studybuddy / fields / computers / switches / ram`. Pages: `/`, `/fields`, `/:field`, `/:field/:group`, `/:field/:group/:idea`; `/:field?around=<idea>` shows one idea with what it builds on and leads to. Actions: ask, attempt, rate, edit-node, add-node, remove-node, about, seed.

## Layers

Built bottom-up, one small language per layer, each live-editable from the REPL:

| Layer | File | Gives |
| --- | --- | --- |
| L0 | `src/util.lisp` | `str`, `join`, `slugify`, `now-iso`, `read-file-forms`/`write-file-forms` (the whole persistence layer) |
| L1 | `src/html.lisp` | the `html` macro: s-expressions in, escaped HTML out; `defcomponent`; `markdown->html` for the small subset the model writes |
| L2 | `src/web.lisp` | `defpage`, `defaction`, `layout`, `redirect`; routes are a table so a re-evaluated form is live |
| L3 | `src/store.lisp` | `defstore`: a list of plists in memory, mirrored to a file on every `put!` |
| L4 | `src/llm.lisp` | `defprompt`, `ask`, `ask-structured`, `ask-with-search` — structured answers as plists, never prose |
| L5 | `src/nodes.lisp`, `src/pages.lisp`, `src/actions.lisp` | Field, Node, Level, Attempt, Message; the pages; the `converse` prompt and `apply-changes!` |

## Data

Lisp data in files you can read and edit by hand. `data/maps/<field>.lisp` is the map: one `(:map …)`, then `(:group …)` and `(:node …)` forms, one per line; nodes carry `:notes` for depth grown over time. The model's edits rewrite this file. Everything that is yours lives beside it, keyed by `"<field>/<node-id>"`: `levels.lisp`, `attempts.lisp` (append-only), `messages.lisp` (the conversation per field, append-only), `settings.lisp`. `data/about.md` is the home page. Back it all up by copying the folder.

`data/library.json` and `data/cards.lisp` are the v1 export and its hunted sources; nothing reads them any more.

## Claude via the subscription relay

The app never holds an API key. Every model call is a POST to the ClaudeSubscription relay (`../hf-space`, deployed on Hugging Face Spaces), which runs the Claude Agent SDK on the Claude Code subscription. Structured output is enforced by the engine (`outputFormat: json_schema`) and comes back in a `structured` SSE event. Set in the environment SBCL starts from:

```
STUDYBUDDY_SERVER_URL=https://roanjtaylor-claudesubscription.hf.space   # default; or http://localhost:5174 when running hf-space locally
STUDYBUDDY_APP_SECRET=<the value of the Space secret studybuddySecretKey>
```

The Space sleeps when idle, so the first call after a pause is slow. Creating a field uses web search and takes minutes; ticking "search the web" on an ask does too. The form shows "thinking…" while it waits.

## Run it

```lisp
;; ~/.sbclrc already pushes this folder onto asdf:*central-registry*
(ql:quickload :studybuddy)
(studybuddy:start)              ; opens http://localhost:8080/
(in-package :studybuddy)        ; then edit any defpage / defaction / defprompt, re-evaluate, refresh
(studybuddy:stop)
```

Check a hand-edited map with `(load-map "computers")` then `(check-map)`.
