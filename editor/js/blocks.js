// The blocks of the Logic tab (Blockly) and the Lua they become: calls to kit (pinyol/lib/kit.lua). Events are the hat
// blocks a game is made of; the rest is what happens in them. Dropdowns list what the project has (its objects,
// tiles and sounds), read when they open.
/* global Blockly, lua */
import { t } from './i18n.js';

let project = null; // the project being edited (set by main.js)
export function setProject(p) { project = p; }

const none = [[t('(no hay)'), '_']];
const kinds = () => { const k = project ? project.drawings.filter(d => d.use === 'object').map(d => [d.name, d.name]) : []; return k.length ? k : none; };
const tiles = () => { const l = project ? project.drawings.filter(d => d.use === 'tile').map(d => [d.name, d.name]) : []; return l.length ? l : none; };
const levels = () => (project ? project.levels.map(l => [l.name, l.id]) : []);
const anyLevel = () => [[t('cualquier nivel'), '_'], ...levels()];
const someLevel = () => { const l = levels(); return l.length ? l : none; };
const named = keep => () => { const s = project ? project.sounds.filter(keep).map(x => [x.name, x.name]) : []; return s.length ? s : none; };
const sounds = named(x => x.use !== 'music'), tunes = named(x => x.use === 'music');
const videos = () => { const v = project && project.videos ? project.videos.map(x => [x.name, x.name]) : []; return v.length ? v : none; };
const WINDOWS = [[t('arriba a la derecha'), 'top_right'], [t('arriba a la izquierda'), 'top_left'],
  [t('abajo a la derecha'), 'bottom_right'], [t('abajo a la izquierda'), 'bottom_left']];
const BUTTONS = [['A', 'a'], ['B', 'b'], ['C', 'c'], [t('arriba'), 'up'], [t('abajo'), 'down'], [t('izquierda'), 'left'],
  [t('derecha'), 'right'], ['START', 'start']];
const PROPS = [['x', 'x'], ['y', 'y'], [t('velocidad x'), 'vx'], [t('velocidad y'), 'vy']];
const PLACES = [[t('arriba a la izquierda'), 'top_left'], [t('arriba|sitio'), 'top'], [t('arriba a la derecha'), 'top_right'],
  [t('abajo|sitio'), 'bottom'], [t('abajo a la izquierda'), 'bottom_left'], [t('abajo a la derecha'), 'bottom_right']];
const COLOURS = [[t('amarillas'), '0xFFE070'], [t('blancas'), '0xFFFFFF'], [t('rojas'), '0xFF4040'], [t('verdes'), '0x60E060'],
  [t('azules'), '0x50A0FF'], [t('moradas'), '0xC070FF']];

const EVENT = 40, OBJECT = 200, ACTION = 290, INPUT = 160, MIC = 330, TALK = 20, VIDEO = 260, SAVE = 120, LIVES = 0;
const STYLES = [[t('normal'), 'normal'], [t('con sombra'), 'shadow'], [t('ondulada'), 'wave'], [t('grande'), 'big'],
  [t('en degradado'), 'gradient']];
export const EVENTS = new Set(['kit_start', 'kit_level', 'kit_tick', 'kit_press', 'kit_hold', 'kit_touch', 'kit_tile', 'kit_out',
  'kit_every', 'kit_tap', 'kit_clap', 'kit_blow', 'kit_answer', 'kit_video_end', 'kit_no_lives', 'kit_time_up']);

// define(type, colour, parts, kind): parts are text and fields/inputs in order; kind: 'event', 'statement', a value type
function define(type, colour, parts, kind, tooltip) {
  Blockly.Blocks[type] = {
    init() {
      let row = this.appendDummyInput();
      for (const p of parts) {
        if (typeof p === 'string') row.appendField(p);
        else if (p.dropdown) row.appendField(new Blockly.FieldDropdown(p.dropdown), p.name);
        else if (p.number !== undefined) row.appendField(new Blockly.FieldNumber(p.number, p.min, p.max, p.step), p.name);
        else if (p.text !== undefined) row.appendField(new Blockly.FieldTextInput(p.text), p.name);
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
  define('kit_start', EVENT, [t('al empezar la partida')], 'event', t('Una vez, antes del primer nivel (y en cada partida nueva)'));
  define('kit_level', EVENT, [t('al empezar'), { dropdown: anyLevel, name: 'LEVEL' }], 'event',
         t('Cada vez que empieza ese nivel (también al repetirlo tras perder)'));
  define('kit_tick', EVENT, [t('en cada momento')], 'event', t('60 veces por segundo'));
  define('kit_press', EVENT, [t('al pulsar'), { dropdown: BUTTONS, name: 'BUTTON' }], 'event');
  define('kit_hold', EVENT, [t('mientras se pulsa'), { dropdown: BUTTONS, name: 'BUTTON' }], 'event');
  define('kit_touch', EVENT, [t('cuando'), { dropdown: kinds, name: 'A' }, t('toca'), { dropdown: kinds, name: 'B' }], 'event',
         t('Dentro, «este» es el primero y «el otro» el segundo'));
  define('kit_tile', EVENT, [t('cuando'), { dropdown: kinds, name: 'A' }, t('pisa'), { dropdown: tiles, name: 'TILE' }], 'event',
         t('También al chocar con una baldosa sólida (una pared, una puerta). Dentro: «x de la baldosa», «y de la baldosa»'));
  define('kit_out', EVENT, [t('cuando'), { dropdown: kinds, name: 'A' }, t('sale del mapa')], 'event',
         t('Lo que sale del mapa desaparece. Si es el jugador y no usas este bloque, pierde.'));
  define('kit_every', EVENT, [t('cada'), { number: 2, min: 0.1, max: 600, step: 0.1, name: 'SECONDS' }, t('segundos')], 'event');
  define('kit_tap', EVENT, [t('al tocar la pantalla')], 'event', t('Dónde: «x tocada», «y tocada»'));
  // objects (este, otro: the Lua names of the two in an event, whatever the menu says)
  define('kit_this', OBJECT, [{ dropdown: [[t('este'), 'este'], [t('el otro'), 'otro']], name: 'WHO' }], 'Obj');
  define('kit_player', OBJECT, [t('el jugador')], 'Obj');
  define('kit_first', OBJECT, [t('un objeto'), { dropdown: kinds, name: 'KIND' }], 'Obj');
  define('kit_spawn', OBJECT, [t('crear'), { dropdown: kinds, name: 'KIND' }, { value: true, name: 'X', check: 'Number', label: t('en x') },
    { value: true, name: 'Y', check: 'Number', label: 'y' }], 'statement');
  define('kit_spawn_at', OBJECT, [t('crear'), { dropdown: kinds, name: 'KIND' },
    { value: true, name: 'OBJ', check: 'Obj', label: t('donde está') }], 'statement');
  define('kit_destroy', OBJECT, [{ value: true, name: 'OBJ', check: 'Obj', label: t('quitar') }], 'statement');
  define('kit_set', OBJECT, [t('poner'), { dropdown: PROPS, name: 'PROP' }, { value: true, name: 'OBJ', check: 'Obj', label: t('de') },
    { value: true, name: 'V', check: 'Number', label: t('a') }], 'statement');
  define('kit_change', OBJECT, [{ value: true, name: 'V', check: 'Number', label: t('sumar') }, t('a'), { dropdown: PROPS, name: 'PROP' },
    { value: true, name: 'OBJ', check: 'Obj', label: t('de') }], 'statement');
  define('kit_get', OBJECT, [{ dropdown: PROPS, name: 'PROP' }, { value: true, name: 'OBJ', check: 'Obj', label: t('de') }], 'Number');
  define('kit_count', OBJECT, [t('cuántos objetos'), { dropdown: kinds, name: 'KIND' }, t('hay')], 'Number');
  define('kit_count_on', OBJECT, [t('cuántos objetos'), { dropdown: kinds, name: 'KIND' }, t('hay sobre'), { dropdown: tiles, name: 'TILE' }],
         'Number', t('Los que están quietos encima de esa baldosa: cajas en sus marcas'));
  define('kit_sprite', OBJECT, [{ value: true, name: 'OBJ', check: 'Obj', label: t('cambiar el dibujo de') }, t('a'),
    { dropdown: kinds, name: 'KIND' }], 'statement');
  // actions
  define('kit_sound', ACTION, [t('sonar'), { dropdown: sounds, name: 'SOUND' }], 'statement');
  define('kit_music', ACTION, [t('poner la música'), { dropdown: tunes, name: 'MUSIC' }], 'statement',
         t('Una música añadida en Sonidos, en bucle (cada nivel empieza con la suya, si tiene)'));
  define('kit_music_stop', ACTION, [t('parar la música')], 'statement');
  define('kit_label', ACTION, [{ value: true, name: 'TEXT', label: t('mostrar') }, { dropdown: PLACES, name: 'WHERE' }, t('con letra'),
    { dropdown: STYLES, name: 'STYLE' }], 'statement',
         t('Se queda en pantalla hasta que se cambia'));
  define('kit_message', ACTION, [{ value: true, name: 'TEXT', label: t('mostrar el mensaje') }, t('durante'),
    { number: 2, min: 0.1, max: 60, step: 0.1, name: 'SECONDS' }, t('segundos')], 'statement');
  define('kit_win', ACTION, [{ value: true, name: 'TEXT', label: t('ganar y decir') }], 'statement',
         t('Se acaba la partida: con A se vuelve a la portada'));
  define('kit_lose', ACTION, [{ value: true, name: 'TEXT', label: t('perder y decir') }], 'statement',
         t('Con A se repite el nivel'));
  define('kit_shake', ACTION, [t('sacudir la pantalla')], 'statement');
  define('kit_burst', ACTION, [t('chispas'), { dropdown: COLOURS, name: 'COLOUR' }, { value: true, name: 'OBJ', check: 'Obj', label: t('en') }],
         'statement');
  define('kit_restart', ACTION, [t('volver a empezar')], 'statement', t('La partida, desde el primer nivel'));
  define('kit_next_level', ACTION, [t('pasar al siguiente nivel')], 'statement', t('Después del último, se gana'));
  define('kit_retry', ACTION, [t('repetir el nivel')], 'statement', t('Este nivel desde su principio'));
  define('kit_goto_level', ACTION, [t('ir a'), { dropdown: someLevel, name: 'LEVEL' }], 'statement');
  define('kit_set_tile', ACTION, [t('poner'), { dropdown: () => [[t('nada'), '_'], ...tiles().filter(x => x[1] !== '_')], name: 'TILE' },
    { value: true, name: 'X', check: 'Number', label: t('en x') }, { value: true, name: 'Y', check: 'Number', label: 'y' }], 'statement');
  // named animations: walk and idle play by themselves; a hit when told
  define('kit_play_hit', OBJECT, [{ value: true, name: 'OBJ', check: 'Obj', label: t('animación de golpe de') }], 'statement',
         t('Los fotogramas de golpe de su dibujo, una vez (se eligen en Dibujos, en Animaciones)'));
  // lives and a countdown: hearts and a clock on the screen
  define('kit_set_lives', LIVES, [t('empezar con'), { number: 3, min: 0, max: 99, name: 'N' }, t('vidas')], 'statement',
         t('Se ven como corazones arriba a la derecha'));
  define('kit_lose_life', LIVES, [t('quitar una vida')], 'statement',
         t('Sin ninguna, se pierde (o pasa lo que diga «cuando se acaban las vidas»)'));
  define('kit_add_lives', LIVES, [{ value: true, name: 'V', check: 'Number', label: t('sumar a las vidas') }], 'statement');
  define('kit_lives', LIVES, [t('vidas que quedan')], 'Number');
  define('kit_no_lives', LIVES, [t('cuando se acaban las vidas')], 'event', t('Sin este evento, se pierde y se prueba el nivel otra vez'));
  define('kit_countdown', LIVES, [t('cuenta atrás de'), { number: 60, min: 1, max: 3600, name: 'SECONDS' }, t('segundos')], 'statement',
         t('Un reloj arriba en el centro'));
  define('kit_add_time', LIVES, [{ value: true, name: 'V', check: 'Number', label: t('sumar segundos al reloj') }], 'statement');
  define('kit_time_left', LIVES, [t('segundos que quedan')], 'Number');
  define('kit_stop_countdown', LIVES, [t('parar el reloj')], 'statement');
  define('kit_time_up', LIVES, [t('cuando se acaba el tiempo')], 'event', t('Sin este evento, se pierde y se prueba el nivel otra vez'));
  // saved in the console: still there when it is turned off and on (store, stored); 'récord', the key, is the game's data
  const KEEP = t('Se queda en la consola aunque la apagues. Úsalo al acabar un nivel o la partida, no dentro de «en cada momento»');
  define('kit_store', SAVE, [t('guardar como'), { text: 'récord', name: 'KEY' }, { value: true, name: 'V', label: t('el valor') }],
         'statement', KEEP);
  define('kit_store_max', SAVE, [t('guardar como'), { text: 'récord', name: 'KEY' },
    { value: true, name: 'V', check: 'Number', label: t('si es más que lo guardado') }], 'statement', t('{keep}. Para récords', { keep: KEEP }));
  define('kit_stored', SAVE, [t('lo guardado como'), { text: 'récord', name: 'KEY' }], 'any', t('Lo que se guardó; 0 si aún no hay nada'));
  // input
  define('kit_button', INPUT, [{ dropdown: BUTTONS, name: 'BUTTON' }, t('está pulsado')], 'Boolean');
  define('kit_tap_x', INPUT, [t('x tocada')], 'Number');
  define('kit_tap_y', INPUT, [t('y tocada')], 'Number');
  define('kit_tile_x', INPUT, [t('x de la baldosa')], 'Number', t('Dentro de «cuando … pisa …»'));
  define('kit_tile_y', INPUT, [t('y de la baldosa')], 'Number', t('Dentro de «cuando … pisa …»'));
  // the microphone
  define('kit_clap', MIC, [t('al dar una palmada')], 'event',
         t('El micrófono oye un ruido de repente: una palmada, un golpe en la mesa, un grito'));
  define('kit_blow', MIC, [t('al soplar')], 'event', t('El micrófono oye un soplido: un ruido fuerte y sin nota, durante un momento'));
  define('kit_mic_level', MIC, [t('volumen del micrófono')], 'Number', t('De 0 (silencio) a 100 (un grito cerca). 0 si no hay micrófono'));
  define('kit_mic_note', MIC, [t('nota que se oye (Hz)')], 'Number', t('La nota de una voz o un silbido; 0 si no hay una clara. El la central es 440'));
  // conversations
  define('kit_say', TALK, [{ value: true, name: 'WHO' }, { value: true, name: 'TEXT', label: t('dice') }], 'statement',
         t('Un cuadro abajo, letra a letra; el juego espera y con A sigue. Si hay varios seguidos, salen uno tras otro'));
  define('kit_ask', TALK, [{ value: true, name: 'TEXT', label: t('preguntar') }, { value: true, name: 'A', label: t('opciones') },
    { value: true, name: 'B' }, { value: true, name: 'C' }], 'statement', t('Las opciones vacías no salen. Se elige con arriba, abajo y A'));
  define('kit_answer', TALK, [t('al elegir la respuesta'), { dropdown: [['1', '1'], ['2', '2'], ['3', '3']], name: 'N' }], 'event');
  // video
  define('kit_video_full', VIDEO, [t('poner el vídeo'), { dropdown: videos, name: 'VIDEO' }, t('en toda la pantalla')], 'statement',
         t('El juego espera a que acabe (A lo salta). Los vídeos se añaden en la pestaña Sonidos'));
  define('kit_video_window', VIDEO, [t('poner el vídeo'), { dropdown: videos, name: 'VIDEO' }, t('en una ventana'),
    { dropdown: WINDOWS, name: 'WHERE' }], 'statement', t('En bucle, mientras se juega'));
  define('kit_video_stop', VIDEO, [t('quitar el vídeo')], 'statement');
  define('kit_video_end', VIDEO, [t('al acabar el vídeo')], 'event', t('Uno en toda la pantalla, cuando acaba o se salta'));
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
  F.kit_label = b => { const st = b.getFieldValue('STYLE'); // (normal: as labels always were)
    return `kit.label(${q(b.getFieldValue('WHERE'))}, ${text(b)}, ${q(b.getFieldValue('WHERE'))}${st && st !== 'normal' ? ', ' + q(st) : ''})\n`; };
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
  F.kit_play_hit = b => `kit.play(${obj(b)}, "hit")\n`;
  F.kit_set_lives = b => `kit.set_lives(${Number(b.getFieldValue('N')) || 0})\n`;
  F.kit_lose_life = () => 'kit.add_lives(-1)\n';
  F.kit_add_lives = b => `kit.add_lives(${val(b, 'V')})\n`;
  F.kit_lives = () => ['kit.lives()', O.HIGH];
  F.kit_no_lives = b => on('"no_lives"', b);
  F.kit_countdown = b => `kit.countdown(${Number(b.getFieldValue('SECONDS')) || 60})\n`;
  F.kit_add_time = b => `kit.add_time(${val(b, 'V')})\n`;
  F.kit_time_left = () => ['kit.time_left()', O.HIGH];
  F.kit_stop_countdown = () => 'kit.stop_countdown()\n';
  F.kit_time_up = b => on('"time_up"', b);
  const key = b => q(b.getFieldValue('KEY').trim() || 'récord');
  F.kit_store = b => `store(${key(b)}, ${val(b, 'V')})\n`;
  F.kit_store_max = b => `do local v = ${val(b, 'V')} if v > (tonumber(stored(${key(b)}, 0)) or 0) then store(${key(b)}, v) end end\n`;
  F.kit_stored = b => [`stored(${key(b)}, 0)`, O.HIGH];
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
    { kind: 'category', name: t('Eventos'), colour: EVENT, contents: ['kit_start', 'kit_level', 'kit_tick', 'kit_press', 'kit_hold', 'kit_touch',
      'kit_tile', 'kit_out', 'kit_every', 'kit_tap'].map(type => ({ kind: 'block', type })) },
    { kind: 'category', name: t('Objetos'), colour: OBJECT, contents: [
      { kind: 'block', type: 'kit_this' }, { kind: 'block', type: 'kit_player' }, { kind: 'block', type: 'kit_first' },
      { kind: 'block', type: 'kit_spawn', inputs: { X: num(100), Y: num(50) } },
      { kind: 'block', type: 'kit_spawn_at', inputs: { OBJ: thisBlock() } },
      { kind: 'block', type: 'kit_destroy', inputs: { OBJ: thisBlock('otro') } },
      { kind: 'block', type: 'kit_set', inputs: { OBJ: thisBlock(), V: num(0) } },
      { kind: 'block', type: 'kit_change', inputs: { OBJ: thisBlock(), V: num(1) } },
      { kind: 'block', type: 'kit_get', inputs: { OBJ: thisBlock() } }, { kind: 'block', type: 'kit_count' },
      { kind: 'block', type: 'kit_count_on' },
      { kind: 'block', type: 'kit_sprite', inputs: { OBJ: thisBlock() } },
      { kind: 'block', type: 'kit_play_hit', inputs: { OBJ: thisBlock() } }] },
    { kind: 'category', name: t('Acciones'), colour: ACTION, contents: [
      { kind: 'block', type: 'kit_sound' }, { kind: 'block', type: 'kit_music' }, { kind: 'block', type: 'kit_music_stop' },
      { kind: 'block', type: 'kit_label', inputs: { TEXT: str(t('Puntos: 0')) } },
      { kind: 'block', type: 'kit_message', inputs: { TEXT: str(t('¡Hola!')) } },
      { kind: 'block', type: 'kit_win', inputs: { TEXT: str(t('¡Has ganado!')) } },
      { kind: 'block', type: 'kit_lose', inputs: { TEXT: str(t('Has perdido')) } }, { kind: 'block', type: 'kit_shake' },
      { kind: 'block', type: 'kit_burst', inputs: { OBJ: thisBlock() } }, { kind: 'block', type: 'kit_next_level' },
      { kind: 'block', type: 'kit_goto_level' }, { kind: 'block', type: 'kit_retry' }, { kind: 'block', type: 'kit_restart' },
      { kind: 'block', type: 'kit_set_tile', inputs: { X: num(0), Y: num(0) } }] },
    { kind: 'category', name: t('Mandos'), colour: INPUT, contents: ['kit_button', 'kit_tap_x', 'kit_tap_y', 'kit_tile_x', 'kit_tile_y']
      .map(type => ({ kind: 'block', type })) },
    { kind: 'category', name: t('Micrófono'), colour: MIC, contents: ['kit_clap', 'kit_blow', 'kit_mic_level', 'kit_mic_note']
      .map(type => ({ kind: 'block', type })) },
    { kind: 'category', name: t('Diálogos'), colour: TALK, contents: [
      { kind: 'block', type: 'kit_say', inputs: { WHO: str('Ana'), TEXT: str(t('¡Hola! ¿Me ayudas?')) } },
      { kind: 'block', type: 'kit_ask', inputs: { TEXT: str(t('¿Vienes?')), A: str(t('Sí')), B: str(t('No')), C: str('') } },
      { kind: 'block', type: 'kit_answer' }] },
    { kind: 'category', name: t('Vídeo'), colour: VIDEO, contents: ['kit_video_full', 'kit_video_window', 'kit_video_stop',
      'kit_video_end'].map(type => ({ kind: 'block', type })) },
    { kind: 'category', name: t('Vidas y tiempo'), colour: LIVES, contents: [
      { kind: 'block', type: 'kit_set_lives' }, { kind: 'block', type: 'kit_lose_life' },
      { kind: 'block', type: 'kit_add_lives', inputs: { V: num(1) } }, { kind: 'block', type: 'kit_lives' },
      { kind: 'block', type: 'kit_no_lives' }, { kind: 'block', type: 'kit_countdown' },
      { kind: 'block', type: 'kit_add_time', inputs: { V: num(10) } }, { kind: 'block', type: 'kit_time_left' },
      { kind: 'block', type: 'kit_stop_countdown' }, { kind: 'block', type: 'kit_time_up' }] },
    { kind: 'category', name: t('Guardar'), colour: SAVE, contents: [
      { kind: 'block', type: 'kit_store_max', inputs: { V: num(0) } },
      { kind: 'block', type: 'kit_store', inputs: { V: num(1) } }, { kind: 'block', type: 'kit_stored' }] },
    { kind: 'sep' },
    { kind: 'category', name: t('Condiciones'), categorystyle: 'logic_category', contents: ['controls_if', 'logic_compare', 'logic_operation',
      'logic_negate', 'logic_boolean'].map(type => ({ kind: 'block', type })) },
    { kind: 'category', name: t('Repetir'), categorystyle: 'loop_category', contents: [
      { kind: 'block', type: 'controls_repeat_ext', inputs: { TIMES: num(3) } }, { kind: 'block', type: 'controls_whileUntil' }] },
    { kind: 'category', name: t('Números'), categorystyle: 'math_category', contents: [
      { kind: 'block', type: 'math_number' }, { kind: 'block', type: 'math_arithmetic' },
      { kind: 'block', type: 'math_random_int', inputs: { FROM: num(1), TO: num(10) } }, { kind: 'block', type: 'math_round' }] },
    { kind: 'category', name: t('Texto'), categorystyle: 'text_category', contents: [
      { kind: 'block', type: 'text' }, { kind: 'block', type: 'text_join' }] },
    { kind: 'category', name: t('Variables'), categorystyle: 'variable_category', custom: 'VARIABLE' },
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

// (their texts are the game's, in the editor's language; variables and names are Lua's and the drawings', as they are)
const TEMPLATE_BLOCKS = {
  plataformas() {
    const P = 'v_puntos';
    return [[{ name: 'puntos', id: P }], [
      ev('kit_start', {}, [set(P, N(0)), label('top_left', T(t('Monedas: 0')))]),
      ev('kit_touch', { A: 'heroe', B: 'moneda' }, [
        b('kit_destroy', {}, { OBJ: THIS('otro') }), sound('moneda'), b('kit_burst', { COLOUR: '0xFFE070' }, { OBJ: THIS('otro') }),
        add(P, 1), label('top_left', join(T(t('Monedas: ')), V(P)))]),
      ev('kit_touch', { A: 'heroe', B: 'babosa' }, lose(t('¡Te ha pillado la babosa!'))),
      ev('kit_tile', { A: 'heroe', TILE: 'pinchos' }, [b('kit_lose', {}, { TEXT: T(t('¡Pinchos!')) })]),
      ev('kit_out', { A: 'heroe' }, [sound('golpe'), b('kit_lose', {}, { TEXT: T(t('¡Te has caído!')) })]),
      ev('kit_touch', { A: 'heroe', B: 'meta' }, [sound('moneda'), b('kit_next_level')]),
      ev('kit_press', { BUTTON: 'a' }, [sound('salto')]),
    ]];
  },
  aventura() {
    const G = 'v_gemas', K = 'v_llaves';
    return [[{ name: 'gemas', id: G }, { name: 'llaves', id: K }], [
      ev('kit_start', {}, [set(G, N(0)), set(K, N(0)), label('top_left', T(t('Gemas: 0'))), label('top_right', T(t('Llaves: 0')))]),
      ev('kit_touch', { A: 'exploradora', B: 'gema' }, [
        b('kit_destroy', {}, { OBJ: THIS('otro') }), sound('gema'), b('kit_burst', { COLOUR: '0xC070FF' }, { OBJ: THIS('otro') }),
        add(G, 1), label('top_left', join(T(t('Gemas: ')), V(G)))]),
      ev('kit_touch', { A: 'exploradora', B: 'llave' }, [
        b('kit_destroy', {}, { OBJ: THIS('otro') }), sound('llave'), add(K, 1), label('top_right', join(T(t('Llaves: ')), V(K))),
        say(t('¡Una llave!'))]),
      ev('kit_tile', { A: 'exploradora', TILE: 'puerta' }, [iff(cmp('GT', V(K), N(0)), [
        b('kit_set_tile', { TILE: '_' }, { X: { block: b('kit_tile_x') }, Y: { block: b('kit_tile_y') } }), add(K, -1),
        label('top_right', join(T(t('Llaves: ')), V(K))), sound('puerta'), say(t('¡Abierta!'), 1)], [say(t('Hace falta una llave'))])]),
      ev('kit_touch', { A: 'exploradora', B: 'cangrejo' }, lose(t('¡Un cangrejo!'))),
      ev('kit_touch', { A: 'exploradora', B: 'fantasma' }, lose(t('¡Un fantasma!'))),
      ev('kit_touch', { A: 'exploradora', B: 'escalera' }, [sound('llave'), b('kit_next_level')]),
    ]];
  },
  naves() {
    const P = 'v_puntos', D = 'v_derribados', W = 'v_oleada';
    const hit = (enemy, points) => ev('kit_touch', { A: 'laser', B: enemy }, [
      b('kit_destroy', {}, { OBJ: THIS('este') }), b('kit_destroy', {}, { OBJ: THIS('otro') }),
      b('kit_burst', { COLOUR: '0xFFE070' }, { OBJ: THIS('otro') }), sound('explosion'), add(P, points), add(D, 1),
      label('top_left', join(T(t('Puntos: ')), V(P)))]);
    const fall = (kind, seconds, only) => ev('kit_every', { SECONDS: seconds }, [
      ...(only ? [iff(cmp('EQ', V(W), N(only)), [b('kit_spawn', { KIND: kind }, { X: rnd(8, 216), Y: N(-16) })])]
        : [b('kit_spawn', { KIND: kind }, { X: rnd(8, 216), Y: N(-16) })])]);
    return [[{ name: 'puntos', id: P }, { name: 'derribados', id: D }, { name: 'oleada', id: W }], [
      ev('kit_start', {}, [set(P, N(0)), set(W, N(1)), label('top_left', T(t('Puntos: 0')))]),
      ev('kit_level', { LEVEL: '_' }, [set(D, N(0))]),
      ev('kit_level', { LEVEL: 'nivel2' }, [set(W, N(2))]),
      ev('kit_press', { BUTTON: 'a' }, [b('kit_spawn_at', { KIND: 'laser' }, { OBJ: { block: b('kit_player') } }), sound('laser')]),
      fall('ovni', 1.2), fall('cometa', 0.9, 2),
      hit('ovni', 1), hit('cometa', 2),
      ev('kit_touch', { A: 'nave', B: 'ovni' }, lose(t('¡Te han dado!'))),
      ev('kit_touch', { A: 'nave', B: 'cometa' }, lose(t('¡Un cometa!'))),
      ev('kit_tick', {}, [iff(cmp('GTE', V(D), N(12)), [b('kit_next_level')])]),
    ]];
  },
  puzle() {
    return [[], [
      ev('kit_start', {}, [label('bottom', T(t('B: empezar el puzle otra vez')))]),
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
