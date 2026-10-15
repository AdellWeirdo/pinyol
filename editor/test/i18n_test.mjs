// The editor in Catalan and English (js/i18n/ca.js, en.js): every Spanish text the code says through t() and every text
// and label of index.html (as js/i18n.js translatePage finds them) has its translation in both tables, with the same
// {names}; no table keeps a text nothing says any more. Each text missing, or left over, is listed.
//   node editor/test/i18n_test.mjs
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ATTRS } from '../js/i18n.js';

const editor = join(dirname(fileURLToPath(import.meta.url)), '..'), js = join(editor, 'js');
const keys = new Map(), problems = []; // key -> where it is said first
const said = (key, where) => { if (!keys.has(key)) keys.set(key, where); };

// the code's: t('…'), t("…"), t(`…`), each one whole literal text (a computed or joined one cannot be checked here)
for (const f of readdirSync(js).filter(f => f.endsWith('.js') && f !== 'i18n.js')) {
  const src = readFileSync(join(js, f), 'utf8');
  for (const m of src.matchAll(/(?<![\w.$])t\(\s*/g)) {
    const at = m.index + m[0].length, q = src[at], where = `${f}:${src.slice(0, m.index).split('\n').length}`;
    if (!'\'"`'.includes(q)) { problems.push(`${where}: t() of something that is not a literal text`); continue; }
    let end = at + 1;
    while (end < src.length && src[end] !== q) end += src[end] === '\\' ? 2 : 1;
    const literal = src.slice(at, end + 1);
    if (q === '`' && literal.includes('${')) { problems.push(`${where}: t(\`…\${…}…\`): say it with {name} and vars`); continue; }
    if (/^\s*\+/.test(src.slice(end + 1))) problems.push(`${where}: t('…' + …): one whole text a t()`);
    said(Function(`"use strict"; return ${literal};`)(), where); // (the repo's own literal, as JavaScript reads it)
  }
}

// the page's: texts between tags and the attributes translatePage says, trimmed, with a letter; not translate="no"
const html = readFileSync(join(editor, 'index.html'), 'utf8').replace(/<!--[\s\S]*?-->/g, '')
  .replace(/<(script|style)\b[\s\S]*?<\/\1>/g, '').replace(/<(\w+)\b[^>]*\btranslate="no"[^>]*>[\s\S]*?<\/\1>/g, '<x>');
const text = s => s.trim().replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&amp;/g, '&');
for (const [, s] of html.matchAll(/>([^<]+)</g)) if (/\p{L}/u.test(s)) said(text(s), 'index.html');
for (const [, , s] of html.matchAll(new RegExp(`\\s(${ATTRS.join('|')})="([^"]*)"`, 'g'))) if (/\p{L}/u.test(s)) said(text(s), 'index.html');

const names = s => [...new Set([...s.matchAll(/\{(\w+)\}/g)].map(m => m[1]))].sort().join();
const ends = s => /^\s*/.exec(s)[0] + '|' + /\s*$/.exec(s)[0]; // 'Monedas: ' + points: the space is the text's
for (const lang of ['ca', 'en']) {
  const table = (await import(`../js/i18n/${lang}.js`)).default;
  for (const [k, where] of keys)
    if (!Object.hasOwn(table, k)) problems.push(`${lang}.js: missing ${JSON.stringify(k)} (${where})`);
    else if (typeof table[k] !== 'string' || !table[k].trim()) problems.push(`${lang}.js: empty ${JSON.stringify(k)}`);
    else if (names(table[k]) !== names(k)) problems.push(`${lang}.js: ${JSON.stringify(k)} has other {names}: ${JSON.stringify(table[k])}`);
    else if (ends(table[k]) !== ends(k)) problems.push(`${lang}.js: ${JSON.stringify(k)} starts or ends in other spaces: ${JSON.stringify(table[k])}`);
  for (const k of Object.keys(table)) if (!keys.has(k)) problems.push(`${lang}.js: ${JSON.stringify(k)} is said nowhere any more`);
}
if (problems.length) {
  console.error(problems.join('\n') + `\n${problems.length} problems in the editor's translations`);
  process.exit(1);
}
console.log(`i18n: ${keys.size} texts of the editor, each in Catalan and English`);
