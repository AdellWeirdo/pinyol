// The videos of a game (in the Sounds tab): brought in from a video file or an animated GIF, made into a clip for
// pinyol's video() here in the browser (npv.js), shown looping, renamed, taken away. The blocks of Vídeo play them.
import { safeName, uniqueName } from './project.js';
import { toBase64 } from './audio.js';
import { encode, decode } from './npv.js';
import { t } from './i18n.js';

export const VIDEO_FPS = 10, VIDEO_MAX_S = 20, VIDEO_W = 192, VIDEO_H = 128; // fitted inside: 2.5x fills the screen
export const VIDEO_MAX_BYTES = 3 << 20;

const $ = id => document.getElementById(id);
let app, cur = -1, shown = null, timer = 0;

const fromBase64 = text => Uint8Array.from(atob(text), c => c.charCodeAt(0));
export const bytesOf = v => fromBase64(v.npv);

function fit(w, h) { // within VIDEO_W x VIDEO_H, its shape kept, even sides
  const s = Math.min(VIDEO_W / w, VIDEO_H / h, 1);
  return [Math.max(2, Math.round(w * s / 2) * 2), Math.max(2, Math.round(h * s / 2) * 2)];
}

async function framesOfVideo(file, note) { // seeks a <video> along it: a frame each 1/VIDEO_FPS s
  const url = URL.createObjectURL(file), v = document.createElement('video');
  v.muted = true, v.playsInline = true, v.preload = 'auto', v.src = url;
  try {
    await new Promise((ok, fail) => { v.onloadeddata = ok; v.onerror = () => fail(new Error(t('no se puede leer'))); });
    const [w, h] = fit(v.videoWidth, v.videoHeight), c = new OffscreenCanvas(w, h), g = c.getContext('2d');
    const n = Math.max(1, Math.min(Math.floor((v.duration || 0) * VIDEO_FPS), VIDEO_MAX_S * VIDEO_FPS)), frames = [];
    for (let k = 0; k < n; k++) {
      await new Promise(ok => { v.onseeked = ok; v.currentTime = k / VIDEO_FPS; });
      g.drawImage(v, 0, 0, w, h);
      frames.push(g.getImageData(0, 0, w, h).data);
      if (k % 10 === 0) note(t('Leyendo el vídeo… {n} %', { n: Math.round(100 * k / n) }));
    }
    return { frames, w, h, cut: (v.duration || 0) > VIDEO_MAX_S };
  } finally {
    URL.revokeObjectURL(url);
  }
}

async function framesOfGif(file) { // its frames held for their time, taken every 1/VIDEO_FPS s
  if (typeof ImageDecoder === 'undefined') throw new Error(t('este navegador no lee GIF animados: prueba con un vídeo'));
  const d = new ImageDecoder({ data: file.stream(), type: file.type || 'image/gif' });
  await d.tracks.ready;
  const count = d.tracks.selectedTrack.frameCount, pics = [];
  for (let i = 0; i < count; i++) pics.push((await d.decode({ frameIndex: i })).image);
  const [w, h] = fit(pics[0].displayWidth, pics[0].displayHeight), c = new OffscreenCanvas(w, h), g = c.getContext('2d');
  const total = pics.reduce((t, p) => t + (p.duration || 100000), 0) / 1e6, frames = [];
  for (let k = 0, t = 0, i = 0, end = (pics[0].duration || 100000) / 1e6; k < Math.min(total * VIDEO_FPS, VIDEO_MAX_S * VIDEO_FPS); k++) {
    t = k / VIDEO_FPS;
    while (t >= end && i + 1 < pics.length) end += (pics[++i].duration || 100000) / 1e6;
    g.clearRect(0, 0, w, h);
    g.drawImage(pics[i], 0, 0, w, h);
    frames.push(g.getImageData(0, 0, w, h).data);
  }
  pics.forEach(p => p.close());
  return { frames: frames.length ? frames : [g.getImageData(0, 0, w, h).data], w, h, cut: total > VIDEO_MAX_S };
}

async function bringIn(file) {
  if (!file) return;
  const note = text => { $('video-note').textContent = text; };
  try {
    note(t('Leyendo el vídeo…'));
    const got = /gif$/i.test(file.type) || /\.gif$/i.test(file.name) ? await framesOfGif(file) : await framesOfVideo(file, note);
    note(t('Convirtiéndolo para la consola…'));
    await new Promise(r => setTimeout(r, 30)); // (the note shows first)
    const npv = encode(got.frames, got.w, got.h, VIDEO_FPS);
    if (npv.length > VIDEO_MAX_BYTES)
      throw new Error(t('ocupa {kb} KB y caben {max}: usa uno más corto o más quieto', { kb: npv.length >> 10, max: VIDEO_MAX_BYTES >> 10 }));
    const names = new Set(app.project.videos.map(v => v.name));
    app.project.videos.push({ name: uniqueName(safeName(file.name.replace(/\.[^.]*$/, ''), 'video'), names),
                              npv: toBase64(npv), w: got.w, h: got.h, frames: got.frames.length, fps: VIDEO_FPS });
    cur = app.project.videos.length - 1;
    app.changed();
    render();
    note('');
    app.toast(got.cut ? t('Vídeo añadido: sus primeros {n} segundos.', { n: VIDEO_MAX_S }) : t('Vídeo añadido: ponlo con los bloques de Vídeo.'));
  } catch (err) {
    note('');
    app.oops(t('No se ha podido añadir ese vídeo: {why}', { why: err.message }));
  }
}

function show() { // the video selected, looping in the preview
  clearInterval(timer);
  const v = app.project.videos[cur], c = $('video-preview'), g = c.getContext('2d');
  g.fillStyle = '#000', g.fillRect(0, 0, c.width, c.height);
  if (!v) { shown = null; return; }
  shown = decode(bytesOf(v));
  if (!shown) return;
  const img = new ImageData(shown.w, shown.h), s = Math.min(c.width / shown.w, c.height / shown.h);
  const tmp = new OffscreenCanvas(shown.w, shown.h);
  let k = 0;
  const step = () => {
    img.data.set(shown.frames[k]);
    tmp.getContext('2d').putImageData(img, 0, 0);
    g.imageSmoothingEnabled = false;
    g.drawImage(tmp, (c.width - shown.w * s) / 2, (c.height - shown.h * s) / 2, shown.w * s, shown.h * s);
    k = (k + 1) % shown.frames.length;
  };
  step();
  timer = setInterval(step, 1000 / shown.fps);
}

function render() {
  const ul = $('videos');
  ul.replaceChildren();
  app.project.videos.forEach((v, i) => {
    const li = document.createElement('li'), b = document.createElement('button');
    b.textContent = `${v.name} · ${(v.frames / v.fps).toFixed(1)} s`;
    b.setAttribute('aria-pressed', String(i === cur));
    b.addEventListener('click', () => { cur = i; render(); });
    li.append(b);
    ul.append(li);
  });
  const v = app.project.videos[cur];
  $('video-edit').hidden = !v;
  if (v) $('v-name').value = v.name;
  show();
}

export function initVideos(ctx) {
  app = ctx;
  $('video-file').addEventListener('change', e => { const f = e.target.files[0]; e.target.value = ''; bringIn(f); });
  $('video-del').addEventListener('click', () => {
    const v = app.project.videos[cur];
    if (!v || !confirm(t('¿Quitar el vídeo «{name}»?', { name: v.name }))) return;
    app.project.videos.splice(cur, 1);
    cur = Math.min(cur, app.project.videos.length - 1);
    app.changed();
    render();
  });
  $('v-name').addEventListener('change', e => {
    const v = app.project.videos[cur];
    if (!v) return;
    const names = new Set(app.project.videos.filter(x => x !== v).map(x => x.name));
    const name = uniqueName(safeName(e.target.value, v.name), names);
    if (name !== v.name) app.renameVideo(v.name, name);
    v.name = name;
    if (name !== e.target.value) app.toast(t('Se llama «{name}»: sin acentos ni espacios, así sale en los bloques.', { name }));
    app.changed();
    render();
  });
  return { render, reset: () => { cur = app.project.videos.length ? 0 : -1; render(); } };
}
