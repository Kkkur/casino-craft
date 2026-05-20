-- rednet_manager.lua
-- Handles all wireless communication with slot machines

local Net = {}

-- Protocol name 
Net.PROTOCOL = "CASINO_NET"

Net.MSG = {
    PING        = "ping",        -- check if machine is alive
    SET_CONFIG  = "set_config",  -- update machine settings
    GET_STATS   = "get_stats",   -- request machine stats
    ENABLE      = "enable",      -- enable machine
    DISABLE     = "disable",     -- disable machine
    RESET_STATS = "reset_stats", -- clear machine counters
}

Net.EVT = {
    PONG        = "pong",        -- alive response
    PLAY_RESULT = "play_result", -- a play was made
    STATS       = "stats",       -- stat report
    REGISTER    = "register",    -- machine announcing itself
    ERROR       = "error",       -- machine error
}

-- Open the modem 
function Net.open(side)
    if side then
        rednet.open(side)
        return true
    end
    -- Autodetect wireless modem
    local sides = { "top", "bottom", "left", "right", "front", "back" }
    for _, s in ipairs(sides) do
        if peripheral.getType(s) == "modem" then
            local m = peripheral.wrap(s)
            if m and m.isWireless and m.isWireless() then
                rednet.open(s)
                return true
            end
        end
    end
    return false
end

function Net.send(id, msgType, payload)
    local msg = {
        type    = msgType,
        payload = payload or {},
        time    = os.time(),
    }
    rednet.send(id, msg, Net.PROTOCOL)
end

function Net.broadcast(msgType, payload)
    local msg = {
        type    = msgType,
        payload = payload or {},
        time    = os.time(),
    }
    rednet.broadcast(msg, Net.PROTOCOL)
end

function Net.receive(timeout)
    local id, msg = rednet.receive(Net.PROTOCOL, timeout)
    if id == nil then return nil, nil end
    return id, msg
end

function Net.ping(id, timeout)
    timeout = timeout or 3
    Net.send(id, Net.MSG.PING, {})
    local sender, msg = Net.receive(timeout)
    if sender == id and msg and msg.type == Net.EVT.PONG then
        return true
    end
    return false
end

-- Send config update to a machine
-- config: { winPercent, enabled, label, ... }
function Net.sendConfig(id, config)
    Net.send(id, Net.MSG.SET_CONFIG, config)
end

-- Request stats from a machine
function Net.requestStats(id)
    Net.send(id, Net.MSG.GET_STATS, {})
end

-- Ping all known machines and return a table 
function Net.pingAll(ids, timeout)
    timeout = timeout or 2
    local results = {}
    -- Send all pings first
    for _, id in ipairs(ids) do
        Net.send(id, Net.MSG.PING, {})
        results[id] = false
    end
    -- Collect responses within timeout
    local deadline = os.clock() + timeout
    local remaining = #ids
    while remaining > 0 and os.clock() < deadline do
        local sender, msg = Net.receive(deadline - os.clock())
        if sender and msg and msg.type == Net.EVT.PONG then
            if results[sender] == false then
                results[sender] = true
                remaining = remaining - 1
            end
        end
    end
    return results
end

return Net
