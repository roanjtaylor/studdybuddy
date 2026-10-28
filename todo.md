# StudyBuddy in Lisp — MVP spec and build list

Status: spec, 28 Oct 2026. Owner: Roan.

StudyBuddy v2 is a knowledge map where understanding is proven by writing: you pick an idea, write your explanation of it cold, get feedback naming what is right, missing and wrong, and rate yourself. v1 (the Next.js source hunter) stays as a reference; v2 is a fresh Common Lisp program, built bottom-up, that grows out of the current `viaweb` system.

This document is the to-do list. Work top to bottom. Every task has a done-test; a task is done when its test passes in the REPL or the browser, not before.

---

## 0. Rules the program must obey

1. Theory from the originator, products by using them. Sources are primary.
2. Ideas, not tools. A node is an idea with a one-sentence compression.
3. Nothing is understood until written out and checked. The Attempt is the core object; levels are set by hand after feedback, never by the model.
4. Bottom-up. Each layer is a small language the layer above is written in. If a function in the app layer is longer than a screen, the missing operator belongs in a lower layer.
5. Local, personal, one user. Data is Lisp data in files. No accounts, no database server, no deployment.

---

## 1. The layers

Build in this order. Each layer has its own file and is tested on its own before the next starts.

| Layer | File | Gives the layer above | Done when |
| --- | --- | --- | --- |
| L0 Utilities | `src/util.lisp` | `with-gensyms`, `mkstr`, `symb`, string/list helpers, `now-iso` | Each utility has a one-line REPL test |
| L1 HTML | `src/html.lisp` | `html` macro: s-expressions in, HTML string out, auto-escaped | `(html (:p "a<b"))` → `<p>a&lt;b</p>` |
| L2 Web | `src/web.lisp` | `defpage`, `defaction`, `start`, `stop`, `layout` | A `defpage` form is live in Chrome without restart |
| L3 Store | `src/store.lisp` | `defstore`, `save`, `load-all`, `find-by`, `put!` | Data survives `stop`/`start` and a fresh image |
| L4 Model | `src/llm.lisp` | `defprompt`, `ask`, `ask-structured` (tool-use schemas) | `(ask-structured 'check ...)` returns a plist, never prose |
| L5 App | `src/nodes.lisp`, `src/pages.lisp`, `src/actions.lisp` | Node, Map, Attempt, Card; the three screens; six AI actions | The learning loop works end to end |
| Seed | `data/maps/computers.lisp` | The first map | Map renders with all nodes grey |

---

## 2. Project layout

```
studybuddy/
  studybuddy.asd
  src/
    package.lisp
    util.lisp
    html.lisp
    web.lisp
    store.lisp
    llm.lisp
    nodes.lisp
    pages.lisp
    actions.lisp
    main.lisp
  data/
    maps/computers.lisp      ; the map: groups + nodes
    attempts.lisp            ; append-only
    cards.lisp               ; v1-style study cards keyed by node id
    levels.lisp              ; node-id → level, written on each rating
  static/
    style.css
    map.js                   ; only for pan/zoom on the SVG; nothing else
```

- [x] Rename or copy the existing `viaweb` system to `studybuddy` (keep Viaweb separate; this is a sibling system that reuses what you learned).
- [x] `studybuddy.asd` with `:depends-on (:hunchentoot :dexador :com.inuoe.jzon :uiop)` and `:serial t` over the files above in order.
- [x] `src/package.lisp`: `(defpackage :studybuddy (:use :cl) (:export #:start #:stop))`.
- [x] `(ql:quickload :studybuddy)` loads clean with no warnings.

Done-test: `(studybuddy:start)` opens Chrome at `http://localhost:8080/` showing a placeholder page.

---

## 3. L0 — Utilities

The small operators you will wish Lisp had. Add to this file every time you write the same three lines twice.

- [x] `with-gensyms` (standard macro hygiene helper).
- [x] `mkstr` and `symb` (On Lisp §4.3): build strings and symbols from parts.
- [x] `str` — `(str "a" 1 :b)` → `"a1B"`; concatenation without `format` noise.
- [x] `now-iso` → `"2026-10-28T13:54:00"` via `get-decoded-time`.
- [x] `slugify` — `"Fetch-decode-execute loop"` → `"fetch-decode-execute-loop"`.
- [x] `getf*` — `getf` with a default.
- [x] `read-file-forms` / `write-file-forms` — read all forms from a file; write a list of forms with `*print-readably*` on. These are the whole persistence layer.

Done-test: each one has a one-line call in a comment above it showing input and output, and the call returns that output at the REPL.

---

## 4. L1 — HTML as s-expressions

The first real bottom-up move. HTML is a tree; Lisp writes trees. One macro and you never type an angle bracket again.

```lisp
(html
  (:div :class "node"
    (:h1 title)
    (:p :class "quiet" compression)
    (dolist (p prereqs) (html (:a :href (str "/node/" p) p)))))
```

- [x] `escape` — `&`, `<`, `>`, `"` → entities.
- [x] `html` macro: a form `(:tag attrs... children...)` where keyword/value pairs before the first non-keyword are attributes; strings are escaped; symbols and other forms are evaluated and their result escaped; `(:raw s)` inserts unescaped. Output is written to `*html-out*`, a string stream bound by the outermost call.
- [x] Void elements (`br`, `img`, `input`, `meta`, `link`) emit no closing tag.
- [x] `defcomponent` — `(defcomponent button (text &key href) (html (:a :class "btn" :href href text)))`; a component call inside `html` splices its output.

Done-test: `(html (:ul (dolist (x '(1 2)) (html (:li x)))))` → `<ul><li>1</li><li>2</li></ul>`, and a string with `<script>` in it comes out escaped.

Why not cl-who or spinneret: using them is fine later, but writing your own 60-line version is the fastest way to feel the "build the language up" idea, and you will know exactly what it does when it breaks.

---

## 5. L2 — Web

Wrap Hunchentoot so a page is one form.

```lisp
(defpage node-page "/node/:id" (id)
  (let ((node (find-node id)))
    (layout (node-title node)
      (node-view node))))

(defaction rate "/action/rate" (node-id level)
  (set-level! node-id (parse-integer level))
  (redirect (str "/node/" node-id)))
```

- [x] `*server*`, `start`, `stop`, `open-browser` — carry over from Viaweb, with `start` idempotent (calling it twice restarts cleanly).
- [x] `defpage name path (params) body` — expands to a Hunchentoot easy-handler; `:id` segments in the path become bound variables; query params with the same names also bind. Returns the body's string.
- [x] `defaction name path (params) body` — same, POST only, params from the form body. Every action ends with `redirect`.
- [x] `layout title &rest body` — the one page shell: `<head>` with `style.css`, a top bar with links to Map and Timeline, the body, nothing else.
- [x] `static/` served at `/static/` via `create-folder-dispatcher-and-handler`.
- [x] `redirect`, `param`, `not-found`.

Done-test: with the server running, change a `defpage` body, re-evaluate only that form in Alive, refresh Chrome, see the change. No restart. This is the test that the whole project rests on.

---

## 6. L3 — Store

Persistence is Lisp's reader and printer. A data file is a list of plists you can read in any editor and edit by hand.

```lisp
(defstore attempt (:file "data/attempts.lisp" :key :id :append t))
(defstore level   (:file "data/levels.lisp"   :key :node-id))
```

- [x] `defstore name (&key file key append)` — defines `<name>s` (in-memory list), `load-<name>s`, `save-<name>s`, `find-<name>` by key, and `put-<name>!` which replaces by key (or appends when `:append t`) and saves. The in-memory list is the truth while the image runs; the file is written on every `put!`.
- [x] `load-all-stores` called from `start`.
- [x] Maps are read-only data files under `data/maps/`; `load-map "computers"` reads the forms and returns the map plist. Editing a map = editing the file and calling `load-map` again.
- [x] A `*data-dir*` so tests can point at a temp folder.

Done-test: `(put-attempt! (list :id (now-iso) :node-id "transistor" :text "..."))`, then `stop`, kill SBCL, start a fresh image, `start`, and `(find-attempt ...)` returns it.

---

## 7. L4 — Model

One function talks to the API; a macro defines prompts as data; structured outputs come back as plists through tool use so the UI never sees free prose.

```lisp
(defprompt check-explanation
  :system "You are checking a learner's written explanation of one idea. ..."
  :schema (:object
            (:right   (:array :string))
            (:missing (:array :string))
            (:wrong   (:array :string))
            (:verdict :string)
            (:suggested-level :integer)))

(ask-structured 'check-explanation
  (str "Idea: " compression #\Newline "Learner wrote: " text))
```

- [x] `*api-key*` read from the env var `ANTHROPIC_API_KEY` at `start`; never in a file.
- [x] `*model*` as a defvar you set once; the model id comes from the Claude docs, not from this spec.
- [x] `messages-request` — one `dexador:post` to the Messages API (`https://api.anthropic.com/v1/messages`, headers `x-api-key` and `anthropic-version`, JSON body with `model`, `max_tokens`, `system`, `messages`, optional `tools` and `tool_choice`). Parses the response with jzon. Errors surface as a Lisp condition with the HTTP body attached. See https://docs.claude.com for the exact request shape before writing this.
- [x] `defprompt name &key system schema` — stores system text and a schema written in the small s-expression form above.
- [x] `schema->json` — turns the s-expression schema into a JSON Schema object for a tool definition.
- [x] `ask name user-text` — plain call, returns the text.
- [x] `ask-structured name user-text` — sends one tool built from the schema, forces it with `tool_choice`, and returns the tool input as a plist. If the response has no tool call, signal an error; never fall back to parsing prose.
- [x] `ask-with-search` — same as `ask-structured` but with the web search tool enabled, for source hunting and map seeding. Check the docs for how the search tool is declared.
- [x] Subscription option, later: if you want calls to draw on the Claude plan rather than API credit as v1 did, `sb-ext:run-program` can call the `claude` CLI in print mode with JSON output. Not for v1.

Done-test: `(ask-structured 'check-explanation "Idea: a transistor is a switch controlled by a switch. Learner wrote: it's a thing that makes computers fast")` returns a plist whose `:missing` list is non-empty.

---

## 8. L5 — The app

### 8.1 Data (`nodes.lisp`)

A node is a plist in the map file. Levels and attempts live in their own stores so the map file stays a clean, hand-editable description of the field.

```lisp
(:id "flip-flop" :title "Flip-flop as one bit of memory"
 :compression "Two gates wired in a loop hold a value until pushed."
 :why "This is one bit of RAM. Memory is just a loop."
 :group "switches" :prereqs ("logic-gates") :era 1918)
```

- [x] `load-map`, `map-nodes`, `map-groups`, `find-node id`.
- [x] `node-level id` → 0 when unset. `set-level! id n`.
- [x] `node-attempts id` → newest first. `add-attempt! id text feedback`.
- [x] `node-card id` / `set-card!` — v1-style card plist: `:principles` and `:sources`, each source `(:title :url :blurb)`.
- [x] `prereqs-met-p id` — every prereq at level ≥ 2.
- [x] `grey-frontier` — nodes at level 0 whose prereqs are met. This is what the map should pull you toward.

### 8.2 Pages (`pages.lisp`)

Three screens, each one `defpage`, each built from `defcomponent`s.

- [x] **Map** `/` — one inline SVG. Columns = groups in map order; rows = prerequisite depth within a group. A rect per node, fill by level (0 grey, 1 pale, 2 mid, 3 full accent), title inside, a line per prereq. Frontier nodes get a thicker border. `map.js` adds pan/zoom only.
- [x] **Timeline** `/timeline` — the same nodes sorted by `:era`, one row each, group as a tag. Plain HTML list; no SVG needed.
- [x] **Node** `/node/:id` — compression in large type; `:why`; prereq links with their levels; the writing box (a `<textarea>` with no placeholder text and no sources visible); attempt history with feedback as three lists; the level selector; the card as a sources panel or a "hunt sources" button; a study column (8.3).
- [x] Each page passes the done-test of L2: editable live.

### 8.3 Actions (`actions.lisp`)

Six AI actions plus two plain ones. Every AI action is one `defprompt` and one `defaction`; the action calls `ask-structured`, stores the result, redirects back to the node.

| Action | Route | Prompt input | Schema | Stores |
| --- | --- | --- | --- | --- |
| Rate | `POST /action/rate` | — | — | level |
| Write | `POST /action/attempt` | node compression + prereq compressions + text | `right missing wrong verdict suggested-level` | attempt with feedback |
| Questions | `POST /action/questions` | node + past attempts | `questions[]` | shown on the node page only |
| Quiz | `POST /action/quiz` | node (+ neighbours) | `questions[] (prompt options answer explanation)` | shown only |
| Gaps | `POST /action/gaps` | whole map with levels + latest verdicts | `weak-nodes[] missing-nodes[]` | shown on the map page as proposals |
| Hunt sources | `POST /action/hunt` | node title + compression, with search | v1 card schema | card |
| Seed map | `POST /action/seed` | field name + background note, with search | `groups[] nodes[]` | writes `data/maps/<field>.lisp` |
| Accept gap | `POST /action/accept-node` | a proposed node | — | appends to the map file |

- [x] Every prompt's system text carries the three rules from §0.
- [x] The Write prompt also says: judge only what is written, do not supply what the learner meant, name the single most important missing idea first.
- [x] The level is never changed by an action other than Rate.

Done-test (the MVP): open a grey node, write an explanation, submit, see right/missing/wrong under it, set the level, return to the map and see the colour change. Then `stop`, `start`, and it is all still there.

---

## 9. Seed map: `data/maps/computers.lisp`

Write this by hand first; the seed action exists for the second field. Seven groups, each with its compression, in this order (prerequisite order flows top to bottom and across groups). Give every node `:id`, `:title`, `:compression`, `:why`, `:group`, `:prereqs`, `:era`.

| Group id | Compression | Nodes (ids) |
| --- | --- | --- |
| `switches` | A switch can control another switch. | transistor · logic-gates · adder · clock · flip-flop · ram |
| `stored-program` | Instructions are data in the same memory. | fetch-decode-execute · registers-pc · instruction-set · machine-code-assembly · reset-vector-bootstrap · code-and-data-alike |
| `loaders` | Every layer is a program that loads the next. | firmware-uefi · bootloader · kernel · drivers · shell · editor · lisp-image |
| `sharing` | Many programs share one machine. | processes-threads · scheduler · virtual-memory · files · syscall-boundary · os-as-referee |
| `languages` | Languages are compressions over machine code. | compiler-vs-interpreter · call-stack · garbage-collection · code-as-data · image-and-repl · types |
| `network` | Machines talk. | packets-ip · tcp · sockets · http · browser-as-renderer · client-server · web-as-app-platform |
| `learned` | Programs can be found, not written. | neuron-weighted-sum · gradient-training · transformer · next-token · model-as-loop-plus-weights · gpu-inference · wrapper-as-app-layer |

- [x] File written, 45 nodes, every prereq id resolves (`check-map` function that reports dangling ids).
- [ ] First use: rate every node honestly from A-level CS plus Squadova; run Gaps; read the result and leave it as a note on the map page.

---

## 10. Build order

Four weekends. Each ends with something used the following week.

- [ ] **Weekend 1 — L0 to L3.** Utilities, the `html` macro, `defpage`/`defaction`, the store. End state: the node page renders from the seed file, the writing box saves attempts with no feedback yet. Start writing explanations cold anyway; they are the first real data.
- [ ] **Weekend 2 — L4 and Write.** `ask-structured`, the check-explanation prompt, feedback under attempts, the Rate action. End state: the loop works. This is the MVP.
- [ ] **Weekend 3 — Map and sources.** The SVG map with level colours and the frontier, the timeline, Hunt sources wiring the v1 card into the node page.
- [ ] **Weekend 4 — Study column and gaps.** Questions, Quiz, Gaps with accept-node, Seed map for a second field (do not use it yet).

After a month of daily use, write the v2 spec from the attempts file, not from imagination.

---

## 11. Out of scope for v1

- Accounts, sharing, hosting, HTTPS.
- Automatic level changes, spaced repetition, streaks.
- Saved chat transcripts. Attempts and notes are the record.
- Embedded video or interactive visuals in nodes; a pin is a link.
- A second field before the computer map has been used for three months.
- Porting v1's Next.js code. v1 stays as it is; the card schema is the only thing carried over.

---

## 12. Running it

```lisp
(ql:quickload :studybuddy)
(studybuddy:start)          ; opens http://localhost:8080/
;; edit any defpage / defaction / defprompt, re-evaluate the form, refresh
(studybuddy:stop)
```

`ANTHROPIC_API_KEY` must be set in the environment SBCL was started from. Data lives in `data/`; back it up by copying the folder.

---

## 13. Bottom-up checkpoints

At the end of each weekend, answer in a note at the top of `main.lisp`:

1. Which function in L5 got shorter because of an operator added to a lower layer this week?
2. Which three lines did I write twice, and what is the operator that removes them?
3. What did the live image let me do that a restart-based workflow would not have?

If the answers are empty two weekends running, the program is being written top-down, and the point of doing this in Lisp is being missed.