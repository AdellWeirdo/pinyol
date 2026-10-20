# La Charanga de Emergencia · episodio 1, «La entrevista»

Juego rítmico táctil para Pinyol y la consola Cirera. Una charanga sale de un ascensor y acompaña a una persona nerviosa
hasta la puerta de su entrevista. El jugador marca el ritmo; la persona entra siempre, y la puntuación cambia la
energía de la escena y del cierre. Vertical slice: un episodio de un minuto.

## Controles

- **Dedo**: toca cada círculo numerado cuando su aro se cierre sobre él. En un camino amarillo, toca su inicio a
  tiempo y sigue la bola con el dedo hasta el final.
- **Botones**: A toca la nota que toca en ese momento y, mantenido, sigue un camino; A o START empiezan y repiten.
- **Pausa**: START para la música; START o «Seguir» la reanudan desde el principio del compás; «Salir» vuelve a la portada.
- **Ajustar ritmo** (portada, o C): suena el bombo y tocas a la vez; la mediana de 12 toques es tu compensación, guardada
  para las siguientes partidas (`chart.OFFSET`).

## Estructura

| Archivo | Qué es |
|---|---|
| `main.lua` | estados (portada, partida, entrada, resultado), juicio de golpes y caminos, feedback |
| `song.lua` | música **temporal** hecha con el secuenciador del motor (`studio`) y su reloj: `studio.pos()` contado en compases |
| `chart.lua` | la partitura: notas en tiempos de negra, ventanas de acierto, posiciones en pantalla |
| `scene.lua` | el pasillo: dónde está cada personaje en cada momento, el medidor de ánimo |
| `es.lua` | todos los textos visibles (para traducir: una copia con las mismas claves) |
| `art.py` | `art/raw/` (imágenes generadas) → `art/` → `assets/`; `art/raw/prompts.txt` guarda cada prompt. `send_game.py` no envía `art/` a la consola |
| `tests/charanga.script` | portada, acierto, fallo, botón A, camino, final, resultado y reintento |
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

- **Audio temporal**: bombo, caja y platos hechos con `sound()`, trompeta y tuba con `studio.synth`. No es la banda
  sonora final.
- **Arte**: estilo «PlayStation y Saturn 2D» (`docs/art.md`), generado: fondo del pasillo, cuatro poses de la charanga
  (apiñada en el ascensor, desfilando, fanfarria y celebrando, esta solo con el ánimo a 0,4 o más) y cinco de la
  protagonista. La hoja de la charanga vino con un damero pintado: `art.py` lo quita.
- **Sin hacer**: selección de dificultad (Ensayo,
  Pasacalles, La plaza a reventar), la nota circular, más episodios.
- **Probado**: simulador headless (el test pasa). En la Cirera física (2026-10-20): arranca y la portada va a 59 fps
  sin errores; jugada a mano por Pau la primera versión. La calibración y la pausa solo están probadas en headless.
