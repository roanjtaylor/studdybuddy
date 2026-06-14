// Renders the whole library into a single, self-contained HTML file that needs
// no server: all styling is inlined and every topic is embedded as JSON, then
// painted by a tiny vanilla script. Open it straight from disk (file://) to keep
// reading your researched topics while the Next.js server is off.
//
// Shared on purpose: the /api/library PUT handler calls this on every save so the
// snapshot stays fresh, and scripts/gen-static.mjs uses it for the first build.

/** @param {import('../app/types').StudyCard[]} cards */
export function renderStaticHtml(cards) {
  const generatedAt = new Date().toISOString();

  // Embed the data safely inside a <script> tag: escape '<' (so "</script>" can't
  // close the tag early) plus the U+2028/U+2029 separators JSON leaves raw (they
  // are invalid unescaped in a JS source position).
  const json = JSON.stringify(cards ?? []).replace(
    /[<\u2028\u2029]/g,
    (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'),
  );

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>studybuddy — offline library</title>
<style>
  :root {
    --bg: #fafaf7;
    --fg: #1a1a1a;
    --muted: #666;
    --line: #e5e5e0;
    --accent: #c2410c;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0f0f0e;
      --fg: #ededed;
      --muted: #999;
      --line: #2a2a28;
      --accent: #fb923c;
    }
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; }
  body {
    background: var(--bg);
    color: var(--fg);
    font-family: Georgia, 'Times New Roman', serif;
    line-height: 1.6;
    -webkit-font-smoothing: antialiased;
  }
  main { max-width: 48rem; margin: 0 auto; padding: 3rem 1.5rem; }
  a { color: inherit; }

  header { border-bottom: 1px solid var(--line); padding-bottom: 1.5rem; margin-bottom: 2.5rem; }
  .titlebar { display: flex; align-items: baseline; justify-content: space-between; gap: 1rem; flex-wrap: wrap; }
  h1 { font-size: 1.875rem; font-weight: 600; letter-spacing: -0.01em; margin: 0; }
  .tagline { margin: 0.5rem 0 0; color: var(--muted); font-style: italic; }
  .snapshot { font-size: 0.7rem; color: var(--muted); white-space: nowrap; }
  .snapshot .dot { color: var(--accent); }

  nav { display: flex; flex-wrap: wrap; gap: 0.75rem; margin-bottom: 2rem; }
  .chip {
    border: 1px solid var(--line);
    color: var(--muted);
    background: transparent;
    padding: 0.25rem 0.75rem;
    font: inherit;
    font-size: 0.875rem;
    cursor: pointer;
  }
  .chip:hover { border-color: var(--accent); color: var(--accent); }
  .chip.active { border-color: var(--accent); color: var(--accent); }

  h2 { font-size: 1.5rem; font-weight: 600; margin: 0 0 2rem; }
  .section { margin-bottom: 3rem; }
  .kicker {
    font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.15em;
    color: var(--muted); margin: 0 0 0.75rem;
  }
  ol.principles { padding-left: 1.25rem; margin: 0; }
  ol.principles li { margin-bottom: 0.5rem; }

  ul.sources { list-style: none; padding: 0; margin: 0; }
  ul.sources > li { border-left: 2px solid var(--line); padding-left: 1rem; margin-bottom: 2rem; }
  .src-head { display: flex; align-items: baseline; justify-content: space-between; gap: 0.75rem; }
  .src-title { font-size: 1.125rem; font-weight: 500; text-decoration: underline; text-decoration-color: var(--line); text-underline-offset: 4px; }
  .src-title:hover { text-decoration-color: var(--accent); }
  .src-meta { flex-shrink: 0; font-size: 0.75rem; color: var(--muted); }
  .src-author { margin-top: 0.25rem; font-size: 0.875rem; color: var(--muted); }
  .src-blurb { margin-top: 0.75rem; }
  .src-core { margin-top: 0.75rem; font-size: 0.875rem; }
  .src-core .label { color: var(--muted); }
  .src-why { margin-top: 0.5rem; font-size: 0.875rem; color: var(--muted); }

  .empty { color: var(--muted); font-style: italic; }
</style>
</head>
<body>
<main>
  <header>
    <div class="titlebar">
      <div>
        <h1>studybuddy</h1>
        <p class="tagline">Find the canonical source. Skip the remixes.</p>
      </div>
      <div class="snapshot">
        <span class="dot">●</span> offline snapshot · saved ${escapeHtml(generatedAt)}
      </div>
    </div>
  </header>

  <nav id="nav"></nav>
  <div id="card"></div>
</main>

<script id="data" type="application/json">${json}</script>
<script>
(function () {
  var cards = [];
  try { cards = JSON.parse(document.getElementById('data').textContent || '[]'); } catch (e) {}

  var nav = document.getElementById('nav');
  var card = document.getElementById('card');

  function el(tag, attrs, text) {
    var e = document.createElement(tag);
    if (attrs) for (var k in attrs) {
      if (k === 'class') e.className = attrs[k];
      else e.setAttribute(k, attrs[k]);
    }
    if (text != null) e.textContent = text;
    return e;
  }

  function renderCard(c) {
    card.innerHTML = '';
    card.appendChild(el('h2', null, c.topic || 'Untitled'));

    if (c.firstPrinciples && c.firstPrinciples.length) {
      var sec = el('div', { class: 'section' });
      sec.appendChild(el('h3', { class: 'kicker' }, 'First principles'));
      var ol = el('ol', { class: 'principles' });
      c.firstPrinciples.forEach(function (p) { ol.appendChild(el('li', null, p)); });
      sec.appendChild(ol);
      card.appendChild(sec);
    }

    var ssec = el('div', { class: 'section' });
    ssec.appendChild(el('h3', { class: 'kicker' }, 'Canonical sources'));
    var ul = el('ul', { class: 'sources' });
    (c.sources || []).forEach(function (s) {
      var li = el('li');
      var head = el('div', { class: 'src-head' });
      head.appendChild(el('a', { class: 'src-title', href: s.url || '#', target: '_blank', rel: 'noreferrer' }, s.title || s.url || 'source'));
      head.appendChild(el('span', { class: 'src-meta' }, [s.kind, s.timeCost].filter(Boolean).join(' · ')));
      li.appendChild(head);
      if (s.author) li.appendChild(el('div', { class: 'src-author' }, s.author));
      if (s.blurb) li.appendChild(el('p', { class: 'src-blurb' }, s.blurb));
      if (s.coreIdea) {
        var core = el('p', { class: 'src-core' });
        core.appendChild(el('span', { class: 'label' }, 'Core idea: '));
        core.appendChild(el('em', null, s.coreIdea));
        li.appendChild(core);
      }
      if (s.whyCanonical) li.appendChild(el('p', { class: 'src-why' }, 'Why canonical: ' + s.whyCanonical));
      ul.appendChild(li);
    });
    ssec.appendChild(ul);
    card.appendChild(ssec);
  }

  function select(i) {
    Array.prototype.forEach.call(nav.children, function (b, j) {
      b.className = 'chip' + (j === i ? ' active' : '');
    });
    renderCard(cards[i]);
  }

  if (!cards.length) {
    card.appendChild(el('p', { class: 'empty' }, 'No topics saved yet. Research a topic with the server running, then this snapshot will fill up.'));
    return;
  }

  cards.forEach(function (c, i) {
    var b = el('button', { class: 'chip', type: 'button' }, c.topic || 'Untitled');
    b.addEventListener('click', function () { select(i); });
    nav.appendChild(b);
  });
  select(0);
})();
</script>
</body>
</html>
`;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
  });
}
