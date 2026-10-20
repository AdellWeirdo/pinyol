// A game sent to the console over its USB cable (Web Serial: Chrome and Edge on a computer). The console's side is
// firmware/main/cable.c: a line each way, every line answered "@pinyol ok" or "@pinyol err <why>", so this never sends
// faster than the console writes; tools/send_game.py does the same from a terminal.
import { t } from './i18n.js';

export const cableWorks = 'serial' in navigator;
const CHUNK = 768, ESPRESSIF = 0x303a, TIMEOUT = Symbol('timeout');

const WHY = [ // what the console says, as the editor says it
  [/^no room/, t('no cabe en la consola: borra algún juego de la tarjeta')],
  [/^not a game/, t('la consola no acepta este juego (¿es demasiado grande?)')],
  [/^cannot write/, t('la consola no puede escribir en su tarjeta (¿está bloqueada o llena?)')],
  [/^nothing came/, t('el envío se ha cortado')],
];
const said = why => (WHY.find(([re]) => re.test(why)) || [, t('la consola dice: {why}', { why })])[1];

function base64(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}

// files: Map of path -> bytes (buildFiles); progress(0..1)
export async function send(files, id, progress) {
  let port;
  try { port = await navigator.serial.requestPort({ filters: [{ usbVendorId: ESPRESSIF }] }); }
  catch { throw new Error(t('no se ha elegido ninguna consola')); }
  try { await port.open({ baudRate: 115200 }); }
  catch { throw new Error(t('el cable está ocupado por otro programa: ciérralo y vuelve a probar')); }
  const writer = port.writable.getWriter(), reader = port.readable.getReader(), text = new TextDecoder(), enc = new TextEncoder();
  let buf = '', pending = null;
  const answer = async ms => { // the console's next answer, skipping its log
    const end = Date.now() + ms;
    for (;;) {
      for (let i; (i = buf.indexOf('\n')) >= 0;) {
        const line = buf.slice(0, i).trim();
        buf = buf.slice(i + 1);
        const answer = /^@(?:pinyol|np2d) (.*)$/.exec(line); // np2d: firmware from before the engine's rename
        if (answer) return answer[1];
      }
      const left = end - Date.now();
      if (left <= 0) throw new Error(t('la consola no contesta: ¿está encendida y conectada?'));
      pending = pending || reader.read(); // a read that outlives a timeout is kept for the next turn
      const r = await Promise.race([pending, new Promise(ok => setTimeout(() => ok(TIMEOUT), left))]);
      if (r === TIMEOUT) continue;
      pending = null;
      if (r.done) throw new Error(t('el cable se ha desconectado'));
      buf += text.decode(r.value, { stream: true });
    }
  };
  const ask = async (line, ms = 5000) => {
    await writer.write(enc.encode(line + '\n'));
    const a = await answer(ms);
    if (a.startsWith('err')) throw new Error(said(a.slice(4)));
    return a;
  };
  try {
    const hello = await ask('hello', 4000);
    if (Number(hello.split(' ')[1]) >= 2) { // a console that keeps a wall clock: this computer's time and its offset from UTC
      const now = new Date();
      await ask(`time ${Math.floor(now.getTime() / 1000)} ${-now.getTimezoneOffset()}`);
    }
    const total = [...files.values()].reduce((n, b) => n + b.length, 0);
    let sent = 0;
    await ask(`begin ${id} ${total}`, 15000); // the game playing on it stops first
    for (const [path, bytes] of files) {
      await ask(`file ${path} ${bytes.length}`);
      for (let i = 0; i < bytes.length; i += CHUNK) {
        await ask('data ' + base64(bytes.subarray(i, i + CHUNK)));
        sent += Math.min(CHUNK, bytes.length - i);
        progress(sent / total);
      }
    }
    await ask('end', 30000);
  } catch (e) {
    try { await writer.write(enc.encode('abort\n')); } catch { /* gone */ }
    throw e;
  } finally {
    try { await reader.cancel(); } catch { /* already closed */ }
    reader.releaseLock();
    writer.releaseLock();
    await port.close().catch(() => {});
  }
}
