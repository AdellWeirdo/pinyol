// The page works without this file: it only adds the reveals, the counters, the copy buttons, and pauses the
// animations nobody is looking at.
document.documentElement.classList.add('js');
const still = matchMedia('(prefers-reduced-motion: reduce)').matches;

const fmt = (v, dec) => new Intl.NumberFormat('es-ES', { minimumFractionDigits: dec, maximumFractionDigits: dec }).format(v);

function count(el) {
  const to = parseFloat(el.dataset.count), from = parseFloat(el.dataset.from) || 0, dec = +el.dataset.dec || 0, t0 = performance.now(), T = 1100;
  if (!isFinite(to)) return;
  const step = now => {
    const k = Math.min(1, (now - t0) / T), e = 1 - Math.pow(2, -10 * k); // ease out
    el.textContent = fmt(k < 1 ? from + (to - from) * e : to, dec);
    if (k < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

if ('IntersectionObserver' in window) {
  const reveal = new IntersectionObserver(entries => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add('in');
      if (!still) e.target.querySelectorAll('[data-count]').forEach(count);
      reveal.unobserve(e.target);
    }
  }, { threshold: 0.2 });
  document.querySelectorAll('.reveal').forEach(el => reveal.observe(el));

  const live = new IntersectionObserver(entries => {
    for (const e of entries) e.target.classList.toggle('live', e.isIntersecting);
  });
  document.querySelectorAll('[data-live]').forEach(el => live.observe(el));
} else {
  document.querySelectorAll('.reveal, [data-live]').forEach(el => el.classList.add('in', 'live'));
}

const said = document.createElement('p');
said.className = 'sr';
said.setAttribute('aria-live', 'polite');
document.body.append(said);
document.querySelectorAll('.copy').forEach(b => b.addEventListener('click', async () => {
  const text = b.parentElement.querySelector('code').textContent;
  try {
    await navigator.clipboard.writeText(text);
    b.textContent = said.textContent = 'Copiado';
  } catch {
    b.textContent = 'Selecciónalo y copia';
    said.textContent = 'No se ha podido copiar: selecciona el texto y cópialo';
  }
  setTimeout(() => { b.textContent = 'Copiar'; said.textContent = ''; }, 2000); // cleared, so the next copy is announced again
}));
