local Blitbuffer = require("ffi/blitbuffer")
local Device     = require("device")
local Font       = require("ui/font")
local RenderText = require("ui/rendertext")
local _          = require("i18n")

local Screen = Device.screen

-- ---------------------------------------------------------------------------
-- TilePainter — draws one tile face (the white top of a tile) at a given
-- size, in black and greys only. Two styles:
--
--   "readable"  a big Arabic number with a suit sign under it (a ring for
--               dots, two canes for bamboo, 萬 for characters), wind letters
--               in the reader's language, dragons as boxes (filled, letter,
--               empty), flowers and seasons as drawn icons with their number.
--   "classic"   the traditional faces: dot and bamboo patterns, Chinese
--               numerals over 萬, 東南西北, 中 發 and the white dragon's frame,
--               with a small corner index on the Chinese ones.
--
-- Chinese characters come from Noto Sans CJK, which KOReader ships as its
-- fallback font on every device.
-- ---------------------------------------------------------------------------

local C_FG    = Blitbuffer.COLOR_BLACK
local C_BG    = Blitbuffer.COLOR_WHITE

local LATIN = "NotoSans-Bold.ttf"
local CJK   = "NotoSansCJKsc-Regular.otf"

local CN_NUM  = { "一", "二", "三", "四", "五", "六", "七", "八", "九" }
local CN_WIND = { "東", "南", "西", "北" }

-- Wind letters by reader language (E S W N order).
local WIND_LETTERS = {
    en = { "E", "S", "W", "N" },
    fr = { "E", "S", "O", "N" },
    es = { "E", "S", "O", "N" },
    de = { "O", "S", "W", "N" },
}
-- Dragon letters (red, green) by reader language.
local DRAGON_LETTERS = {
    en = { "R", "G" },
    fr = { "R", "V" },
    es = { "R", "V" },
    de = { "R", "G" },
}

local TilePainter = {}
TilePainter.__index = TilePainter

-- Faces sized in pixels: Font:getFace() scales by DPI, so undo that.
local function face(name, px)
    local scale = Screen:scaleBySize(1000) / 1000
    return Font:getFace(name, math.max(4, math.floor(px / scale + 0.5)))
end

-- w, h: the face's size in pixels (inside its border).
function TilePainter.new(w, h, style)
    local self = setmetatable({ w = w, h = h, style = style or "readable", faces = {} }, TilePainter)
    local lang = _.lang and _.lang() or "en"
    self.wind_letters   = WIND_LETTERS[lang] or WIND_LETTERS.en
    self.dragon_letters = DRAGON_LETTERS[lang] or DRAGON_LETTERS.en
    return self
end

-- Font `name` sized so that `sample` is `ink_h` pixels tall (ink, not em).
function TilePainter:_fit(name, sample, ink_h, max_w, bold)
    local key = name .. "|" .. sample .. "|" .. ink_h .. "|" .. (max_w or 0)
    local f = self.faces[key]
    if f then return f end
    local px = ink_h
    for _try = 1, 6 do
        f = face(name, px)
        local m = RenderText:sizeUtf8Text(0, 10000, f, sample, true, bold)
        local ink = m.y_top + m.y_bottom
        if ink <= 0 then break end
        local k = ink_h / ink
        if max_w and m.x * k > max_w then k = max_w / m.x end
        local nxt = math.floor(px * k + 0.5)
        if math.abs(nxt - px) <= 1 then px = math.min(px, nxt); f = face(name, px); break end
        px = nxt
    end
    self.faces[key] = f
    return f
end

-- Text centred on (cx, cy), by its ink.
local function text(bb, f, str, cx, cy, color, bold)
    local m = RenderText:sizeUtf8Text(0, 10000, f, str, true, bold)
    local base = cy + math.floor((m.y_top - m.y_bottom) / 2)
    RenderText:renderUtf8Text(bb, cx - math.floor(m.x / 2), base, f, str, true, bold, color or C_FG)
end

-- ---------------------------------------------------------------------------
-- Drawn signs
-- ---------------------------------------------------------------------------

-- A dot: black ring, white band, black centre.
local function ring(bb, cx, cy, r)
    if r < 3 then
        bb:paintCircle(cx, cy, math.max(1, r), C_FG)
        return
    end
    bb:paintCircle(cx, cy, r, C_FG)
    local w = math.max(1, math.floor(r * 0.28))
    bb:paintCircle(cx, cy, r - w, C_BG)
    bb:paintCircle(cx, cy, math.max(1, math.floor(r * 0.38)), C_FG)
end

-- A bamboo cane: dark rounded bar with a white node line in the middle and
-- lighter ends.
local function cane(bb, x, y, w, h)
    w = math.max(2, w)
    local r = math.min(math.floor(w / 2), 4)
    bb:paintRoundedRect(x, y, w, h, C_FG, r)
    if w >= 4 and h >= 10 then
        -- One node across the middle.
        local t = math.max(1, math.floor(h / 10))
        bb:paintRect(x, y + math.floor(h / 2) - math.floor(t / 2), w, t, C_BG)
    end
end

-- Flower: five petals round a white heart.
local function flower(bb, cx, cy, r)
    local pr = math.max(2, math.floor(r * 0.42))
    for k = 0, 4 do
        local a = -math.pi / 2 + k * 2 * math.pi / 5
        local px = cx + math.floor(math.cos(a) * (r - pr) + 0.5)
        local py = cy + math.floor(math.sin(a) * (r - pr) + 0.5)
        bb:paintCircle(px, py, pr, C_FG)
    end
    bb:paintCircle(cx, cy, math.max(2, math.floor(r * 0.36)), C_BG)
    bb:paintCircle(cx, cy, math.max(1, math.floor(r * 0.18)), C_FG)
end

-- Season: a sun, ring with eight rays.
local function sun(bb, cx, cy, r)
    local core = math.max(2, math.floor(r * 0.5))
    local t = math.max(1, math.floor(r * 0.14))
    for k = 0, 7 do
        local a = k * math.pi / 4
        local c, s = math.cos(a), math.sin(a)
        for d = core + math.floor(r * 0.15), r do
            bb:paintRect(cx + math.floor(c * d + 0.5) - math.floor(t / 2),
                         cy + math.floor(s * d + 0.5) - math.floor(t / 2), t + 1, t + 1, C_FG)
        end
    end
    bb:paintCircle(cx, cy, core, C_FG)
    bb:paintCircle(cx, cy, math.max(1, core - math.max(2, math.floor(core * 0.35))), C_BG)
end

-- Frame of the white dragon: two nested rectangles.
local function frame(bb, x, y, w, h, t)
    bb:paintBorder(x, y, w, h, t, C_FG)
    local g = t * 2
    if w > 2 * (g + t) and h > 2 * (g + t) then
        bb:paintBorder(x + g, y + g, w - 2 * g, h - 2 * g, math.max(1, math.floor(t / 2)), C_FG)
    end
end

-- ---------------------------------------------------------------------------
-- Classic patterns (centres as fractions of the face)
-- ---------------------------------------------------------------------------

local DOT_LAYOUT = {
    { { .5, .5 } },
    { { .5, .27 }, { .5, .73 } },
    { { .24, .2 }, { .5, .5 }, { .76, .8 } },
    { { .28, .27 }, { .72, .27 }, { .28, .73 }, { .72, .73 } },
    { { .27, .22 }, { .73, .22 }, { .5, .5 }, { .27, .78 }, { .73, .78 } },
    { { .3, .2 }, { .7, .2 }, { .3, .5 }, { .7, .5 }, { .3, .8 }, { .7, .8 } },
    { { .2, .14 }, { .5, .25 }, { .8, .36 }, { .3, .6 }, { .7, .6 }, { .3, .85 }, { .7, .85 } },
    { { .3, .14 }, { .7, .14 }, { .3, .38 }, { .7, .38 }, { .3, .62 }, { .7, .62 }, { .3, .86 }, { .7, .86 } },
    { { .2, .2 }, { .5, .2 }, { .8, .2 }, { .2, .5 }, { .5, .5 }, { .8, .5 }, { .2, .8 }, { .5, .8 }, { .8, .8 } },
}
local DOT_RADIUS = { .3, .2, .14, .17, .14, .14, .11, .1, .11 }

-- Bamboo: columns of canes, each { x centre, y top, y bottom } as fractions.
local CANE_LAYOUT = {
    { { .5, .1, .9 } },
    { { .5, .08, .46 }, { .5, .54, .92 } },
    { { .5, .08, .46 }, { .3, .54, .92 }, { .7, .54, .92 } },
    { { .3, .08, .46 }, { .7, .08, .46 }, { .3, .54, .92 }, { .7, .54, .92 } },
    { { .22, .08, .46 }, { .78, .08, .46 }, { .5, .3, .7 }, { .22, .54, .92 }, { .78, .54, .92 } },
    { { .2, .08, .46 }, { .5, .08, .46 }, { .8, .08, .46 }, { .2, .54, .92 }, { .5, .54, .92 }, { .8, .54, .92 } },
    { { .5, .05, .33 }, { .2, .37, .65 }, { .5, .37, .65 }, { .8, .37, .65 }, { .2, .69, .96 }, { .5, .69, .96 }, { .8, .69, .96 } },
    { { .14, .08, .46 }, { .38, .08, .46 }, { .62, .08, .46 }, { .86, .08, .46 },
      { .14, .54, .92 }, { .38, .54, .92 }, { .62, .54, .92 }, { .86, .54, .92 } },
    { { .2, .05, .32 }, { .5, .05, .32 }, { .8, .05, .32 }, { .2, .37, .64 }, { .5, .37, .64 }, { .8, .37, .64 },
      { .2, .69, .96 }, { .5, .69, .96 }, { .8, .69, .96 } },
}

-- ---------------------------------------------------------------------------
-- Faces
-- ---------------------------------------------------------------------------

-- Paints face `f` (1..42) in the box x, y, w, h (the face's inside).
function TilePainter:paint(bb, f, x, y)
    local w, h = self.w, self.h
    if self.style == "classic" then
        self:_classic(bb, f, x, y, w, h)
    else
        self:_readable(bb, f, x, y, w, h)
    end
end

-- The suit sign of the readable style, centred on (cx, cy), about s tall.
function TilePainter:_suitSign(bb, suit, cx, cy, s)
    if suit == 1 then
        ring(bb, cx, cy, math.floor(s / 2))
    elseif suit == 2 then
        local cw = math.max(3, math.floor(s * 0.3))
        local gap = math.max(2, math.floor(s * 0.12))
        cane(bb, cx - cw - math.floor(gap / 2), cy - math.floor(s / 2), cw, s)
        cane(bb, cx + math.floor((gap + 1) / 2), cy - math.floor(s / 2), cw, s)
    else
        local f = self:_fit(CJK, "萬", s, math.floor(self.w * 0.9), true)
        text(bb, f, "萬", cx, cy, C_FG, true)
    end
end

function TilePainter:_readable(bb, f, x, y, w, h)
    local cx = x + math.floor(w / 2)
    if f <= 27 then
        local suit, n = math.floor((f - 1) / 9) + 1, (f - 1) % 9 + 1
        local dh = math.floor(math.min(h * 0.4, w * 0.62))
        local fd = self:_fit(LATIN, "8", dh, math.floor(w * 0.9))
        local s = math.floor(math.min(h * 0.4, w * 0.7))
        -- Number and sign share the height, with equal gaps around them.
        local gap = math.floor((h - dh - s) / 3)
        text(bb, fd, tostring(n), cx, y + gap + math.floor(dh / 2), C_FG)
        self:_suitSign(bb, suit, cx, y + h - gap - math.floor(s / 2), s)
    elseif f <= 31 then
        local k = f - 27
        local fl = self:_fit(LATIN, "W", math.floor(h * 0.42), math.floor(w * 0.9))
        text(bb, fl, self.wind_letters[k], cx, y + math.floor(h * 0.32), C_FG)
        local fc = self:_fit(CJK, "東", math.floor(h * 0.24), math.floor(w * 0.8), true)
        text(bb, fc, CN_WIND[k], cx, y + math.floor(h * 0.77), C_FG, true)
    elseif f <= 34 then
        local m = math.max(2, math.floor(w * 0.1))
        local bx, by, bw, bh = x + m, y + math.floor(h * 0.12), w - 2 * m, math.floor(h * 0.76)
        local t = math.max(2, math.floor(w * 0.07))
        if f == 34 then
            frame(bb, bx, by, bw, bh, t)
        else
            local fl = self:_fit(LATIN, "G", math.floor(h * 0.4), math.floor(bw * 0.8))
            if f == 32 then
                bb:paintRoundedRect(bx, by, bw, bh, C_FG, t)
                text(bb, fl, self.dragon_letters[1], cx, by + math.floor(bh / 2), C_BG)
            else
                bb:paintBorder(bx, by, bw, bh, t, C_FG, t)
                text(bb, fl, self.dragon_letters[2], cx, by + math.floor(bh / 2), C_FG)
            end
        end
    else
        self:_bonus(bb, f, x, y, w, h)
    end
end

-- Flowers and seasons, both styles: the icon and its number.
function TilePainter:_bonus(bb, f, x, y, w, h)
    local cx = x + math.floor(w / 2)
    local r = math.floor(math.min(w * 0.42, h * 0.3))
    local icy = y + math.floor(h * 0.36)
    if f <= 38 then flower(bb, cx, icy, r) else sun(bb, cx, icy, r) end
    local n = f <= 38 and f - 34 or f - 38
    local fd = self:_fit(LATIN, "8", math.floor(h * 0.22), math.floor(w * 0.5))
    text(bb, fd, tostring(n), cx, y + math.floor(h * 0.82), C_FG)
end

function TilePainter:_corner(bb, str, x, y, w, h)
    local s = math.floor(h * 0.15)
    if s < 7 then return end
    local f = self:_fit(LATIN, "W", s, math.floor(w * 0.3))
    local m = RenderText:sizeUtf8Text(0, 10000, f, str, true, false)
    RenderText:renderUtf8Text(bb, x + math.max(1, math.floor(w * 0.05)),
        y + math.max(1, math.floor(h * 0.03)) + m.y_top, f, str, true, false, C_FG)
end

function TilePainter:_classic(bb, f, x, y, w, h)
    local cx = x + math.floor(w / 2)
    if f <= 9 then
        local n = f
        local r = math.floor(math.min(w, h * 0.77) * DOT_RADIUS[n])
        for _, p in ipairs(DOT_LAYOUT[n]) do
            ring(bb, x + math.floor(w * p[1] + 0.5), y + math.floor(h * p[2] + 0.5), r)
        end
    elseif f <= 18 then
        local n = f - 9
        local cw = math.max(3, math.floor(w * (n == 1 and 0.22 or (n == 8 and 0.13 or 0.16))))
        for _, p in ipairs(CANE_LAYOUT[n]) do
            local y0, y1 = y + math.floor(h * p[2]), y + math.floor(h * p[3])
            cane(bb, x + math.floor(w * p[1]) - math.floor(cw / 2), y0, cw, y1 - y0)
        end
    elseif f <= 27 then
        local n = f - 18
        local f1 = self:_fit(CJK, "三", math.floor(h * 0.28), math.floor(w * 0.62), true)
        local f2 = self:_fit(CJK, "萬", math.floor(h * 0.38), math.floor(w * 0.85), true)
        -- 一二三 are thin strokes: size them by 三 so they are not huge bars.
        -- The numeral sits right of centre, clear of the corner index.
        text(bb, f1, CN_NUM[n], cx + math.floor(w * 0.1), y + math.floor(h * 0.25), C_FG, true)
        text(bb, f2, "萬", cx, y + math.floor(h * 0.72), C_FG, true)
        self:_corner(bb, tostring(n), x, y, w, h)
    elseif f <= 31 then
        local k = f - 27
        local fc = self:_fit(CJK, "東", math.floor(h * 0.5), math.floor(w * 0.85), true)
        text(bb, fc, CN_WIND[k], cx, y + math.floor(h * 0.55), C_FG, true)
        self:_corner(bb, self.wind_letters[k], x, y, w, h)
    elseif f == 32 then
        local fc = self:_fit(CJK, "中", math.floor(h * 0.55), math.floor(w * 0.85), true)
        text(bb, fc, "中", cx, y + math.floor(h * 0.5), C_FG, true)
    elseif f == 33 then
        local fc = self:_fit(CJK, "發", math.floor(h * 0.5), math.floor(w * 0.85), true)
        text(bb, fc, "發", cx, y + math.floor(h * 0.5), C_FG, true)
    elseif f == 34 then
        local m = math.max(2, math.floor(w * 0.12))
        frame(bb, x + m, y + math.floor(h * 0.14), w - 2 * m, math.floor(h * 0.72), math.max(2, math.floor(w * 0.07)))
    else
        self:_bonus(bb, f, x, y, w, h)
    end
end

return TilePainter
