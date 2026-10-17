// The Juega tab: the player in a frame (play/player.html?frame=1), the game chosen in the list (?juego=<id>, so a
// link opens it) or a .zip of one's own, from the button or dropped anywhere on the page. The frame says how tall it
// is; a new game gets a fresh player, as the engine starts once per page. The Library's games approved since the site
// was built come from its list on GitHub, as the Biblioteca tab reads it.
(() => {
  'use strict';
  const LANG = document.documentElement.lang;
  const frame = document.getElementById('player');
  const GAMES = Object.fromEntries(JSON.parse(document.getElementById('catalog').textContent).map(g => [g.id, g]));
  const PLAYER = new URL(frame.dataset.player, location.href);
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
  // A phone or tablet (or ?touch=1, to try it on a computer): the console is never taller than the screen, so it all
  // shows without scrolling, and the games list is below it.
  const TOUCH = matchMedia('(pointer: coarse)').matches || /[?&]touch=1/.test(location.search);
  if (TOUCH) document.documentElement.classList.add('touch-play');
  let ready = Promise.resolve(), isReady = () => {};

  function show(id) {
    const url = new URL(PLAYER);
    url.searchParams.set('frame', '1');
    if (LANG === 'ca' || LANG === 'en') url.searchParams.set('lang', LANG);
    if (/[?&]touch=1/.test(location.search)) url.searchParams.set('touch', '1');
    if (id) url.searchParams.set('game', GAMES[id].zip);
    ready = new Promise(r => { isReady = r; });
    frame.src = url.href;
    for (const a of document.querySelectorAll('.pick')) {
      if (a.dataset.id === id) a.setAttribute('aria-current', 'true');
      else a.removeAttribute('aria-current');
    }
  }

  // A .zip of one's own: a fresh player, handed the file (it waits for Jugar, so the sound can start)
  async function open(buf) {
    show(null);
    history.replaceState(null, '', location.pathname);
    await ready;
    frame.contentWindow.postMessage({ pinyol: 'open', zip: buf }, location.origin, [buf]);
    frame.scrollIntoView({ behavior: still ? 'auto' : 'smooth', block: 'start' });
  }

  addEventListener('message', e => {
    if (e.origin !== location.origin || e.source !== frame.contentWindow || !e.data) return;
    if (e.data.pinyol === 'size' && e.data.h > 0) { frame.style.aspectRatio = 'auto'; frame.style.height = Math.min(e.data.h, TOUCH ? innerHeight : Infinity) + 'px'; }
    if (e.data.pinyol === 'ready') isReady();
    if (e.data.pinyol === 'dropped' && e.data.zip instanceof ArrayBuffer) open(e.data.zip);
  });

  document.addEventListener('click', e => {
    const a = e.target.closest('.pick');
    if (!a || !GAMES[a.dataset.id] || e.metaKey || e.ctrlKey || e.shiftKey || e.button) return;
    e.preventDefault();
    show(a.dataset.id);
    history.pushState({ id: a.dataset.id }, '', '?juego=' + a.dataset.id);
    frame.scrollIntoView({ behavior: still ? 'auto' : 'smooth', block: 'start' });
  });
  addEventListener('popstate', () => show(chosen()));

  document.getElementById('zip-file').addEventListener('change', async e => {
    const f = e.target.files[0];
    if (f) open(await f.arrayBuffer());
    e.target.value = '';
  });
  document.addEventListener('dragover', e => { e.preventDefault(); document.body.classList.add('dropping'); });
  document.addEventListener('dragleave', e => { if (!e.relatedTarget) document.body.classList.remove('dropping'); });
  document.addEventListener('drop', async e => {
    e.preventDefault();
    document.body.classList.remove('dropping');
    const f = e.dataTransfer.files[0];
    if (f) open(await f.arrayBuffer());
  });

  const chosen = () => {
    const id = new URLSearchParams(location.search).get('juego');
    return id && GAMES[id] ? id : null;
  };

  async function newInLibrary() {
    const ul = document.getElementById('picks-library');
    if (!ul) return;
    const r = await fetch(ul.dataset.src, { cache: 'no-cache' });
    if (!r.ok) return;
    const fresh = (await r.json()).filter(g => g && /^[a-z0-9_-]{1,40}$/.test(g.id) && typeof g.title === 'string' && !GAMES[g.id]);
    ul.prepend(...fresh.map(g => {
      GAMES[g.id] = { id: g.id, title: g.title, zip: ul.dataset.base + g.id + '/game.zip' };
      const a = document.createElement('a');
      a.className = 'pick';
      a.href = '?juego=' + g.id;
      a.dataset.id = g.id;
      const shot = document.createElement(g.cover ? 'img' : 'span');
      if (g.cover) Object.assign(shot, { src: ul.dataset.base + g.id + '/cover.png', alt: '', width: 240, height: 160, loading: 'lazy', decoding: 'async' });
      else shot.className = 'noshot';
      const name = document.createElement('span');
      name.translate = false;
      name.textContent = g.title;
      a.append(shot, name);
      const li = document.createElement('li');
      li.append(a);
      return li;
    }));
  }

  // a link to a game newer than the site waits for the Library's list; without the list, the site's own games still play
  const asked = new URLSearchParams(location.search).get('juego');
  const late = asked && !GAMES[asked];
  if (!late) show(chosen());
  newInLibrary().catch(() => {}).finally(() => { if (late) show(chosen()); });
})();
