-- ---------------------------------------------------------------------------
-- deal.lua — tiles, dealing and solving. Pure Lua, no UI.
--
-- Faces 1..42:
--    1– 9  dots 1–9          10–18  bamboo 1–9        19–27  characters 1–9
--   28–31  winds E S W N     32–34  dragons red, green, white
--   35–38  flowers 1–4       39–42  seasons 1–4
-- Tiles match when they are in the same group: the face itself for 1..34,
-- any flower with any flower (group 35), any season with any season (36).
--
-- Dealing works backwards. With every slot filled by a blank tile, pairs of
-- free tiles are taken off until the layout is empty; that order is a way to
-- clear the layout whatever the faces are, since being free depends only on
-- which slots are filled. Each pair taken off then gets two matching faces.
-- Playing the pairs in the same order clears the deal, so every deal can be
-- won. Shuffling does the same with the tiles left on the table.
--
-- The solver answers "can this position still be cleared?" for hints: a
-- depth-first search with two shortcuts that never lose a solution (taking
-- off every remaining tile of a group when they are all free; skipping
-- positions already seen), bounded in nodes and time for slow readers.
-- ---------------------------------------------------------------------------

local Deal = {}

Deal.FACES  = 42
Deal.GROUPS = 36

function Deal.group(face)
    if face <= 34 then return face end
    return face <= 38 and 35 or 36
end

function Deal.matches(f1, f2)
    return f1 and f2 and Deal.group(f1) == Deal.group(f2) or false
end

-- Faces of group g: four copies for 1..34, the four flowers or seasons.
local function groupFaces(g)
    if g <= 34 then return { g, g, g, g } end
    local b = g == 35 and 35 or 39
    return { b, b + 1, b + 2, b + 3 }
end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- ---------------------------------------------------------------------------
-- Free tiles
-- ---------------------------------------------------------------------------

local function anyPresent(list, present)
    for k = 1, #list do
        if present[list[k]] then return true end
    end
    return false
end

-- A tile is free when nothing lies on it and one of its long sides is open.
function Deal.isFree(L, present, i)
    if not present[i] then return false end
    if anyPresent(L.above[i], present) then return false end
    return not anyPresent(L.left[i], present) or not anyPresent(L.right[i], present)
end

function Deal.freeTiles(L, present)
    local t = {}
    for i = 1, L.n do
        if present[i] and Deal.isFree(L, present, i) then t[#t + 1] = i end
    end
    return t
end

-- ---------------------------------------------------------------------------
-- Dealing
-- ---------------------------------------------------------------------------

-- How much taking tile i off now helps: tiles under it and beside it. Taking
-- the high, crowded tiles first keeps the order from leaving one tile stuck
-- on top of another at the end.
local function weight(L, present, i)
    local w = 1 + 3 * L.slots[i].z
    for _, list in ipairs({ L.below[i], L.left[i], L.right[i] }) do
        for k = 1, #list do
            if present[list[k]] then w = w + 2 end
        end
    end
    return w
end

local function pickWeighted(L, present, free, skip)
    local total = 0
    for k = 1, #free do
        if free[k] ~= skip then total = total + weight(L, present, free[k]) end
    end
    local r = math.random() * total
    for k = 1, #free do
        local i = free[k]
        if i ~= skip then
            r = r - weight(L, present, i)
            if r <= 0 then return i end
        end
    end
    for k = #free, 1, -1 do
        if free[k] ~= skip then return free[k] end
    end
end

-- An order taking off every slot listed in `slots` two free tiles at a time:
-- a list of pairs { a, b }, or nil when none was found (some sets of slots
-- cannot be cleared at all, e.g. one tile alone on top of another).
function Deal.removalOrder(L, slots, attempts)
    for _try = 1, attempts or 300 do
        local present, left = {}, #slots
        for _, i in ipairs(slots) do present[i] = true end
        local order = {}
        while left > 0 do
            local free = Deal.freeTiles(L, present)
            if #free < 2 then break end
            local a = pickWeighted(L, present, free)
            local b = pickWeighted(L, present, free, a)
            present[a], present[b] = nil, nil
            order[#order + 1] = { a, b }
            left = left - 2
        end
        if left == 0 then return order end
    end
    return nil
end

-- The faces for a deal of n tiles (n even): whole groups of four, chosen at
-- random when the layout is smaller than the full 144-tile set, and one group
-- of two when n is not a multiple of four. Returned as pairs of matching faces.
function Deal.facePairs(n)
    local groups = {}
    for g = 1, Deal.GROUPS do groups[g] = g end
    shuffle(groups)
    local pairs_ = {}
    local whole = math.min(math.floor(n / 4), Deal.GROUPS)
    for k = 1, whole do
        local f = shuffle(groupFaces(groups[k]))
        pairs_[#pairs_ + 1] = { f[1], f[2] }
        pairs_[#pairs_ + 1] = { f[3], f[4] }
    end
    local k = whole
    while #pairs_ * 2 < n do
        -- n % 4 == 2, or a layout above 144 tiles: one more pair per group.
        k = k % Deal.GROUPS + 1
        local f = shuffle(groupFaces(groups[k]))
        pairs_[#pairs_ + 1] = { f[1], f[2] }
    end
    return shuffle(pairs_)
end

-- Gives each pair of `order` one pair of faces. Returns faces[slot].
local function assign(order, face_pairs, faces)
    faces = faces or {}
    for k, pr in ipairs(order) do
        local fp = face_pairs[k]
        faces[pr[1]], faces[pr[2]] = fp[1], fp[2]
    end
    return faces
end

-- A new deal on layout L: faces[slot] plus the order it was built in (a
-- solution). Uses math.random only, so the daily seed makes it repeatable.
function Deal.generate(L)
    local all = {}
    for i = 1, L.n do all[i] = i end
    local order = Deal.removalOrder(L, all, 1000)
    if not order then return nil end
    return assign(order, Deal.facePairs(L.n)), order
end

-- New faces for the tiles still on the table, arranged so they can all be
-- taken off. Returns the new faces table (removed slots untouched) and the
-- order that clears it, or nil when the slots left cannot be cleared
-- whatever their faces.
function Deal.reshuffle(L, faces, present)
    local slots, by_group = {}, {}
    for i = 1, L.n do
        if present[i] then
            slots[#slots + 1] = i
            local g = Deal.group(faces[i])
            by_group[g] = by_group[g] or {}
            table.insert(by_group[g], faces[i])
        end
    end
    local order = Deal.removalOrder(L, slots, 600)
    if not order then return nil end
    local face_pairs = {}
    for g = 1, Deal.GROUPS do
        local f = by_group[g]
        if f then
            shuffle(f)
            for k = 1, #f - 1, 2 do face_pairs[#face_pairs + 1] = { f[k], f[k + 1] } end
        end
    end
    if #face_pairs ~= #order then return nil end
    local new = {}
    for i = 1, L.n do new[i] = faces[i] end
    return assign(order, shuffle(face_pairs), new), order
end

-- ---------------------------------------------------------------------------
-- Moves available
-- ---------------------------------------------------------------------------

-- The free tiles grouped by match group: { [g] = { slot, ... } }.
function Deal.freeByGroup(L, faces, present)
    local by = {}
    for _, i in ipairs(Deal.freeTiles(L, present)) do
        local g = Deal.group(faces[i])
        by[g] = by[g] or {}
        table.insert(by[g], i)
    end
    return by
end

-- Number of different pairs that could be taken off now.
function Deal.countMoves(L, faces, present)
    local n = 0
    for _, list in pairs(Deal.freeByGroup(L, faces, present)) do
        n = n + #list * (#list - 1) / 2
    end
    return n
end

-- A pair that can never hurt: every tile left in its group is free, so taking
-- them off loses nothing. Returns a, b or nil.
function Deal.safePair(L, faces, present)
    local remaining = {}
    for i = 1, L.n do
        if present[i] then
            local g = Deal.group(faces[i])
            remaining[g] = (remaining[g] or 0) + 1
        end
    end
    local best
    for g, list in pairs(Deal.freeByGroup(L, faces, present)) do
        if #list >= 2 and #list == remaining[g] and (not best or g < best) then best = g end
    end
    if not best then return nil end
    local list = Deal.freeByGroup(L, faces, present)[best]
    table.sort(list)
    return list[1], list[2]
end

-- ---------------------------------------------------------------------------
-- Solver
-- ---------------------------------------------------------------------------

-- Position keys: two sums of per-slot random numbers (exact in doubles), from
-- a private generator so loading this module never disturbs math.random.
local zob1, zob2 = {}, {}
do
    local s = 123456789
    local function nxt()
        s = (s * 16807) % 2147483647
        return s
    end
    for i = 1, 256 do
        -- Below 2^38, so a sum over 256 slots stays under 10^14 and prints
        -- exactly in LuaJIT's 14-digit number formatting.
        zob1[i] = nxt() * 128 + nxt() % 128
        zob2[i] = nxt() * 128 + nxt() % 128
    end
end

-- Searches for a way to clear the table from `present`.
-- opts.max_nodes (default 40000), opts.max_time in seconds (default 2).
-- Returns path (list of { a, b }), or nil plus "unsolvable" (the search ran
-- to the end: this position cannot be cleared) or "budget".
function Deal.solve(L, faces, present, opts)
    opts = opts or {}
    local max_nodes = opts.max_nodes or 20000
    local max_time  = opts.max_time or 2
    local clock     = os.clock
    local t0        = clock()

    local n = L.n
    local above, left, right, below, sl = L.above, L.left, L.right, L.below, L.slots
    local pres, grp, remaining = {}, {}, {}
    local count, h1, h2 = 0, 0, 0
    for i = 1, n do
        grp[i] = faces[i] and Deal.group(faces[i]) or 0
        if present[i] then
            pres[i] = true
            count = count + 1
            remaining[grp[i]] = (remaining[grp[i]] or 0) + 1
            h1, h2 = h1 + zob1[i], h2 + zob2[i]
        end
    end

    local function free(i)
        local l = above[i]
        for k = 1, #l do if pres[l[k]] then return false end end
        local lt, rt = left[i], right[i]
        local lb = false
        for k = 1, #lt do if pres[lt[k]] then lb = true; break end end
        if not lb then return true end
        for k = 1, #rt do if pres[rt[k]] then return false end end
        return true
    end

    local function take(i)
        pres[i] = nil
        count = count - 1
        remaining[grp[i]] = remaining[grp[i]] - 1
        h1, h2 = h1 - zob1[i], h2 - zob2[i]
    end
    local function put(i)
        pres[i] = true
        count = count + 1
        remaining[grp[i]] = remaining[grp[i]] + 1
        h1, h2 = h1 + zob1[i], h2 + zob2[i]
    end

    -- Taking tile i off: how many tiles it was holding down or hemming in.
    local function score(i)
        local s = sl[i].z * 4
        for _, list in ipairs({ below[i], left[i], right[i] }) do
            for k = 1, #list do if pres[list[k]] then s = s + 1 end end
        end
        return s
    end

    -- Tiles that must all go before tile i can be free: what lies on it,
    -- and on those, and so on. A tile whose remaining partners all lie on it
    -- can never be taken off: the position is lost.
    local closure = L.closure
    if not closure then
        closure = {}
        local function close(i)
            if closure[i] then return closure[i] end
            local set = {}
            for _, j in ipairs(above[i]) do
                set[j] = true
                for k in pairs(close(j)) do set[k] = true end
            end
            closure[i] = set
            return set
        end
        for i = 1, n do close(i) end
        L.closure = closure
    end
    local members = {}
    for i = 1, n do
        if pres[i] then
            local g = grp[i]
            members[g] = members[g] or {}
            table.insert(members[g], i)
        end
    end
    local function dead()
        for g, list in pairs(members) do
            if remaining[g] > 0 then
                for a = 1, #list do
                    local t = list[a]
                    if pres[t] then
                        local cl, partner = closure[t], false
                        for b = 1, #list do
                            local o = list[b]
                            if o ~= t and pres[o] and not cl[o] then partner = true; break end
                        end
                        if not partner then return true end
                    end
                end
            end
        end
        return false
    end

    -- Restarts: a depth-first search that starts down a bad branch can spend
    -- its whole budget there, so it runs in rounds of growing size, each with
    -- a different tie-break among equally good moves. Positions proven lost
    -- stay known across rounds; the last round is unbounded but for the
    -- overall budget, so a search that ends there without a path is a proof.
    local lost, nodes, aborted = {}, 0, false
    local round_limit, jitter = 0, 0
    local path = {}
    local rs = 987654321
    local function rnd()
        rs = (rs * 16807) % 2147483647
        return rs
    end

    local function search()
        if count == 0 then return true end
        nodes = nodes + 1
        if nodes > round_limit or (nodes % 256 == 0 and clock() - t0 > max_time) then
            aborted = true
            return false
        end

        local by = {}
        for i = 1, n do
            if pres[i] and free(i) then
                local g = grp[i]
                local t = by[g]
                if not t then t = {}; by[g] = t end
                t[#t + 1] = i
            end
        end

        -- Whole groups that are all free come off without a choice.
        local forced = {}
        for g, t in pairs(by) do
            if #t >= 2 and #t == remaining[g] then
                for k = 1, #t - 1, 2 do forced[#forced + 1] = { t[k], t[k + 1] } end
            end
        end
        if #forced > 0 then
            for _, pr in ipairs(forced) do
                take(pr[1]); take(pr[2])
                path[#path + 1] = pr
            end
            if search() then return true end
            for k = #forced, 1, -1 do
                local pr = forced[k]
                put(pr[1]); put(pr[2])
                path[#path] = nil
            end
            return false
        end

        local key = h1 .. ":" .. h2
        if lost[key] then return false end
        if dead() then lost[key] = true; return false end

        local cands = {}
        for _g, t in pairs(by) do
            for a = 1, #t - 1 do
                for b = a + 1, #t do
                    local i, j = t[a], t[b]
                    local sc = score(i) + score(j)
                    if jitter > 0 then sc = sc + (rnd() % jitter) end
                    cands[#cands + 1] = { i, j, sc }
                end
            end
        end
        table.sort(cands, function(x, y)
            if x[3] ~= y[3] then return x[3] > y[3] end
            if x[1] ~= y[1] then return x[1] < y[1] end
            return x[2] < y[2]
        end)
        for _, c in ipairs(cands) do
            take(c[1]); take(c[2])
            path[#path + 1] = { c[1], c[2] }
            if search() then return true end
            path[#path] = nil
            put(c[1]); put(c[2])
            if aborted then return false end
        end
        -- Every move from here was tried to the end: lost.
        lost[key] = true
        return false
    end

    local limit = opts.first_round or 200
    while true do
        aborted = false
        round_limit = nodes + limit
        if round_limit >= max_nodes then round_limit = max_nodes end
        if search() then return path, nil, nodes end
        if not aborted then return nil, "unsolvable", nodes end
        if round_limit >= max_nodes or clock() - t0 > max_time then
            return nil, "budget", nodes
        end
        limit = math.floor(limit * (opts.growth or 1.5))
        jitter = opts.jitter or 40
    end
end

return Deal
