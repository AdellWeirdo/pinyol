// The editor's words in Spanish (its own, as the code writes them), Catalan or English. LANG: ?lang= in the address,
// else the one chosen before in this browser, else the browser's own; in Node (the tests) always Spanish. t() says a
// Spanish text in LANG from its table (i18n/<lang>.js, keyed by the exact Spanish); translatePage() does the same for
// index.html's own texts, as platform/web/player.html does with its WORDS. test/i18n_test.mjs checks the tables.
const KNOWN = ['es', 'ca', 'en'], KEY = 'pinyol-editor-lang';
export const ATTRS = ['aria-label', 'aria-roledescription', 'title', 'placeholder']; // what translatePage says besides texts

function asked() {
  if (typeof location === 'undefined') return 'es'; // Node has a navigator, and the games it builds are the Spanish ones
  const url = new URLSearchParams(location.search).get('lang');
  if (KNOWN.includes(url)) return url;
  try { const kept = localStorage.getItem(KEY); if (KNOWN.includes(kept)) return kept; } catch { /* storage blocked */ }
  const own = String((typeof navigator !== 'undefined' && navigator.language) || '').toLowerCase();
  return own.startsWith('ca') ? 'ca' : own.startsWith('en') ? 'en' : 'es';
}

const wanted = asked();
let words = null; // Spanish: none, the code's own
if (wanted !== 'es') {
  try { words = (await import(`./i18n/${wanted}.js`)).default; } catch { /* its table did not load: Spanish, not no editor */ }
}
export const LANG = words ? wanted : 'es';

// spanish in LANG, its {name}s filled from vars; a text with no translation stays Spanish. A key "text|why" is the
// Spanish text said apart where another language has two words for it (arriba: a button's up, a place's top)
export function t(spanish, vars) {
  const s = words && Object.hasOwn(words, spanish) ? words[spanish]
    : typeof spanish === 'string' ? spanish.replace(/\|[^|]*$/, '') : spanish;
  if (!vars || typeof s !== 'string') return s;
  return s.replace(/\{(\w+)\}/g, (m, k) => (Object.hasOwn(vars, k) ? String(vars[k]) : m));
}

// index.html's texts and labels in LANG: a text node or attribute whose trimmed text is a key (its spaces kept);
// anything inside translate="no" stays (file and folder names)
export function translatePage(root = document) {
  const doc = root.ownerDocument || root, has = k => Object.hasOwn(words, k);
  doc.documentElement.lang = LANG;
  if (!words) return;
  const walk = doc.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  for (let n; (n = walk.nextNode());) {
    const k = n.data.trim();
    if (k && has(k) && !n.parentElement?.closest('[translate=no]')) n.data = n.data.replace(k, () => words[k]);
  }
  for (const a of ATTRS)
    for (const el of root.querySelectorAll(`[${a}]`)) {
      const k = el.getAttribute(a).trim();
      if (has(k) && !el.closest('[translate=no]')) el.setAttribute(a, words[k]);
    }
}

// the editor in another language: kept for next time, and the page again in it
export function chooseLang(lang) {
  if (!KNOWN.includes(lang)) return;
  try { localStorage.setItem(KEY, lang); } catch { /* a private window: the address keeps it */ }
  const url = new URL(location.href);
  url.searchParams.set('lang', lang);
  location.assign(url);
}
