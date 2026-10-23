# pinyol

[![tests](https://github.com/ipaud/pinyol/actions/workflows/ci.yml/badge.svg)](https://github.com/ipaud/pinyol/actions/workflows/ci.yml)

[English](README.md) · Español · [Català](README.ca.md)

**[Juega todos los ejemplos en el navegador](https://pinyol.ipaud.dev/)**, con las medidas del motor en la consola.

<p align="center"><img src="docs/media/logo.webp" alt="pinyol" width="480"></p>

Un motor pequeño en C para juegos 2D en la consola **Cirera**, una portátil libre hecha con un ESP32-S3 (pantalla táctil de 480×320, botones, altavoz, microSD).

<p align="center"><img src="docs/media/console.webp" alt="La consola, una placa Freenove FNK0104N, arrancando: la intro de pinyol, el menú de Cirera con sus juegos y algunos en marcha" width="480"></p>

Un juego es **una carpeta**: cópiala en la microSD de la consola dentro de `games/<id>/` y aparece en la lista de juegos. La misma carpeta funciona en un simulador de escritorio y en el navegador. Hay dos tipos:

- **Juegos en Lua** (`"engine": "pinyol@2"`), de cualquier género. El motor les da una consola virtual a imagen de la Game Boy Advance: cuatro capas de fondo (tiles, giradas y escaladas, Mode 7), 128 sprites, paletas, transparencias, ventanas, mosaico y efectos por línea, con el texto dibujado encima a resolución completa. Van a 60 fps en la consola. Más allá de la pantalla y los botones: el micrófono (volumen, tono, palmadas, grabaciones), historias escritas como texto, el reloj de una canción para juegos de ritmo, cuerpos que vuelcan, ruedan y flotan, clips de vídeo en lienzos, el LED y la batería de la consola, y consolas que juegan juntas. La API: [docs/lua.md](docs/lua.md) (en inglés).
- **Aventuras hechas de datos** (`"engine": "pinyol@1"`): JSON para zonas, diálogos, objetos, puzles y eventos, sin código. Los primeros juegos del motor se hicieron así: [docs/game-format.md](docs/game-format.md).

Un juego se parece a la consola para la que está hecho, y el motor los mueve todos: elige un aspecto y sigue su receta en
[docs/art.md](docs/art.md#0-choose-a-look). Cada imagen es un momento de juego del ejemplo de ese aspecto
(`docs/looks/shots.sh` las vuelve a sacar).

| | |
|---|---|
| ![Un plataformas de Game Boy en cuatro tonos de verde, a pantalla completa](docs/looks/gameboy.png) | ![Una sala de ZX Spectrum: bloques de dos colores, un minero y un guardián](docs/looks/spectrum.png) |
| **Game Boy**: [cerezo](examples/cerezo), una aventura al estilo Zelda | **ZX Spectrum**: [socavon](examples/socavon), una mina, desde la carga de cinta |
| ![Un plataformas de tesoros de Game Boy Advance: una selva en cuatro capas, unas ruinas, una seta y un cartel](docs/looks/gba.png) | ![Un plataformas de velocidad de 16 bits: tierra a cuadros y un mar movido línea a línea](docs/looks/16bits.png) |
| **Game Boy Advance**: [botin](examples/botin), un plataformas de tesoros | **SNES / Mega Drive**: [veloz](examples/veloz), todo su arte dibujado con código |
| ![Un run and gun de Neo Geo: un cocinero en un tractor por una calle de pueblo, disparando a gaviotas mecánicas](docs/looks/neogeo.png) | ![Un juego de lucha de CPS2: luchadores de 15 colores sobre un suelo en perspectiva](docs/looks/cps2.png) |
| **Neo Geo**: [paella](examples/paella), un run and gun | **CPS2**: [torneo](examples/torneo) |
| ![Un puzle de tumbas de PICO-8: 128x128 en dieciséis colores](docs/looks/pico8.png) | ![Una maquinita LCD: un malabarista en un circo, figuras encendidas o apagadas](docs/looks/lcd.png) |
| **PICO-8**: [tumba](examples/tumba), un puzle de deslizamiento | **Maquinita LCD**: [malabar](examples/malabar), una Game & Watch |
| ![Un juego vectorial: líneas brillantes sobre negro](docs/looks/vector.png) | ![Un matamarcianos vertical, girado: se juega con la consola de lado](docs/looks/vertical.png) |
| **Recreativa vectorial**: [pozo](examples/pozo), sin imágenes | **Pantalla vertical**: [tormenta](examples/tormenta), con la consola de lado |
| ![Un laberinto en primera persona: pasillos de piedra y un fantasma, a lo Wolfenstein](docs/looks/firstperson.png) | ![Una pantalla de carga de ZX Spectrum: un minero en una cueva de cristal, dos colores por bloque](docs/looks/loading.png) |
| **Primera persona**: [laberinto](examples/laberinto), `raycast()` | **ZX Spectrum**: la carga de cinta de [socavon](examples/socavon) |
| ![La sala de un castillo gótico: brillos de vela, un fantasma a medias y una cazadora con látigo](docs/looks/32bits.png) | ![El jefe calavera girando y creciendo, sus bolas de fuego brillando](docs/looks/32bits_boss.png) |
| **PlayStation / Saturn 2D**: [gotico](examples/gotico) | **PlayStation / Saturn 2D**: su jefe |

## Para empezar

macOS: `brew install cmake sdl2 uv`. En Linux, instala esos tres con tu gestor de paquetes (`libsdl2-dev`).

```sh
cmake -B build && cmake --build build
./build/pinyol_sim --game examples/botin   # o naves, carreras, hola
ctest --test-dir build                       # valida cada ejemplo y juega su guion de prueba
```

| Acción | Teclado | Consola |
|---|---|---|
| Moverse | Flechas / WASD | Cruceta |
| A: usar, avanzar, saltar, disparar | Enter, E, Espacio, Z | A |
| B: atrás | Esc, Retroceso, X | B |
| Cambiar de objetivo, ayuda del puzle | Tab, C | C |
| Bolsa | I | MENU |
| Pausa | P | START |
| Tocar | Ratón | Pantalla |
| Reiniciar el juego (el simulador también lo reinicia cuando guardas uno de sus archivos) | F5 | |
| Captura (PNG), la portada desde la pantalla, grabar la partida como guion de prueba, los últimos 8 s en GIF | F6, F7, F8, F9 | |

## Haz tu juego

### Con un agente de código

En un Mac, instala [Homebrew](https://brew.sh) (trae git y el compilador de Apple) y un agente, por ejemplo
Codex: `brew install codex`, y luego `codex login` con una cuenta de ChatGPT. Clona este repositorio, abre el agente en
su carpeta (`codex`) y pídele el juego que quieras, en cualquier idioma. Lee [AGENTS.md](AGENTS.md), instala lo que
falta (apruébalo cuando lo pida: instalar se hace fuera de su sandbox), compila el motor, hace el juego en
`games/<id>/` y lo juega con una prueba para comprobarlo. `./build/pinyol_sim --game games/<id>` lo juega en tu pantalla.
La [escalera](https://pinyol.ipaud.dev/crear/#codex) de la web enseña cinco juegos que Codex hizo así, de un juego de palas a
un plataformas de velocidad de Mega Drive, cada uno con su encargo, su tiempo y sus tokens, y sus fps en la consola.

### Sin código: el editor

<p align="center"><a href="https://pinyol.ipaud.dev/video/linea0.mp4"><img src="docs/media/editor.webp" alt="LÍNEA 0 hecho en el editor: dibujos, mapas, reglas y a jugar" width="640"></a><br>
<sub>LÍNEA 0, un juego de Game Boy Advance hecho entero con el editor, en directo, aquí acelerado: <a href="https://pinyol.ipaud.dev/video/linea0.mp4">el vídeo entero</a>.</sub></p>

`editor/` es una página web para hacer un juego sin programar: dibuja las imágenes píxel a píxel (con fotogramas para
animarlas) o tráelas de archivos de imagen (PNG con transparencia, JPG, una fila de fotogramas; soltados o pegados), en
cualquiera de los colores de la consola; pinta con ellas los mapas de los niveles y pon los objetos encima (un
protagonista que anda y salta, enemigos que patrullan o persiguen, monedas), con hasta tres imágenes detrás de cada
uno que se mueven más despacio que la cámara, y una portada antes del primero; haz los sonidos con recetas (moneda,
láser, explosión, salto...) o tráelos de archivos (WAV, MP3, OGG...: efectos, y música para cada nivel y la portada,
recortada y más alta o más baja), o compón una canción en una cuadrícula (melodía, bajo y batería, en una escala donde
toda nota encaja); escribe las reglas con bloques ("cuando el protagonista toca una moneda: quita la otra, suena
moneda, suma 1 a puntos"; "cuando el protagonista toca la bandera: pasa al siguiente nivel"), y con los bloques de
Diálogos (personajes que hablan y preguntan, y el juego espera la respuesta), Micrófono (cuando aplaudes, cuando
soplas, cuánto ruido) y Vídeo (un vídeo traído de un archivo o un GIF, a pantalla completa o en una ventana) y Guardar (un récord o el progreso, que se queda en la consola); la música
puede ser también un `.mod` de tracker. La portada es además la imagen del juego en el menú de la consola, con una
línea, quién lo ha hecho y de qué va. **Jugar** lo juega ahí mismo; **Pasar a la consola** lo manda por el cable USB (Chrome y Edge, con Web Serial) o da el
zip para la tarjeta. Una guía corta acompaña a quien lo abre por primera vez (otra vez con **?**); todo funciona también
con el teclado, y en un móvil o una tableta. Un juego tiene un
**aspecto** (Game Boy, PICO-8, ZX Spectrum, 16 bits o libre): los colores de su consola para todos los dibujos, sus
baldosas (de 8 o 16 píxeles), su letra y los colores de sus textos; y un idioma para las frases que dice el motor. Los
objetos pueden tener animaciones con nombre (quieto, andar, golpe), y los bloques de Vidas y tiempo ponen corazones y
una cuenta atrás en la pantalla. **Nuevo** empieza desde uno de seis juegos para cambiar, cada uno con sus dibujos,
niveles y reglas: un plataformas, una aventura vista desde arriba (llaves y puertas), un matamarcianos, un puzle de
empujar cajas y **Abella**, un juego de Game Boy entero en tres niveles (hecho en directo en el editor, y el primero de
la Biblioteca de la web), y **LÍNEA 0**, un juego de Game Boy Advance en cinco niveles de cinco géneros sobre un
metro que no obedece sus propias reglas (hecho también en directo: su vídeo está en la web). La interfaz está en castellano, catalán o inglés (se elige arriba, en **Idioma**). Necesita al lado el reproductor web (mira
[más abajo](#comparte-un-juego-juégalo-en-el-navegador) cómo compilarlo):

```sh
python3 tools/make_editor.py dist/editor --player build-web
python3 -m http.server -d dist/editor    # abre http://localhost:8000
```

El editor guarda el proyecto en el navegador (IndexedDB) a medida que cambia; **Guardar archivo** lo guarda en un
archivo (`.pinyol.json`) y **Abrir** lo vuelve a abrir. El juego que hace es Lua normal sobre la librería `kit`
([lib/kit.lua](lib/kit.lua)), así que se puede seguir a mano; lleva su propia copia de kit, así que se juega igual en
una consola con un firmware más antiguo.

### En Lua

```sh
uv run tools/new_game.py games/mijuego --lua --title "Mi juego"
./build/pinyol_sim --game games/mijuego
```

Te queda un juego pequeño para cambiar: una sala más grande que la pantalla, un personaje que se pasea por ella, gemas que recoger, sonidos y un mejor tiempo guardado. `main.lua` es el juego, `room.lua` la sala como texto, y `art.py` dibuja el arte y lo convierte (cambia sus PNG por los tuyos y vuelve a ejecutarlo). **[docs/tutorial.md](docs/tutorial.md) sigue desde ahí paso a paso** (en inglés), hasta un juego en la consola y en el navegador. Los niveles se pueden dibujar en [Tiled](https://www.mapeditor.org) e importar con `tools/tiled2asset.py`. Arte hecho con un modelo de imagen (fondos quitados, fotogramas cortados, escala y pies ajustados): [docs/art.md](docs/art.md). Todo lo demás está en [docs/lua.md](docs/lua.md), y los ejemplos enseñan más:

| Ejemplo | Lo que enseña |
|---|---|
| [botin](examples/botin) | un plataformas de tesoros como los de la Game Boy Advance: cuatro mundos (selva, una cueva con foco de luz, un galeón hundido, una fragua), cuatro piezas de joya en cada uno, una embestida que rompe bloques y un golpe desde arriba, enemigos que se aturden, se cogen y se lanzan, un interruptor-rana que arranca una huida contra el reloj y un Gólem de oro de jefe; cuatro capas con las colinas cortadas en bandas, bancos de paleta de 16 colores que recolorean un dibujo, ventanas para el foco de la cueva, agua con transparencia y ondas, cambios de escena en mosaico, sprites girados para el jefe, música desde un banco de muestras y un menú que desmonta la pantalla |
| [naves](examples/naves) | un matamarcianos: un campo de estrellas con una velocidad por línea, un planeta que gira, explosiones mezcladas, un destello |
| [carreras](examples/carreras) | una carrera de karts en Mode 7: un suelo en perspectiva, rivales como sprites escalados, vueltas y posiciones |
| [puzle](examples/puzle) | un puzle deslizante para la pantalla táctil: una pista fantasma por mezcla, una revelación en mosaico, música hecha de notas |
| [aldea](examples/aldea) | una aventura vista desde arriba: un pueblo dibujado en Tiled, gente con diálogos que se escriben letra a letra, copas de árbol por detrás de las que pasas |
| [estilos](examples/estilos) | el aspecto propio de un juego: fuentes de la biblioteca, texto con contorno y ondulado, marcos cortados de una imagen, imágenes giradas |
| [inventos](examples/inventos) | juguetes sin género, solo con código: pintar, tierra que se rompe, estelas generativas, triángulos 3D, una pantalla partida |
| [juntos](examples/juntos) | consolas que juegan juntas por el aire (ESP-NOW, sin router): una pizarra compartida, una pelota que pasa de pantalla en pantalla |
| [paella](examples/paella) | un run and gun como los de Metal Slug, con sus propios chistes: seis cocineros (homenajes con nombres inventados) contra un ejército de gaviotas mecánicas por un puerto, una calle mayor y una playa, un tractor con cañón de sardinas, abuelas que liberar, comida como puntos y una gaviota gigante de jefe; todo a 480x320 nativos con imágenes empaquetadas, cada cocinero hecho de dos sprites clavados en la cintura (piernas y torso, así cualquier puntería va con cualquier paso), música en MIDI sobre un banco de muestras y un menú que explica los trucos de la Neo Geo |
| [nubes](examples/nubes) | un matamarcianos horizontal sobre un mar de nubes: drones en formación, un acorazado que llena el cielo de esferas (enjambres) |
| [calle](examples/calle) | un beat-em-up en una calle de neón de noche: profundidad, grupos de matones, la cámara que se para en cada pelea |
| [futbol](examples/futbol) | fútbol cinco contra cinco en un campo el doble de ancho que la pantalla: cuatro equipaciones que son una imagen en cuatro paletas |
| [moto](examples/moto) | una carrera de motos: la carretera en el suelo Mode 7 del mundo, la costa, la cuneta y los rivales a resolución completa encima |
| [duelo](examples/duelo) | un juego de lucha como los de Neo Geo: cada píxel a 480x320, un escenario en dos capas, luchadores en fotogramas de 192x184 como imágenes empaquetadas, destellos y chispas de golpe, un rival que juega la consola |
| [torneo](examples/torneo) | un juego de lucha como los de CPS2: luchadores en 15 colores y treinta fotogramas, nunca ampliados, un suelo en perspectiva dibujado en bandas de filas, columnas delante, el mismo luchador dos veces en otros colores |
| [mazmorra](examples/mazmorra) | un beat-em-up en una mazmorra como los de CPS2: goblins y esqueletos en grupos, antorchas que parpadean, columnas que pasan por delante de todos |
| [cerezo](examples/cerezo) | una aventura vista desde arriba como las últimas de Game Boy: un mundo de pantallas que se deslizan, una mazmorra, un jefe, diálogos, cuatro tonos que C cambia por las paletas de la Color; arte y música hechos con código |
| [socavon](examples/socavon) | una mina de plataformas de una pantalla como las del ZX Spectrum, desde la carga de cinta (borde a rayas, la pantalla en su propio orden): ocho salas, bloques de dos colores, sprites que se pisan el color, llaves que parpadean, cintas, suelos que se derrumban, una voz de pitido y un menú que enseña los atributos |
| [veloz](examples/veloz) | un plataformas de velocidad como los de las consolas de 16 bits: un mar movido línea a línea, un cielo en degradado, charcos transparentes, un título en Mode 7; un pangolín que se hace bola |
| [tumba](examples/tumba) | un puzle de deslizamiento como un cartucho de PICO-8: dieciséis niveles de tumba en una pantalla de 128x128 en sus dieciséis colores, cada uno con su par (el mínimo de movimientos, hallado por un solucionador); arenas movedizas, muros que se rompen, portales, llaves, sentidos únicos; cuatro canales de chiptune; y un menú que enseña de qué está hecho un cartucho |
| [malabar](examples/malabar) | una maquinita LCD como una Game & Watch: un malabarista lanza bolas de mano en mano y las atrapas a tiempo; cada figura es un polígono fijo, encendido o un fantasma tenue sobre un circo impreso, la puntuación en siete segmentos, un paso y un pitido cada vez, juegos A y B, un reloj cuando nadie juega, y un menú que enseña qué es una pantalla de segmentos |
| [pozo](examples/pozo) | un tirador vectorial de recreativa en un pozo geométrico: líneas brillantes con resplandor, hasta las letras, sin imágenes; su menú repite un fotograma línea a línea, como lo dibujaba el haz |
| [tormenta](examples/tormenta) | un matamarcianos vertical para jugar con la consola de lado: un lienzo de pie que se ve girado, cientos de balas |
| [laberinto](examples/laberinto) | primera persona como la dibujaba Wolfenstein 3D: raycast() dibuja el laberinto desde dentro, con texturas y niebla, fantasmas y gemas de pie en él |
| [gotico](examples/gotico) | la sala de un castillo de noche como la dibujaban las consolas de 32 bits: luz de velas sumada, un fantasma y las estelas de un dash vistos a medias, un jefe calavera que gira y crece |
| [sonidos](examples/sonidos) | sonidos hechos de números (una fábrica de monedas, láseres, explosiones), un theremin, un motor que sigue la velocidad, música en capas, un teclado que toca una muestra como cualquier nota |
| [control](examples/control) | dirigir un informativo de 1994 desde la sala de control: cortes, cinta y rótulos al ritmo de la sintonía, las frases de la realizadora escritas como una historia en catalán y castellano, el LED de la consola como piloto de cámara, un clip de vídeo en un monitor; luego una cámara que no existe te mira, te oye y sabe cuánta batería te queda |
| [raton_de_biblioteca](examples/raton_de_biblioteca) | hecho por Codex con una frase en un clon nuevo: un ratón con aspecto de Game Boy en una biblioteca, queso y gatos (luego puesto a pantalla completa a mano) |
| [oxigeno](examples/oxigeno) | hecho por Codex con una frase: un astronauta con aspecto de ZX Spectrum que busca botellas de oxígeno, con su pantalla de carga de cinta |
| [museo_nocturno](examples/museo_nocturno) | hecho por Codex con una frase: un museo de noche en primera persona, cinco cuadros robados y vigilantes |
| [paletes](examples/paletes) | hecho por Codex con una frase: palas y pelota contra la consola, en vectores, a 7 puntos |
| [cripta](examples/cripta) | un metroidvania en ocho salas, cada una su mapa de Tiled importado con `tools/tiled2asset.py` y colocada en el castillo con dos propiedades del mapa: alas para un segundo salto, una ráfaga que rompe las paredes agrietadas, cada poder abre el camino al siguiente, estatuas que guardan, un mapa de las salas recorridas y una gárgola; un solucionador demuestra que el castillo se termina en ese orden |
| [horizonte](examples/horizonte) | un día entero sobre el mar con unas pocas entradas de paleta, recoloreadas línea a línea con `line_pal` y `line_pal_obj`: el cielo que se oscurece hacia arriba, las nubes iluminadas por abajo, el sol que se enrojece al ponerse, el agua que brilla bajo él y la vela de un barco pintada por el atardecer; A lo enseña sin ello |
| [isla](examples/isla) | una isla isométrica como la pintaban los juegos de GBA: el suelo es un fondo de tiles, y las columnas, las cajas, las palmeras, las gemas y el héroe son sprites que reciben cada frame su número por profundidad, así el héroe pasa por detrás de una torre y por delante de otra; cinco gemas, unas a las que se llega andando y saltando, otras empujando una caja contra un pilar o al mar para cruzar |
| [sima](examples/sima) | un roguelike por turnos a la manera de los Mystery Dungeon de GBA: cinco pisos hechos con la semilla de la bajada (una nueva con los ticks hasta pulsar A, o la del día para todos, con `clock()`), escritos en un fondo celda a celda con `mset`, la niebla de lo no visto en un segundo fondo por encima de los sprites y monstruos que persiguen al héroe por un único campo de `grid:distances`; un bot juega una bajada entera en los tests |
| [microjuegos](examples/microjuegos) | a la manera de WarioWare: ocho juegos de pocos segundos (pulsar, esquivar, contar, machacar, buscar, girar, estarse quieto, un jefe), cuatro vidas, una velocidad que sube cada cuatro; cada uno deja algo en la imagen o en el sonido a propósito (un fundido, una ventana redonda, un mosaico, una nota, el LED) y `scene.go(..., {clean = true})` lo devuelve todo a su sitio; una demostración jugada por los bots de los propios juegos |
| [tablero](examples/tablero) | tácticas por turnos sobre una cuadrícula, a la manera de Advance Wars: dos ejércitos de cuatro en un campo de 15 x 10 con bosque, montaña, un río y dos puentes; alcance, caminos, campos de distancia y un mapa de peligro con `grid`, resaltes en una segunda capa de la imagen (`mset`, `blend`), una IA que decide con lo mismo que el jugador y una demostración de la IA contra sí misma |
| [combate](examples/combate) | un pequeño RPG: un prado, hierba alta que esconde enemigos y un combate por turnos que empieza con los efectos propios de la imagen (destello, ondulación línea a línea, mosaico, un iris con `line_window`); enemigos girados y escalados por una matriz, menús, un grupo que sube de nivel y se guarda |
| [pinball](examples/pinball) | una mesa entera en pantalla, tres bolas, cuatro topes y dos aletas que giran por su extremo (`physics` y su `w:drive`), un muelle que se tensa con ABAJO, una bola salvada |
| [costa_relampago](examples/costa_relampago) | hecho por Codex en tres encargos (el juego, su arte generado, 60 fps en la consola): una ardilla con aspecto de Mega Drive en una costa, capas a su propia velocidad y un mar movido línea a línea |

### Como una aventura hecha de datos

```sh
uv run tools/new_game.py games/mijuego --title "Mi juego"
./build/pinyol_sim --game games/mijuego
./build/pinyol_headless --game games/mijuego --validate     # cada ID existe, cada texto cabe
```

`new_game.py` escribe un juego diminuto pero completo: dos zonas, un protagonista, un amigo con una elección en el diálogo, una llave, una puerta cerrada, un cofre y la pantalla final. Todo su arte es provisional, dibujado con código. Luego hazlo tuyo:

- **Texto y lógica** son JSON. La referencia completa está en [docs/game-format.md](docs/game-format.md).
- **Arte**: dibuja un PNG y conviértelo con el mismo ID. Las hojas de personaje son tiras horizontales en el orden de direcciones N, E, S, O.
  ```sh
  uv run tools/png2asset.py calle.png games/mijuego/assets BG_Z01 --type background
  uv run tools/png2asset.py heroe_anda.png games/mijuego/assets PJ_WALK --frames 16 --ms 125 --anchor 12,29
  uv run tools/png2asset.py luchador.png games/mijuego/assets SPR_KAI --frames 11 --packed   # arte grande: su propia paleta, una cuarta parte de la memoria
  ```
- **Sonido**: WAV, PCM de 16 bits mono a 22.050 Hz.
- **Fuentes**: `tools/font2fnt.py` convierte un TTF, OTF, BDF o una hoja PNG al formato FNT del motor; vienen doce
  fuentes de píxel libres (`third_party/fonts`), así que cada juego puede tener sus propias letras.
- **Pruebas**: un guion juega el juego con entradas reales y comprueba flags, zonas y pantallas. Mira [tests/hola.script](tests/hola.script); se ejecuta con `./build/pinyol_headless --game DIR --fresh --script FILE`, y `tools/record.sh DIR FILE out.mp4` graba la partida en vídeo.

## Un juego en su propio repositorio

Un juego más grande puede vivir en su propio repositorio y compilar pinyol como subproyecto, con sus propias pruebas:

```cmake
cmake_minimum_required(VERSION 3.21)
project(mijuego C)
set(GAME_DIR ${CMAKE_SOURCE_DIR}/games/mijuego)  # lo que pinyol_sim y pinyol_headless abren por defecto
add_subdirectory(../pinyol pinyol)               # pinyol_core, pinyol_headless, pinyol_sim
enable_testing()
add_test(NAME validate COMMAND pinyol_headless --game ${GAME_DIR} --validate)
```

Las aventuras de datos con las que empezó pinyol se compilan así.

## Comparte un juego, juégalo en el navegador

```sh
python3 tools/pack_game.py games/mijuego -o dist/      # -> dist/mijuego.zip, con una carpeta mijuego/ dentro
```

Descomprimido en la carpeta `games/` de la tarjeta, el juego queda instalado. El mismo zip se juega en un navegador: el simulador se compila con [Emscripten](https://emscripten.org) a `player.html`, que juega el zip de cualquier juego, dado como `player.html?game=URL` o soltado en la página, con botones en pantalla en los móviles, un mando por USB o Bluetooth (distribución estándar: el botón de abajo es A) y las partidas guardadas en el navegador. `?lang=ca` o `?lang=en` pone sus textos en catalán o en inglés.

```sh
emcmake cmake -B build-web -DCMAKE_BUILD_TYPE=Release
cmake --build build-web --target pinyol_player
cp dist/mijuego.zip build-web/
python3 -m http.server -d build-web     # abre http://localhost:8000/player.html?game=mijuego.zip
```

El objetivo `pinyol_web` hace un `index.html` en su lugar, con un juego (`-DGAME_DIR=...`) empaquetado dentro.

Una estantería entera de juegos, cada uno jugable y descargable, con una imagen de su pantalla de título:

```sh
python3 tools/make_gallery.py gallery/ --player build-web --headless build/pinyol_headless examples/*
python3 -m http.server -d gallery       # abre http://localhost:8000
```

Un juego terminado puede ir a la [Biblioteca](https://pinyol.ipaud.dev/biblioteca/) de la web, para jugarlo allí y descargarlo para la consola: [súbelo con un formulario](https://github.com/ipaud/pinyol/issues/new?template=biblioteca.yml), un robot lo abre, lo juega diez segundos y, cuando lo revisamos, aparece allí.

<p align="center"><a href="https://pinyol.ipaud.dev/video/subir.mp4"><img src="docs/media/library.webp" alt="Del .zip del editor a la Biblioteca: el formulario, la comprobación del robot, la aprobación y el juego en la web" width="640"></a><br>
<sub>De tu juego a la Biblioteca, acelerado: <a href="https://pinyol.ipaud.dev/video/subir.mp4">el tutorial entero</a>.</sub></p>

## Llévalo a la consola

Lo más rápido: la web [instala la última versión](https://pinyol.ipaud.dev/consola/#consola) en una placa por USB,
desde Chrome o Edge, con quince juegos en su memoria flash.

El firmware de [firmware/](firmware/) es la plataforma de la consola: pantalla, táctil, botones, audio, microSD, batería y actualizaciones por la tarjeta. Necesita [ESP-IDF 5.4](https://docs.espressif.com/projects/esp-idf/en/v5.4.2/esp32s3/get-started/).

```sh
. $IDF_PATH/export.sh
cd firmware
idf.py build
idf.py -p /dev/cu.usbmodem1101 flash        # el puerto de tu placa
```

Un juego también puede ir por el cable USB, directamente desde el editor (Chrome o Edge) o desde un terminal: la
consola lo escribe en la tarjeta (o, sin tarjeta, en su flash) y lo arranca.

```sh
uv run --with pyserial tools/send_game.py games/mijuego     # la carpeta de un juego, o su .zip
```

El firmware también graba juegos en la flash, así que la consola funciona sin tarjeta: `examples/hola` por defecto, o una lista, `idf.py -DFLASH_GAME="/abs/a;/abs/b" build` (y entonces graba también `build/game.bin`, en 0x420000). Cualquier otro juego va en la microSD (FAT32) como `games/<id>/`. Mantener MENU pulsado dos segundos sale de un juego en Lua a la lista. Para actualizar el firmware más adelante, copia `build/pinyol_console.bin` en la tarjeta como `firmware.bin` (una consola con una compilación de main del 21 o el 22 de octubre de 2026 no puede: su driver de flash corrompía la memoria al borrar; los firmwares publicados, el 0.3.0 y los anteriores, nunca tuvieron ese driver; grábala una vez por el cable, `esptool write_flash 0xf000 ota_data_initial.bin 0x20000 pinyol_console.bin`).

La consola arranca en el menú de **Cirera**, que es a su vez un juego de pinyol ([firmware/cirera](firmware/cirera))
grabado en la flash con el firmware: una intro animada y luego cada juego como una carta con su portada, para elegir con
la cruceta y A (B pregunta antes de apagar la consola). La portada de un juego es su `cover.rgb565`, una imagen de
240×160 que `tools/cover.py` saca de un momento de juego; sin ella, su pantalla de título (`assets/BG_TITLE`) o una
carta con su nombre.

Pines y periféricos, cada uno con su fuente: [docs/hardware.md](docs/hardware.md).

## Cirera en tu ordenador: Mac, Windows y Linux

La consola hecha aplicación: su menú, los ejemplos dentro, y el .zip de cualquier juego que sueltes sobre su ventana,
instalado. Se descarga de la [release «cirera»](https://github.com/ipaud/pinyol/releases/tag/cirera) o de la [web](https://pinyol.ipaud.dev/consola/#escritorio), que explica cómo
abrirla la primera vez (aún no está firmada por Apple ni por Microsoft). Sus juegos y partidas van a
`~/Library/Application Support/pinyol/Cirera` en el Mac, a `%APPDATA%\pinyol\Cirera` en Windows y a
`~/.local/share/pinyol/Cirera` en Linux (x86_64 o aarch64, glibc 2.35 o posterior; un juego soltado se descomprime con
unzip).

Es `pinyol_sim` compilado como aplicación, y `tools/make_app.py` la empaqueta:

```sh
cmake -B build-app -DCMAKE_BUILD_TYPE=Release -DPINYOL_APP=ON
cmake --build build-app --target pinyol_sim             # -> build-app/Cirera (Cirera.exe en Windows)
python3 tools/make_app.py build-app/Cirera -o dist/     # -> dist/Cirera-mac.zip (Cirera-linux-*.tar.gz en Linux)
```

La de Windows se compila desde un Mac o un Linux con MinGW-w64 (`cmake/mingw-w64-x86_64.cmake`).
[.github/workflows/desktop.yml](.github/workflows/desktop.yml) las compila todas con SDL dentro, así que no necesitan
nada instalado, y abre cada una en su sistema antes de publicarla. El simulador también juega a la consola:
`pinyol_sim --console examples --menu firmware/cirera`.

## Juégalo en RetroArch: RetroPie, Batocera, Lakka

El motor también es un core [libretro](https://www.libretro.com), que juega el zip de un juego en RetroArch y en
todo lo que se basa en él, entre ellos una Raspberry Pi con RetroPie:

```sh
cmake -B build-release -DCMAKE_BUILD_TYPE=Release
cmake --build build-release --target pinyol_libretro    # -> build-release/pinyol_libretro.so
```

Cómo instalarlo, los controles y lo que aún no hace: [docs/libretro.md](docs/libretro.md) (en inglés).

## Cómo está hecho

```
src/             el motor, C11 portable: sin cabeceras de SDL ni de ESP-IDF (hal.h es todo el contrato con la plataforma)
  ppu.c          el procesador de imagen virtual (capas, sprites, efectos) con el que dibujan los juegos en Lua
  lua_game.c     pinyol@2: la sandbox de Lua y su API
platform/sdl/    simulador de escritorio, la aplicación Cirera (-DPINYOL_APP=ON), y los reproductores web cuando se compila con Emscripten
platform/desktop/ los iconos de la aplicación
platform/null/   pinyol_headless: validador y ejecutor de pruebas sin ventana
platform/libretro/ el core libretro, para RetroArch y RetroPie
platform/web/    las páginas web alrededor de los reproductores
site/            la web (https://pinyol.ipaud.dev/), hecha por site/build.py en castellano, catalán e inglés
firmware/        la consola: proyecto de ESP-IDF, compila src/ sin cambios; cirera/ es su menú, un juego de pinyol
examples/        juegos tal como van en la microSD: treinta y dos en Lua, hola como datos
templates/lua/   el juego desde el que empieza new_game.py --lua
tests/           guiones de prueba de los ejemplos, y las pruebas propias de la PPU
tools/           new_game.py, png2asset.py, tiled2asset.py, pack_game.py, make_gallery.py, font2fnt.py, clip2npv.py, ...
lib/             librerías de Lua dentro del motor, que cualquier juego carga con require(): juice, particles, physics, keyboard, kit, story
editor/          el editor web (HTML y JavaScript a pelo, sin compilar) y Blockly en vendor/
third_party/     cJSON, Lua 5.4, pocketmod, puff (unzip), libretro.h, la fuente Pixelify Sans y una biblioteca de fuentes de píxel (fonts/)
```

El mundo son 240×160 píxeles lógicos dibujados a 2× en un frame de 480×320; el texto y la interfaz usan la resolución completa. La lógica va a 60 ticks por segundo en todas las plataformas. En la consola, el frame llega al panel en franjas de 32 filas dibujadas directamente desde el juego mientras se envía la anterior, al compás del refresco del panel; la imagen de un juego en Lua la dibujan los dos núcleos. Cómo llegó a ir lo bastante rápido, medido: [docs/measurements.md](docs/measurements.md).

<p align="center"><img src="docs/media/strips.gif" alt="Animación: la pantalla dividida en 15 franjas; cada una se llena desde arriba, mitad por el núcleo 0 y mitad por el núcleo 1, y luego aparece en el panel mientras se dibuja la siguiente" width="480"><br>
<sub>A cámara lenta: un frame de verdad tarda 16,6 ms; aquí, 2,4 segundos. En rojo, el núcleo 0; en amarillo, el núcleo 1.</sub></p>

## Estado

pinyol se escribió primero para dos aventuras de datos, y luego se abrió con Lua a cualquier género. Lo que hay que saber:

- La API de Lua (`pinyol@2`) es nueva y aún puede cambiar; el formato de datos (`pinyol@1`) es estable.
- Los textos de interfaz propios de las aventuras de datos (menús, pausa, bolsa) están en castellano.
- Algunos valores por defecto de pinyol@1 vienen del primer juego: sin un `"player"` en `game.json` el protagonista es `KLAUS` con prefijo de sprite `KL`, y la zona inicial por defecto es `Z01`. Ponlos en tu `game.json`.
- Lo que se hizo y se midió, paso a paso: [docs/progress.md](docs/progress.md).
- pinyol se llamó primero np2d: los juegos cuyo `game.json` dice `"engine": "np2d@1"` o `"np2d@2"` siguen funcionando, y el repositorio de un juego aún puede usar los objetivos `bp_core`, `bp_headless` y `bp_sim`.

## Licencia

pinyol tiene licencia MIT ([LICENSE](LICENSE)). Incluye [cJSON](third_party/cjson/LICENSE) (MIT), [Lua 5.4](third_party/lua/LICENSE) (MIT), [pocketmod](third_party/pocketmod/LICENSE) (MIT), [puff](third_party/puff/puff.h) (zlib), el [libretro.h](third_party/libretro/libretro.h) de libretro (MIT), la fuente [Pixelify Sans](third_party/pixelify/OFL.txt) y las fuentes de píxel de [third_party/fonts](third_party/fonts/README.md) (todas SIL Open Font License 1.1). El editor incluye [Blockly](editor/vendor/blockly/LICENSE) (Apache 2.0). La web sirve [ESP Web Tools](site/vendor/esp-web-tools/LICENSE) (Apache 2.0) para instalar el firmware, y el count.js de [GoatCounter](site/vendor/goatcounter/README.pinyol) (ISC) para contar las visitas; el firmware se construye con [ESP-IDF](https://github.com/espressif/esp-idf) (Apache 2.0, con partes bajo licencias MIT y BSD) y el reproductor web con Emscripten y SDL2. La aplicación de escritorio lleva SDL2 (zlib) y, en Windows, el runtime de MinGW-w64 ([ZPL 2.1 y MIT](third_party/mingw-w64/COPYING)). Todos los avisos que piden están en [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), que también va con cada release.

Las imágenes, sonidos, música y vídeo de los ejemplos, la plantilla y las pruebas se hicieron para pinyol, generados
con un modelo de imagen o dibujados y sintetizados con código (el `art.py` y `art/` de cada juego): se dedican al
dominio público ([CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)), para usarlos en tus juegos como quieras.

Game Boy, Game Boy Advance, PlayStation, Saturn, Mega Drive, Super Nintendo, Neo Geo, CPS2, PICO-8, ZX Spectrum,
Wolfenstein 3D y las demás consolas y juegos que se nombran aquí son marcas de sus dueños. pinyol y Cirera no tienen
relación con ellos ni su respaldo: los nombres solo dicen a qué aspecto se parece un juego.
