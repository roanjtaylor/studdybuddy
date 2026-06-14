import { promises as fs } from 'fs';
import path from 'path';
import type { StudyCard } from '../../types';

export const runtime = 'nodejs';

// Hard copy of the library, written straight to the project folder so there's a
// real file on disk (not just browser localStorage). Self-hosted/local only.
const DATA_DIR = path.join(process.cwd(), 'data');
const FILE = path.join(DATA_DIR, 'library.json');

function extractCards(parsed: unknown): StudyCard[] {
  if (Array.isArray(parsed)) return parsed as StudyCard[];
  if (parsed && typeof parsed === 'object' && Array.isArray((parsed as { cards?: unknown }).cards)) {
    return (parsed as { cards: StudyCard[] }).cards;
  }
  return [];
}

export async function GET() {
  try {
    const raw = await fs.readFile(FILE, 'utf8');
    return Response.json({ cards: extractCards(JSON.parse(raw)) });
  } catch {
    // No file yet (or unreadable) — start empty.
    return Response.json({ cards: [] });
  }
}

export async function PUT(req: Request) {
  try {
    const cards = extractCards(await req.json());
    await fs.mkdir(DATA_DIR, { recursive: true });
    const payload = {
      schema: 'studybuddy.library.v1',
      updatedAt: new Date().toISOString(),
      cards,
    };
    await fs.writeFile(FILE, JSON.stringify(payload, null, 2), 'utf8');
    return Response.json({ ok: true, count: cards.length });
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'write failed';
    return Response.json({ error: msg }, { status: 500 });
  }
}
