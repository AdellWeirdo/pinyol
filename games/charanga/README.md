# La Charanga de Emergencia · episodio 1, «La entrevista»

Juego rítmico táctil para Pinyol y la consola Cirera. Una charanga sale de un ascensor y acompaña a una persona nerviosa
hasta la puerta de su entrevista. El jugador marca el ritmo; la persona entra siempre, y la puntuación cambia la
energía de la escena y del cierre. Vertical slice: un episodio de un minuto.

## Controles

- **Dedo**: toca cada círculo numerado cuando su aro se cierre sobre él. En un camino amarillo, toca su inicio a
  tiempo y sigue la bola con el dedo hasta el final.
- **Botones**: A toca la nota que toca en ese momento y, mantenido, sigue un camino; A o START empiezan y repiten.
- **Dificultad** (los tres carteles de la portada; la cruceta elige): **Ensayo** (±200 ms, sin notas seguidas),
  **Pasacalles** (±160 ms, la partitura tal cual), **La plaza a reventar** (±120 ms, notas añadidas en los huecos, aviso
  más corto). La canción es la misma en las tres. Se recuerda para la siguiente partida.
- **Pausa**: START para la música; START o «Seguir» la reanudan desde el principio del compás; «Salir» vuelve a la portada.
- **Ajustar ritmo** (portada, o C): suena el bombo y tocas a la vez; la mediana de 12 toques es tu compensación, guardada
  para las siguientes partidas (`chart.OFFSET`).

## Estructura

| Archivo | Qué es |
|---|---|
| `main.lua` | estados (portada, partida, entrada, resultado), juicio de golpes y caminos, feedback |
| `song.lua` | la música, «Pasodoble del ascensor», hecha con el secuenciador del motor (`studio`), y su reloj: `studio.pos()` contado en compases |
| `chart.lua` | la partitura: notas en tiempos de negra, ventanas de acierto, posiciones en pantalla |
| `scene.lua` | el pasillo: dónde está cada personaje en cada momento, el medidor de ánimo |
| `es.lua` | todos los textos visibles (para traducir: una copia con las mismas claves) |
| `art.py` | `art/raw/` (imágenes generadas) → `art/` → `assets/`; `art/raw/prompts.txt` guarda cada prompt. `send_game.py` no envía `art/` a la consola |
| `tests/charanga.script` | portada, acierto, fallo, botón A, camino, final, resultado y reintento |
| `tests/niveles.script` | las tres dificultades: notas, ventanas, la elección guardada y la cruceta |
| `tests/ajustes.script` | la calibración (toques 0,1 s tarde dan unos +100 ms, guardados) y la pausa |

El reloj es el del secuenciador (`studio.pos()`, que ya descuenta lo que espera en el altavoz), no ticks acumulados.
`chart.OFFSET` suma una compensación en segundos para todas las notas.

## Ejecutar, probar, empaquetar

```sh
./build/pinyol_sim --game games/charanga
./build/pinyol_headless --game games/charanga --fresh --script games/charanga/tests/charanga.script --check-strips --strict-assets
uv run games/charanga/art.py                 # tras cambiar algo en art/raw/
python3 tools/pack_game.py games/charanga -o dist/
uv run --with pyserial tools/send_game.py games/charanga   # a la consola por USB
```

## Estado

- **Música**: «Pasodoble del ascensor», original, con el secuenciador: bombo, caja, platillos y los sonidos de la
  oficina (el «ding» del ascensor, el tic-tac del reloj en la duda, el «toc, toc» en la puerta) hechos con `sound()`;
  trompeta, segunda trompeta a una tercera, trombón con glissandos y tuba en voces de sintetizador. La duda va en re
  menor; la fanfarria sube un tono (sol mayor). Mezcla medida con `--audio`: sin saturar, metales 3 dB bajo la
  percusión en RMS (el altavoz de la consola apenas da los graves del bombo).
- **Arte**: estilo «PlayStation y Saturn 2D» (`docs/art.md`), generado: fondo del pasillo, cuatro poses de la charanga
  (apiñada en el ascensor, desfilando, fanfarria y celebrando, esta solo con el ánimo a 0,4 o más) y cinco de la
  protagonista. La hoja de la charanga vino con un damero pintado: `art.py` lo quita.
- **Sin hacer**: la nota circular, más episodios.
- **Probado**: simulador headless (el test pasa). En la Cirera física (2026-10-20): arranca y la portada va a 59 fps
  sin errores; jugada a mano por Pau: los golpes, los caminos y la calibración se sienten a tiempo.
  Con la música y las dificultades (2026-10-21): 60 fps, el audio un 18 % de un núcleo y sin cortes; la melodía
  se oye sobre el bombo y se distinguen los sonidos de la oficina. Mientras suena, la RAM interna libre baja de 32 a 24 KB.
