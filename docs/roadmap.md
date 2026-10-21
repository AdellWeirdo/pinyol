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
  (también en el robot de la Biblioteca), F6/F7/F8/F9 en el simulador. **No hecho:** QR en el crash, remapeo
  completo y mantener/alternar (solo A/B), recientes/favoritos/tiempo jugado (en la fase 5).

- **Fase 2, hecho:** `lib/move` (actores y sólidos de Celeste, coyote, buffer, salto corto, ápice, esquinas, plataformas
  de un sentido, sólidos que llevan y empujan), `lib/autotile` (blob 47 y dual-grid 16), juice (trauma con ruido, kick,
  muelles de segundo orden, squash), story (secuencias `{a|b}`, `{&}`, `{~}`, `{!}` y `visits()`), audio (`bus()`,
  `duck()`, `sfx` con `pitch_var`, `gain_var`, `max`, `cooldown`), `lib/voice` (blips tipo Animalese, `rich` acepta
  una función en `blip`). **No hecho:** cadena del altavoz (paso alto, compresor, bajo virtual: hay que afinarla con el
  micro de la placa), rampas/bucles tipo Sonic.

- **Fase 3, hecho:** `palcycle` con BlendShift, `line_affine` y `line_scroll_ramp` (las tablas por línea del PPU
  desde Lua), `shock` y `haze` (post-proceso sobre el mundo, `src/post.c`), `lib/stack` (sprite stacking con caché de
  ángulos en canvases), `lib/water` (muelles), `lib/road` (carretera pseudo-3D sobre `line_affine`). Comprobado por
  píxel en `tests/looks_check.py`. **No hecho:** dither de ruido azul, visibilidad 2D, silueta tras paredes, cleanEdge,
  Voxel Space, luz normal por paleta, mallas 3D.

- **Fase 4, hecho:** música adaptativa (`music(id, fade, {bar, beats, loop_at, layers, at = "bar"})`: la canción nueva
  espera aparcada y el mezclador la cambia en la línea de compás; `music_beat()`, `music_queued()`), `lib/brain` (IA de
  utilidad), `lib/rng` (Squirrel noise, flujos por semilla, fbm), `lib/gen` (cuevas, BSP, paseo, salas de Spelunky,
  `connected`), `lib/chain` (cadenas, patas que dan pasos, FABRIK, dos huesos), `lib/steer` (seek/flee/arrive/wander/
  pursue/separate/flock y un hash espacial), `grid`: `l:scale`, `l:mix`, `g:rescan` (mapas de huida de Brogue).
  **No hecho:** XM/S3M (micromod), voz FM, importar `.uge`/FamiStudio, marcadores en WAV.

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
