-- Estilos: lo que hace que cada juego se vea suyo. Fuentes propias (fonts/<nombre>.fnt, hechas con
-- tools/font2fnt.py desde la biblioteca de np2d, un TTF, un BDF o una hoja PNG), estilos de texto (contorno, sombra,
-- degradado, escala, onda, temblor), marcos sacados de una imagen del juego (frame) y dibujos girados, escalados y
-- volteados (img). Todo a la resolución de la pantalla, 480x320.
--   ‹ ›  cambia de página

local CX = SCREEN_W // 2
local PAGES = {"Fuentes", "Texto", "Marcos", "Imágenes"}
page = 1 -- global: the test looks at it
local t = 0

-- each font in fonts/, with something to write in it
local FONTS = {
  {"arcade", "ARCADE 1984"}, {"silk", "Silkscreen"}, {"silk_bold", "Silkscreen Bold"}, {"terminal", "> terminal_ok"},
  {"jersey", "Jersey: el partit"}, {"micro", "micro 5 · 0123"}, {"byte", "bytesized tiny"},
  {"gotica", "Gòtica de Valls"}, {"bastarda", "Bastarda"}, {"dots", "DotGothic 16"},
  {"jersey_big", "JERSEY 20"}, {"pixelify_big", "Pixelify"},
}

function _init()
  show(0) -- nothing from the 240x160 world: this example draws only at full resolution
  backdrop(0)
end

function _update()
  t = t + 1
  if btnp("right") then page = page % #PAGES + 1 end
  if btnp("left") then page = (page - 2) % #PAGES + 1 end
end

local function header(bg)
  rect(0, 0, SCREEN_W, SCREEN_H, bg)
  text(PAGES[page], 14, 8, {font = "silk_bold", color = 0xFFFFFF, shadow = 0x000000})
  text("‹ › " .. page .. "/" .. #PAGES, SCREEN_W - 14, 10, 0xC0C8D0, "main", "right")
end

local function page_fonts()
  header(0x1E2230)
  local y, x = 44, 16
  for i, f in ipairs(FONTS) do
    if i == 7 then y, x = 44, 250 end -- the second column
    local _, h = text(f[2], x, y, {font = f[1], color = i % 2 == 0 and 0xFFD070 or 0xF2F2F2})
    text(f[1], x, y + h, 0x8090A0, "main")
    y = y + h + 20
  end
end

local function page_text()
  header(0x2B1B2E)
  text("¡HOLA!", CX, 36, {font = "jersey_big", scale = 2, align = "center", color = 0xFFE070, gradient = 0xFF5020,
                          outline = 0x3A0E10, shadow = 0x000000, shadow_x = 2, shadow_y = 2})
  text("una onda que no para", CX, 126, {font = "arcade", align = "center", color = 0x90F0FF, wave = 4})
  text("¡TIEMBLA!", 40, 160, {font = "silk_bold", scale = 2, color = 0xFF5050, outline = 0x000000, shake = 2})
  text("E S P A I", 300, 166, {font = "silk", color = 0xFFFFFF, spacing = 3, shadow = 0x6040A0})
  local msg = "El texto también se escribe letra a letra, con la fuente y el estilo de cada juego."
  frame("FR_PERGAMI", 24, 214, 432, 92, 2)
  text(msg, 44, 230, {font = "gotica", color = 0x40220E, width = 392, chars = t // 2 % (#msg + 40)})
end

local function page_frames()
  header(0x12301E)
  frame("FR_MADERA", 16, 40, 210, 120, 2)
  text("Taverna", 121, 58, {font = "bastarda", align = "center", color = 0x5A2A10})
  text("pa amb tomàquet  3", 40, 104, {font = "micro", color = 0x3A2010})
  frame("FR_NEON", 248, 40, 216, 120, 2)
  text("SISTEMA LLEST", 264, 60, {font = "terminal", color = 0x70F4FF})
  text("> energia 98%", 264, 84, {font = "terminal", color = 0xFF60C8, chars = t // 4 % 20})
  local w = 180 + math.floor(math.sin(t / 30) * 120) -- the same picture, any size: corners once, the rest repeated
  frame("FR_PERGAMI", CX - w // 2, 180, w, 120, 2)
  text(w .. " px", CX, 228, {font = "jersey", align = "center", color = 0x5A3418})
end

local function page_images()
  header(0x182838)
  img("STAR", 40, 60, {angle = t * 3, scale = 3})
  img("STAR", 200, 70, {scale = 2 + math.sin(t / 20) * 1.2})
  img("STAR", 340, 60, {scale = 3, flip_y = true})
  for i = 0, 7 do img("STAR", 24 + i * 56, 220, {angle = -t * 2 + i * 45, scale = 1 + i * 0.25}) end
  text("girar · escalar · voltear", CX, 290, {font = "silk", align = "center", color = 0xE0E8F0})
end

local DRAW = {page_fonts, page_text, page_frames, page_images}

function _draw()
  DRAW[page]()
end
