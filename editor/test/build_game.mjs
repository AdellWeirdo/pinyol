// The editor's platformer template built as the browser builds it (its blocks become Lua, its drawings pictures) into
// a game folder, for the engine to play in a test (tests/editor.script): node editor/test/build_game.mjs OUT_DIR
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

const { templatePlatformer } = await import('../js/project.js');
const { defineBlocks, setProject, workspaceLua, templateBlocks } = await import('../js/blocks.js');
const { buildFiles } = await import('../js/build.js');

defineBlocks();
const project = templatePlatformer();
setProject(project);
const ws = new Blockly.Workspace();
Blockly.serialization.workspaces.load(templateBlocks(), ws);
const fonts = ['FONT_MAIN.fnt', 'FONT_BOLD.fnt', 'FONT_MAIN_L.fnt', 'FONT_BOLD_L.fnt']
  .map(f => [f, readFileSync(join(editor, 'fonts', f))]);

rmSync(out, { recursive: true, force: true });
for (const [path, bytes] of buildFiles(project, workspaceLua(ws), fonts)) {
  mkdirSync(dirname(join(out, path)), { recursive: true });
  writeFileSync(join(out, path), bytes);
}
console.log('built', out);
