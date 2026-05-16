'use client';

import { useEffect, useRef, useState } from 'react';
import type { StudyCard } from './types';

const STORAGE_KEY = 'studybuddy.library.v1';
const ONBOARDED_KEY = 'studybuddy.onboarded.v1';

export default function Home() {
  const [topic, setTopic] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [rawDebug, setRawDebug] = useState<string | null>(null);
  const [library, setLibrary] = useState<StudyCard[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [showIntro, setShowIntro] = useState(false);
  const [importMsg, setImportMsg] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      try {
        const parsed: StudyCard[] = JSON.parse(raw);
        setLibrary(parsed);
        if (parsed[0]) setActiveId(parsed[0].id);
      } catch {}
    }
    if (!localStorage.getItem(ONBOARDED_KEY)) setShowIntro(true);
  }, []);

  function persist(next: StudyCard[]) {
    setLibrary(next);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  }

  function dismissIntro() {
    localStorage.setItem(ONBOARDED_KEY, '1');
    setShowIntro(false);
  }

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    const trimmed = topic.trim();
    if (!trimmed || loading) return;

    const existing = library.find(
      (c) => c.topic.toLowerCase() === trimmed.toLowerCase(),
    );
    if (existing) {
      setActiveId(existing.id);
      setTopic('');
      return;
    }

    setLoading(true);
    setError(null);
    setRawDebug(null);
    try {
      const res = await fetch('/api/study', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ topic: trimmed }),
      });
      const data = await res.json();
      if (!res.ok) {
        if (data.raw) setRawDebug(data.raw);
        throw new Error(
          data.error +
            (data.stopReason ? ` (stop_reason: ${data.stopReason})` : '') +
            (data.parseError ? ` — ${data.parseError}` : ''),
        );
      }
      const card: StudyCard = {
        id: crypto.randomUUID(),
        topic: data.topic ?? trimmed,
        firstPrinciples: data.firstPrinciples ?? [],
        sources: data.sources ?? [],
        createdAt: Date.now(),
      };
      const next = [card, ...library];
      persist(next);
      setActiveId(card.id);
      setTopic('');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'unknown error');
    } finally {
      setLoading(false);
    }
  }

  function remove(id: string) {
    const next = library.filter((c) => c.id !== id);
    persist(next);
    if (activeId === id) setActiveId(next[0]?.id ?? null);
  }

  function exportLibrary() {
    const payload = {
      schema: 'studybuddy.library.v1',
      exportedAt: new Date().toISOString(),
      cards: library,
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], {
      type: 'application/json',
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    const stamp = new Date().toISOString().slice(0, 10);
    a.href = url;
    a.download = `studybuddy-${stamp}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }

  async function importLibrary(file: File) {
    setImportMsg(null);
    try {
      const text = await file.text();
      const parsed = JSON.parse(text);
      const incoming: StudyCard[] = Array.isArray(parsed)
        ? parsed
        : Array.isArray(parsed.cards)
          ? parsed.cards
          : [];
      if (incoming.length === 0) throw new Error('no cards found in file');

      const byId = new Map<string, StudyCard>();
      for (const c of library) byId.set(c.id, c);
      let added = 0;
      let skipped = 0;
      for (const c of incoming) {
        if (!c || typeof c !== 'object' || !c.topic || !Array.isArray(c.sources)) {
          skipped++;
          continue;
        }
        const id = c.id || crypto.randomUUID();
        if (byId.has(id)) {
          skipped++;
          continue;
        }
        byId.set(id, { ...c, id });
        added++;
      }
      const merged = [...byId.values()].sort(
        (a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0),
      );
      persist(merged);
      if (!activeId && merged[0]) setActiveId(merged[0].id);
      setImportMsg(`Imported ${added} card${added === 1 ? '' : 's'}${skipped ? `, skipped ${skipped}` : ''}.`);
    } catch (err) {
      setImportMsg(`Import failed: ${err instanceof Error ? err.message : 'invalid file'}`);
    }
  }

  const active = library.find((c) => c.id === activeId) ?? null;

  if (showIntro) return <Intro onDismiss={dismissIntro} />;

  return (
    <main className="mx-auto max-w-3xl px-6 py-12">
      <header className="mb-10 border-b border-[var(--line)] pb-6">
        <div className="flex items-baseline justify-between gap-4">
          <div>
            <h1 className="text-3xl font-semibold tracking-tight">studybuddy</h1>
            <p className="mt-2 text-[var(--muted)] italic">
              Find the canonical source. Skip the remixes.
            </p>
          </div>
          <div className="flex shrink-0 gap-3 text-xs text-[var(--muted)]">
            <button onClick={() => setShowIntro(true)} className="hover:text-[var(--accent)]">
              the principle
            </button>
            <span aria-hidden>·</span>
            <button onClick={exportLibrary} className="hover:text-[var(--accent)]" disabled={library.length === 0}>
              export
            </button>
            <span aria-hidden>·</span>
            <button onClick={() => fileInputRef.current?.click()} className="hover:text-[var(--accent)]">
              import
            </button>
            <input
              ref={fileInputRef}
              type="file"
              accept="application/json,.json"
              className="hidden"
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) importLibrary(f);
                e.target.value = '';
              }}
            />
          </div>
        </div>
      </header>

      <form onSubmit={onSubmit} className="mb-4 flex gap-2">
        <input
          value={topic}
          onChange={(e) => setTopic(e.target.value)}
          placeholder="A topic — e.g. 'startups', 'databases', 'transformers'"
          className="flex-1 border-b border-[var(--line)] bg-transparent py-2 outline-none placeholder:text-[var(--muted)] focus:border-[var(--accent)]"
          disabled={loading}
        />
        <button
          type="submit"
          disabled={loading || !topic.trim()}
          className="border border-[var(--line)] px-4 py-2 text-sm hover:border-[var(--accent)] hover:text-[var(--accent)] disabled:opacity-40"
        >
          {loading ? 'hunting…' : 'find sources'}
        </button>
      </form>

      <p className="mb-10 text-xs text-[var(--muted)]">
        Asking about a <em>field of theory</em> (databases, transformers)? You're in the right place.
        Asking about a <em>product</em> (Supabase, Stripe)? Read its docs and use it instead — products are studied by using them.{' '}
        <button onClick={() => setShowIntro(true)} className="underline decoration-[var(--line)] underline-offset-4 hover:text-[var(--accent)]">
          remind me why
        </button>
      </p>

      {importMsg && (
        <div className="mb-8 border border-[var(--line)] px-4 py-3 text-sm text-[var(--muted)]">
          {importMsg}
        </div>
      )}

      {error && (
        <div className="mb-8 border border-red-500/40 bg-red-500/5 px-4 py-3 text-sm text-red-500">
          <div>{error}</div>
          {rawDebug && (
            <details className="mt-3">
              <summary className="cursor-pointer text-xs opacity-70">show raw model output</summary>
              <pre className="mt-2 max-h-96 overflow-auto whitespace-pre-wrap break-words text-xs opacity-80">
                {rawDebug}
              </pre>
            </details>
          )}
        </div>
      )}

      {library.length > 0 && (
        <nav className="mb-8 flex flex-wrap gap-2">
          {library.map((c) => (
            <button
              key={c.id}
              onClick={() => setActiveId(c.id)}
              className={`border px-3 py-1 text-sm ${
                c.id === activeId
                  ? 'border-[var(--accent)] text-[var(--accent)]'
                  : 'border-[var(--line)] text-[var(--muted)] hover:border-[var(--accent)] hover:text-[var(--accent)]'
              }`}
            >
              {c.topic}
            </button>
          ))}
        </nav>
      )}

      {active && <CardView card={active} onDelete={() => remove(active.id)} />}

      {!active && !loading && library.length === 0 && (
        <p className="text-[var(--muted)] italic">
          Try a topic. Or <button onClick={() => fileInputRef.current?.click()} className="underline decoration-[var(--line)] underline-offset-4 hover:text-[var(--accent)]">import a saved library</button> to pick up where you left off.
        </p>
      )}
    </main>
  );
}

type Page = { heading?: string; lines: React.ReactNode[]; accent?: 'yellow' | 'red' };

const PAGES: Page[] = [
  {
    heading: 'HELLO!',
    lines: [
      'Welcome to the world of self-directed learning!',
      'My name is STUDYBUDDY.',
      <>People call me the <span style={{ color: '#ffde00' }}>SOURCE HUNTER!</span></>,
    ],
  },
  {
    lines: [
      'This world is filled with IDEAS — and endless remixes of those ideas.',
      'The remixes are infinite.',
      'The originals are few.',
    ],
  },
  {
    heading: 'RULE #1',
    accent: 'yellow',
    lines: [
      <>THEORY is studied by <span style={{ color: '#ffde00' }}>READING THE SOURCE.</span></>,
      'Databases. Transformers. Startups.',
      'Codd. Faraday. Paul Graham.',
      'Read their words — not the remix.',
    ],
  },
  {
    heading: 'RULE #2',
    accent: 'red',
    lines: [
      <>PRODUCTS are studied by <span style={{ color: '#ff5959' }}>USING THEM.</span></>,
      'Supabase. Stripe. Vercel.',
      'No first principles — only docs and decisions.',
      'Walk around the Aston Martin.',
    ],
  },
  {
    heading: 'BEFORE YOU HUNT',
    lines: [
      'Ask yourself:',
      <>An <span style={{ color: '#ffde00' }}>IDEA</span>, or a <span style={{ color: '#ff5959' }}>TOOL</span>?</>,
      'Pick the right path.',
    ],
  },
  {
    heading: 'READY?',
    lines: [
      'STUDYBUDDY is waiting.',
      'Let the hunt begin!',
    ],
  },
];

function Intro({ onDismiss }: { onDismiss: () => void }) {
  const [page, setPage] = useState(0);
  const isLast = page === PAGES.length - 1;

  function next() {
    if (isLast) onDismiss();
    else setPage((p) => p + 1);
  }

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Enter' || e.key === ' ' || e.key === 'ArrowRight') {
        e.preventDefault();
        next();
      } else if (e.key === 'Escape') {
        onDismiss();
      }
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  const current = PAGES[page];

  return (
    <main className="pkmn-screen flex items-center justify-center px-4 py-8" onClick={next}>
      <div className="w-full max-w-2xl">
        <div className="pkmn-box relative">
          {current.heading && (
            <div
              className="pkmn-heading mb-5 text-base"
              style={{
                color:
                  current.accent === 'yellow'
                    ? '#ffde00'
                    : current.accent === 'red'
                      ? '#ff5959'
                      : '#fff',
              }}
            >
              {current.heading}
            </div>
          )}
          <div className="pkmn-body space-y-3">
            {current.lines.map((l, i) => (
              <p key={i}>{l}</p>
            ))}
          </div>
          <div className="mt-6 flex items-center justify-between">
            <div className="pkmn-heading text-[0.55rem] opacity-70">
              {page + 1} / {PAGES.length}
            </div>
            {isLast ? (
              <button
                className="pkmn-btn"
                onClick={(e) => {
                  e.stopPropagation();
                  onDismiss();
                }}
              >
                ▶ BEGIN
              </button>
            ) : (
              <span className="pkmn-blink pkmn-heading text-sm">▼</span>
            )}
          </div>
        </div>
        <div
          className="pkmn-heading mt-6 text-center text-[0.55rem]"
          style={{ opacity: 0.65 }}
        >
          CLICK · PRESS SPACE · ENTER
        </div>
      </div>
    </main>
  );
}

function CardView({ card, onDelete }: { card: StudyCard; onDelete: () => void }) {
  return (
    <article>
      <div className="mb-8 flex items-baseline justify-between">
        <h2 className="text-2xl font-semibold">{card.topic}</h2>
        <button
          onClick={onDelete}
          className="text-xs text-[var(--muted)] hover:text-red-500"
        >
          delete
        </button>
      </div>

      {card.firstPrinciples.length > 0 && (
        <section className="mb-12">
          <h3 className="mb-3 text-xs uppercase tracking-widest text-[var(--muted)]">
            First principles
          </h3>
          <ol className="space-y-2 pl-5 [list-style:decimal]">
            {card.firstPrinciples.map((p, i) => (
              <li key={i}>{p}</li>
            ))}
          </ol>
        </section>
      )}

      <section>
        <h3 className="mb-4 text-xs uppercase tracking-widest text-[var(--muted)]">
          Canonical sources
        </h3>
        <ul className="space-y-8">
          {card.sources.map((s, i) => (
            <li key={i} className="border-l-2 border-[var(--line)] pl-4">
              <div className="flex items-baseline justify-between gap-3">
                <a
                  href={s.url}
                  target="_blank"
                  rel="noreferrer"
                  className="text-lg font-medium underline decoration-[var(--line)] underline-offset-4 hover:decoration-[var(--accent)]"
                >
                  {s.title}
                </a>
                <span className="shrink-0 text-xs text-[var(--muted)]">
                  {s.kind} · {s.timeCost}
                </span>
              </div>
              <div className="mt-1 text-sm text-[var(--muted)]">{s.author}</div>
              <p className="mt-3">{s.blurb}</p>
              <p className="mt-3 text-sm">
                <span className="text-[var(--muted)]">Core idea: </span>
                <em>{s.coreIdea}</em>
              </p>
              <p className="mt-2 text-sm text-[var(--muted)]">
                Why canonical: {s.whyCanonical}
              </p>
            </li>
          ))}
        </ul>
      </section>
    </article>
  );
}
