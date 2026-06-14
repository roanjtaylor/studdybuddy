# studybuddy

A source hunter for self-directed learners. Type a topic, get the canonical primary sources — not the remix layer.

## Core truths

- **Theory is studied by reading the source.** Databases → Codd. Transformers → Faraday. Startups → Paul Graham. Read the originator, not the blog post about the blog post.
- **Products are studied by using them.** Supabase, Stripe, Vercel — no first principles, just docs. studybuddy is for *ideas*, not tools.
- Every topic produces a **study card**: 3–5 first principles + 3–5 canonical sources, each with a 3–5 sentence blurb so you have the gist before clicking through.

## How it works

- **Frontend** (`app/page.tsx`): single-page Next.js app. A topic input, a card view, and a localStorage-backed library you can export/import as JSON. First visit shows a Pokémon-styled intro that explains the two rules above.
- **API** (`app/api/study/route.ts`): POST `/api/study` with `{ topic }`. Runs Claude (`claude-opus-4-8`) through the **Claude Agent SDK** with two tools:
  - `WebSearch` (built-in SDK tool) to research the topic.
  - `submit_results` (in-process MCP tool with a strict zod schema) — the model **must** call this exactly once to deliver the study card. No prose answers.
- The system prompt rejects listicles/tutorials/marketing and prefers original papers, essays, lectures, and authoritative textbook chapters.
- Library persists in `localStorage` under `studybuddy.library.v1`. Nothing is stored server-side.

## Subscription auth (not the API)

The research runs on the Agent SDK authenticated by a **Claude Pro/Max subscription**, so usage draws from your plan's limits instead of billed API tokens. Two consequences:

- The Claude Code CLI must be installed and a subscription token present at runtime — so studybuddy runs **locally / self-hosted, not on serverless** (Vercel functions can't host the binary).
- Subscriptions are for personal, interactive use. Keep this a tool you run for yourself; don't ship it as a shared/public service on subscription auth.

## Run it

```bash
npm install -g @anthropic-ai/claude-code   # if you don't already have the CLI
npm install
claude setup-token                          # paste the token into .env.local as CLAUDE_CODE_OAUTH_TOKEN
npm run dev
```

Open http://localhost:3000.

## Stack

Next.js 16 (App Router) · React 19 · Tailwind v4 · `@anthropic-ai/claude-agent-sdk` (subscription OAuth) · Node.js runtime (300s max duration for web research).
