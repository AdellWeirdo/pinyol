# Hoja de ruta: qué falta en pinyol (21 octubre 2026)

Investigación web en siete frentes (rendimiento del ESP32-S3, plataformas tipo Playdate/PICO-8, sensación de juego,
gráficos retro, audio, red y patentes, herramientas y accesibilidad), cruzada con lo que el motor ya tiene. Solo lo que
falta. Los costes de CPU y RAM son **estimaciones**: medir en la placa antes de decidir. [V] = comprobado en la fuente o
en el repo; [U] = deducido.

Ya cubierto, no repetir: hit-stop (`juice.freeze`), buffer de salto (`btnb`), mapas de Dijkstra (`g:distances`,
`l:descend`), `noise()`, efectos por línea (HDMA), sin límite de sprites por línea, sombra/brillo vía ventanas y `fade`,
`.mod`, sonidos de números (sfxr), director musical (solo aventuras JSON), investigación GBA/PS1/Saturn/DS.

## Estado (21 octubre 2026)

- **Fase 0, hecho:** código del sistema y driver de flash fuera de IRAM (+19,8 KB; `firmware/sdkconfig.defaults`),
  `perf("lua")` y `--profile` (profiler por muestreo), `span_mix_const` con PIE para cajas de un color mezcladas
  (comprobado en QEMU, `tests/pie/run.sh`). **Pendiente de placa:** medir fps con las tiras y PIE, probar
  `CONFIG_ESP32S3_DATA_CACHE_32KB` (+32 KB) y `CONFIG_SPIRAM_XIP_FROM_PSRAM`; saltar tiras sin cambios no compensa
  mientras el DMA ya solapa el dibujo (ganaría batería, no fps).
- **Fase 1, hecho:** menú del sistema (`sysmenu.c`), ajustes de consola (`conf.c`: volumen, destellos, filtro de
  color, velocidad, idioma, A/B), pantalla de crash y `crash.txt`, `--record` y el comando `in`, `--check-flashes`
  (también en el robot de la Biblioteca), F6/F7/F8/F9 en el simulador. **Cerrada el 22 de octubre:** QR en la
  pantalla de crash (`third_party/qrcodegen`, el error con el id del juego en ≤ 57×57 módulos a 2 px; un móvil lo lee
  en la pantalla de la consola), remapeo completo de A, B y C (`settings().buttons`, los seis órdenes en Ajustes) y
  mantener/alternar (`settings().sticky`: pulsar deja el botón pulsado hasta la siguiente pulsación; el motor lo
  hace, el juego no se entera); recientes/favoritos/tiempo jugado quedaron en la fase 5.

- **Fase 2, hecho:** `lib/move` (actores y sólidos de Celeste, coyote, buffer, salto corto, ápice, esquinas, plataformas
  de un sentido, sólidos que llevan y empujan), `lib/autotile` (blob 47 y dual-grid 16), juice (trauma con ruido, kick,
  muelles de segundo orden, squash), story (secuencias `{a|b}`, `{&}`, `{~}`, `{!}` y `visits()`), audio (`bus()`,
  `duck()`, `sfx` con `pitch_var`, `gain_var`, `max`, `cooldown`), `lib/voice` (blips tipo Animalese, `rich` acepta
  una función en `blip`). **No hecho:** cadena del altavoz (paso alto, compresor, bajo virtual: hay que afinarla con el
  micro de la placa), rampas/bucles tipo Sonic.

- **Fase 3, hecho:** `palcycle` con BlendShift, `line_affine` y `line_scroll_ramp` (las tablas por línea del PPU
  desde Lua), `shock` y `haze` (post-proceso sobre el mundo, `src/post.c`), `lib/stack` (sprite stacking con caché de
  ángulos en canvases), `lib/water` (muelles), `lib/road` (carretera pseudo-3D sobre `line_affine`). Comprobado por
  píxel en `tests/looks_check.py`. **Hecho el 22 de octubre:** visibilidad 2D (`g:fov`, shadowcasting en C sobre la
  rejilla; `g:sees`, línea de visión) y silueta tras paredes (`SILHOUETTE` en `spr`, `silhouette(color, fuerza)`: el PPU
  mezcla el color donde un fondo más cercano tapa al sprite); el mismo día, dither de ruido azul (`src/bluenoise.h`,
  32×32 por void-and-cluster, en el disolvente de `shade`/`img`), Voxel Space (`voxels()`, terreno de Comanche sobre un
  canvas) y luz por paleta (`lib/light`: entradas que son superficies, iluminadas desde la dirección de la lámpara).
  **No hecho:** cleanEdge (un escalado de 240→480 por píxel con pendientes: en la ESP32 no cabe en el frame; la
  consola escala ×2 por DMA), mallas 3D.

- **Fase 4, hecho:** música adaptativa (`music(id, fade, {bar, beats, loop_at, layers, at = "bar"})`: la canción nueva
  espera aparcada y el mezclador la cambia en la línea de compás; `music_beat()`, `music_queued()`), `lib/brain` (IA de
  utilidad), `lib/rng` (Squirrel noise, flujos por semilla, fbm), `lib/gen` (cuevas, BSP, paseo, salas de Spelunky,
  `connected`), `lib/chain` (cadenas, patas que dan pasos, FABRIK, dos huesos), `lib/steer` (seek/flee/arrive/wander/
  pursue/separate/flock y un hash espacial), `grid`: `l:scale`, `l:mix`, `g:rescan` (mapas de huida de Brogue).
  **Hecho el 22 de octubre:** voz FM (`wave = "fm"` en `tone` y `sound`: dos operadores, `fm_ratio`, `fm_index` que sigue
  la envolvente), marcadores propios del WAV (`smpl` para el bucle, dos `cue` para el compás, cuando `music()` no los
  da), y XM/S3M (IBXM de Martin Cameron, BSD; `music("ID")` encuentra `.mod`, `.xm` o `.s3m`, con
  compás, cola y parada en la línea como los `.mod`; `tests/make_tracker.py` genera los tres módulos de prueba). En la
  placa, un XM de ocho canales cuesta el 7 % de un núcleo y nada de RAM interna (docs/measurements.md).
  `tools/famistudio2mod.py` convierte la exportación de texto de FamiStudio en un `.mod` de cuatro canales (duty, triángulo,
  ruido; envolvente de volumen fila a fila; sin arpegios ni DPCM). **No hecho:** `.uge` (hUGETracker, binario y por versión).

- **Fase 5, hecho:** `lib/lockstep` (juego en paso sobre `link`: solo botones, tramas de 3 ticks con repetición,
  retardo de 2 tramas), registro de la consola (`played.json`: partidas, tiempo, última vez, favoritos, logros),
  `achieve()`/`achievements()` con `game.json "achievements"`, `console_played()`/`console_favourite()`, y el menú de
  Cirera ordena favoritos y recientes, muestra partidas/tiempo/logros y C marca favorito. **Hecho el 22 de octubre:**
  `lib/rollback` (netcode con retroceso sobre el transporte de `lockstep`: el juego da `save`/`load`/`run`, corre sin
  esperar, adivina y rehace los ticks cuando llega la verdad; probado en headless con una consola fingida por el guion).
  **No hecho:** ESP-NOW v2, Download Play y tarjetas tipo StreetPass (hacen falta dos placas), estantería de logros en
  la Biblioteca.

- **Fase 6, hecho:** `tools/ase2asset.py` (lee el `.aseprite`: capas, cels comprimidos y enlazados, paletas, tags,
  slices → imagen + `<id>_anims.lua`), `tools/ldtk2asset.py` (export simplificado: fondo o tiles, IntGrid, entidades →
  `<id>.lua`), recarga en caliente que conserva el estado (`v2_hotswap`, el simulador la usa al guardar un módulo;
  `hotswap FILE MOD` en scripts), `lib/lang` + `tools/strings_check.py` (CSV por idioma, letras que faltan en las
  fuentes, pseudo-idioma), `pack_game --budget`, `llms.txt` en el sitio. **No hecho:** REPL y `tweak()` por el cable
  (hace falta placa), depurador DAP, robot de cobertura en la Biblioteca.

- **Fase 7, hecho:** `tilt()`, `tilt_zero()`, `rumble()` sobre `hal_imu`/`hal_rumble` (por defecto "no hay"), comandos
  `tilt` y `expect_rumble` en los scripts, y `docs/hardware-rev2.md` (los añadidos por I2C, direcciones, patentes).
  **No hecho (hace falta la placa):** los drivers del firmware para la IMU y el DRV2605L.

### Hecho en la placa (21 octubre 2026, tarde; detalles y tablas en docs/measurements.md)

1. Firmware de `main` flasheado (app + otadata): el menú arranca con 51 KB internos (antes 32); juntos enciende la
   radio y le quedan 24 KB (antes 6); juegos por el cable y `game_init` como antes.
2. Caja mezclada de pantalla completa (PIE): 3,4 ms de tiras (antes 12,3).
3. Variantes medidas jugando nueve juegos con el mismo guion por el cable: caché de datos a 32 KB (+31 KB internos,
   coste nulo) y XIP desde PSRAM (mundo −10-30 %, −1,7 MB de PSRAM). Las dos quedan en `sdkconfig.defaults`: un juego
   Lua corre con ~70 KB internos libres (antes ~40); con la radio, ~43.
4. Juegos exigentes en juego: trece, duelo, torneo, castells, control, paleta, horizonte, veloz a 59-60 fps; maqueta
   56,9 (su propio `_draw`, 6 ms, igual en todas las builds); Bajo Pueblo (aventura) 60 fps andando, 52-58 en diálogo,
   38-50 en su portada (una imagen de 480×320 cada frame), igual que con la build antigua.
5. Menú del sistema sobre TRECE visto en la pantalla real (captura por el cable). `played.json` no se escribía en
   FAT (`rename` sobre un archivo existente): arreglado (`played.c`).

6. ILUSTRES (44 MB, enviado por el cable): combates a 57,6-59,8 fps, intro de asalto a 53, con 2 MB de PSRAM de margen.
   El 22 de octubre, dos consolas por `lib/lockstep` (VERSUS > DUES CONSOLES: P1 la de id menor, sus reglas para las
   dos, secretos solo los que tienen ambas; espera y abandono a los 10 s), probado en el headless con la otra consola
   simulada (`link_from`), no en dos placas. Lo que enseñó: una consola que espera a la otra no puede seguir muestreando
   tramas (se salían del `history` y la que llegaba tarde no las recibía nunca): `lockstep` ahora se para a una trama
   de la que juega y reenvía las últimas cada 6 ticks mientras espera.
   El mismo día, en ILUSTRES: TECH! (A+C al ser agarrado rompe la proyección, GDD 4.6) y CONTRAATAC! (el especial
   pedido bloqueando, por un stock, GDD 5.1); bloqueo aéreo y barra de guardia descartados (no están en el GDD y mueven
   el balance medido por parejas). Medido en la placa (`juegos/ILUSTRES-ESP/tests/cps2bench`, `sh make.sh`; docs/measurements.md): el escenario de
   ILUSTRES todo en el overlay cuesta 12,6 ms de CPU por frame en strips; con la capa lejana en el mundo (canvas a
   mitad, el PPU la dobla) 5,6 + 2,1 de capas; con las dos en el mundo 1,9 + 3,0. Pasar la lejana al mundo libera
   ~5 ms de CPU por frame sin que se note; la cercana a mitad pierde el público. Decisión de Pau. Suelo en perspectiva: no hace
   falta nada nuevo en C: `warp` con `rows` para una franja, bandas `clip`+`img` como torneo (36 bandas a 60-61 fps) o
   `line_scroll_ramp` si la capa pasa al mundo.
   Y lo que apareció al jugarlo en la placa (22 de octubre): un luchador sin dibujar (`asset SPR_RODOREDA: not a packed
   picture`), no por falta de memoria sino por trozos: 12 000 bloques de Lua entre las imágenes dejaban 1,5 MB libres con
   un bloque mayor de 320 KB, y un fallo de carga era para toda la partida. Arreglado en el motor (los objetos pequeños de
   Lua en trozos de 32 KB, las imágenes se sueltan de una en una, una carga sin memoria se reintenta, 300 KB estáticos de
   las capturas fuera) y en el juego (precarga sin los fondos de SUPER): ver docs/measurements.md, «PSRAM in pieces».

7. Vistos en la pantalla real sobre horizonte: el menú del sistema, la página de ajustes, el filtro protan (1,8 ms por
   frame) y la pantalla de crash con A reiniciando. Y un abort encontrado y arreglado (9bb4905): el dibujo corre en los
   dos núcleos y no puede tocar el estado de Lua.

8. `music(..., {at = "bar"})` en el mezclador de la consola: con compás de 2 s, la canción encolada espera
   (`music_queued()` true, la vieja a 0,90 s) y entra en la línea (en la muestra siguiente, la nueva a 0,32 s = 0,9 + 1,1).

### Un juego real sobre la ronda: CONTROL (21 octubre, noche)

Las bibliotecas estaban probadas contra tests, no contra un juego. CONTROL (`juegos/CONTROL`, la sala de control de
TV, Lua) usa ahora `lib/voice` (Marta y Joan hablan en blips de su onda y su tono, uno cada dos letras, la altura por
la letra), `duck()` bajo el intercomunicador de la Núria, las opciones de `sfx` (clics variados, errores con
`cooldown`, un pip a la vez), `music(nil, 200, {at = "bar"})` para que la sintonía acabe en su línea de compás, logros
en `game.json` con `achieve()` (el informe nombra los nuevos), `settings().reduce_flashing` (los tallies ámbar fijos,
la nieve del monitor quieta) y `juice.tween` (las fichas entran deslizando). Sus cuatro guiones pasan en el headless.

Lo que el juego real sacó del motor, arreglado en la misma noche:

- **El profiler estaba muerto** desde 479ba09 (`v2_free` lo paraba al arrancar cada juego, y `game_init` empieza por
  `game_shutdown`): ahora el profiler es de la plataforma (`prof_stop` al salir del player, del simulador y del core
  libretro), y el hook de cuenta no se reinicia en cada llamada, así los ticks cortos (< 1000 instrucciones) también
  se muestrean. `--profile` sobre CONTROL: 554 ms de Lua en dos programas enteros; nada que optimizar
  (`score.tick` 110 ms, `pilot` 189 ms solo en los tests, `babble` 42 ms; la carga domina: `third_below` y `letters`).
- **`lib/voice` callaba las vocales con acento** (`%a` es ASCII en Lua): à, é, ñ, ç... se dicen como la letra de debajo.
- **Los módulos `.mod` esquivaban el bus de música**: entraban al mezclador después del bus, así que `bus("music")`,
  `duck()` y `at = "bar"` no les llegaban, y las sintonías de CONTROL son módulos. Ahora pasan por el bus como un WAV,
  `music("ID", fade, {at = "bar"})` espera la línea de compás del módulo que suena (dieciséis líneas, cuatro tiempos de
  cuatro), `music(nil, fade, {at = "bar"})` lo deja llegar a su línea y lo funde ahí, y `music_beat()` cuenta sus
  compases. `tests/games/music/audio/LOOP.mod` (generado, 2 KB) lo comprueba en el headless.
- Un guion de test no puede escribir `#t` (es comentario): `rawlen`.

En la placa (bench del propio juego, autopiloto en silencio, 76 s): Lua `_update` 0,74 → 0,80 ms, `_draw` 4,5 → 4,5 ms,
59,8 fps, 77 → 76 KB internos, 0 underruns, en el mismo firmware. Con el firmware de esta noche (módulos por el bus,
voces con acento): 0,79 / 4,61 ms, 59,8 fps, 76 KB, audio al 14 % de un núcleo, 0 underruns. El firmware se queda en
la consola (remoto) y el juego normal en la tarjeta, para oírlo.

### Dos juegos más: TRECE y 07:59 · Ocho mañanas (21 octubre, noche)

TRECE (petanca en primera persona, Mode 7): el rival decide cada bola con `lib/brain` (arrimar, tirar a la mejor
contraria o empujar el boliche, pesado por el momento y la persona; el cartel dice lo que pretende), un golpe sacude
los ojos de Remei (`juice.trauma` leído en la cámara de Mode 7: un paso, un cabeceo, un giro) y manda un anillo por
la imagen desde donde chocó el acero (`shock`), la calor tiembla sobre los pies de las casas (`haze`), cada persona
tiene su voz en la historia (`lib/voice` como función `blip` de `story`: Remei grave, Tina aguda), cuatro logros, y
la película de 1983 no parpadea ni deslumbra con "menos destellos". Sus cuatro guiones pasan.

Ocho mañanas (ritmo táctil): el sello del acierto cae grande y se asienta (`juice.tween`), un fallo encoge los bustos y
el toro que roza tambalea a Dani (`juice.trauma`), cuatro logros, rayos de un solo color con "menos destellos". Sus
seis guiones pasan.

PALETA (puzle de gotas, 22 octubre): el estallido de un grupo sacude la paleta, más con cada eslabón de cadena
(`juice.trauma` sumado a la esquina del tablero), la ficha del resultado entra deslizando (`juice.tween`), cuatro
logros (la ficha nombra los nuevos), y con "menos destellos" el fogonazo de la cadena se queda en un brillo y el grupo
no parpadea. De paso, `tests/reglas.script` llevaba tiempo roto (un estallido forzado sin pareja caída no tenía
eslabón): arreglado en `juego.lua`. Sus dos guiones pasan. En la placa, con el autopiloto (3 ms de tick suyos):
3,05 → 3,24 ms, 51,6 → 51,5 fps, mismos niveles ganados.

Lo que sacaron del motor: `post.c` copiaba la imagen entera (76 KB, en PSRAM) cada frame aunque la neblina fuera de
veinte filas: en la placa TRECE pasó de 58,5 a 55,5 fps (mínimo 43) con la neblina siempre puesta. Ahora copia solo
las filas que leen los efectos (la neblina las suyas, cada anillo su alcance): 58,0 fps, render 15,6 ms (antes de
los efectos 15,45). Y dos aclaraciones en `docs/lua.md`: `shock`/`haze` actúan sobre el mundo (capas y sprites), no
sobre lo que `img`, las formas y `text` dibujan a resolución completa encima (un juego solo de `img` no los ve), y
el `blip` de una historia puede ser una función (una voz por personaje). `lib/brain`, `juice`, `voice`, `achieve()`
y `settings()` no pidieron ningún cambio.

**Aún pendiente de placa:** nada de esta ronda. Oír `at = "bar"` y las voces de `lib/voice` con el altavoz es cosa de
orejas, no de log.

## Fase 0 · Memoria y rendimiento

Lo que más limita es la RAM interna (la radio pide 27 KB). Criterio de salida: ≥ 40 KB internos libres con radio y
studio a la vez, sin perder fps.

| Qué | Ganancia | Fuente |
|---|---|---|
| `CONFIG_FREERTOS_PLACE_FUNCTIONS_INTO_FLASH`, `CONFIG_RINGBUF_PLACE_FUNCTIONS_INTO_FLASH`, `CONFIG_HEAP_PLACE_FUNCTION_INTO_FLASH` (y quizá `CONFIG_SPI_FLASH_ROM_IMPL`) | +20-30 KB IRAM [U]; en el map del 17-oct: freertos 15 KB, spi_flash 10.9, heap 6.7, ringbuf 4.1 [V] | [ram-usage](https://docs.espressif.com/projects/esp-idf/en/v5.4/esp32s3/api-guides/performance/ram-usage.html) |
| Caché de datos 64 → 32 KB | +32 KB de heap [V]; coste en PSRAM desconocido | idem |
| PIE (SIMD) en las tiras del overlay: fill, copy, blend, add | copy 0.35 vs 3.4 ciclos/px [V] | [esp_lvgl_port simd](https://github.com/espressif/esp-bsp/tree/master/components/esp_lvgl_port/test_apps/simd) (Apache-2), [Jet](https://github.com/CubeCoders/Jet) `src/BlendSpans.cpp` (MIT) |
| Saltar tiras que no cambian (hash por banda) | ~0.5 ms y batería por tira [U] | idea de [retro-go rg_display.c](https://github.com/ducalex/retro-go/blob/master/components/retro-go/rg_display.c) (GPL: solo la idea) |
| `CONFIG_SPIRAM_XIP_FROM_PSRAM` | guardar sin congelar el juego [V]; velocidad sin medir | [external-ram](https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/api-guides/external-ram.html) |
| Profiler Lua por muestreo: hook `LUA_MASKCOUNT` en `arm()`, `perf("lua")` y folded stacks | saber qué función Lua es la lenta | [lmprof](https://github.com/citizenfx/lmprof) (MIT) |

Luego: Lua 5.5 (`table.create`, arrays 60 % más pequeños, GC mayor incremental; cambios que rompen: `global`, variables
de for de solo lectura). `esp_new_jpeg` (480×320 con giro a ~31-36 fps, 10 KB internos [V]). No: PSRAM a 120 MHz
(experimental), ESP32-P4 (sin ESP-NOW [V]).

## Fase 1 · Plataforma: lo que todos los juegos heredan

- **Menú de pausa del sistema** (toque corto de MENU; mantener sigue saliendo), con opciones del juego: como
  `menuitem()` de [PICO-8](https://www.lexaloffle.com/dl/docs/pico-8_manual.html) y el menú de
  [Playdate](https://sdk.play.date/inside-playdate/).
- **Pantalla de crash**: traza entera (`msgh` ya la hace), A reinicia, B a Cirera, log en la carpeta de guardados, QR a un
  issue rellenado.
- **Ajustes globales**: volumen por bus, reducir destellos (`getReduceFlashing` de Playdate), filtro de daltonismo sobre
  la paleta ([Machado 2009](https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html)),
  remapeo y mantener/alternar ([XAG 107](https://learn.microsoft.com/gaming/accessibility/xbox-accessibility-guidelines/107)),
  velocidad del juego ([modo asistido de Celeste](https://gameaccessibilityguidelines.com/celeste-assist-mode/)).
- **Grabar una partida como `.script`** (`--record`): informe de bug, test y fantasma a la vez.
- **Detector de destellos** en el headless y el robot de la Biblioteca
  ([WCAG 2.3.1](https://www.w3.org/WAI/WCAG22/Understanding/three-flashes-or-below-threshold.html),
  [XAG 118](https://learn.microsoft.com/gaming/accessibility/xbox-accessibility-guidelines/118); validar con
  [EA IRIS](https://github.com/electronicarts/IRIS), BSD-3).
- **Captura** de pantalla y GIF de los últimos 10 s ([msf_gif](https://github.com/notnullnotvoid/msf_gif), dominio
  público), y portada tomada del momento.

## Fase 2 · Sensación de juego

- **`move`**: actores y sólidos de Celeste/TowerFall, coyote, media gravedad en el ápice, corrección de esquinas,
  plataformas de un sentido y móviles ([Celeste & TowerFall physics](https://maddymakesgames.com/articles/celeste_and_towerfall_physics),
  [forgiveness](https://maddymakesgames.com/articles/celeste_and_forgiveness/), [Player.cs](https://github.com/NoelFB/Celeste/blob/master/Source/Player.cs)).
  `kit` y `plataformas` hoy escriben cada uno el suyo.
- **juice**: temblor `trauma²` con ruido ([Eiserloh GDC 2016](https://www.gdcvault.com/play/1023557/)), muelles de
  segundo orden ([t3ssel8r](https://www.youtube.com/watch?v=KPoeNZZ6H4s)), squash & stretch.
- **`autotile`**: blob 47 ([Boris the Brave](https://www.boristhebrave.com/permanent/24/06/cr31/stagecast/wang/blob.html))
  y dual-grid de 16 tiles ([jess::codes](https://www.youtube.com/watch?v=jEWFSv3ivTg)).
- **Audio**: buses, ducking y snapshots desde Lua (biquads del [Audio EQ Cookbook](https://www.w3.org/TR/audio-eq-cookbook));
  cadena del altavoz de 1.5 W (paso alto, compresor, bajo virtual); `sfx` con `pitch_var`, `max`, `cooldown`; voces tipo
  Animalese ([Springbound](https://brycetown.substack.com/p/springbound-devlog-4-making-critters-talk)).
- **story**: contador de visitas y secuencias/barajas `{a|b|c}` como Ink.

## Fase 3 · Looks nuevos

- `palcycle` con BlendShift ([Mark Ferrari GDC 2016](https://www.youtube.com/watch?v=aMcJ1Jvtef0),
  [canvascycle](https://github.com/jhuckaby/canvascycle), MIT). `pal()` hoy solo escribe.
- Exponer las tablas por línea del PPU: `line_affine`, `line_scroll_ramp`, `col_scroll` (`ppu_line_affine` ya existe).
- Onda de choque y calima sobre el frame del PPU ([iq deform](https://iquilezles.org/articles/deform/)).
- Sprite stacking con caché por ángulo; dither de ruido azul ([texturas CC0](https://momentsingraphics.de/BlueNoise.html));
  `road` pseudo-3D ([Lou's Pseudo 3d](http://www.extentofthejam.com/pseudo/)); agua con muelles
  ([Tuts+](https://code.tutsplus.com/make-a-splash-with-dynamic-2d-water-effects--gamedev-236t)); visibilidad 2D
  ([Red Blob](https://www.redblobgames.com/articles/visibility/)); silueta detrás de paredes.
- Después: [Voxel Space](https://github.com/s-macke/VoxelSpace), luz normal por paleta
  ([30fps.net](https://30fps.net/pages/palette-lighting-tricks-n64/)), rotación [cleanEdge](https://torcado.com/cleanEdge/)
  pre-renderizada (MIT), mallas con [small3dlib](https://gitlab.com/drummyfish/small3dlib) (CC0) o Jet.

## Fase 4 · Música y sistemas

- Música adaptativa en Lua tipo [iMUSE](https://patents.google.com/patent/US5315057A) (caducada 2011): cambio en compás,
  tiempo o marcador; stingers.
- XM/S3M con [micromod](https://github.com/martincameron/micromod) (BSD-3); voz FM 4-op propia para el look 16 bits
  (no [ymfm](https://github.com/aaronsgiles/ymfm): pesado); `.uge` y FamiStudio sobre el PSG.
- `brain` (IA de utilidad, [Mark & Dill GDC 2010](https://gdcvault.com/play/1012410/)), `g:rescan`/`l:mix` en C
  ([Dijkstra maps](https://www.roguebasin.com/index.php?title=The_Incredible_Power_of_Dijkstra_Maps)), `rng`/`gen`
  (cuevas, BSP, [Spelunky](https://tinysubversions.com/spelunkyGen2/)), `chain`/IK ([FABRIK](https://www.andreasaristidou.com/FABRIK)),
  `steer`/boids.

## Fase 5 · Jugar juntos (necesita la RAM de la fase 0)

- [ESP-NOW v2](https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/api-reference/network/esp_now.html), 1470 B.
- `btn(p)` por jugador → lockstep → rollback-lite para duelo y torneo (inputs de los últimos 8-16 frames por paquete,
  snapshots en PSRAM). [Infil](https://words.infil.net/w02-netcode.html), [GGPO](https://en.wikipedia.org/wiki/GGPO) (MIT),
  [WASM-4](https://wasm4.org/docs/guides/multiplayer).
- Download Play: el juego por trozos a la SD de otra consola, con minijuego mientras carga
  ([Namco US5718632](https://patents.google.com/patent/US5718632A/en), caducada 2015).
- Tarjetas tipo StreetPass en el menú; launcher con recientes, favoritos y tiempo; logros con el formato de
  [pd-achievements](https://github.com/PlaydateSquad/pd-achievements).

## Fase 6 · Herramientas

Recarga en caliente que conserva el estado ([lume.hotswap](https://github.com/rxi/lume), MIT), REPL y `tweak()` por el
cable, `ase2asset` ([spec](https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md)), `ldtk2asset`
([super simple export](https://ldtk.io/docs/game-dev/super-simple-export)), localización con CSV y comprobación de glifos,
`pack_game --budget`, [`llms.txt`](https://llmstxt.org). Depurador DAP al final (el sandbox no tiene `debug`).

## Fase 7 · Hardware (Cirera rev2)

No queda ningún GPIO libre: todo por I2C (SDA 38, SCL 39; ocupadas 0x18, 0x20, 0x55). IMU LSM6DS3/BMI270 para inclinar
([Nintendo US6375572](https://patents.google.com/patent/US6375572B1/en), caducada 2020); DRV2605L vibración; manivela
[AS5600](https://components.espressif.com/components/espressif/as5600); reloj PCF8563; segundo PCF8574 para L/R.

## Evitar

- Patentes vivas: Nemesis de WB (US11192028), StreetPass con podómetro de Nintendo (US9687733, hasta 2031).
- Licencias: SAM (sin licencia), espeak-ng (GPL-3), Furnace (GPL), Nuked-OPN2 (LGPL), Game_Music_Emu (LGPL),
  retro-go (GPL, solo ideas).
- PSRAM a 120 MHz, WFC o GOAP en la consola, ESP32-P4 como placa mientras no tenga ESP-NOW.
