// The guide: eight steps through the editor the first time it opens (again with the ? button), each on the tab it
// speaks about, with what it speaks about outlined. A panel in a corner, not in the way: everything still works.
import { t } from './i18n.js';

const $ = id => document.getElementById(id);
const SEEN = 'np2d-guide-seen';
const TOUCH = matchMedia('(pointer: coarse)').matches;

const STEPS = [
  { tab: 'draw', at: 'play', title: t('Esto ya es un juego'),
    text: () => (TOUCH ? t('Pulsa ▶ Jugar y pruébalo. Usa los botones de debajo de la pantalla. Luego lo cambiaremos.')
      : t('Pulsa ▶ Jugar y pruébalo. Flechas para moverte, Z para saltar. Luego lo cambiaremos.')) },
  { tab: 'draw', at: 'pixels', title: t('Tus dibujos'),
    text: () => t('Elige un dibujo en la lista y píntalo con el lápiz. Si tiene varios fotogramas (su animación), cambia cada uno o marca «Pintar en todos los fotogramas». «Deshacer» arregla cualquier error.') },
  { tab: 'draw', at: '.use', title: t('Qué es cada dibujo'),
    text: () => t('Una baldosa es un trozo de suelo o pared. Un objeto es un personaje o una cosa: se mueve como tú digas. Un fondo es un paisaje detrás. También puedes añadir imágenes tuyas.') },
  { tab: 'map', at: 'map-palette', title: t('El mapa de cada nivel'),
    text: () => t('Elige una pieza (una baldosa o un objeto, como la moneda) y haz clic en el mapa para ponerla. La goma la quita. Arriba a la izquierda están los niveles y la portada.') },
  { tab: 'logic', at: 'blockly', title: t('Las reglas son bloques'),
    text: () => t('Lee los bloques como frases: «cuando heroe toca moneda: quitar el otro, sumar 1 a puntos». Arrastra bloques de la izquierda para inventar reglas nuevas.') },
  { tab: 'sound', at: 'song-add', title: t('Sonidos y música'),
    text: () => t('Haz efectos con las recetas (moneda, salto, láser…), añade sonidos tuyos o compón una música en una cuadrícula. En Mapa, cada nivel elige su música.') },
  { tab: 'game', at: 'play-start', title: t('Prueba tus cambios'),
    text: () => t('Cada vez que cambies algo, juega otra vez. Con «Empezar en» vas directo al nivel que estás haciendo.') },
  { tab: 'game', at: 'export', title: t('A tu consola'),
    text: () => t('«Pasar a la consola» lo envía por el cable o te da un archivo para la tarjeta. El juego se guarda solo en este navegador; «Guardar archivo» te da una copia.') },
];

export function initGuide(app, showTab) {
  const box = document.createElement('section');
  box.className = 'guide';
  box.setAttribute('role', 'dialog');
  box.setAttribute('aria-labelledby', 'guide-title');
  box.hidden = true;
  box.innerHTML = `<p class="guide-step" id="guide-step"></p><h2 id="guide-title" tabindex="-1"></h2><p id="guide-text"></p>
    <div class="guide-buttons"><button id="guide-skip"></button><span class="gap"></span>
    <button id="guide-back"></button><button id="guide-next" class="primary"></button></div>`;
  document.body.append(box);
  $('guide-skip').textContent = t('Cerrar la guía');
  $('guide-back').textContent = t('Atrás');
  let step = 0, marked = null;

  const show = i => {
    step = i;
    const s = STEPS[i];
    showTab(s.tab);
    if (marked) marked.classList.remove('guided');
    marked = s.at.startsWith('.') ? document.querySelector(s.at) : $(s.at);
    if (marked) { marked.classList.add('guided'); marked.scrollIntoView({ block: 'nearest', inline: 'nearest' }); }
    $('guide-step').textContent = t('Paso {n} de {all}', { n: i + 1, all: STEPS.length });
    $('guide-title').textContent = s.title;
    $('guide-text').textContent = s.text();
    $('guide-back').disabled = i === 0;
    $('guide-next').textContent = i === STEPS.length - 1 ? t('¡A jugar!') : t('Siguiente');
    $('guide-title').focus();
  };
  const close = () => {
    box.hidden = true;
    if (marked) marked.classList.remove('guided');
    try { localStorage.setItem(SEEN, '1'); } catch { /* a private window: it shows again next time */ }
    showTab('draw');
    $('help').focus();
  };
  const open = () => { box.hidden = false; show(0); };

  $('guide-next').addEventListener('click', () => (step < STEPS.length - 1 ? show(step + 1) : close()));
  $('guide-back').addEventListener('click', () => step > 0 && show(step - 1));
  $('guide-skip').addEventListener('click', close);
  box.addEventListener('keydown', e => { if (e.key === 'Escape') close(); });
  $('help').addEventListener('click', open);
  let seen = false;
  try { seen = !!localStorage.getItem(SEEN); } catch { /* none kept */ }
  if (!seen) open();
}
