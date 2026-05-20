-- data.lua
-- Machine registry, stats, and persistence etc

local Data = {}

local SAVE_FILE = "casino_data.json"

-- Default structure
local function defaultState()
    return {
        machines = {},      
        nextSlot  = 1,      
        global    = {},     
    }
end

local state = defaultState()

function Data.save()
    local f = fs.open(SAVE_FILE, "w")
    if f then
        f.write(textutils.serializeJSON(state))
        f.close()
    end
end

function Data.load()
    if fs.exists(SAVE_FILE) then
        local f = fs.open(SAVE_FILE, "r")
        if f then
            local raw = f.readAll()
            f.close()
            local ok, parsed = pcall(textutils.unserializeJSON, raw)
            if ok and parsed then
                state = parsed
                if not state.global then state.global = {} end
                return true
            end
        end
    end
    state = defaultState()
    return false
end

function Data.registerMachine(id, info)
    local idStr = tostring(id)
    if not state.machines[idStr] then
        state.machines[idStr] = {
            id          = id,
            slot        = state.nextSlot,
            label       = info.label or ("Machine #" .. state.nextSlot),
            winPercent  = info.winPercent or 30,
            enabled     = true,
            totalIn     = 0,   -- total spurs inserted
            totalOut    = 0,   -- total spurs paid out
            totalPlays  = 0,
            lastSeen    = os.time(),
            online      = true,
        }
        state.nextSlot = state.nextSlot + 1
    else
        state.machines[idStr].online   = true
        state.machines[idStr].lastSeen = os.time()
        if info.label      then state.machines[idStr].label      = info.label      end
        if info.winPercent then state.machines[idStr].winPercent = info.winPercent end
    end
    Data.save()
    return state.machines[idStr]
end

function Data.getMachine(id)
    return state.machines[tostring(id)]
end

function Data.getAllMachines()
    local list = {}
    for _, machine in pairs(state.machines) do
        table.insert(list, machine)
    end
    table.sort(list, function(a, b) return a.slot < b.slot end)
    return list
end

function Data.recordPlay(id, amountIn, amountOut, won)
    local m = state.machines[tostring(id)]
    if not m then return end
    m.totalIn    = (m.totalIn    or 0) + amountIn
    m.totalOut   = (m.totalOut   or 0) + amountOut
    m.totalPlays = (m.totalPlays or 0) + 1
    Data.save()
end

function Data.setConfig(id, key, value)
    local m = state.machines[tostring(id)]
    if not m then return false end
    m[key] = value
    Data.save()
    return true
end

function Data.setGlobalStat(key, value)
    state.global[key] = value
end

function Data.pruneOffline(thresholdSeconds)
    local now = os.time()
    for _, m in pairs(state.machines) do
        if (now - (m.lastSeen or 0)) > thresholdSeconds then
            m.online = false
        end
    end
end

function Data.globalStats()
    local totalIn    = 0
    local totalOut   = 0
    local totalPlays = 0
    local online     = 0
    for _, m in pairs(state.machines) do
        totalIn    = totalIn    + (m.totalIn    or 0)
        totalOut   = totalOut   + (m.totalOut   or 0)
        totalPlays = totalPlays + (m.totalPlays or 0)
        if m.online then online = online + 1 end
    end

    local result = {
        totalIn    = totalIn,
        totalOut   = totalOut,
        profit     = totalIn - totalOut,
        totalPlays = totalPlays,
        online     = online,
        total      = #Data.getAllMachines(),
    }

    for k, v in pairs(state.global) do
        result[k] = v
    end

    return result
end

return Data