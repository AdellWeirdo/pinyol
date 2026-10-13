// The blocks of the Logic tab (Blockly) and the Lua they become: calls to kit (np2d/lib/kit.lua). Events are the hat
// blocks a game is made of; the rest is what happens in them. Dropdowns list what the project has (its objects,
// tiles and sounds), read when they open.
/* global Blockly, lua */

let project = null; // the project being edited (set by main.js)
export function setProject(p) { project = p; }

const none = [['(ninguno)', '_']];
const kinds = () => { const k = project ? project.drawings.filter(d => d.use === 'object').map(d => [d.name, d.name]) : []; return k.length ? k : none; };
const tiles = () => { const t = project ? project.drawings.filter(d => d.use === 'tile').map(d => [d.name, d.name]) : []; return t.length ? t : none; };
const sounds = () => { const s = project ? project.sounds.map(x => [x.name, x.name]) : []; return s.length ? s : none; };
const BUTTONS = [['A', 'a'], ['B', 'b'], ['C', 'c'], ['arriba', 'up'], ['abajo', 'down'], ['izquierda', 'left'],
  ['derecha', 'right'], ['START', 'start']];
const PROPS = [['x', 'x'], ['y', 'y'], ['velocidad x', 'vx'], ['velocidad y', 'vy']];
const PLACES = [['arriba a la izquierda', 'top_left'], ['arriba', 'top'], ['arriba a la derecha', 'top_right'],
  ['abajo', 'bottom'], ['abajo a la izquierda', 'bottom_left'], ['abajo a la derecha', 'bottom_right']];
const COLOURS = [['amarillas', '0xFFE070'], ['blancas', '0xFFFFFF'], ['rojas', '0xFF4040'], ['verdes', '0x60E060'],
  ['azules', '0x50A0FF'], ['moradas', '0xC070FF']];

const EVENT = 40, OBJECT = 200, ACTION = 290, INPUT = 160;
export const EVENTS = new Set(['kit_start', 'kit_tick', 'kit_press', 'kit_hold', 'kit_touch', 'kit_tile', 'kit_every', 'kit_tap']);

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
  define('kit_start', EVENT, ['al empezar el juego'], 'event', 'Una vez, al empezar (y al volver a empezar)');
  define('kit_tick', EVENT, ['en cada momento'], 'event', '60 veces por segundo');
  define('kit_press', EVENT, ['al pulsar', { dropdown: BUTTONS, name: 'BUTTON' }], 'event');
  define('kit_hold', EVENT, ['mientras se pulsa', { dropdown: BUTTONS, name: 'BUTTON' }], 'event');
  define('kit_touch', EVENT, ['cuando', { dropdown: kinds, name: 'A' }, 'toca', { dropdown: kinds, name: 'B' }], 'event',
         'Dentro, «este» es el primero y «el otro» el segundo');
  define('kit_tile', EVENT, ['cuando', { dropdown: kinds, name: 'A' }, 'pisa', { dropdown: tiles, name: 'TILE' }], 'event');
  define('kit_every', EVENT, ['cada', { number: 1, min: 0.1, max: 600, step: 0.1, name: 'SECONDS' }, 'segundos'], 'event');
  define('kit_tap', EVENT, ['al tocar la pantalla'], 'event', 'Dónde: «x tocada», «y tocada»');
  // objects
  define('kit_this', OBJECT, [{ dropdown: [['este', 'este'], ['el otro', 'otro']], name: 'WHO' }], 'Obj');
  define('kit_player', OBJECT, ['el jugador'], 'Obj');
  define('kit_first', OBJECT, ['un', { dropdown: kinds, name: 'KIND' }], 'Obj');
  define('kit_spawn', OBJECT, ['crear', { dropdown: kinds, name: 'KIND' }, { value: true, name: 'X', check: 'Number', label: 'en x' },
    { value: true, name: 'Y', check: 'Number', label: 'y' }], 'statement');
  define('kit_spawn_at', OBJECT, ['crear', { dropdown: kinds, name: 'KIND' }, { value: true, name: 'OBJ', check: 'Obj', label: 'donde está' }], 'statement');
  define('kit_destroy', OBJECT, [{ value: true, name: 'OBJ', check: 'Obj', label: 'quitar' }], 'statement');
  define('kit_set', OBJECT, ['poner', { dropdown: PROPS, name: 'PROP' }, { value: true, name: 'OBJ', check: 'Obj', label: 'de' },
    { value: true, name: 'V', check: 'Number', label: 'a' }], 'statement');
  define('kit_change', OBJECT, [{ value: true, name: 'V', check: 'Number', label: 'sumar' }, 'a', { dropdown: PROPS, name: 'PROP' },
    { value: true, name: 'OBJ', check: 'Obj', label: 'de' }], 'statement');
  define('kit_get', OBJECT, [{ dropdown: PROPS, name: 'PROP' }, { value: true, name: 'OBJ', check: 'Obj', label: 'de' }], 'Number');
  define('kit_count', OBJECT, ['cuántos', { dropdown: kinds, name: 'KIND' }, 'hay'], 'Number');
  define('kit_sprite', OBJECT, [{ value: true, name: 'OBJ', check: 'Obj', label: 'cambiar el dibujo de' }, 'a',
    { dropdown: kinds, name: 'KIND' }], 'statement');
  // actions
  define('kit_sound', ACTION, ['sonar', { dropdown: sounds, name: 'SOUND' }], 'statement');
  define('kit_label', ACTION, [{ value: true, name: 'TEXT', label: 'mostrar' }, { dropdown: PLACES, name: 'WHERE' }], 'statement',
         'Se queda en pantalla hasta que se cambia');
  define('kit_message', ACTION, [{ value: true, name: 'TEXT', label: 'mensaje' }, 'durante',
    { number: 2, min: 0.1, max: 60, step: 0.1, name: 'SECONDS' }, 's'], 'statement');
  define('kit_win', ACTION, [{ value: true, name: 'TEXT', label: 'ganar:' }], 'statement');
  define('kit_lose', ACTION, [{ value: true, name: 'TEXT', label: 'perder:' }], 'statement');
  define('kit_shake', ACTION, ['sacudir la pantalla'], 'statement');
  define('kit_burst', ACTION, ['chispas', { dropdown: COLOURS, name: 'COLOUR' }, { value: true, name: 'OBJ', check: 'Obj', label: 'en' }], 'statement');
  define('kit_restart', ACTION, ['volver a empezar'], 'statement');
  define('kit_set_tile', ACTION, ['poner', { dropdown: () => [['nada', '_'], ...tiles().filter(t => t[1] !== '_')], name: 'TILE' },
    { value: true, name: 'X', check: 'Number', label: 'en x' }, { value: true, name: 'Y', check: 'Number', label: 'y' }], 'statement');
  // input
  define('kit_button', INPUT, [{ dropdown: BUTTONS, name: 'BUTTON' }, 'está pulsado'], 'Boolean');
  define('kit_tap_x', INPUT, ['x tocada'], 'Number');
  define('kit_tap_y', INPUT, ['y tocada'], 'Number');
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
  F.kit_tick = b => on('"tick"', b);
  F.kit_press = b => on(`"press", ${q(b.getFieldValue('BUTTON'))}`, b);
  F.kit_hold = b => on(`"hold", ${q(b.getFieldValue('BUTTON'))}`, b);
  F.kit_touch = b => on(`"touch", ${q(b.getFieldValue('A'))}, ${q(b.getFieldValue('B'))}`, b, 'este, otro');
  F.kit_tile = b => on(`"tile", ${q(b.getFieldValue('A'))}, ${q(b.getFieldValue('TILE'))}`, b, 'este');
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
  F.kit_sprite = b => `kit.set_sprite(${obj(b)}, ${q(b.getFieldValue('KIND'))})\n`;
  F.kit_sound = b => `kit.sound(${q(b.getFieldValue('SOUND'))})\n`;
  F.kit_label = b => `kit.label(${q(b.getFieldValue('WHERE'))}, ${text(b)}, ${q(b.getFieldValue('WHERE'))})\n`;
  F.kit_message = b => `kit.message(${text(b)}, ${Number(b.getFieldValue('SECONDS')) || 2})\n`;
  F.kit_win = b => `kit.win(${text(b)})\n`;
  F.kit_lose = b => `kit.lose(${text(b)})\n`;
  F.kit_shake = () => 'kit.shake(5)\n';
  F.kit_burst = b => `kit.burst_at(${obj(b)}, ${b.getFieldValue('COLOUR')})\n`;
  F.kit_restart = () => 'kit.restart()\n';
  F.kit_set_tile = b => `kit.set_tile(${val(b, 'X')}, ${val(b, 'Y')}, ${q(b.getFieldValue('TILE') === '_' ? '' : b.getFieldValue('TILE'))})\n`;
  F.kit_button = b => [`btn(${q(b.getFieldValue('BUTTON'))})`, O.HIGH];
  F.kit_tap_x = () => ['(tap_x or 0)', O.ATOMIC];
  F.kit_tap_y = () => ['(tap_y or 0)', O.ATOMIC];
}

// The Lua of the events on the workspace; blocks left loose outside an event do nothing (and are not written).
export function workspaceLua(ws) {
  const g = lua.luaGenerator;
  g.init(ws);
  let code = '';
  for (const b of ws.getTopBlocks(true)) if (EVENTS.has(b.type) && b.isEnabled()) code += g.blockToCode(b) + '\n';
  return g.finish(code);
}

export const TOOLBOX = {
  kind: 'categoryToolbox',
  contents: [
    { kind: 'category', name: 'Eventos', colour: EVENT, contents: ['kit_start', 'kit_tick', 'kit_press', 'kit_hold', 'kit_touch',
      'kit_tile', 'kit_every', 'kit_tap'].map(type => ({ kind: 'block', type })) },
    { kind: 'category', name: 'Objetos', colour: OBJECT, contents: [
      { kind: 'block', type: 'kit_this' }, { kind: 'block', type: 'kit_player' }, { kind: 'block', type: 'kit_first' },
      { kind: 'block', type: 'kit_spawn', inputs: { X: num(100), Y: num(50) } },
      { kind: 'block', type: 'kit_spawn_at', inputs: { OBJ: thisBlock() } },
      { kind: 'block', type: 'kit_destroy', inputs: { OBJ: thisBlock('otro') } },
      { kind: 'block', type: 'kit_set', inputs: { OBJ: thisBlock(), V: num(0) } },
      { kind: 'block', type: 'kit_change', inputs: { OBJ: thisBlock(), V: num(1) } },
      { kind: 'block', type: 'kit_get', inputs: { OBJ: thisBlock() } }, { kind: 'block', type: 'kit_count' },
      { kind: 'block', type: 'kit_sprite', inputs: { OBJ: thisBlock() } }] },
    { kind: 'category', name: 'Acciones', colour: ACTION, contents: [
      { kind: 'block', type: 'kit_sound' }, { kind: 'block', type: 'kit_label', inputs: { TEXT: str('Puntos: 0') } },
      { kind: 'block', type: 'kit_message', inputs: { TEXT: str('¡Hola!') } },
      { kind: 'block', type: 'kit_win', inputs: { TEXT: str('¡Has ganado!') } },
      { kind: 'block', type: 'kit_lose', inputs: { TEXT: str('Has perdido') } }, { kind: 'block', type: 'kit_shake' },
      { kind: 'block', type: 'kit_burst', inputs: { OBJ: thisBlock() } }, { kind: 'block', type: 'kit_restart' },
      { kind: 'block', type: 'kit_set_tile', inputs: { X: num(0), Y: num(0) } }] },
    { kind: 'category', name: 'Mandos', colour: INPUT, contents: ['kit_button', 'kit_tap_x', 'kit_tap_y'].map(type => ({ kind: 'block', type })) },
    { kind: 'sep' },
    { kind: 'category', name: 'Lógica', categorystyle: 'logic_category', contents: ['controls_if', 'logic_compare', 'logic_operation',
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

export function templateBlocks() {
  const P = 'v_puntos';
  const event = (x, y, type, fields, statements) => ({ ...b(type, fields, { DO: { block: chain(statements) } }), x, y });
  return {
    variables: [{ name: 'puntos', id: P }],
    blocks: { languageVersion: 0, blocks: [
      event(20, 20, 'kit_start', {}, [
        b('variables_set', { VAR: { id: P } }, { VALUE: { block: b('math_number', { NUM: 0 }) } }),
        b('kit_label', { WHERE: 'top_left' }, { TEXT: T('Monedas: 0') })]),
      event(20, 170, 'kit_touch', { A: 'heroe', B: 'moneda' }, [
        b('kit_destroy', {}, { OBJ: THIS('otro') }), b('kit_sound', { SOUND: 'moneda' }),
        b('kit_burst', { COLOUR: '0xFFE070' }, { OBJ: THIS('otro') }),
        b('math_change', { VAR: { id: P } }, { DELTA: { block: b('math_number', { NUM: 1 }) } }),
        b('kit_label', { WHERE: 'top_left' }, { TEXT: join(T('Monedas: '), V(P)) })]),
      event(480, 20, 'kit_touch', { A: 'heroe', B: 'babosa' }, [
        b('kit_sound', { SOUND: 'golpe' }), b('kit_shake'), b('kit_lose', {}, { TEXT: T('¡Te ha pillado la babosa!') })]),
      event(480, 190, 'kit_tile', { A: 'heroe', TILE: 'pinchos' }, [b('kit_lose', {}, { TEXT: T('¡Pinchos!') })]),
      event(480, 300, 'kit_touch', { A: 'heroe', B: 'meta' }, [
        b('kit_win', {}, { TEXT: join(T('¡Llegaste! Monedas: '), V(P)) })]),
      event(20, 420, 'kit_press', { BUTTON: 'a' }, [b('kit_sound', { SOUND: 'salto' })]),
    ] },
  };
}
