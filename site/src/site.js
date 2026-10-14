// The page works without this file: it only adds the reveals, the counters, the copy buttons, and pauses the
// animations nobody is looking at.
document.documentElement.classList.add('js');
const still = matchMedia('(prefers-reduced-motion: reduce)').matches;

// The page's words, in the page's language (the page itself is translated when the site is built: site/i18n.py)
const LANG = document.documentElement.lang;
const WORDS = {
  es: { copied: 'Copiado', copy: 'Copiar', select: 'Selecciónalo y copia', noCopy: 'No se ha podido copiar: selecciona el texto y cópialo',
        newTab: ' (se abre en una pestaña nueva)', retry: 'Reintentar', play: 'Jugar', playX: 'Jugar a ', zip: 'Descargar .zip',
        zipX: t => 'Descargar ' + t + ' para la consola', by: 'por ', loading: 'Cargando la Biblioteca…',
        empty: 'Todavía no hay juegos en la Biblioteca. ¡Sube el primero!', failed: 'No se ha podido cargar la Biblioteca. Comprueba la conexión.' },
  ca: { copied: 'Copiat', copy: 'Copia', select: 'Selecciona-ho i copia', noCopy: "No s'ha pogut copiar: selecciona el text i copia'l",
        newTab: " (s'obre en una pestanya nova)", retry: 'Torna-ho a provar', play: 'Juga', playX: 'Juga a ', zip: 'Descarrega el .zip',
        zipX: t => 'Descarrega ' + t + ' per a la consola', by: 'per ', loading: 'Carregant la Biblioteca…',
        empty: 'Encara no hi ha jocs a la Biblioteca. Puja el primer!', failed: "No s'ha pogut carregar la Biblioteca. Comprova la connexió." },
  en: { copied: 'Copied', copy: 'Copy', select: 'Select it and copy', noCopy: "Couldn't copy: select the text and copy it",
        newTab: ' (opens in a new tab)', retry: 'Try again', play: 'Play', playX: 'Play ', zip: 'Download .zip',
        zipX: t => 'Download ' + t + ' for the console', by: 'by ', loading: 'Loading the Library…',
        empty: 'No games in the Library yet. Send the first one!', failed: "Couldn't load the Library. Check the connection." },
};
const W = WORDS[LANG] || WORDS.es;

const fmt = (v, dec) => new Intl.NumberFormat({ es: 'es-ES', ca: 'ca-ES', en: 'en-GB' }[LANG] || 'es-ES', { minimumFractionDigits: dec, maximumFractionDigits: dec }).format(v);

function count(el) {
  const to = parseFloat(el.dataset.count), from = parseFloat(el.dataset.from) || 0, dec = +el.dataset.dec || 0, t0 = performance.now(), T = 1100;
  if (!isFinite(to)) return;
  const step = now => {
    const k = Math.min(1, (now - t0) / T), e = 1 - Math.pow(2, -10 * k); // ease out
    el.textContent = fmt(k < 1 ? from + (to - from) * e : to, dec);
    if (k < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

if ('IntersectionObserver' in window) {
  const reveal = new IntersectionObserver(entries => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add('in');
      if (!still) e.target.querySelectorAll('[data-count]').forEach(count);
      reveal.unobserve(e.target);
    }
  }, { threshold: 0.2 });
  document.querySelectorAll('.reveal').forEach(el => reveal.observe(el));

  const live = new IntersectionObserver(entries => {
    for (const e of entries) e.target.classList.toggle('live', e.isIntersecting);
  });
  document.querySelectorAll('[data-live]').forEach(el => live.observe(el));
} else {
  document.querySelectorAll('.reveal, [data-live]').forEach(el => el.classList.add('in', 'live'));
}

const said = document.createElement('p');
said.className = 'sr';
said.setAttribute('aria-live', 'polite');
document.body.append(said);
document.querySelectorAll('.copy').forEach(b => b.addEventListener('click', async () => {
  const text = b.parentElement.querySelector('code').textContent;
  try {
    await navigator.clipboard.writeText(text);
    b.textContent = said.textContent = W.copied;
  } catch {
    b.textContent = W.select;
    said.textContent = W.noCopy;
  }
  setTimeout(() => { b.textContent = W.copy; said.textContent = ''; }, 2000); // cleared, so the next copy is announced again
}));

// The Library: people's games, read from the repository when the page opens (tools/library.py publishes them).
// Everything people wrote goes in as text, never as HTML; ids and logins are checked before they make a URL.
const lib = document.getElementById('library');
function el(tag, attrs, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) e.setAttribute(k, v);
  e.append(...kids);
  return e;
}
function libState(text, retry) {
  const p = el('p', { class: 'lib-state', role: 'status' }, text);
  if (retry) {
    const b = el('button', { type: 'button', class: 'btn btn-ghost' }, W.retry);
    b.addEventListener('click', loadLibrary);
    p.append(' ', b);
  }
  lib.replaceChildren(p);
}
function playUrl(zip) {
  const url = new URL(lib.dataset.play, location.href);
  if (LANG !== 'es') url.searchParams.set('lang', LANG);
  url.searchParams.set('game', zip);
  return url.href;
}
function libCard(g, base) {
  const zip = base + g.id + '/game.zip';
  const shot = el('div', { class: 'shot' });
  if (g.cover) shot.append(el('img', { src: base + g.id + '/cover.png', alt: '', width: 480, height: 320, loading: 'lazy', decoding: 'async' }));
  const who = el('a', { href: 'https://github.com/' + g.author, target: '_blank', rel: 'noopener' }, '@' + g.author);
  const chips = el('ul', { class: 'chips' });
  if (g.license) chips.append(el('li', { class: 'chip' }, g.license));
  if (/^\d{4}-\d{2}-\d{2}$/.test(g.date || '')) chips.append(el('li', { class: 'chip' }, g.date.split('-').reverse().join('/')));
  const row = el('div', { class: 'row' },
    el('a', { class: 'play', href: playUrl(zip), target: '_blank', rel: 'noopener',
              'aria-label': W.playX + g.title + W.newTab }, W.play),
    el('a', { class: 'zip', href: zip, 'aria-label': W.zipX(g.title) }, W.zip));
  return el('li', { class: 'cart job' }, shot,
    el('div', { class: 'label' }, el('h3', {}, g.title), el('p', { class: 'what' }, g.description || ''),
      el('p', { class: 'after' }, W.by, who), chips, row));
}
async function loadLibrary() {
  libState(W.loading);
  try {
    const r = await fetch(lib.dataset.src, { cache: 'no-cache' });
    if (!r.ok) throw new Error(r.status);
    const games = (await r.json()).filter(g => g && /^[a-z0-9_-]{1,40}$/.test(g.id) && /^[A-Za-z0-9-]{1,39}$/.test(g.author)
                                               && typeof g.title === 'string');
    if (!games.length) return libState(W.empty);
    lib.replaceChildren(el('ul', { class: 'jobs' }, ...games.map(g => libCard(g, lib.dataset.base))));
  } catch {
    libState(W.failed, true);
  }
}
if (lib) loadLibrary();
