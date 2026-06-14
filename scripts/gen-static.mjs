// Builds public/studybuddy.html from data/library.json without the server.
// The /api/library save handler does this automatically on every save; this
// script is for a first build (or a manual refresh): `npm run gen:static`.
import { promises as fs } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { renderStaticHtml } from '../lib/staticPage.mjs';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const SRC = path.join(root, 'data', 'library.json');
const OUT = path.join(root, 'public', 'studybuddy.html');

function extractCards(parsed) {
  if (Array.isArray(parsed)) return parsed;
  if (parsed && Array.isArray(parsed.cards)) return parsed.cards;
  return [];
}

let cards = [];
try {
  cards = extractCards(JSON.parse(await fs.readFile(SRC, 'utf8')));
} catch {
  console.warn(`No readable ${SRC} — writing an empty snapshot.`);
}

await fs.mkdir(path.dirname(OUT), { recursive: true });
await fs.writeFile(OUT, renderStaticHtml(cards), 'utf8');
console.log(`Wrote ${OUT} (${cards.length} topic${cards.length === 1 ? '' : 's'}).`);
