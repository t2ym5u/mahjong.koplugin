local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer     = require("ffi/blitbuffer")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager      = require("ui/uimanager")

local TilePainter = lrequire("tile_painter")

local C_BG      = Blitbuffer.COLOR_WHITE
local C_FG      = Blitbuffer.COLOR_BLACK
local C_BLOCKED = Blitbuffer.COLOR_GRAY_D

-- Tile height over width: at least RATIO; up to MAX_RATIO when the layout is
-- wide and the screen has height to spare (the Turtle in portrait), which
-- gives the faces room for bigger signs.
local RATIO = 1.3
local MAX_RATIO = 1.6
-- Thickness of a tile's visible side, and how far each layer is shifted up
-- and right, as a fraction of the tile width.
local DEPTH = 0.13

-- ---------------------------------------------------------------------------
-- MahjongBoardWidget: the layout, drawn as stacked tiles. Each tile shows its
-- side on the left and at the bottom (grey), and each layer sits a little up
-- and to the right of the one under it, so stacks read as stacks without
-- colour. Tiles are painted bottom layer first; within a layer from right to
-- left and top to bottom, so every side lands under its neighbour's face.
--
-- The selected tile is drawn inverted; the hinted pair gets a thick dashed
-- outline. With mark_free, blocked tiles get a grey face.
--
-- Taps go to tileTapCallback(slot) with the topmost tile under the finger,
-- or nil for a tap beside the tiles.
-- ---------------------------------------------------------------------------

local MahjongBoardWidget = InputContainer:extend{
    board           = nil,
    max_width       = 0,
    max_height      = 0,
    style           = "readable",
    mark_free       = false,
    tileTapCallback = nil,
}

-- Tile width that fits a layout in max_w × max_h.
function MahjongBoardWidget.fitTileWidth(L, max_w, max_h)
    local layers = L.zmax + 1
    local w1 = max_w / (L.cols + DEPTH * layers)
    local w2 = max_h / (L.rows * RATIO + DEPTH * layers)
    return math.max(12, math.floor(math.min(w1, w2)))
end

function MahjongBoardWidget:init()
    local L = self.board.L
    self.L = L
    local tw = MahjongBoardWidget.fitTileWidth(L, self.max_width, self.max_height)
    local e = math.max(2, math.floor(tw * DEPTH))
    local th = math.floor((self.max_height - (L.zmax + 1) * e) / L.rows)
    th = math.max(math.floor(tw * RATIO), math.min(th, math.floor(tw * MAX_RATIO)))
    -- Even sizes keep half-tile offsets on whole pixels.
    tw, th = tw - tw % 2, th - th % 2
    self.tw, self.th = tw, th
    self.e = e
    self.bw = tw >= 40 and 2 or 1
    self.w = L.cols * tw + (L.zmax + 1) * self.e
    self.h = L.rows * th + (L.zmax + 1) * self.e
    self.dimen = Geom:new{ w = self.w, h = self.h }
    self.painter = TilePainter.new(tw - 2 * self.bw - 2, th - 2 * self.bw - 2, self.style)

    -- Paint order: by layer, then right to left, then top to bottom.
    local order = {}
    for i = 1, L.n do order[i] = i end
    local s = L.slots
    table.sort(order, function(a, b)
        local A, B = s[a], s[b]
        if A.z ~= B.z then return A.z < B.z end
        if A.x ~= B.x then return A.x > B.x end
        if A.y ~= B.y then return A.y < B.y end
        return a < b
    end)
    self.order = order

    self.paint_rect = nil
    local range = function() return self.paint_rect end
    self.ges_events = {
        TileTap = { GestureRange:new{ ges = "tap", range = range } },
    }
end

-- Top-left corner of slot i's face, relative to the widget.
function MahjongBoardWidget:_faceXY(i)
    local p, L, e = self.L.slots[i], self.L, self.e
    local x = e + (p.x - L.minx) * self.tw / 2 + p.z * e
    local y = (L.zmax - p.z) * e + (p.y - L.miny) * self.th / 2
    return x, y
end

-- Screen rectangle of slot i's face (for tests driving the widget).
function MahjongBoardWidget:getTileCenter(i)
    local rect = self.paint_rect or Geom:new{ x = 0, y = 0 }
    local x, y = self:_faceXY(i)
    return rect.x + x + math.floor(self.tw / 2), rect.y + y + math.floor(self.th / 2)
end

-- The topmost tile on the table under screen point (px, py), or nil.
function MahjongBoardWidget:tileAt(px, py)
    if not self.paint_rect then return nil end
    local lx, ly = px - self.paint_rect.x, py - self.paint_rect.y
    local present = self.board.present
    for k = #self.order, 1, -1 do
        local i = self.order[k]
        if present[i] then
            local x, y = self:_faceXY(i)
            -- The face and the side under it.
            if lx >= x - self.e and lx < x + self.tw and ly >= y and ly < y + self.th + self.e then
                return i
            end
        end
    end
    return nil
end

function MahjongBoardWidget:onTileTap(_, ges)
    if self.tileTapCallback then
        self.tileTapCallback(self:tileAt(ges.pos.x, ges.pos.y))
    end
    return true
end

function MahjongBoardWidget:refresh()
    UIManager:setDirty(self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

local function dashedOutline(bb, x, y, w, h, t, dash)
    for xx = x, x + w - 1, 2 * dash do
        local l = math.min(dash, x + w - xx)
        bb:paintRect(xx, y, l, t, C_FG)
        bb:paintRect(xx, y + h - t, l, t, C_FG)
    end
    for yy = y, y + h - 1, 2 * dash do
        local l = math.min(dash, y + h - yy)
        bb:paintRect(x, yy, t, l, C_FG)
        bb:paintRect(x + w - t, yy, t, l, C_FG)
    end
end

-- Side colour by layer: the higher the tile, the darker its side, so the
-- height of a stack shows even where the offsets are small.
local SIDES = {
    Blitbuffer.COLOR_GRAY_B, Blitbuffer.COLOR_GRAY_9, Blitbuffer.COLOR_GRAY_7,
    Blitbuffer.COLOR_GRAY_5, Blitbuffer.COLOR_GRAY_4,
}

function MahjongBoardWidget:_paintTile(bb, ox, oy, i, free)
    local board = self.board
    local tw, th, e, bw = self.tw, self.th, self.e, self.bw
    local fx, fy = self:_faceXY(i)
    fx, fy = ox + fx, oy + fy
    local z = self.L.slots[i].z
    -- Side: the tile's full shape shifted down-left, under the face.
    bb:paintRect(fx - e, fy + e, tw, th, C_FG)
    bb:paintRect(fx - e + bw, fy + e + bw, tw - 2 * bw, th - 2 * bw, SIDES[math.min(z + 1, #SIDES)])
    -- Face.
    bb:paintRect(fx, fy, tw, th, C_FG)
    local blocked = self.mark_free and not free
    bb:paintRect(fx + bw, fy + bw, tw - 2 * bw, th - 2 * bw, blocked and C_BLOCKED or C_BG)
    self.painter:paint(bb, board.faces[i], fx + bw + 1, fy + bw + 1)

    if board.selected == i then
        bb:invertRect(fx + bw, fy + bw, tw - 2 * bw, th - 2 * bw)
    end
    local hint = board.hint
    if hint and (hint.a == i or hint.b == i) then
        local t = math.max(3, math.floor(tw / 10))
        dashedOutline(bb, fx - 1, fy - 1, tw + 2, th + 2, t, math.max(4, math.floor(tw / 6)))
    end
end

function MahjongBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    bb:paintRect(x, y, self.w, self.h, C_BG)
    local board = self.board
    local present = board.present
    for _, i in ipairs(self.order) do
        if present[i] then
            self:_paintTile(bb, x, y, i, self.mark_free and board:isFree(i))
        end
    end
end

return MahjongBoardWidget
