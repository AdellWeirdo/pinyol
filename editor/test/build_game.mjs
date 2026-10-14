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
const { HZ, cut, wav, audioFiles } = await import('../js/audio.js');
const { newSong, renderSong } = await import('../js/song.js');

defineBlocks();
const carried = [...['FONT_MAIN.fnt', 'FONT_BOLD.fnt', 'FONT_MAIN_L.fnt', 'FONT_BOLD_L.fnt']
  .map(f => ['fonts/' + f, readFileSync(join(editor, 'fonts', f))]),
  ...['kit.lua', 'juice.lua', 'particles.lua'].map(f => [f, readFileSync(join(editor, '..', 'lib', f))])];

rmSync(out, { recursive: true, force: true });
for (const t of TEMPLATES) {
  const project = await t.make();
  setProject(project);
  const ws = new Blockly.Workspace();
  Blockly.serialization.workspaces.load(t.blocks ? await t.blocks() : templateBlocks(t.key), ws);
  const lettered = carried.map(([path, bytes]) => [path, project.font && /^fonts\/FONT_/.test(path) ? // its own letters
    readFileSync(join(editor, 'fonts', project.font, path.slice(6))) : bytes]);
  for (const [path, bytes] of buildFiles(project, workspaceLua(ws), lettered, { audio: await audioFiles(project) })) {
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
  const mod = { name: 'modulo', file: readFileSync(join(editor, '..', 'tests/games/clock/audio/TUNE.mod')).toString('base64'),
                use: 'music', mod: true }; // a tracker's module, kept as it is
  project.sounds.push(music, effect, song, mod);
  project.levels[0].music = project.cover.music = 'tema';
  project.levels[1].music = 'cancion';
  setProject(project);
  const ws = new Blockly.Workspace();
  Blockly.serialization.workspaces.load(templateBlocks('plataformas'), ws);
  // and the blocks of Guardar: C keeps 7 as the record unless more is kept, and the record is shown
  const saves = new Blockly.Workspace(), n = v => ({ block: { type: 'math_number', fields: { NUM: v } } });
  Blockly.serialization.workspaces.load({ blocks: { languageVersion: 0, blocks: [{ type: 'kit_press', fields: { BUTTON: 'c' },
    inputs: { DO: { block: { type: 'kit_store_max', fields: { KEY: 'récord' }, inputs: { V: n(7) }, next: { block: {
      type: 'kit_label', fields: { WHERE: 'top_right' }, inputs: { TEXT: { block: { type: 'kit_stored', fields: { KEY: 'récord' } } } } } } } } } }] } }, saves);
  const saving = workspaceLua(saves);
  if (!saving.includes('store("récord", v)') || !saving.includes('stored("récord", 0)')) throw new Error('sonido: the save blocks did not become their Lua');
  saves.dispose();
  const code = workspaceLua(ws) + saving + 'kit.on("press", "b", function() kit.sound("boing") end)\n';
  const audio = [['audio/MUS_tema.wav', wav(cut(music, tune))], ['audio/SFX_boing.wav', wav(cut(effect, boing))],
                 ['audio/MUS_cancion.wav', wav(renderSong(song.song))], ...await audioFiles({ sounds: [mod] })];
  for (const [path, bytes] of buildFiles(project, code, carried, { audio })) {
    mkdirSync(dirname(join(out, 'sonido', path)), { recursive: true });
    writeFileSync(join(out, 'sonido', path), bytes);
  }
  ws.dispose();
}
// and the platformer with a conversation, the microphone and a video (tests/editor_conversa.script): the blocks of
// Diálogos, Micrófono and Vídeo, and a clip made by npv.js from frames drawn here (as the browser makes one from a file)
{
  const { encode } = await import('../js/npv.js');
  const project = TEMPLATES[0].make(), w = 64, h = 48, frames = [];
  for (let k = 0; k < 20; k++) { // a red square crossing a blue field, a frame number in the top left corner's green
    const f = new Uint8ClampedArray(w * h * 4);
    for (let i = 0; i < w * h; i++) {
      const x = i % w, y = Math.floor(i / w), sq = x >= k * 2 && x < k * 2 + 10 && y >= 18 && y < 28;
      f.set(sq ? [255, 0, 0, 255] : x < 4 && y < 4 ? [0, k * 12, 0, 255] : [0, 0, 128, 255], 4 * i);
    }
    frames.push(f);
  }
  project.videos = [{ name: 'intro', npv: Buffer.from(encode(frames, w, h, 10)).toString('base64'), w, h, frames: 20, fps: 10 }];
  setProject(project);
  const V = (name, id) => ({ name, id }), vars = [V('respuesta', 'v1'), V('palmadas', 'v2'), V('soplidos', 'v3'), V('visto', 'v4')];
  const set = (id, n, next) => ({ type: 'variables_set', fields: { VAR: { id } },
    inputs: { VALUE: { block: { type: 'math_number', fields: { NUM: n } } } }, ...(next ? { next: { block: next } } : {}) });
  const add1 = id => ({ type: 'math_change', fields: { VAR: { id } }, inputs: { DELTA: { block: { type: 'math_number', fields: { NUM: 1 } } } } });
  const txt = t => ({ block: { type: 'text', fields: { TEXT: t } } });
  const ev = (type, fields, body, x) => ({ type, fields, x, y: 0, inputs: { DO: { block: body } } });
  const blocks = { variables: vars, blocks: { languageVersion: 0, blocks: [
    ev('kit_start', {}, { type: 'kit_say', inputs: { WHO: txt('Ana'), TEXT: txt('¡Hola! ¿Me ayudas?') },
      next: { block: { type: 'kit_ask', inputs: { TEXT: txt('¿Vienes?'), A: txt('Sí'), B: txt('No'), C: txt('') } } } }, 0),
    ev('kit_answer', { N: '1' }, set('v1', 1), 300),
    ev('kit_answer', { N: '2' }, set('v1', 2, { type: 'kit_video_full', fields: { VIDEO: 'intro' } }), 600),
    ev('kit_video_end', {}, set('v4', 1, { type: 'kit_video_window', fields: { VIDEO: 'intro', WHERE: 'top_right' } }), 900),
    ev('kit_clap', {}, add1('v2'), 1200),
    ev('kit_blow', {}, add1('v3'), 1500),
  ] } };
  const ws = new Blockly.Workspace();
  Blockly.serialization.workspaces.load(blocks, ws);
  const code = workspaceLua(ws);
  if (!code.includes('kit.ask(') || !code.includes('kit.video("intro", "full")')) throw new Error('conversa: the blocks did not become their Lua');
  for (const [path, bytes] of buildFiles(project, code, carried)) {
    mkdirSync(dirname(join(out, 'conversa', path)), { recursive: true });
    writeFileSync(join(out, 'conversa', path), bytes);
  }
  ws.dispose();
}
// and the platformer in the Game Boy's look, with its letters, named animations, lives, a countdown and a styled label
// (tests/editor_extras.script)
{
  const { LOOKS, lookColour } = await import('../js/project.js');
  const project = TEMPLATES[0].make(), look = LOOKS.gameboy, hero = project.drawings.find(d => d.name === 'heroe');
  Object.assign(project, { look: 'gameboy', font: 'silkscreen' });
  for (const d of project.drawings) d.frames = d.frames.map(f => f.map(v => lookColour(look, v)));
  hero.frames.push(hero.frames[0].map(v => (v < 0 ? v : lookColour(look, 0)))); // a third frame: the hit, all dark
  hero.anims = { idle: [0, 0], walk: [0, 1], hit: [2, 2] };
  setProject(project);
  const V = (name, id) => ({ name, id }), n = v => ({ block: { type: 'math_number', fields: { NUM: v } } });
  const set = (id, v) => ({ type: 'variables_set', fields: { VAR: { id } }, inputs: { VALUE: n(v) } });
  const ev = (type, fields, body, x) => ({ type, fields, x, y: 0, inputs: { DO: { block: body } } });
  const blocks = { variables: [V('tiempo', 't'), V('sinvidas', 's')], blocks: { languageVersion: 0, blocks: [
    ev('kit_start', {}, { type: 'kit_set_lives', fields: { N: 2 }, next: { block: { type: 'kit_countdown', fields: { SECONDS: 3 },
      next: { block: { type: 'kit_label', fields: { WHERE: 'top_left', STYLE: 'wave' },
                       inputs: { TEXT: { block: { type: 'text', fields: { TEXT: 'Hola' } } } } } } } } }, 0),
    ev('kit_press', { BUTTON: 'b' }, { type: 'kit_lose_life' }, 300),
    ev('kit_press', { BUTTON: 'c' }, { type: 'kit_play_hit', inputs: { OBJ: { block: { type: 'kit_player' } } } }, 600),
    ev('kit_time_up', {}, set('t', 1), 900),
    ev('kit_no_lives', {}, set('s', 1), 1200),
  ] } };
  const ws = new Blockly.Workspace();
  Blockly.serialization.workspaces.load(blocks, ws);
  const code = workspaceLua(ws);
  for (const want of ['kit.set_lives(2)', 'kit.countdown(3)', '"wave")', 'kit.add_lives(-1)', 'kit.play(kit.player(), "hit")', '"time_up"'])
    if (!code.includes(want)) throw new Error('extras: no ' + want + ' in\n' + code);
  const lettered = carried.map(([path, bytes]) => [path, /^fonts\/FONT_/.test(path) ? readFileSync(join(editor, 'fonts/silkscreen', path.slice(6))) : bytes]);
  for (const [path, bytes] of buildFiles(project, code, lettered)) {
    mkdirSync(dirname(join(out, 'extras', path)), { recursive: true });
    writeFileSync(join(out, 'extras', path), bytes);
  }
  ws.dispose();
}
console.log('built', TEMPLATES.map(t => t.key).join(', '), ', sonido, conversa and extras in', out);
