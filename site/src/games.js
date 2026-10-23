// The games' numbers, read from stats.json (tools/stats.py makes it every hour): on the home page, the cover of the
// week and the ranking; on a game's page (site/gamepage.py), its numbers, and its comments and votes (giscus), loaded
// only when asked. Everything from outside goes in as text, never as HTML.
(() => { // its own scope: site.js, on the same page, has names of its own (LANG, W, el)
document.documentElement.classList.add('js');
const LANG = document.documentElement.lang;
const WORDS = {
  es: { pick: 'Lo destacamos esta semana', votes: 'El juego más votado de la semana', comments: 'El juego más comentado de la semana', random: 'Elegido al azar esta semana',
        loading: 'Cargando el ranking…', empty: 'Todavía no hay votos. Entra en la ficha de un juego y vota el primero.',
        failed: 'No se ha podido cargar el ranking. Comprueba la conexión.', retry: 'Reintentar', likes: 'me gusta',
        talks: 'comentarios', plays: 'partidas', played: 'jugado', numbersLoading: 'Cargando las cifras…',
        numbersNone: 'Todavía no hay cifras: se actualizan cada hora.', numbersFailed: 'No se han podido cargar las cifras.',
        numbersAt: d => 'Actualizadas el ' + d + '.', week: 'Semana', sheet: 'Ficha', sheetX: t => 'Ficha de ' + t, noReactions: 'Sin reacciones todavía', reactionsOf: 'Reacciones' },
  ca: { pick: 'El destaquem aquesta setmana', votes: 'El joc més votat de la setmana', comments: 'El joc més comentat de la setmana', random: "Triat a l'atzar aquesta setmana",
        loading: 'Carregant el rànquing…', empty: 'Encara no hi ha vots. Entra a la fitxa d’un joc i vota el primer.',
        failed: "No s'ha pogut carregar el rànquing. Comprova la connexió.", retry: 'Torna-ho a provar', likes: "m'agrada",
        talks: 'comentaris', plays: 'partides', played: 'jugat', numbersLoading: 'Carregant les xifres…',
        numbersNone: 'Encara no hi ha xifres: s’actualitzen cada hora.', numbersFailed: "No s'han pogut carregar les xifres.",
        numbersAt: d => 'Actualitzades el ' + d + '.', week: 'Setmana', sheet: 'Fitxa', sheetX: t => 'Fitxa de ' + t, noReactions: 'Encara sense reaccions', reactionsOf: 'Reaccions' },
  en: { pick: 'Our pick this week', votes: 'The most voted game of the week', comments: 'The most talked-about game of the week', random: 'Picked at random this week',
        loading: 'Loading the ranking…', empty: 'No votes yet. Open a game’s page and be the first to vote.',
        failed: "Couldn't load the ranking. Check the connection.", retry: 'Try again', likes: 'likes',
        talks: 'comments', plays: 'plays', played: 'played', numbersLoading: 'Loading the numbers…',
        numbersNone: 'No numbers yet: they are updated every hour.', numbersFailed: "Couldn't load the numbers.",
        numbersAt: d => 'Updated on ' + d + '.', week: 'Week', sheet: 'Details', sheetX: t => 'Details: ' + t, noReactions: 'No reactions yet', reactionsOf: 'Reactions' },
};
const W = WORDS[LANG] || WORDS.es;
const LOCALE = { es: 'es-ES', ca: 'ca-ES', en: 'en-GB' }[LANG] || 'es-ES';
const num = v => new Intl.NumberFormat(LOCALE).format(v);
const time = m => m < 60 ? num(m) + ' min' : num(Math.floor(m / 60)) + ' h' + (m % 60 ? ' ' + m % 60 + ' min' : '');
const ROOT = new URL('.', document.querySelector('link[rel="stylesheet"]').href); // the site's root, from any page
const HOME = new URL(LANG === 'ca' || LANG === 'en' ? LANG + '/' : './', ROOT);           // this language's home page
const sheetUrl = id => new URL('juegos/' + id + '/', HOME).href;
const ID = /^[a-z0-9_-]{1,40}$/;

function el(tag, attrs, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) e.setAttribute(k, v);
  e.append(...kids);
  return e;
}

// stats.json, once per page; null while there is none yet (the hourly job has not run: a 404)
let statsOnce;
function stats(src) {
  statsOnce = statsOnce || fetch(src, { cache: 'no-cache' }).then(r => {
    if (r.status === 404) return null;
    if (!r.ok) throw new Error(r.status);
    return r.json();
  });
  return statsOnce;
}
const retryable = run => () => { statsOnce = null; run(); };

const playUrl = g => new URL('juega/?juego=' + g.id, HOME).href; // on the Juega tab

// The ISO week ("2026-W42"): the same game for everyone this week when it is chosen at random here
function isoWeek(d = new Date()) {
  const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
  const week = Math.ceil(((t - Date.UTC(t.getUTCFullYear(), 0, 1)) / 864e5 + 1) / 7);
  return t.getUTCFullYear() + '-W' + String(week).padStart(2, '0');
}
const pick = (list, seed) => list[[...seed].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7) % list.length];

// ---------------------------------------------------------------- the home page
const catalogEl = document.getElementById('catalog');
const CATALOG = catalogEl ? JSON.parse(catalogEl.textContent) : [];
const byId = Object.fromEntries(CATALOG.map(g => [g.id, g]));

function showFeatured(choice) {
  const g = choice && byId[choice.id];
  if (!g) return;
  const page = sheetUrl(g.id);
  if (g.image) document.getElementById('feat-img').src = new URL(g.image, ROOT).href;
  document.getElementById('feat-shot').href = page;
  document.getElementById('feat-title').textContent = g.title;
  document.getElementById('feat-why').textContent = (W[choice.reason] || W.random) + ' · ' + W.week + ' ' + (choice.week || isoWeek()).split('-W')[1];
  document.getElementById('feat-play').href = playUrl(g);
  document.getElementById('feat-page').href = page;
  document.getElementById('portada').hidden = false;
}

function rankState(box, text, retry) {
  const p = el('p', { class: 'lib-state', role: 'status' }, text);
  if (retry) {
    const b = el('button', { type: 'button', class: 'btn btn-ghost' }, W.retry);
    b.addEventListener('click', retry);
    p.append(' ', b);
  }
  box.replaceChildren(p);
}

function rankRow(g, n, s) {
  const shot = el('div', { class: 'rank-shot' });
  if (g.image) shot.append(el('img', { src: new URL(g.image, ROOT).href, alt: '', width: 120, height: 80, loading: 'lazy', decoding: 'async' }));
  const facts = el('ul', { class: 'chips' }, el('li', { class: 'chip like' }, num(s.likes || 0) + ' ' + W.likes),
    el('li', { class: 'chip' }, num(s.comments || 0) + ' ' + W.talks));
  if (s.plays != null) facts.append(el('li', { class: 'chip' }, num(s.plays) + ' ' + W.plays));
  if (s.minutes) facts.append(el('li', { class: 'chip' }, time(s.minutes) + ' ' + W.played));
  return el('li', { class: 'rank-row' }, el('span', { class: 'rank-n pixel' }, String(n)), shot,
    el('div', { class: 'rank-info' }, el('h3', {}, el('a', { href: sheetUrl(g.id) }, g.title)), facts));
}

async function loadRanking() {
  const box = document.getElementById('rank');
  rankState(box, W.loading);
  try {
    const data = await stats(box.dataset.src);
    if (document.getElementById('portada'))
      showFeatured(data && data.featured && byId[data.featured.id] ? data.featured
        : { id: pick(CATALOG, isoWeek()).id, reason: 'random', week: isoWeek() });
    const games = (data && data.games) || {};
    const ranked = ((data && data.ranking) || []).filter(id => ID.test(id) && byId[id] && games[id]
      && ((games[id].likes || 0) + (games[id].comments || 0)) > 0).slice(0, +box.dataset.top || 10);
    if (!ranked.length) return rankState(box, W.empty);
    box.replaceChildren(el('ol', { class: 'rank-list' }, ...ranked.map((id, i) => rankRow(byId[id], i + 1, games[id]))));
  } catch {
    const feat = document.getElementById('portada');
    if (feat && feat.hidden && CATALOG.length) showFeatured({ id: pick(CATALOG, isoWeek()).id, reason: 'random' });
    rankState(box, W.failed, retryable(loadRanking));
  }
}
if (document.getElementById('rank')) loadRanking();

// The Library's cards (site.js draws them; the build lists which games have a page): a link to the page, and the
// reactions and comments their giscus Discussion has (stats.json; a card without numbers yet says so)
const EMOJI = { THUMBS_UP: '👍', LAUGH: '😄', HOORAY: '🎉', HEART: '❤️', ROCKET: '🚀', EYES: '👀' }; // (👎 and 😕 are not shown)
const lib = document.getElementById('library');
if (lib) {
  const pages = new Set((lib.dataset.pages || '').split(' '));
  let games = null; // stats.json's games, once read
  const reactionChips = s => {
    const parts = Object.entries(s.reactions || {}).filter(([k, n]) => EMOJI[k] && n > 0).sort((a, b) => b[1] - a[1])
      .map(([k, n]) => [EMOJI[k], n]);
    if (s.comments) parts.push(['💬', s.comments]);
    return parts;
  };
  const decorate = card => {
    if (!games || card.querySelector('.react')) return;
    const id = card.dataset.id;
    const parts = id && games[id] ? reactionChips(games[id]) : [];
    const list = el('ul', { class: 'chips react', 'aria-label': W.reactionsOf },
      ...(parts.length ? parts.map(([e, n]) => el('li', { class: 'chip like' }, e + ' ' + num(n)))
                       : [el('li', { class: 'chip quiet' }, W.noReactions)]));
    (card.querySelector('.chips') || card.querySelector('.row')).after(list);
  };
  const scan = () => {
    for (const card of lib.querySelectorAll('.cart:not([data-sheet])')) {
      card.dataset.sheet = '';
      const zip = card.querySelector('a.zip');
      const id = zip && (zip.getAttribute('href').match(/\/library\/([a-z0-9_-]{1,40})\/game\.zip$/) || [])[1];
      const title = (card.querySelector('h3') || {}).textContent || id;
      if (id) card.dataset.id = id;
      if (id && pages.has(id)) zip.after(' ', el('a', { class: 'sheet-link', href: sheetUrl(id), 'aria-label': W.sheetX(title) }, W.sheet));
    }
    for (const card of lib.querySelectorAll('.cart[data-id]')) decorate(card);
  };
  new MutationObserver(scan).observe(lib, { childList: true, subtree: true });
  if (lib.dataset.stats) stats(lib.dataset.stats).then(data => { games = (data && data.games) || {}; scan(); }, () => {});
}

// ---------------------------------------------------------------- a game's page
async function loadTally() {
  const tally = document.getElementById('tally'), note = document.getElementById('tally-note');
  note.textContent = W.numbersLoading;
  try {
    const data = await stats(tally.dataset.src);
    const s = data && data.games && data.games[tally.dataset.id];
    tally.removeAttribute('aria-busy');
    if (!s) { note.textContent = W.numbersNone; return; }
    const rank = (data.ranking || []).indexOf(tally.dataset.id);
    const show = { visits: s.visits != null ? num(s.visits) : '—', plays: s.plays != null ? num(s.plays) : '—',
                   minutes: s.minutes != null ? time(s.minutes) : '—', likes: num(s.likes || 0), comments: num(s.comments || 0),
                   rank: rank >= 0 && (s.likes || s.comments) ? '#' + (rank + 1) : '—' };
    for (const dd of tally.querySelectorAll('dd[data-k]')) dd.textContent = show[dd.dataset.k];
    const at = new Date(data.updated);
    note.textContent = isNaN(at) ? '' : W.numbersAt(at.toLocaleDateString(LOCALE, { day: 'numeric', month: 'long' }));
  } catch {
    tally.removeAttribute('aria-busy');
    rankState(note, W.numbersFailed, retryable(loadTally));
  }
}
if (document.getElementById('tally')) loadTally();

// giscus: a GitHub Discussion per game, in the page's language, loaded on the click (nothing from giscus.app before)
const talk = document.getElementById('talk');
if (talk && talk.hasAttribute('data-ready')) document.getElementById('talk-load').addEventListener('click', () => {
  const d = talk.dataset;
  const s = el('script', { src: 'https://giscus.app/client.js', 'data-repo': d.repo, 'data-repo-id': d.repoId,
    'data-category': d.category, 'data-category-id': d.categoryId, 'data-mapping': 'specific', 'data-term': d.term,
    'data-strict': '1', 'data-reactions-enabled': '1', 'data-emit-metadata': '0', 'data-input-position': 'top',
    'data-theme': 'transparent_dark', 'data-lang': LANG, crossorigin: 'anonymous' });
  s.async = true;
  talk.replaceChildren(el('div', { class: 'giscus' }), s);
  talk.focus(); // (the button it replaced had the focus)
});
})();
