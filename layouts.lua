-- ---------------------------------------------------------------------------
-- layouts.lua — where the tiles sit. Pure Lua, no UI.
--
-- A layout is a list of tile slots { x, y, z } in half-tile units: a tile
-- covers x..x+2 by y..y+2 on layer z, so x = 1 is half a tile to the right.
-- Every layout has an even number of slots.
--
-- Built once, on first use; each comes with its neighbour lists (what lies on
-- top of a slot, what touches it on the left and on the right), which is all
-- the rules need to tell a free tile from a blocked one.
-- ---------------------------------------------------------------------------

local Layouts = {}

-- Small to large. The default fills a 6" portrait screen with big tiles.
Layouts.IDS = { "pyramid", "fortress", "temple", "bridge", "bigpyramid", "turtle" }
Layouts.DEFAULT = "temple"

local builders = {}

local function slots()
    local t = {}
    local function add(x, y, z) t[#t + 1] = { x = math.floor(x * 2 + 0.5), y = math.floor(y * 2 + 0.5), z = z } end
    -- nx × ny block of tiles whose top-left tile is at (x, y), in tile units.
    local function rect(x, y, nx, ny, z)
        for j = 0, ny - 1 do
            for i = 0, nx - 1 do add(x + i, y + j, z) end
        end
    end
    return t, add, rect
end

-- 56: three square layers.
builders.pyramid = function()
    local t, _add, rect = slots()
    rect(0, 0, 6, 6, 0)
    rect(1, 1, 4, 4, 1)
    rect(2, 2, 2, 2, 2)
    return t
end

-- 72: walls round a moat, towers in the corners, a keep in the middle.
builders.fortress = function()
    local t, add, rect = slots()
    rect(0, 0, 8, 1, 0)
    rect(0, 7, 8, 1, 0)
    rect(0, 1, 1, 6, 0)
    rect(7, 1, 1, 6, 0)
    rect(2, 2, 4, 4, 0)
    for _, p in ipairs({ { 0, 0 }, { 7, 0 }, { 0, 7 }, { 7, 7 } }) do
        add(p[1], p[2], 1)
        add(p[1], p[2], 2)
    end
    add(3.5, 0, 1); add(3.5, 7, 1); add(0, 3.5, 1); add(7, 3.5, 1)
    add(3.5, 0, 2); add(3.5, 7, 2)
    rect(2.5, 2.5, 3, 3, 1)
    rect(3, 3, 2, 2, 2)
    add(3.5, 3.5, 3)
    return t
end

-- 72: a wide base, a stepped roof.
builders.temple = function()
    local t, _add, rect = slots()
    rect(0, 0, 8, 6, 0)
    rect(1, 1.5, 6, 3, 1)
    rect(3, 1.5, 2, 3, 2)
    return t
end

-- 88: two towers joined by a deck.
builders.bridge = function()
    local t, _add, rect = slots()
    for _, x in ipairs({ 0, 8 }) do
        rect(x, 0, 2, 7, 0)
        rect(x, 1, 2, 5, 1)
        rect(x, 2, 2, 3, 2)
    end
    rect(2, 2, 6, 3, 0)
    rect(3, 2.5, 4, 2, 1)
    rect(4, 3, 2, 1, 2)
    return t
end

-- 120: four square layers.
builders.bigpyramid = function()
    local t, _add, rect = slots()
    rect(0, 0, 8, 8, 0)
    rect(1, 1, 6, 6, 1)
    rect(2, 2, 4, 4, 2)
    rect(3, 3, 2, 2, 3)
    return t
end

-- 144: the traditional layout.
builders.turtle = function()
    local t, add, rect = slots()
    local rows = { { 1, 12 }, { 3, 8 }, { 2, 10 }, { 1, 12 }, { 1, 12 }, { 2, 10 }, { 3, 8 }, { 1, 12 } }
    for y, r in ipairs(rows) do rect(r[1], y - 1, r[2], 1, 0) end
    add(0, 3.5, 0); add(13, 3.5, 0); add(14, 3.5, 0)
    rect(4, 1, 6, 6, 1)
    rect(5, 2, 4, 4, 2)
    rect(6, 3, 2, 2, 3)
    add(6.5, 3.5, 4)
    return t
end

local cache = {}

-- Tiles overlap when their 2×2 footprints share an area.
local function overlaps(a, b)
    return math.abs(a.x - b.x) < 2 and math.abs(a.y - b.y) < 2
end

-- Layout `id`: { id, slots, above = {i → list}, left = {…}, right = {…},
-- cols, rows, zmax, minx, miny } or nil.
function Layouts.get(id)
    if cache[id] then return cache[id] end
    local build = builders[id]
    if not build then return nil end
    local s = build()
    local n = #s
    local above, left, right, below = {}, {}, {}, {}
    local minx, miny, maxx, maxy, zmax = math.huge, math.huge, -math.huge, -math.huge, 0
    for i = 1, n do
        above[i], left[i], right[i], below[i] = {}, {}, {}, {}
        local a = s[i]
        minx = math.min(minx, a.x); maxx = math.max(maxx, a.x)
        miny = math.min(miny, a.y); maxy = math.max(maxy, a.y)
        zmax = math.max(zmax, a.z)
    end
    for i = 1, n do
        local a = s[i]
        for j = 1, n do
            if i ~= j then
                local b = s[j]
                if b.z > a.z and overlaps(a, b) then
                    above[i][#above[i] + 1] = j
                    if b.z == a.z + 1 then below[j][#below[j] + 1] = i end
                elseif b.z == a.z and math.abs(a.y - b.y) < 2 then
                    if b.x == a.x - 2 then left[i][#left[i] + 1] = j
                    elseif b.x == a.x + 2 then right[i][#right[i] + 1] = j end
                end
            end
        end
    end
    local L = {
        id = id, slots = s, n = n,
        above = above, left = left, right = right, below = below,
        minx = minx, miny = miny,
        cols = (maxx - minx) / 2 + 1,   -- extent in tiles
        rows = (maxy - miny) / 2 + 1,
        zmax = zmax,
    }
    cache[id] = L
    return L
end

function Layouts.isLayout(id)
    return builders[id] ~= nil
end

function Layouts.count(id)
    local L = Layouts.get(id)
    return L and L.n or 0
end

return Layouts
