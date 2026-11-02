local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local Layouts = require("layouts")
local Deal    = require("deal")
local Board   = require("board")

local function allPresent(L)
    local p = {}
    for i = 1, L.n do p[i] = true end
    return p
end

-- Plays `order` from `present`; true if every pair was free and matching.
local function replay(L, faces, present, order)
    for _, pr in ipairs(order) do
        local a, b = pr[1], pr[2]
        if not (Deal.isFree(L, present, a) and Deal.isFree(L, present, b)) then return false end
        if not Deal.matches(faces[a], faces[b]) then return false end
        present[a], present[b] = nil, nil
    end
    for i = 1, L.n do if present[i] then return false end end
    return true
end

-- The slot of layout L at (x, y, z) in tile units.
local function slotAt(L, x, y, z)
    for i, s in ipairs(L.slots) do
        if s.x == x * 2 and s.y == y * 2 and s.z == z then return i end
    end
end

describe("Layouts", function()
    local expected = { pyramid = 56, fortress = 72, temple = 72, bridge = 88, bigpyramid = 120, turtle = 144 }

    it("have the stated tile counts, all even", function()
        for _, id in ipairs(Layouts.IDS) do
            assert.are.equal(expected[id], Layouts.count(id), id)
            assert.are.equal(0, Layouts.count(id) % 2, id)
        end
        assert.is_true(Layouts.isLayout(Layouts.DEFAULT))
        assert.is_nil(Layouts.get("nope"))
    end)

    it("never put two tiles in the same place on a layer", function()
        for _, id in ipairs(Layouts.IDS) do
            local L = Layouts.get(id)
            for i = 1, L.n do
                for j = i + 1, L.n do
                    local a, b = L.slots[i], L.slots[j]
                    local overlap = a.z == b.z and math.abs(a.x - b.x) < 2 and math.abs(a.y - b.y) < 2
                    assert.is_false(overlap, id .. " " .. i .. "/" .. j)
                end
            end
        end
    end)

    it("rest every upper tile on tiles below", function()
        for _, id in ipairs(Layouts.IDS) do
            local L = Layouts.get(id)
            for i = 1, L.n do
                if L.slots[i].z > 0 then
                    local held = false
                    for j = 1, L.n do
                        for _, k in ipairs(L.above[j]) do
                            if k == i and L.slots[j].z == L.slots[i].z - 1 then held = true end
                        end
                    end
                    assert.is_true(held, id .. " slot " .. i)
                end
            end
        end
    end)

    it("know the traditional turtle's neighbours", function()
        local L = Layouts.get("turtle")
        local top = slotAt(L, 6.5, 3.5, 4)
        assert.is_not_nil(top)
        -- The top tile lies on the four tiles of layer 3.
        local under = 0
        for i = 1, L.n do
            for _, k in ipairs(L.above[i]) do if k == top and L.slots[i].z == 3 then under = under + 1 end end
        end
        assert.are.equal(4, under)
        -- The lone left tile hems in both tiles of rows 4 and 5.
        local lone = slotAt(L, 0, 3.5, 0)
        local r4 = slotAt(L, 1, 3, 0)
        assert.are.same({ lone }, L.left[r4])
    end)
end)

describe("Free tiles", function()
    it("needs nothing on top and one open side", function()
        local L = Layouts.get("pyramid")
        local p = allPresent(L)
        local corner = slotAt(L, 0, 0, 0)
        local middle = slotAt(L, 2, 0, 0)
        local under  = slotAt(L, 2, 2, 0)
        local top    = slotAt(L, 2, 2, 2)
        assert.is_true(Deal.isFree(L, p, corner))
        assert.is_false(Deal.isFree(L, p, middle))   -- neighbours on both sides
        assert.is_false(Deal.isFree(L, p, under))    -- covered
        assert.is_true(Deal.isFree(L, p, top))       -- left side open on layer 2
        -- Clear the left of the top row: the middle tile becomes free.
        p[slotAt(L, 0, 0, 0)], p[slotAt(L, 1, 0, 0)] = nil, nil
        assert.is_true(Deal.isFree(L, p, middle))
    end)
end)

describe("Dealing", function()
    it("matches flowers with flowers and seasons with seasons", function()
        assert.is_true(Deal.matches(35, 38))
        assert.is_true(Deal.matches(39, 42))
        assert.is_false(Deal.matches(38, 39))
        assert.is_true(Deal.matches(5, 5))
        assert.is_false(Deal.matches(5, 14))
    end)

    it("uses the full 144-tile set on the turtle", function()
        math.randomseed(1)
        local L = Layouts.get("turtle")
        local faces = Deal.generate(L)
        local count = {}
        for i = 1, L.n do count[faces[i]] = (count[faces[i]] or 0) + 1 end
        for f = 1, 34 do assert.are.equal(4, count[f], "face " .. f) end
        for f = 35, 42 do assert.are.equal(1, count[f], "face " .. f) end
    end)

    it("gives every group an even number of tiles on smaller layouts", function()
        math.randomseed(2)
        for _, id in ipairs(Layouts.IDS) do
            local L = Layouts.get(id)
            local faces = Deal.generate(L)
            local g = {}
            for i = 1, L.n do
                local k = Deal.group(faces[i])
                g[k] = (g[k] or 0) + 1
            end
            for k, n in pairs(g) do assert.are.equal(0, n % 2, id .. " group " .. k) end
        end
    end)

    it("deals only winnable games: the build order clears the table", function()
        math.randomseed(3)
        for _, id in ipairs(Layouts.IDS) do
            local L = Layouts.get(id)
            for _k = 1, 25 do
                local faces, order = Deal.generate(L)
                assert.is_not_nil(faces, id)
                assert.is_true(replay(L, faces, allPresent(L), order), id)
            end
        end
    end)

    it("repeats a deal under the same seed (Daily Challenge)", function()
        local L = Layouts.get("temple")
        math.randomseed(42)
        local a = table.concat(Deal.generate(L), ",")
        math.randomseed(42)
        local b = table.concat(Deal.generate(L), ",")
        assert.are.equal(a, b)
    end)
end)

describe("Solver", function()
    it("solves fresh deals and its path is legal", function()
        math.randomseed(4)
        for _, id in ipairs(Layouts.IDS) do
            local L = Layouts.get(id)
            for _k = 1, 10 do
                local faces = Deal.generate(L)
                local path = Deal.solve(L, faces, allPresent(L), { max_nodes = 200000, max_time = 30 })
                assert.is_not_nil(path, id)
                assert.is_true(replay(L, faces, allPresent(L), path), id)
            end
        end
    end)

    it("proves a stack of two matching tiles lost", function()
        local L = Layouts.get("pyramid")
        local top, mid = slotAt(L, 2, 2, 2), slotAt(L, 2, 2, 1)
        local faces = {}
        for i = 1, L.n do faces[i] = 1 end
        local present = { [top] = true, [mid] = true }
        local path, why = Deal.solve(L, faces, present)
        assert.is_nil(path)
        assert.are.equal("unsolvable", why)
        -- And no reshuffle can help those two.
        assert.is_nil(Deal.reshuffle(L, faces, present))
    end)

    it("reports a budget overrun honestly", function()
        math.randomseed(5)
        local L = Layouts.get("turtle")
        local faces = Deal.generate(L)
        local path, why = Deal.solve(L, faces, allPresent(L), { max_nodes = 1 })
        if not path then assert.are.equal("budget", why) end
    end)

    it("finds a safe pair when a whole group is free", function()
        local L = Layouts.get("pyramid")
        local p = allPresent(L)
        local faces = {}
        for i = 1, L.n do faces[i] = 9 + (i % 9) end
        local a, b = slotAt(L, 0, 0, 0), slotAt(L, 5, 0, 0)
        for i = 1, L.n do if faces[i] == 1 then faces[i] = 2 end end
        faces[a], faces[b] = 1, 1
        local x, y = Deal.safePair(L, faces, p)
        assert.are.same({ math.min(a, b), math.max(a, b) }, { x, y })
    end)
end)

describe("Board", function()
    local function newBoard(id, seed)
        math.randomseed(seed or 7)
        local b = Board:new()
        assert.is_true(b:newDeal(id or "temple"))
        return b
    end

    it("selects, refuses blocked tiles, removes matching pairs", function()
        local b = newBoard()
        local blocked
        for i = 1, b.L.n do if not b:isFree(i) then blocked = i; break end end
        assert.are.equal("blocked", b:tap(blocked))
        local pr = b.plan[1]
        assert.are.equal("select", b:tap(pr[1]))
        assert.are.equal("deselect", b:tap(pr[1]))
        b:tap(pr[1])
        assert.are.equal("remove", b:tap(pr[2]))
        assert.are.equal(70, b:tilesLeft())
        assert.is_true(b:canUndo())
        assert.is_true(b:undo())
        assert.are.equal(72, b:tilesLeft())
        assert.is_true(b.present[pr[1]] and b.present[pr[2]])
    end)

    it("wins by following hints, even after straying from the plan", function()
        for seed = 1, 6 do
            local b = newBoard(seed % 2 == 0 and "turtle" or "fortress", seed)
            -- Stray: take the first available pair that is not the plan's.
            local by = Deal.freeByGroup(b.L, b.faces, b.present)
            for _g, l in pairs(by) do
                if #l >= 2 then b:removePair(l[1], l[2]); break end
            end
            local guard = 0
            while not b:isWon() and guard < 200 do
                guard = guard + 1
                local step, why = b:findHint()
                if not step then
                    -- Strayed into a lost game: shuffle (always possible
                    -- here) and go on.
                    assert.are_not.equal("complete", why)
                    assert.is_true(b:shuffle())
                else
                    assert.is_true(b:applyHint(step))
                end
            end
            assert.is_true(b:isWon(), "seed " .. seed)
        end
    end)

    it("keeps its plan valid after any pair of the plan and after undo", function()
        local b = newBoard("bigpyramid", 11)
        local last = b.plan[#b.plan]
        -- Take the plan's pairs from the end that are free now.
        if b:isFree(last[1]) and b:isFree(last[2]) then
            b:removePair(last[1], last[2])
            assert.is_true(b:_planWorks(b.plan))
        end
        b:removePair(b.plan[1][1], b.plan[1][2])
        assert.is_true(b:_planWorks(b.plan))
        b:undo()
        assert.is_true(b:_planWorks(b.plan))
    end)

    it("shuffles into a winnable arrangement and undoes the shuffle", function()
        local b = newBoard("turtle", 12)
        for _k = 1, 10 do b:removePair(b.plan[1][1], b.plan[1][2]) end
        local before = table.concat(b.faces, ",")
        assert.is_true(b:shuffle())
        assert.is_true(b:_planWorks(b.plan))
        assert.are.equal(124, b:tilesLeft())
        assert.is_true(b:undo())
        assert.are.equal(before, table.concat(b.faces, ","))
    end)

    it("detects a game with no pair left", function()
        local b = newBoard("pyramid", 13)
        local L = b.L
        for i = 1, L.n do b.present[i] = nil end
        local top, mid = slotAt(L, 2, 2, 2), slotAt(L, 2, 2, 1)
        b.present[top], b.present[mid] = true, true
        b.count = 2
        b.faces[top], b.faces[mid] = 3, 3
        b.plan = nil
        assert.is_true(b:isStuck())
        local step, why = b:findHint()
        assert.is_nil(step)
        assert.are.equal("stuck", why)
        assert.is_false(b:shuffle())
    end)

    it("saves and restores a game in progress", function()
        local b = newBoard("bridge", 14)
        b:removePair(b.plan[1][1], b.plan[1][2])
        assert.is_true(b:shuffle())
        b:tap(b.plan[1][1])
        local data = b:serialize()
        local c = Board:new()
        assert.is_true(c:load(data))
        assert.are.equal(b:tilesLeft(), c:tilesLeft())
        assert.are.equal(table.concat(b.faces, ","), table.concat(c.faces, ","))
        assert.are.equal(b.selected, c.selected)
        assert.is_true(c:_planWorks(c.plan))
        assert.is_true(c:undo())           -- the shuffle
        assert.is_true(c:undo())           -- the pair
        assert.are.equal(88, c:tilesLeft())
        assert.is_false(Board:new():load({ layout = "temple", faces = "x" }))
        assert.is_false(Board:new():load(nil))
    end)
end)
