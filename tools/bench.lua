-- Offline check of the dealer and the solver (not shipped).
-- usage (from the plugin dir): luajit tools/bench.lua [deals_per_layout]
package.path = "./?.lua;" .. package.path
local Layouts = require("layouts")
local Deal    = require("deal")
local N = tonumber(arg[1]) or 50
math.randomseed(os.time())
for _, id in ipairs(Layouts.IDS) do
    local L = Layouts.get(id)
    local t0 = os.clock()
    local ok, fails = 0, 0
    local solved, budget, unsolv, tmax, nodes_max = 0, 0, 0, 0, 0
    local mid_s, mid_b, mid_u = 0, 0, 0
    for _ = 1, N do
        local faces, order = Deal.generate(L)
        if faces then
            ok = ok + 1
            local present = {}
            for i = 1, L.n do present[i] = true end
            local s = os.clock()
            local path, why, nodes = Deal.solve(L, faces, present)
            local dt = os.clock() - s
            tmax = math.max(tmax, dt)
            if path then solved = solved + 1 elseif why == "budget" then budget = budget + 1 else unsolv = unsolv + 1 end
            -- A random player: take random available pairs for a third of the game, then ask.
            for _k = 1, math.floor(L.n / 6) do
                local by = Deal.freeByGroup(L, faces, present)
                local cands = {}
                for _g, l in pairs(by) do for a = 1, #l - 1 do for b = a + 1, #l do cands[#cands + 1] = { l[a], l[b] } end end end
                if #cands == 0 then break end
                local c = cands[math.random(#cands)]
                present[c[1]], present[c[2]] = nil, nil
            end
            s = os.clock()
            local p2, why2, n2 = Deal.solve(L, faces, present)
            dt = os.clock() - s
            tmax = math.max(tmax, dt)
            nodes_max = math.max(nodes_max, n2 or 0)
            if p2 then mid_s = mid_s + 1 elseif why2 == "budget" then mid_b = mid_b + 1 else mid_u = mid_u + 1 end
        else
            fails = fails + 1
        end
    end
    print(string.format("%-11s n=%3d deals %d/%d  start: solved %d budget %d unsolv %d | mid: solved %d budget %d unsolv %d | max solve %.3fs  gen+solve total %.2fs",
        id, L.n, ok, N, solved, budget, unsolv, mid_s, mid_b, mid_u, tmax, os.clock() - t0))
end
