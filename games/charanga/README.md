# La Charanga de Emergencia · episodio 1, «La entrevista»

Juego rítmico táctil para Pinyol y la consola Cirera. Una charanga sale de un ascensor y acompaña a una persona nerviosa
hasta la puerta de su entrevista. El jugador marca el ritmo; la persona entra siempre, y la puntuación cambia la
energía de la escena y del cierre. Vertical slice: un episodio de un minuto.

## Controles

- **Dedo**: toca cada círculo numerado cuando su aro se cierre sobre él. En un camino amarillo, toca su inicio a
  tiempo y sigue la bola con el dedo hasta el final.
- **Botones**: A toca la nota que toca en ese momento y, mantenido, sigue un camino; A o START empiezan y repiten.

## Estructura

| Archivo | Qué es |
|---|---|
| `main.lua` | estados (portada, partida, entrada, resultado), juicio de golpes y caminos, feedback |
| `song.lua` | música **temporal** hecha con el secuenciador del motor (`studio`) y su reloj: `studio.pos()` contado en compases |
| `chart.lua` | la partitura: notas en tiempos de negra, ventanas de acierto, posiciones en pantalla |
| `scene.lua` | el pasillo: dónde está cada personaje en cada momento, el medidor de ánimo |
| `es.lua` | todos los textos visibles (para traducir: una copia con las mismas claves) |
| `art.py` | `raw/` (imágenes generadas) → `art/` → `assets/`; `raw/prompts.txt` guarda cada prompt |
| `tests/charanga.script` | portada, acierto, fallo, botón A, camino, final, resultado y reintento |

El reloj es el del secuenciador (`studio.pos()`, que ya descuenta lo que espera en el altavoz), no ticks acumulados.
`chart.OFFSET` suma una compensación en segundos para todas las notas.

## Ejecutar, probar, empaquetar

```sh
./build/pinyol_sim --game games/charanga
./build/pinyol_headless --game games/charanga --fresh --script games/charanga/tests/charanga.script --check-strips --strict-assets
uv run games/charanga/art.py                 # tras cambiar algo en raw/
python3 tools/pack_game.py games/charanga -o dist/
uv run --with pyserial tools/send_game.py games/charanga   # a la consola por USB
```

## Estado

- **Audio temporal**: bombo, caja y platos hechos con `sound()`, trompeta y tuba con `studio.synth`. No es la banda
  sonora final.
- **Arte**: estilo «PlayStation y Saturn 2D» (`docs/art.md`), generado: fondo del pasillo, la charanga como grupo y cinco
  poses de la protagonista. La charanga se anima por código (botes al compás); no tiene poses propias aún.
- **Sin hacer**: pausa, calibración de la compensación en la propia partida, selección de dificultad (Ensayo,
  Pasacalles, La plaza a reventar), la nota circular, más episodios.
- **Probado**: simulador headless (el test pasa). En la Cirera física (2026-10-20): arranca y la portada va a 59 fps
  sin errores; la partida con el dedo y la sincronía de oído aún no se han probado a mano.
