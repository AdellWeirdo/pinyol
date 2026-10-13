// Every template of the editor built as the browser builds it (its blocks become Lua, its drawings pictures) into a
// game folder each, OUT_DIR/<template>, for the engine to play in tests (tests/editor_<template>.script):
//   node editor/test/build_game.mjs OUT_DIR
import { createRequire } from 'node:module';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const out = process.argv[2];
if (!out) { console.error('usage: node build_game.mjs OUT_DIR'); process.exit(2); }
const editor = join(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
globalThis.Blockly = require('../vendor/blockly/blockly_compressed.js');
Blockly.setLocale(require('../vendor/blockly/msg/es.js')); // the built-in blocks' words, as in the browser
require('../vendor/blockly/blocks_compressed.js'); // the built-in blocks (variables, text, maths)
globalThis.lua = require('../vendor/blockly/lua_compressed.js');

const { TEMPLATES } = await import('../js/templates.js');
const { defineBlocks, setProject, workspaceLua, templateBlocks } = await import('../js/blocks.js');
const { buildFiles } = await import('../js/build.js');
const { HZ, cut, wav } = await import('../js/audio.js');
const { newSong, renderSong } = await import('../js/song.js');

defineBlocks();
const carried = [...['FONT_MAIN.fnt', 'FONT_BOLD.fnt', 'FONT_MAIN_L.fnt', 'FONT_BOLD_L.fnt']
  .map(f => ['fonts/' + f, readFileSync(join(editor, 'fonts', f))]),
  ...['kit.lua', 'juice.lua', 'particles.lua'].map(f => [f, readFileSync(join(editor, '..', 'lib', f))])];

rmSync(out, { recursive: true, force: true });
for (const t of TEMPLATES) {
  const project = t.make();
  setProject(project);
  const ws = new Blockly.Workspace();
  Blockly.serialization.workspaces.load(templateBlocks(t.key), ws);
  for (const [path, bytes] of buildFiles(project, workspaceLua(ws), carried)) {
    mkdirSync(dirname(join(out, t.key, path)), { recursive: true });
    writeFileSync(join(out, t.key, path), bytes);
  }
  ws.dispose();
}

// and the platformer with sounds brought in (tests/editor_sonido.script): a tune for the cover and the first level, an
// effect, as the browser would make them from files but from samples made here (Node decodes no audio files); and a
// song composed in the editor (song.js) for the second level
{
  const project = TEMPLATES[0].make(), notes = [262, 330, 392, 523], tune = new Float32Array(HZ * 2), boing = new Float32Array(HZ / 4);
  for (let i = 0; i < tune.length; i++) tune[i] = 0.3 * Math.sin(2 * Math.PI * notes[Math.floor(i / (HZ / 2))] * i / HZ);
  for (let i = 0; i < boing.length; i++) boing[i] = 0.5 * Math.sin(2 * Math.PI * (200 + i / 20) * i / HZ) * (1 - i / boing.length);
  const music = { name: 'tema', file: 'made here', use: 'music', start: 0, end: 0, volume: 1 };
  const effect = { name: 'boing', file: 'made here', use: 'effect', start: 0, end: 0, volume: 1 };
  const song = { name: 'cancion', song: newSong(), use: 'music' };
  project.sounds.push(music, effect, song);
  project.levels[0].music = project.cover.music = 'tema';
  project.levels[1].music = 'cancion';
  setProject(project);
  const ws = new Blockly.Workspace();
  Blockly.serialization.workspaces.load(templateBlocks('plataformas'), ws);
  const code = workspaceLua(ws) + 'kit.on("press", "b", function() kit.sound("boing") end)\n';
  const audio = [['audio/MUS_tema.wav', wav(cut(music, tune))], ['audio/SFX_boing.wav', wav(cut(effect, boing))],
                 ['audio/MUS_cancion.wav', wav(renderSong(song.song))]];
  for (const [path, bytes] of buildFiles(project, code, carried, { audio })) {
    mkdirSync(dirname(join(out, 'sonido', path)), { recursive: true });
    writeFileSync(join(out, 'sonido', path), bytes);
  }
  ws.dispose();
}
console.log('built', TEMPLATES.map(t => t.key).join(', '), 'and sonido in', out);
