// js/cable.js against a console made of streams (Node has no Web Serial): its answers come cut into pieces and mixed
// with log lines, as over the real cable; the game it receives must be the game sent. Then a console that says no.
//   node editor/test/cable_test.mjs
import assert from 'node:assert/strict';

function fakeConsole({ refuse = null } = {}) {
  const got = { files: new Map(), lines: 0 };
  let out, current = null, inBuf = '';
  const readable = new ReadableStream({ start(c) { out = c; } });
  const say = text => { // the answer cut in two, a line of log before it
    const bytes = new TextEncoder().encode(`I (123) log: busy\r\n@np2d ${text}\r\n`);
    const cut = Math.floor(bytes.length / 2);
    const put = b => { try { out.enqueue(b); } catch { /* the editor has closed the port */ } };
    put(bytes.subarray(0, cut));
    setTimeout(() => put(bytes.subarray(cut)), 1);
  };
  const line = l => {
    got.lines++;
    const [cmd, a, b] = l.split(' ');
    if (cmd === 'hello') return say('hello 1 card 1000');
    if (cmd === 'begin') return refuse ? say('err ' + refuse) : (got.id = a, got.total = Number(b), say('ok'));
    if (cmd === 'file') return (current = a, got.files.set(a, []), say('ok'));
    if (cmd === 'data') return (got.files.get(current).push(...Buffer.from(a, 'base64')), say('ok'));
    if (cmd === 'end' || cmd === 'abort') return (got.ended = cmd, say('ok'));
    say('err unknown line');
  };
  const writable = new WritableStream({ write(chunk) {
    inBuf += new TextDecoder().decode(chunk);
    for (let i; (i = inBuf.indexOf('\n')) >= 0;) { line(inBuf.slice(0, i)); inBuf = inBuf.slice(i + 1); }
  } });
  const port = { readable, writable, open: async () => {}, close: async () => {} };
  return { got, serial: { requestPort: async () => port } };
}

const files = new Map([['game.json', new TextEncoder().encode('{"id":"prueba"}')],
                       ['assets/SPR_x.rgb565', Uint8Array.from({ length: 2000 }, (_, i) => i * 7 & 255)]]);

{
  const fake = fakeConsole();
  Object.defineProperty(navigator, 'serial', { value: fake.serial, configurable: true });
  const { send } = await import('../js/cable.js?ok');
  const seen = [];
  await send(files, 'prueba', f => seen.push(f));
  assert.equal(fake.got.id, 'prueba');
  assert.equal(fake.got.total, 2000 + files.get('game.json').length);
  for (const [path, bytes] of files) assert.deepEqual(Uint8Array.from(fake.got.files.get(path)), bytes, path);
  assert.equal(fake.got.ended, 'end');
  assert.equal(seen.at(-1), 1);
}
{
  const fake = fakeConsole({ refuse: 'no room: 12 KB free' });
  Object.defineProperty(navigator, 'serial', { value: fake.serial, configurable: true });
  const { send } = await import('../js/cable.js?no');
  await assert.rejects(send(files, 'prueba', () => {}), /no cabe en la consola/);
  assert.equal(fake.got.ended, 'abort'); // what came is thrown away
}
console.log('cable: a game sent whole through a chatty console; a refusal said in Spanish');
