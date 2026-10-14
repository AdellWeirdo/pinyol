// The page works without this file: it only adds the reveals, the counters, the copy buttons, and pauses the
// animations nobody is looking at.
document.documentElement.classList.add('js');
const still = matchMedia('(prefers-reduced-motion: reduce)').matches;

const fmt = (v, dec) => new Intl.NumberFormat('es-ES', { minimumFractionDigits: dec, maximumFractionDigits: dec }).format(v);

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
    b.textContent = said.textContent = 'Copiado';
  } catch {
    b.textContent = 'Selecciónalo y copia';
    said.textContent = 'No se ha podido copiar: selecciona el texto y cópialo';
  }
  setTimeout(() => { b.textContent = 'Copiar'; said.textContent = ''; }, 2000); // cleared, so the next copy is announced again
}));

// The Library: people's games, read from the repository when the page opens (tools/library.py publishes them).
// Everything people wrote goes in as text, never as HTML; ids and logins are checked before they make a URL.
const lib = document.getElementById('library');
const NEW_TAB = ' (se abre en una pestaña nueva)';
function el(tag, attrs, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) e.setAttribute(k, v);
  e.append(...kids);
  return e;
}
function libState(text, retry) {
  const p = el('p', { class: 'lib-state', role: 'status' }, text);
  if (retry) {
    const b = el('button', { type: 'button', class: 'btn btn-ghost' }, 'Reintentar');
    b.addEventListener('click', loadLibrary);
    p.append(' ', b);
  }
  lib.replaceChildren(p);
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
    el('a', { class: 'play', href: 'play/player.html?game=' + encodeURIComponent(zip), target: '_blank', rel: 'noopener',
              'aria-label': 'Jugar a ' + g.title + NEW_TAB }, 'Jugar'),
    el('a', { class: 'zip', href: zip, 'aria-label': 'Descargar ' + g.title + ' para la consola' }, 'Descargar .zip'));
  return el('li', { class: 'cart job' }, shot,
    el('div', { class: 'label' }, el('h3', {}, g.title), el('p', { class: 'what' }, g.description || ''),
      el('p', { class: 'after' }, 'por ', who), chips, row));
}
async function loadLibrary() {
  libState('Cargando la Biblioteca…');
  try {
    const r = await fetch(lib.dataset.src, { cache: 'no-cache' });
    if (!r.ok) throw new Error(r.status);
    const games = (await r.json()).filter(g => g && /^[a-z0-9_-]{1,40}$/.test(g.id) && /^[A-Za-z0-9-]{1,39}$/.test(g.author)
                                               && typeof g.title === 'string');
    if (!games.length) return libState('Todavía no hay juegos en la Biblioteca. ¡Sube el primero!');
    lib.replaceChildren(el('ul', { class: 'jobs' }, ...games.map(g => libCard(g, lib.dataset.base))));
  } catch {
    libState('No se ha podido cargar la Biblioteca. Comprueba la conexión.', true);
  }
}
if (lib) loadLibrary();
