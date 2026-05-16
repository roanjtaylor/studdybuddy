# studybuddy

A source hunter for self-directed learners. Type a topic, get the canonical primary sources — not the remix layer.

## Core truths

- **Theory is studied by reading the source.** Databases → Codd. Transformers → Faraday. Startups → Paul Graham. Read the originator, not the blog post about the blog post.
- **Products are studied by using them.** Supabase, Stripe, Vercel — no first principles, just docs. studybuddy is for *ideas*, not tools.
- Every topic produces a **study card**: 3–5 first principles + 3–5 canonical sources, each with a 3–5 sentence blurb so you have the gist before clicking through.

## How it works

- **Frontend** (`app/page.tsx`): single-page Next.js app. A topic input, a card view, and a localStorage-backed library you can export/import as JSON. First visit shows a Pokémon-styled intro that explains the two rules above.
- **API** (`app/api/study/route.ts`): POST `/api/study` with `{ topic }`. Calls Claude (`claude-opus-4-7`) with two tools:
  - `web_search` (Anthropic server-side tool, up to 8 uses) to research the topic.
  - `submit_results` (custom tool with a strict JSON schema) — the model **must** call this exactly once to deliver the study card. No prose answers.
- The system prompt rejects listicles/tutorials/marketing and prefers original papers, essays, lectures, and authoritative textbook chapters.
- Library persists in `localStorage` under `studybuddy.library.v1`. Nothing is stored server-side.

## Run it

```bash
npm install
cp .env.example .env.local   # add your ANTHROPIC_API_KEY
npm run dev
```

Open http://localhost:3000.

## Stack

Next.js 16 (App Router) · React 19 · Tailwind v4 · `@anthropic-ai/sdk` · Node.js runtime (300s max duration for web research).
