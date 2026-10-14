// The blocks of the Logic tab (Blockly) and the Lua they become: calls to kit (pinyol/lib/kit.lua). Events are the hat
// blocks a game is made of; the rest is what happens in them. Dropdowns list what the project has (its objects,
// tiles and sounds), read when they open.
/* global Blockly, lua */

let project = null; // the project being edited (set by main.js)
export function setProject(p) { project = p; }

const none = [['(no hay)', '_']];
const kinds = () => { const k = project ? project.drawings.filter(d => d.use === 'object').map(d => [d.name, d.name]) : []; return k.length ? k : none; };
const tiles = () => { const t = project ? project.drawings.filter(d => d.use === 'tile').map(d => [d.name, d.name]) : []; return t.length ? t : none; };
const levels = () => (project ? project.levels.map(l => [l.name, l.id]) : []);
const anyLevel = () => [['cualquier nivel', '_'], ...levels()];
const someLevel = () => { const l = levels(); return l.length ? l : none; };
const named = keep => () => { const s = project ? project.sounds.filter(keep).map(x => [x.name, x.name]) : []; return s.length ? s : none; };
const sounds = named(x => x.use !== 'music'), tunes = named(x => x.use === 'music');
const videos = () => { const v = project && project.videos ? project.videos.map(x => [x.name, x.name]) : []; return v.length ? v : none; };
const WINDOWS = [['arriba a la derecha', 'top_right'], ['arriba a la izquierda', 'top_left'], ['abajo a la derecha', 'bottom_right'],
  ['abajo a la izquierda', 'bottom_left']];
const BUTTONS = [['A', 'a'], ['B', 'b'], ['C', 'c'], ['arriba', 'up'], ['abajo', 'down'], ['izquierda', 'left'],
  ['derecha', 'right'], ['START', 'start']];
const PROPS = [['x', 'x'], ['y', 'y'], ['velocidad x', 'vx'], ['velocidad y', 'vy']];
const PLACES = [['arriba a la izquierda', 'top_left'], ['arriba', 'top'], ['arriba a la derecha', 'top_right'],
  ['abajo', 'bottom'], ['abajo a la izquierda', 'bottom_left'], ['abajo a la derecha', 'bottom_right']];
const COLOURS = [['amarillas', '0xFFE070'], ['blancas', '0xFFFFFF'], ['rojas', '0xFF4040'], ['verdes', '0x60E060'],
  ['azules', '0x50A0FF'], ['moradas', '0xC070FF']];

const EVENT = 40, OBJECT = 200, ACTION = 290, INPUT = 160, MIC = 330, TALK = 20, VIDEO = 260;
export const EVENTS = new Set(['kit_start', 'kit_level', 'kit_tick', 'kit_press', 'kit_hold', 'kit_touch', 'kit_tile', 'kit_out',
  'kit_every', 'kit_tap', 'kit_clap', 'kit_blow', 'kit_answer', 'kit_video_end']);

// define(type, colour, parts, kind): parts are text and fields/inputs in order; kind: 'event', 'statement', a value type
function define(type, colour, parts, kind, tooltip) {
  Blockly.Blocks[type] = {
    init() {
      let row = this.appendDummyInput();
      for (const p of parts) {
        if (typeof p === 'string') row.appendField(p);
        else if (p.dropdown) row.appendField(new Blockly.FieldDropdown(p.dropdown), p.name);
        else if (p.number !== undefined) row.appendField(new Blockly.FieldNumber(p.number, p.min, p.max, p.step), p.name);
        else if (p.value) { row = this.appendValueInput(p.name).setCheck(p.check || null); if (p.label) row.appendField(p.label); }
      }
      this.setInputsInline(true);
      if (kind === 'event') {
        this.appendStatementInput('DO');
        this.setInputsInline(false);
      } else if (kind === 'statement') {
        this.setPreviousStatement(true);
        this.setNextStatement(true);
      } else {
        this.setOutput(true, kind === 'any' ? null : kind);
      }
      this.setColour(colour);
      if (tooltip) this.setTooltip(tooltip);
    },
  };
}

export function defineBlocks() {
  // events
  define('kit_start', EVENT, ['al empezar la partida'], 'event', 'Una vez, antes del primer nivel (y en cada partida nueva)');
  define('kit_level', EVENT, ['al empezar', { dropdown: anyLevel, name: 'LEVEL' }], 'event',
         'Cada vez que empieza ese nivel (también al repetirlo tras perder)');
  define('kit_tick', EVENT, ['en cada momento'], 'event', '60 veces por segundo');
  define('kit_press', EVENT, ['al pulsar', { dropdown: BUTTONS, name: 'BUTTON' }], 'event');
  define('kit_hold', EVENT, ['mientras se pulsa', { dropdown: BUTTONS, name: 'BUTTON' }], 'event');
  define('kit_touch', EVENT, ['cuando', { dropdown: kinds, name: 'A' }, 'toca', { dropdown: kinds, name: 'B' }], 'event',
         'Dentro, «este» es el primero y «el otro» el segundo');
  define('kit_tile', EVENT, ['cuando', { dropdown: kinds, name: 'A' }, 'pisa', { dropdown: tiles, name: 'TILE' }], 'event',
         'También al chocar con una baldosa sólida (una pared, una puerta). Dentro: «x de la baldosa», «y de la baldosa»');
  define('kit_out', EVENT, ['cuando', { dropdown: kinds, name: 'A' }, 'sale del mapa'], 'event',
         'Lo que sale del mapa desaparece. Si es el jugador y no usas este bloque, pierde.');
  define('kit_every', EVENT, ['cada', { number: 2, min: 0.1, max: 600, step: 0.1, name: 'SECONDS' }, 'segundos'], 'event');
  define('kit_tap', EVENT, ['al tocar la pantalla'], 'event', 'Dónde: «x tocada», «y tocada»');
  // objects
  define('kit_this', OBJECT, [{ dropdown: [['este', 'este'], ['el otro', 'otro']], name: 'WHO' }], 'Obj');
  define('kit_player', OBJECT, ['el jugador'], 'Obj');
  define('kit_first', OBJECT, ['un objeto', { dropdown: kinds, name: 'KIND' }], 'Obj');
  define('kit_spawn', OBJECT, ['crear', { dropdown: kinds, name: 'KIND' }, { value: true, name: 'X', check: 'Number', label: 'en x' },
    { value: true, name: 'Y', check: 'Number', label: 'y' }], 'statement');
  define('kit_spawn_at', OBJECT, ['crear', { dropdown: kinds, name: 'KIND' }, { value: true, name: 'OBJ', check: 'Obj', label: 'donde está' }], 'statement');
  define('kit_destroy', OBJECT, [{ value: true, name: 'OBJ', check: 'Obj', label: 'quitar' }], 'statement');
  define('kit_set', OBJECT, ['poner', { dropdown: PROPS, name: 'PROP' }, { value: true, name: 'OBJ', check: 'Obj', label: 'de' },
    { value: true, name: 'V', check: 'Number', label: 'a' }], 'statement');
  define('kit_change', OBJECT, [{ value: true, name: 'V', check: 'Number', label: 'sumar' }, 'a', { dropdown: PROPS, name: 'PROP' },
    { value: true, name: 'OBJ', check: 'Obj', label: 'de' }], 'statement');
  define('kit_get', OBJECT, [{ dropdown: PROPS, name: 'PROP' }, { value: true, name: 'OBJ', check: 'Obj', label: 'de' }], 'Number');
  define('kit_count', OBJECT, ['cuántos objetos', { dropdown: kinds, name: 'KIND' }, 'hay'], 'Number');
  define('kit_count_on', OBJECT, ['cuántos objetos', { dropdown: kinds, name: 'KIND' }, 'hay sobre', { dropdown: tiles, name: 'TILE' }],
         'Number', 'Los que están quietos encima de esa baldosa: cajas en sus marcas');
  define('kit_sprite', OBJECT, [{ value: true, name: 'OBJ', check: 'Obj', label: 'cambiar el dibujo de' }, 'a',
    { dropdown: kinds, name: 'KIND' }], 'statement');
  // actions
  define('kit_sound', ACTION, ['sonar', { dropdown: sounds, name: 'SOUND' }], 'statement');
  define('kit_music', ACTION, ['poner la música', { dropdown: tunes, name: 'MUSIC' }], 'statement',
         'Una música traída en Sonidos, en bucle (cada nivel empieza con la suya, si tiene)');
  define('kit_music_stop', ACTION, ['parar la música'], 'statement');
  define('kit_label', ACTION, [{ value: true, name: 'TEXT', label: 'mostrar' }, { dropdown: PLACES, name: 'WHERE' }], 'statement',
         'Se queda en pantalla hasta que se cambia');
  define('kit_message', ACTION, [{ value: true, name: 'TEXT', label: 'mostrar el mensaje' }, 'durante',
    { number: 2, min: 0.1, max: 60, step: 0.1, name: 'SECONDS' }, 'segundos'], 'statement');
  define('kit_win', ACTION, [{ value: true, name: 'TEXT', label: 'ganar y decir' }], 'statement',
         'Se acaba la partida: con A se vuelve a la portada');
  define('kit_lose', ACTION, [{ value: true, name: 'TEXT', label: 'perder y decir' }], 'statement',
         'Con A se repite el nivel');
  define('kit_shake', ACTION, ['sacudir la pantalla'], 'statement');
  define('kit_burst', ACTION, ['chispas', { dropdown: COLOURS, name: 'COLOUR' }, { value: true, name: 'OBJ', check: 'Obj', label: 'en' }], 'statement');
  define('kit_restart', ACTION, ['volver a empezar'], 'statement', 'La partida, desde el primer nivel');
  define('kit_next_level', ACTION, ['pasar al siguiente nivel'], 'statement', 'Después del último, se gana');
  define('kit_retry', ACTION, ['repetir el nivel'], 'statement', 'Este nivel desde su principio');
  define('kit_goto_level', ACTION, ['ir a', { dropdown: someLevel, name: 'LEVEL' }], 'statement');
  define('kit_set_tile', ACTION, ['poner', { dropdown: () => [['nada', '_'], ...tiles().filter(t => t[1] !== '_')], name: 'TILE' },
    { value: true, name: 'X', check: 'Number', label: 'en x' }, { value: true, name: 'Y', check: 'Number', label: 'y' }], 'statement');
  // input
  define('kit_button', INPUT, [{ dropdown: BUTTONS, name: 'BUTTON' }, 'está pulsado'], 'Boolean');
  define('kit_tap_x', INPUT, ['x tocada'], 'Number');
  define('kit_tap_y', INPUT, ['y tocada'], 'Number');
  define('kit_tile_x', INPUT, ['x de la baldosa'], 'Number', 'Dentro de «cuando … pisa …»');
  define('kit_tile_y', INPUT, ['y de la baldosa'], 'Number', 'Dentro de «cuando … pisa …»');
  // the microphone
  define('kit_clap', MIC, ['al dar una palmada'], 'event', 'El micrófono oye un ruido de repente: una palmada, un golpe en la mesa, un grito');
  define('kit_blow', MIC, ['al soplar'], 'event', 'El micrófono oye un soplido: fuerte y sin nota, un momento');
  define('kit_mic_level', MIC, ['volumen del micrófono'], 'Number', 'De 0 (silencio) a 100 (un grito cerca). 0 si no hay micrófono');
  define('kit_mic_note', MIC, ['nota que se oye (Hz)'], 'Number', 'La nota de una voz o un silbido; 0 si no hay una clara. Un La es 440');
  // conversations
  define('kit_say', TALK, [{ value: true, name: 'WHO' }, { value: true, name: 'TEXT', label: 'dice' }], 'statement',
         'Un cuadro abajo, letra a letra; el juego espera; A sigue. Varios seguidos salen uno tras otro');
  define('kit_ask', TALK, [{ value: true, name: 'TEXT', label: 'preguntar' }, { value: true, name: 'A', label: 'opciones' },
    { value: true, name: 'B' }, { value: true, name: 'C' }], 'statement', 'Las opciones vacías no salen. Se elige con arriba, abajo y A');
  define('kit_answer', TALK, ['al elegir la respuesta', { dropdown: [['1', '1'], ['2', '2'], ['3', '3']], name: 'N' }], 'event');
  // video
  define('kit_video_full', VIDEO, ['poner el vídeo', { dropdown: videos, name: 'VIDEO' }, 'en toda la pantalla'], 'statement',
         'El juego espera a que acabe (A lo salta). Los vídeos se traen en la pestaña Sonidos');
  define('kit_video_window', VIDEO, ['poner el vídeo', { dropdown: videos, name: 'VIDEO' }, 'en una ventana',
    { dropdown: WINDOWS, name: 'WHERE' }], 'statement', 'En bucle, mientras se juega');
  define('kit_video_stop', VIDEO, ['quitar el vídeo'], 'statement');
  define('kit_video_end', VIDEO, ['al acabar el vídeo'], 'event', 'Uno en toda la pantalla, cuando acaba o se salta');
  defineLua();
}

// ------------------------------------------------------------------ Lua

const q = s => JSON.stringify(String(s)); // a Lua string (JSON's escapes are Lua's for these names)

function defineLua() {
  const g = lua.luaGenerator, O = lua.Order;
  const val = (b, name, d = '0') => g.valueToCode(b, name, O.NONE) || d;
  const obj = b => g.valueToCode(b, 'OBJ', O.NONE) || 'nil';
  const text = b => g.valueToCode(b, 'TEXT', O.NONE) || '""';
  const body = b => g.statementToCode(b, 'DO') || '';
  const on = (head, b, args = '') => `kit.on(${head}, function(${args})\n${body(b)}end)\n`;
  const F = g.forBlock;
  F.kit_start = b => on('"start"', b);
  F.kit_level = b => on(b.getFieldValue('LEVEL') === '_' ? '"level"' : `"level", ${q(b.getFieldValue('LEVEL'))}`, b);
  F.kit_tick = b => on('"tick"', b);
  F.kit_press = b => on(`"press", ${q(b.getFieldValue('BUTTON'))}`, b);
  F.kit_hold = b => on(`"hold", ${q(b.getFieldValue('BUTTON'))}`, b);
  F.kit_touch = b => on(`"touch", ${q(b.getFieldValue('A'))}, ${q(b.getFieldValue('B'))}`, b, 'este, otro');
  F.kit_tile = b => on(`"tile", ${q(b.getFieldValue('A'))}, ${q(b.getFieldValue('TILE'))}`, b, 'este, tile_x, tile_y');
  F.kit_out = b => on(`"out", ${q(b.getFieldValue('A'))}`, b, 'este');
  F.kit_every = b => on(`"every", ${Number(b.getFieldValue('SECONDS')) || 1}`, b);
  F.kit_tap = b => on('"tap"', b, 'tap_x, tap_y');
  F.kit_this = b => [b.getFieldValue('WHO'), O.ATOMIC];
  F.kit_player = () => ['kit.player()', O.HIGH];
  F.kit_first = b => [`kit.first(${q(b.getFieldValue('KIND'))})`, O.HIGH];
  F.kit_spawn = b => `kit.spawn(${q(b.getFieldValue('KIND'))}, ${val(b, 'X')}, ${val(b, 'Y')})\n`;
  F.kit_spawn_at = b => `kit.spawn_at(${q(b.getFieldValue('KIND'))}, ${obj(b)})\n`;
  F.kit_destroy = b => `kit.destroy(${obj(b)})\n`;
  F.kit_set = b => `kit.set(${obj(b)}, ${q(b.getFieldValue('PROP'))}, ${val(b, 'V')})\n`;
  F.kit_change = b => `kit.change(${obj(b)}, ${q(b.getFieldValue('PROP'))}, ${val(b, 'V')})\n`;
  F.kit_get = b => [`kit.get(${obj(b)}, ${q(b.getFieldValue('PROP'))})`, O.HIGH];
  F.kit_count = b => [`kit.count(${q(b.getFieldValue('KIND'))})`, O.HIGH];
  F.kit_count_on = b => [`kit.count_on(${q(b.getFieldValue('KIND'))}, ${q(b.getFieldValue('TILE'))})`, O.HIGH];
  F.kit_sprite = b => `kit.set_sprite(${obj(b)}, ${q(b.getFieldValue('KIND'))})\n`;
  F.kit_sound = b => `kit.sound(${q(b.getFieldValue('SOUND'))})\n`;
  F.kit_music = b => `kit.music(${q(b.getFieldValue('MUSIC'))})\n`;
  F.kit_music_stop = () => 'kit.music(nil)\n';
  F.kit_label = b => `kit.label(${q(b.getFieldValue('WHERE'))}, ${text(b)}, ${q(b.getFieldValue('WHERE'))})\n`;
  F.kit_message = b => `kit.message(${text(b)}, ${Number(b.getFieldValue('SECONDS')) || 2})\n`;
  F.kit_win = b => `kit.win(${text(b)})\n`;
  F.kit_lose = b => `kit.lose(${text(b)})\n`;
  F.kit_shake = () => 'kit.shake(5)\n';
  F.kit_burst = b => `kit.burst_at(${obj(b)}, ${b.getFieldValue('COLOUR')})\n`;
  F.kit_restart = () => 'kit.restart()\n';
  F.kit_next_level = () => 'kit.next_level()\n';
  F.kit_retry = () => 'kit.retry()\n';
  F.kit_goto_level = b => `kit.goto_level(${q(b.getFieldValue('LEVEL'))})\n`;
  F.kit_set_tile = b => `kit.set_tile(${val(b, 'X')}, ${val(b, 'Y')}, ${q(b.getFieldValue('TILE') === '_' ? '' : b.getFieldValue('TILE'))})\n`;
  F.kit_button = b => [`btn(${q(b.getFieldValue('BUTTON'))})`, O.HIGH];
  F.kit_tap_x = () => ['(tap_x or 0)', O.ATOMIC];
  F.kit_tap_y = () => ['(tap_y or 0)', O.ATOMIC];
  F.kit_tile_x = () => ['(tile_x or 0)', O.ATOMIC];
  F.kit_tile_y = () => ['(tile_y or 0)', O.ATOMIC];
  F.kit_clap = b => on('"clap"', b);
  F.kit_blow = b => on('"blow"', b);
  F.kit_mic_level = () => ['kit.mic_level()', O.HIGH];
  F.kit_mic_note = () => ['kit.mic_note()', O.HIGH];
  F.kit_say = b => `kit.say(${val(b, 'WHO', '""')}, ${text(b)})\n`;
  F.kit_ask = b => `kit.ask(${text(b)}, ${val(b, 'A', '""')}, ${val(b, 'B', '""')}, ${val(b, 'C', '""')})\n`;
  F.kit_answer = b => on(`"answer", ${Number(b.getFieldValue('N')) || 1}`, b);
  F.kit_video_full = b => `kit.video(${q(b.getFieldValue('VIDEO'))}, "full")\n`;
  F.kit_video_window = b => `kit.video(${q(b.getFieldValue('VIDEO'))}, ${q(b.getFieldValue('WHERE'))})\n`;
  F.kit_video_stop = () => 'kit.video()\n';
  F.kit_video_end = b => on('"video_end"', b);
}

// The Lua of the events on the workspace; blocks left loose outside an event do nothing (and are not written).
export function workspaceLua(ws) {
  const g = lua.luaGenerator;
  g.init(ws);
  // every variable starts at 0: "add 1 to points" works without setting it first (nil + 1 would stop the game)
  let code = ws.getVariableMap().getAllVariables().map(v => `${g.getVariableName(v.getId())} = 0\n`).join('');
  if (code) code += '\n';
  for (const b of ws.getTopBlocks(true)) if (EVENTS.has(b.type) && b.isEnabled()) code += g.blockToCode(b) + '\n';
  return g.finish(code);
}

export const TOOLBOX = {
  kind: 'categoryToolbox',
  contents: [
    { kind: 'category', name: 'Eventos', colour: EVENT, contents: ['kit_start', 'kit_level', 'kit_tick', 'kit_press', 'kit_hold', 'kit_touch',
      'kit_tile', 'kit_out', 'kit_every', 'kit_tap'].map(type => ({ kind: 'block', type })) },
    { kind: 'category', name: 'Objetos', colour: OBJECT, contents: [
      { kind: 'block', type: 'kit_this' }, { kind: 'block', type: 'kit_player' }, { kind: 'block', type: 'kit_first' },
      { kind: 'block', type: 'kit_spawn', inputs: { X: num(100), Y: num(50) } },
      { kind: 'block', type: 'kit_spawn_at', inputs: { OBJ: thisBlock() } },
      { kind: 'block', type: 'kit_destroy', inputs: { OBJ: thisBlock('otro') } },
      { kind: 'block', type: 'kit_set', inputs: { OBJ: thisBlock(), V: num(0) } },
      { kind: 'block', type: 'kit_change', inputs: { OBJ: thisBlock(), V: num(1) } },
      { kind: 'block', type: 'kit_get', inputs: { OBJ: thisBlock() } }, { kind: 'block', type: 'kit_count' },
      { kind: 'block', type: 'kit_count_on' },
      { kind: 'block', type: 'kit_sprite', inputs: { OBJ: thisBlock() } }] },
    { kind: 'category', name: 'Acciones', colour: ACTION, contents: [
      { kind: 'block', type: 'kit_sound' }, { kind: 'block', type: 'kit_music' }, { kind: 'block', type: 'kit_music_stop' },
      { kind: 'block', type: 'kit_label', inputs: { TEXT: str('Puntos: 0') } },
      { kind: 'block', type: 'kit_message', inputs: { TEXT: str('¡Hola!') } },
      { kind: 'block', type: 'kit_win', inputs: { TEXT: str('¡Has ganado!') } },
      { kind: 'block', type: 'kit_lose', inputs: { TEXT: str('Has perdido') } }, { kind: 'block', type: 'kit_shake' },
      { kind: 'block', type: 'kit_burst', inputs: { OBJ: thisBlock() } }, { kind: 'block', type: 'kit_next_level' },
      { kind: 'block', type: 'kit_goto_level' }, { kind: 'block', type: 'kit_retry' }, { kind: 'block', type: 'kit_restart' },
      { kind: 'block', type: 'kit_set_tile', inputs: { X: num(0), Y: num(0) } }] },
    { kind: 'category', name: 'Mandos', colour: INPUT, contents: ['kit_button', 'kit_tap_x', 'kit_tap_y', 'kit_tile_x', 'kit_tile_y']
      .map(type => ({ kind: 'block', type })) },
    { kind: 'category', name: 'Micrófono', colour: MIC, contents: ['kit_clap', 'kit_blow', 'kit_mic_level', 'kit_mic_note']
      .map(type => ({ kind: 'block', type })) },
    { kind: 'category', name: 'Diálogos', colour: TALK, contents: [
      { kind: 'block', type: 'kit_say', inputs: { WHO: str('Ana'), TEXT: str('¡Hola! ¿Me ayudas?') } },
      { kind: 'block', type: 'kit_ask', inputs: { TEXT: str('¿Vienes?'), A: str('Sí'), B: str('No'), C: str('') } },
      { kind: 'block', type: 'kit_answer' }] },
    { kind: 'category', name: 'Vídeo', colour: VIDEO, contents: ['kit_video_full', 'kit_video_window', 'kit_video_stop',
      'kit_video_end'].map(type => ({ kind: 'block', type })) },
    { kind: 'sep' },
    { kind: 'category', name: 'Condiciones', categorystyle: 'logic_category', contents: ['controls_if', 'logic_compare', 'logic_operation',
      'logic_negate', 'logic_boolean'].map(type => ({ kind: 'block', type })) },
    { kind: 'category', name: 'Repetir', categorystyle: 'loop_category', contents: [
      { kind: 'block', type: 'controls_repeat_ext', inputs: { TIMES: num(3) } }, { kind: 'block', type: 'controls_whileUntil' }] },
    { kind: 'category', name: 'Números', categorystyle: 'math_category', contents: [
      { kind: 'block', type: 'math_number' }, { kind: 'block', type: 'math_arithmetic' },
      { kind: 'block', type: 'math_random_int', inputs: { FROM: num(1), TO: num(10) } }, { kind: 'block', type: 'math_round' }] },
    { kind: 'category', name: 'Texto', categorystyle: 'text_category', contents: [
      { kind: 'block', type: 'text' }, { kind: 'block', type: 'text_join' }] },
    { kind: 'category', name: 'Variables', categorystyle: 'variable_category', custom: 'VARIABLE' },
  ],
};

function num(n) { return { shadow: { type: 'math_number', fields: { NUM: n } } }; }
function str(s) { return { shadow: { type: 'text', fields: { TEXT: s } } }; }
function thisBlock(who = 'este') { return { block: { type: 'kit_this', fields: { WHO: who } } }; }

// ------------------------------------------------------------------ the starter game's blocks

const b = (type, fields = {}, inputs = {}, next = null) => {
  const out = { type, fields };
  if (Object.keys(inputs).length) out.inputs = inputs;
  if (next) out.next = { block: next };
  return out;
};
const chain = list => list.reduceRight((next, blk) => (blk.next = next ? { block: next } : undefined, blk), null) && list[0];
const T = s => ({ block: b('text', { TEXT: s }) });
const V = id => ({ block: b('variables_get', { VAR: { id } }) });
const join = (...parts) => ({ block: { type: 'text_join', extraState: { itemCount: parts.length },
  inputs: Object.fromEntries(parts.map((p, i) => ['ADD' + i, p])) } });
const THIS = who => ({ block: b('kit_this', { WHO: who }) });

const N = n => ({ block: b('math_number', { NUM: n }) });
const set = (id, value) => b('variables_set', { VAR: { id } }, { VALUE: value });
const add = (id, n) => b('math_change', { VAR: { id } }, { DELTA: N(n) });
const cmp = (op, a, c) => ({ block: { type: 'logic_compare', fields: { OP: op }, inputs: { A: a, B: c } } });
const iff = (cond, then, otherwise) => ({ type: 'controls_if', ...(otherwise ? { extraState: { hasElse: true } } : {}),
  inputs: { IF0: cond, DO0: { block: chain(then) }, ...(otherwise ? { ELSE: { block: chain(otherwise) } } : {}) } });
const rnd = (lo, hi) => ({ block: { type: 'math_random_int', inputs: { FROM: N(lo), TO: N(hi) } } });
const label = (where, text) => b('kit_label', { WHERE: where }, { TEXT: text });
const say = (text, seconds = 1.5) => b('kit_message', { SECONDS: seconds }, { TEXT: T(text) });
const sound = name => b('kit_sound', { SOUND: name });
const lose = text => [sound('golpe'), b('kit_shake'), b('kit_lose', {}, { TEXT: T(text) })];

// Each template's blocks, in a column (main.js arranges them): ev(type, fields, statements)
const ev = (type, fields, statements) => ({ ...b(type, fields, { DO: { block: chain(statements) } }), x: 0, y: 0 });

const TEMPLATE_BLOCKS = {
  plataformas() {
    const P = 'v_puntos';
    return [[{ name: 'puntos', id: P }], [
      ev('kit_start', {}, [set(P, N(0)), label('top_left', T('Monedas: 0'))]),
      ev('kit_touch', { A: 'heroe', B: 'moneda' }, [
        b('kit_destroy', {}, { OBJ: THIS('otro') }), sound('moneda'), b('kit_burst', { COLOUR: '0xFFE070' }, { OBJ: THIS('otro') }),
        add(P, 1), label('top_left', join(T('Monedas: '), V(P)))]),
      ev('kit_touch', { A: 'heroe', B: 'babosa' }, lose('¡Te ha pillado la babosa!')),
      ev('kit_tile', { A: 'heroe', TILE: 'pinchos' }, [b('kit_lose', {}, { TEXT: T('¡Pinchos!') })]),
      ev('kit_out', { A: 'heroe' }, [sound('golpe'), b('kit_lose', {}, { TEXT: T('¡Te has caído!') })]),
      ev('kit_touch', { A: 'heroe', B: 'meta' }, [sound('moneda'), b('kit_next_level')]),
      ev('kit_press', { BUTTON: 'a' }, [sound('salto')]),
    ]];
  },
  aventura() {
    const G = 'v_gemas', K = 'v_llaves';
    return [[{ name: 'gemas', id: G }, { name: 'llaves', id: K }], [
      ev('kit_start', {}, [set(G, N(0)), set(K, N(0)), label('top_left', T('Gemas: 0')), label('top_right', T('Llaves: 0'))]),
      ev('kit_touch', { A: 'exploradora', B: 'gema' }, [
        b('kit_destroy', {}, { OBJ: THIS('otro') }), sound('gema'), b('kit_burst', { COLOUR: '0xC070FF' }, { OBJ: THIS('otro') }),
        add(G, 1), label('top_left', join(T('Gemas: '), V(G)))]),
      ev('kit_touch', { A: 'exploradora', B: 'llave' }, [
        b('kit_destroy', {}, { OBJ: THIS('otro') }), sound('llave'), add(K, 1), label('top_right', join(T('Llaves: '), V(K))),
        say('¡Una llave!')]),
      ev('kit_tile', { A: 'exploradora', TILE: 'puerta' }, [iff(cmp('GT', V(K), N(0)), [
        b('kit_set_tile', { TILE: '_' }, { X: { block: b('kit_tile_x') }, Y: { block: b('kit_tile_y') } }), add(K, -1),
        label('top_right', join(T('Llaves: '), V(K))), sound('puerta'), say('¡Abierta!', 1)], [say('Hace falta una llave')])]),
      ev('kit_touch', { A: 'exploradora', B: 'cangrejo' }, lose('¡Un cangrejo!')),
      ev('kit_touch', { A: 'exploradora', B: 'fantasma' }, lose('¡Un fantasma!')),
      ev('kit_touch', { A: 'exploradora', B: 'escalera' }, [sound('llave'), b('kit_next_level')]),
    ]];
  },
  naves() {
    const P = 'v_puntos', D = 'v_derribados', W = 'v_oleada';
    const hit = (enemy, points) => ev('kit_touch', { A: 'laser', B: enemy }, [
      b('kit_destroy', {}, { OBJ: THIS('este') }), b('kit_destroy', {}, { OBJ: THIS('otro') }),
      b('kit_burst', { COLOUR: '0xFFE070' }, { OBJ: THIS('otro') }), sound('explosion'), add(P, points), add(D, 1),
      label('top_left', join(T('Puntos: '), V(P)))]);
    const fall = (kind, seconds, only) => ev('kit_every', { SECONDS: seconds }, [
      ...(only ? [iff(cmp('EQ', V(W), N(only)), [b('kit_spawn', { KIND: kind }, { X: rnd(8, 216), Y: N(-16) })])]
        : [b('kit_spawn', { KIND: kind }, { X: rnd(8, 216), Y: N(-16) })])]);
    return [[{ name: 'puntos', id: P }, { name: 'derribados', id: D }, { name: 'oleada', id: W }], [
      ev('kit_start', {}, [set(P, N(0)), set(W, N(1)), label('top_left', T('Puntos: 0'))]),
      ev('kit_level', { LEVEL: '_' }, [set(D, N(0))]),
      ev('kit_level', { LEVEL: 'nivel2' }, [set(W, N(2))]),
      ev('kit_press', { BUTTON: 'a' }, [b('kit_spawn_at', { KIND: 'laser' }, { OBJ: { block: b('kit_player') } }), sound('laser')]),
      fall('ovni', 1.2), fall('cometa', 0.9, 2),
      hit('ovni', 1), hit('cometa', 2),
      ev('kit_touch', { A: 'nave', B: 'ovni' }, lose('¡Te han dado!')),
      ev('kit_touch', { A: 'nave', B: 'cometa' }, lose('¡Un cometa!')),
      ev('kit_tick', {}, [iff(cmp('GTE', V(D), N(12)), [b('kit_next_level')])]),
    ]];
  },
  puzle() {
    return [[], [
      ev('kit_start', {}, [label('bottom', T('B: empezar el puzle otra vez'))]),
      ev('kit_press', { BUTTON: 'b' }, [sound('otra'), b('kit_retry')]),
      ev('kit_tick', {}, [iff(cmp('EQ', { block: b('kit_count_on', { KIND: 'caja', TILE: 'diana' }) },
        { block: b('kit_count', { KIND: 'caja' }) }), [sound('bien'), b('kit_next_level')])]),
    ]];
  },
};

export function templateBlocks(key = 'plataformas') {
  const [variables, blocks] = (TEMPLATE_BLOCKS[key] || TEMPLATE_BLOCKS.plataformas)();
  return { variables, blocks: { languageVersion: 0, blocks } };
}
