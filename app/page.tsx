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
  const [saveStatus, setSaveStatus] = useState<
    'saved' | 'saving' | 'unsaved' | 'error'
  >('saved');

  useEffect(() => {
    let cancelled = false;

    // Paint instantly from the browser cache…
    let cards: StudyCard[] = [];
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      try {
        cards = JSON.parse(raw);
      } catch {}
    }
    if (cards.length) {
      setLibrary(cards);
      if (cards[0]) setActiveId(cards[0].id);
    }

    // …then reconcile with the on-disk hard copy (the source of truth).
    (async () => {
      try {
        const res = await fetch('/api/library');
        if (!res.ok) return;
        const data = await res.json();
        const fileCards: StudyCard[] = Array.isArray(data.cards) ? data.cards : [];
        if (cancelled) return;
        if (fileCards.length) {
          setLibrary(fileCards);
          setActiveId((cur) => cur ?? fileCards[0]?.id ?? null);
          localStorage.setItem(STORAGE_KEY, JSON.stringify(fileCards));
        } else if (cards.length) {
          // File is empty but the browser has data — migrate it to disk.
          saveToDisk(cards);
        }
      } catch {}
    })();

    if (!localStorage.getItem(ONBOARDED_KEY)) setShowIntro(true);
    return () => {
      cancelled = true;
    };
  }, []);

  // Writes the hard copy to data/library.json. Like a Word document's save:
  // it autosaves on every change, and the header reflects the live status.
  async function saveToDisk(next: StudyCard[]) {
    setSaveStatus('saving');
    try {
      const res = await fetch('/api/library', {
        method: 'PUT',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ cards: next }),
      });
      setSaveStatus(res.ok ? 'saved' : 'error');
    } catch {
      setSaveStatus('error');
    }
  }

  function persist(next: StudyCard[]) {
    setLibrary(next);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
    setSaveStatus('unsaved');
    void saveToDisk(next);
  }

  // Opens the offline snapshot as a real file:// tab via the server, so it keeps
  // working after the server shuts down. Falls back to the served URL if the
  // open call fails for any reason.
  async function openStaticPage() {
    try {
      const res = await fetch('/api/open-static', { method: 'POST' });
      if (res.ok) return;
    } catch {}
    window.open('/studybuddy.html', '_blank', 'noreferrer');
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

  function rename(id: string, nextTopic: string) {
    const t = nextTopic.trim();
    if (!t) return;
    persist(library.map((c) => (c.id === id ? { ...c, topic: t } : c)));
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
          <div className="flex shrink-0 flex-col items-end gap-2 text-xs text-[var(--muted)]">
            <div className="flex items-center gap-3">
              <button onClick={() => setShowIntro(true)} className="hover:text-[var(--accent)]">
                the principle
              </button>
              <span aria-hidden>·</span>
              <SaveButton status={saveStatus} onSave={() => saveToDisk(library)} />
            </div>
            <button
              onClick={openStaticPage}
              title="Open a static, server-free copy as a local file (file://) — stays readable after the server shuts down"
              className="inline-flex items-center gap-1 hover:text-[var(--accent)]"
            >
              View HTML
              <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                <path d="M7 17 17 7" />
                <path d="M7 7h10v10" />
              </svg>
            </button>
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

      {loading && <HuntingBar topic={topic.trim()} />}

      <p className="mb-10 text-xs text-[var(--muted)]">
        Asking about a <em>field of theory</em> (databases, transformers)? You're in the right place.
        Asking about a <em>product</em> (Supabase, Stripe)? Read its docs and use it instead — products are studied by using them.{' '}
        <button onClick={() => setShowIntro(true)} className="underline decoration-[var(--line)] underline-offset-4 hover:text-[var(--accent)]">
          remind me why
        </button>
      </p>

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
        <nav className="mb-8 flex flex-wrap gap-3 pt-2">
          {library.map((c) => (
            <TopicChip
              key={c.id}
              card={c}
              active={c.id === activeId}
              onSelect={() => setActiveId(c.id)}
              onRename={(t) => rename(c.id, t)}
              onDelete={() => remove(c.id)}
            />
          ))}
        </nav>
      )}

      {active && <CardView card={active} onDelete={() => remove(active.id)} />}

      {!active && !loading && library.length === 0 && (
        <p className="text-[var(--muted)] italic">
          Try a topic. Your library saves itself to{' '}
          <code className="not-italic">data/library.json</code> in the project folder.
        </p>
      )}
    </main>
  );
}

function SaveButton({
  status,
  onSave,
}: {
  status: 'saved' | 'saving' | 'unsaved' | 'error';
  onSave: () => void;
}) {
  const label =
    status === 'saving'
      ? 'saving…'
      : status === 'error'
        ? 'save failed — retry'
        : status === 'unsaved'
          ? 'save'
          : 'saved ✓';

  return (
    <button
      onClick={onSave}
      disabled={status === 'saving'}
      title="Saved to data/library.json in the project folder"
      className={`hover:text-[var(--accent)] disabled:opacity-60 ${
        status === 'error' ? 'text-red-500' : ''
      }`}
    >
      {label}
    </button>
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

function TopicChip({
  card,
  active,
  onSelect,
  onRename,
  onDelete,
}: {
  card: StudyCard;
  active: boolean;
  onSelect: () => void;
  onRename: (topic: string) => void;
  onDelete: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [value, setValue] = useState(card.topic);
  const [confirming, setConfirming] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (editing) inputRef.current?.select();
  }, [editing]);

  function commit() {
    const t = value.trim();
    if (t && t !== card.topic) onRename(t);
    else setValue(card.topic);
    setEditing(false);
  }

  if (editing) {
    return (
      <span className="inline-flex items-center border border-[var(--accent)] px-3 py-1 text-sm text-[var(--accent)]">
        <input
          ref={inputRef}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              commit();
            } else if (e.key === 'Escape') {
              setValue(card.topic);
              setEditing(false);
            }
          }}
          onBlur={commit}
          size={Math.max(value.length, 4)}
          className="bg-transparent outline-none"
        />
      </span>
    );
  }

  return (
    <span
      className="group relative inline-flex items-center"
      onMouseLeave={() => setConfirming(false)}
    >
      <button
        onClick={onSelect}
        className={`border px-3 py-1 text-sm ${
          active
            ? 'border-[var(--accent)] text-[var(--accent)]'
            : 'border-[var(--line)] text-[var(--muted)] hover:border-[var(--accent)] hover:text-[var(--accent)]'
        }`}
      >
        {card.topic}
      </button>

      <span className="pointer-events-none absolute -right-2 -top-2 flex gap-1 opacity-0 transition-opacity group-hover:pointer-events-auto group-hover:opacity-100">
        {confirming ? (
          <button
            onClick={onDelete}
            title="Click to confirm delete"
            className="rounded-full border border-red-500 bg-[var(--bg)] px-2 text-[10px] font-medium leading-5 text-red-500 hover:bg-red-500 hover:text-white"
          >
            delete?
          </button>
        ) : (
          <>
            <button
              onClick={() => {
                setValue(card.topic);
                setEditing(true);
              }}
              title="Rename"
              aria-label="Rename topic"
              className="grid h-5 w-5 place-items-center rounded-full border border-[var(--line)] bg-[var(--bg)] text-[var(--muted)] hover:border-[var(--accent)] hover:text-[var(--accent)]"
            >
              <PenIcon />
            </button>
            <button
              onClick={() => setConfirming(true)}
              title="Delete"
              aria-label="Delete topic"
              className="grid h-5 w-5 place-items-center rounded-full border border-[var(--line)] bg-[var(--bg)] text-[var(--muted)] hover:border-red-500 hover:text-red-500"
            >
              <XIcon />
            </button>
          </>
        )}
      </span>
    </span>
  );
}

function PenIcon() {
  return (
    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M12 20h9" />
      <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4Z" />
    </svg>
  );
}

function XIcon() {
  return (
    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M18 6 6 18" />
      <path d="m6 6 12 12" />
    </svg>
  );
}

const HUNT_LINES = [
  'STUDYBUDDY used SEARCH!',
  'Wading through the tall grass…',
  'Dodging listicles and remixes…',
  'A wild PRIMARY SOURCE appeared!',
  "Reading the originator's own words…",
  'Cross-checking the canon…',
  'Distilling first principles…',
];

// The server returns in one shot at the very end, so there's no real progress
// to report. We fake a satisfying, never-quite-finished crawl: the bar eases
// toward ~95% and lands on 100% only when this component unmounts (= done).
function HuntingBar({ topic }: { topic: string }) {
  const [pct, setPct] = useState(8);
  const [line, setLine] = useState(0);

  useEffect(() => {
    const fill = setInterval(() => {
      setPct((p) => (p >= 95 ? 95 : p + Math.max(0.4, (95 - p) * 0.04)));
    }, 180);
    const cycle = setInterval(
      () => setLine((l) => (l + 1) % HUNT_LINES.length),
      2200,
    );
    return () => {
      clearInterval(fill);
      clearInterval(cycle);
    };
  }, []);

  return (
    <div className="mb-10">
      <div className="pkmn-box">
        <div className="mb-4 flex items-center gap-3">
          <span className="pkmn-pokeball" aria-hidden />
          <span className="pkmn-heading text-sm">
            HUNTING{topic ? `: ${topic.toUpperCase()}` : '…'}
          </span>
        </div>

        <div className="flex items-center gap-2">
          <span className="pkmn-hplabel">SRC</span>
          <div className="pkmn-hpbar">
            <div className="pkmn-hpfill" style={{ width: `${pct}%` }} />
          </div>
          <span
            className="pkmn-heading text-[0.6rem] tabular-nums"
            style={{ color: '#ffde00', minWidth: '2.4em', textAlign: 'right' }}
          >
            {Math.round(pct)}%
          </span>
        </div>

        <p className="pkmn-body mt-4" style={{ fontSize: '1.05rem' }}>
          {HUNT_LINES[line]}
        </p>
        <p className="pkmn-heading mt-3 text-[0.55rem]" style={{ opacity: 0.65 }}>
          SEARCHING THE WEB · THIS CAN TAKE A MINUTE · HANG TIGHT
        </p>
      </div>
    </div>
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
