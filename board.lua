local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Timer   = require("timer")
local Layouts = lrequire("layouts")
local Deal    = lrequire("deal")

-- ---------------------------------------------------------------------------
-- MahjongBoard — one deal in play: the faces, which tiles are still on the
-- table, the selection, undo history, hints and the clock. Pure Lua, no UI.
--
-- The board keeps a *plan*: a list of pairs that clears the table from the
-- current position. A new deal or a shuffle comes with one (the order it was
-- built in). Taking off a pair of the plan keeps the rest valid -- removing
-- tiles only ever frees others -- and so does undoing a move. When the player
-- takes off another pair, the plan is repaired if it can be (the same tiles
-- re-paired), otherwise dropped, and the next hint asks the solver.
-- ---------------------------------------------------------------------------

local MahjongBoard = {}
MahjongBoard.__index = MahjongBoard

-- On-device search budget for a hint (see Deal.solve).
MahjongBoard.SOLVE_OPTS = { max_nodes = 20000, max_time = 1.5 }

function MahjongBoard:new()
    return setmetatable({
        timer      = Timer:new(),
        history    = {},
        hints_used = 0,
        shuffles   = 0,
    }, self)
end

local function copyPlan(plan)
    if not plan then return nil end
    local t = {}
    for k, pr in ipairs(plan) do t[k] = { pr[1], pr[2] } end
    return t
end

-- Starts a fresh deal on layout `id`. Returns false if none could be built.
function MahjongBoard:newDeal(id, daily)
    local L = Layouts.get(id)
    if not L then return false end
    local faces, order = Deal.generate(L)
    if not faces then return false end
    self:_setup(L, faces, nil, order)
    self.daily = daily or nil
    self.timer:reset()
    self.timer:start()
    return true
end

function MahjongBoard:_setup(L, faces, present, plan)
    self.layout     = L.id
    self.L          = L
    self.faces      = faces
    self.present    = {}
    self.count      = 0
    for i = 1, L.n do
        if not present or present[i] then
            self.present[i] = true
            self.count = self.count + 1
        end
    end
    self.history    = {}
    self.selected   = nil
    self.hint       = nil
    self.plan       = plan
    self.won        = self.count == 0
    self.hints_used = 0
    self.shuffles   = 0
    self.recorded   = nil
end

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

function MahjongBoard:isFree(i)
    return self.present[i] and Deal.isFree(self.L, self.present, i) or false
end

function MahjongBoard:tilesLeft()
    return self.count
end

-- Number of different pairs that could be taken off now.
function MahjongBoard:movesAvailable()
    return Deal.countMoves(self.L, self.faces, self.present)
end

function MahjongBoard:isWon()
    return self.won
end

-- Tiles left but no pair to take off.
function MahjongBoard:isStuck()
    return not self.won and self.count > 0 and self:movesAvailable() == 0
end

function MahjongBoard:canUndo()
    return #self.history > 0 and not self.won
end

function MahjongBoard:getHintsUsed()
    return self.hints_used or 0
end

function MahjongBoard:noteHintUsed()
    self.hints_used = (self.hints_used or 0) + 1
end

-- ---------------------------------------------------------------------------
-- The plan
-- ---------------------------------------------------------------------------

-- Is `plan` playable, pair after pair, from the current position?
function MahjongBoard:_planWorks(plan)
    local L, faces = self.L, self.faces
    local present, left = {}, self.count
    for i = 1, L.n do present[i] = self.present[i] end
    for _, pr in ipairs(plan) do
        local a, b = pr[1], pr[2]
        if a == b or not Deal.matches(faces[a], faces[b])
            or not Deal.isFree(L, present, a) or not Deal.isFree(L, present, b) then
            return false
        end
        present[a], present[b] = nil, nil
        left = left - 2
    end
    return left == 0
end

-- After the player took off a, b: keep the plan valid if possible.
function MahjongBoard:_followPlan(a, b)
    local plan = self.plan
    if not plan then return end
    local ia, ib
    for k, pr in ipairs(plan) do
        if pr[1] == a or pr[2] == a then ia = k end
        if pr[1] == b or pr[2] == b then ib = k end
    end
    if not ia or not ib then self.plan = nil; return end
    if ia == ib then
        table.remove(plan, ia)
        return
    end
    -- a and b came from two pairs of the same group: their partners c, d
    -- match each other. Try them as one pair at a few places in the order.
    local pa, pb = plan[ia], plan[ib]
    local c = pa[1] == a and pa[2] or pa[1]
    local d = pb[1] == b and pb[2] or pb[1]
    local lo, hi = math.min(ia, ib), math.max(ia, ib)
    local rest = {}
    for k, pr in ipairs(plan) do
        if k ~= ia and k ~= ib then rest[#rest + 1] = pr end
    end
    -- After dropping two entries, index `lo` is where the earlier one was
    -- and `hi - 1` where the later one was.
    local tried = {}
    for _, pos in ipairs({ lo, hi - 1, 1 }) do
        if not tried[pos] then
            tried[pos] = true
            local cand = copyPlan(rest)
            table.insert(cand, pos, { c, d })
            if self:_planWorks(cand) then
                self.plan = cand
                return
            end
        end
    end
    self.plan = nil
end

-- ---------------------------------------------------------------------------
-- Moves
-- ---------------------------------------------------------------------------

-- A tap on tile i. Returns what happened:
--   "blocked"   the tile is not free (the selection stays)
--   "select"    i is now selected
--   "deselect"  i was selected and no longer is
--   "switch"    another tile was selected and did not match: i replaces it
--   "remove"    i matched the selection and both are gone (check isWon())
function MahjongBoard:tap(i)
    if self.won or not self.present[i] then return nil end
    if not self:isFree(i) then return "blocked" end
    local sel = self.selected
    if sel == i then
        self.selected = nil
        return "deselect"
    end
    if sel and Deal.matches(self.faces[sel], self.faces[i]) then
        self:removePair(sel, i)
        return "remove"
    end
    self.selected = i
    return sel and "switch" or "select"
end

-- Takes off a and b if both are free and match. Returns true if done.
function MahjongBoard:removePair(a, b)
    if self.won or a == b or not self.present[a] or not self.present[b] then return false end
    if not Deal.matches(self.faces[a], self.faces[b]) then return false end
    if not self:isFree(a) or not self:isFree(b) then return false end
    self.present[a], self.present[b] = nil, nil
    self.count = self.count - 2
    self.history[#self.history + 1] = { a, b }
    self.selected = nil
    self.hint = nil
    self:_followPlan(a, b)
    if self.count == 0 then
        self.won = true
        self.timer:stop()
    end
    return true
end

function MahjongBoard:undo()
    if not self:canUndo() then return false end
    local h = table.remove(self.history)
    if h.shuffle then
        self.faces = h.faces
        self.plan = h.plan
    else
        local a, b = h[1], h[2]
        self.present[a], self.present[b] = true, true
        self.count = self.count + 2
        -- a and b were free before they went: the plan still works with them
        -- taken off first.
        if self.plan then table.insert(self.plan, 1, { a, b }) end
    end
    self.selected = nil
    self.hint = nil
    return true
end

-- New faces for the tiles left, arranged so they can all be taken off.
-- Returns true, or false when the tiles left cannot be cleared whatever their
-- faces (one alone on top of another...): only Undo helps then.
function MahjongBoard:shuffle()
    if self.won or self.count == 0 then return false end
    local faces, order = Deal.reshuffle(self.L, self.faces, self.present)
    if not faces then return false end
    self.history[#self.history + 1] = { shuffle = true, faces = self.faces, plan = copyPlan(self.plan) }
    self.faces = faces
    self.plan = order
    self.selected = nil
    self.hint = nil
    self.shuffles = (self.shuffles or 0) + 1
    return true
end

-- ---------------------------------------------------------------------------
-- Hints
-- ---------------------------------------------------------------------------

-- The pair to take off next. Returns a step
--   { a, b, kind = "plan" }    keeps the table clearable (proven)
--   { a, b, kind = "safe" }    the solver ran out of time, but this pair
--                              can never hurt
--   { a, b, kind = "unchecked" } the solver ran out of time: just a pair
-- or nil plus a reason: "complete", "lost" (no way to clear the table from
-- here: undo or shuffle) or "stuck" (no pair at all).
function MahjongBoard:findHint()
    if self.won then return nil, "complete" end
    if self.plan and self.plan[1] then
        return { a = self.plan[1][1], b = self.plan[1][2], kind = "plan" }
    end
    local path, why = Deal.solve(self.L, self.faces, self.present, MahjongBoard.SOLVE_OPTS)
    if path then
        self.plan = path
        return { a = path[1][1], b = path[1][2], kind = "plan" }
    end
    if why == "unsolvable" then
        return nil, self:movesAvailable() == 0 and "stuck" or "lost"
    end
    local a, b = Deal.safePair(self.L, self.faces, self.present)
    if a then return { a = a, b = b, kind = "safe" } end
    local by = Deal.freeByGroup(self.L, self.faces, self.present)
    local best
    for g, list in pairs(by) do
        if #list >= 2 and (not best or g < best) then best = g end
    end
    if not best then return nil, "stuck" end
    table.sort(by[best])
    return { a = by[best][1], b = by[best][2], kind = "unchecked" }
end

function MahjongBoard:applyHint(step)
    if not step then return false end
    return self:removePair(step.a, step.b)
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

local function facesToString(faces, n)
    local t = {}
    for i = 1, n do t[i] = string.char(64 + (faces[i] or 0)) end
    return table.concat(t)
end

local function facesFromString(s, n)
    if type(s) ~= "string" or #s ~= n then return nil end
    local t = {}
    for i = 1, n do
        local f = s:byte(i) - 64
        if f < 1 or f > Deal.FACES then return nil end
        t[i] = f
    end
    return t
end

local function planToList(plan)
    if not plan then return nil end
    local t = {}
    for _, pr in ipairs(plan) do t[#t + 1] = pr[1]; t[#t + 1] = pr[2] end
    return t
end

local function planFromList(t)
    if type(t) ~= "table" then return nil end
    local plan = {}
    for k = 1, #t - 1, 2 do plan[#plan + 1] = { tonumber(t[k]), tonumber(t[k + 1]) } end
    return plan
end

function MahjongBoard:serialize()
    if not self.L then return nil end
    local n = self.L.n
    local present = {}
    for i = 1, n do present[i] = self.present[i] and "1" or "0" end
    local history = {}
    for _, h in ipairs(self.history) do
        if h.shuffle then
            history[#history + 1] = { s = facesToString(h.faces, n), p = planToList(h.plan) }
        else
            history[#history + 1] = { h[1], h[2] }
        end
    end
    return {
        layout     = self.layout,
        faces      = facesToString(self.faces, n),
        present    = table.concat(present),
        history    = history,
        plan       = planToList(self.plan),
        daily      = self.daily,
        timer      = self.timer:serialize(),
        hints_used = self.hints_used,
        shuffles   = self.shuffles,
        selected   = self.selected,
        recorded   = self.recorded,
    }
end

-- Restores a saved game. Returns false (board untouched) if `data` is not one.
function MahjongBoard:load(data)
    if type(data) ~= "table" then return false end
    local L = Layouts.get(data.layout)
    if not L then return false end
    local faces = facesFromString(data.faces, L.n)
    if not faces or type(data.present) ~= "string" or #data.present ~= L.n then return false end
    local present = {}
    for i = 1, L.n do present[i] = data.present:sub(i, i) == "1" end
    local plan = planFromList(data.plan)
    self:_setup(L, faces, present, plan)
    if plan and not self:_planWorks(plan) then self.plan = nil end
    for _, h in ipairs(type(data.history) == "table" and data.history or {}) do
        if h.s then
            local f = facesFromString(h.s, L.n)
            if f then self.history[#self.history + 1] = { shuffle = true, faces = f, plan = planFromList(h.p) } end
        elseif tonumber(h[1]) and tonumber(h[2]) then
            self.history[#self.history + 1] = { tonumber(h[1]), tonumber(h[2]) }
        end
    end
    self.daily      = data.daily
    self.hints_used = tonumber(data.hints_used) or 0
    self.shuffles   = tonumber(data.shuffles) or 0
    self.recorded   = data.recorded and true or nil
    local sel = tonumber(data.selected)
    self.selected   = sel and self:isFree(sel) and sel or nil
    self.timer:load(data.timer)
    if self.won then self.timer:stop() end
    return true
end

return MahjongBoard
