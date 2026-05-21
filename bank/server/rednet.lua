-- bank/server/rednet.lua

local rednetHandler = {}

local profiles = dofile("/bank/server/profiles.lua")
local ledger   = dofile("/bank/server/ledger.lua")
local vault    = dofile("/bank/server/vault.lua")

local PROTOCOL = "bank_protocol"
local HOSTNAME = "bank_server"

-- security state
local _token     = nil
local _whitelist = {}         -- [computerID] = true
local _rates     = {}         -- [computerID] = { count, windowStart }
local _locked    = {}         -- [computerID] = unlockEpoch
local _alerts    = {}         -- list of { ts, msg }

local RATE_LIMIT    = 3       -- max requests per second
local LOCKOUT_SECS  = 10      -- auto unlock after this many seconds
local COIN_ITEM     = "createdeco:brass_coin"

-- called by init.lua after loading config
function rednetHandler.init(token, whitelist)
    _token     = token
    _whitelist = {}
    for _, id in ipairs(whitelist or {}) do
        _whitelist[id] = true
    end
end

function rednetHandler.addWhitelist(computerID)
    _whitelist[computerID] = true
end

function rednetHandler.removeWhitelist(computerID)
    _whitelist[computerID] = nil
end

function rednetHandler.getWhitelist()
    local list = {}
    for id in pairs(_whitelist) do
        table.insert(list, id)
    end
    return list
end

function rednetHandler.getAlerts()
    return _alerts
end

function rednetHandler.clearAlerts()
    _alerts = {}
end

local function pushAlert(msg)
    table.insert(_alerts, { ts = os.epoch("utc"), msg = msg })
    -- keep last 50 alerts
    while #_alerts > 50 do table.remove(_alerts, 1) end
end

local function autoUnlock(id)
    local unlockAt = _locked[id]
    if not unlockAt then return false end
    if os.epoch("utc") >= unlockAt then
        _locked[id] = nil
        _rates[id]  = nil
        return false
    end
    return true
end

local function checkRate(id)
    local now = os.epoch("utc")
    local r   = _rates[id]
    if not r then
        _rates[id] = { count = 1, windowStart = now }
        return true
    end
    -- reset window if more than 1 second has passed
    if now - r.windowStart >= 1000 then
        r.count       = 1
        r.windowStart = now
        return true
    end
    r.count = r.count + 1
    if r.count > RATE_LIMIT then
        return false
    end
    return true
end

local function validateRequest(senderId, msg)
    local id = msg.computerID

    -- must have a computerID field matching the actual sender
    if not id or id ~= senderId then
        ledger.recordSecurity("ID_MISMATCH", tostring(senderId))
        pushAlert("ID mismatch from sender " .. tostring(senderId))
        return false, "id_mismatch"
    end

    -- whitelist check
    if not _whitelist[id] then
        ledger.recordSecurity("NOT_WHITELISTED", tostring(id))
        pushAlert("Non-whitelisted machine: " .. tostring(id))
        return false, "not_whitelisted"
    end

    -- lockout check
    if autoUnlock(id) then
        ledger.recordSecurity("LOCKED_OUT", tostring(id))
        pushAlert("Locked machine attempted request: " .. tostring(id))
        return false, "locked"
    end

    -- token check
    if _token and msg.token ~= _token then
        ledger.recordSecurity("BAD_TOKEN", tostring(id))
        pushAlert("Bad token from machine: " .. tostring(id))
        return false, "bad_token"
    end

    -- rate limit check
    if not checkRate(id) then
        _locked[id] = os.epoch("utc") + (LOCKOUT_SECS * 1000)
        ledger.recordSecurity("RATE_LIMITED", tostring(id))
        pushAlert("Rate limit exceeded, locked machine: " .. tostring(id))
        return false, "rate_limited"
    end

    return true
end

local function reconcile()
    local sum            = profiles.sumAll()
    local ok, exp, act   = vault.reconcile(sum, COIN_ITEM)
    if not ok then
        ledger.recordReconcile(exp, act)
        pushAlert("RECONCILE FAIL: expected=" .. exp .. " actual=" .. act .. " delta=" .. (act - exp))
    end
end

local function handle(senderId, msg)
    local action = msg.action
    local player = msg.player
    local amount = msg.amount

    if action == "get" and player then
        local bal = profiles.getBalance(player)
        ledger.record(player, "get", nil, bal, bal)
        return { ok = true, balance = bal }

    elseif action == "add" and player and amount then
        local before = profiles.getBalance(player)
        local after  = profiles.add(player, amount)
        if not after then return { ok = false, err = "error" } end
        ledger.record(player, "add", amount, before, after)
        reconcile()
        return { ok = true, balance = after }

    elseif action == "remove" and player and amount then
        local before       = profiles.getBalance(player)
        local after, err   = profiles.remove(player, amount)
        if not after then return { ok = false, err = err or "insufficient" } end
        ledger.record(player, "remove", amount, before, after)
        reconcile()
        return { ok = true, balance = after }

    elseif action == "set" and player and amount then
        local before = profiles.getBalance(player)
        profiles.setBalance(player, amount)
        ledger.record(player, "set", amount, before, amount)
        reconcile()
        return { ok = true, balance = amount }

    elseif action == "top" then
        local list = profiles.top(msg.limit or 10)
        return { ok = true, top = list }

    else
        return { ok = false, err = "unknown_action" }
    end
end

function rednetHandler.run()
    peripheral.find("modem", rednet.open)
    rednet.host(PROTOCOL, HOSTNAME)
    print("[rednet] Listening as '" .. HOSTNAME .. "' on '" .. PROTOCOL .. "'")
    print("[rednet] Computer ID: " .. os.getComputerID())

    while true do
        local senderId, msg = rednet.receive(PROTOCOL)
        if type(msg) == "table" then
            local ok, reason = validateRequest(senderId, msg)
            if ok then
                local reply = handle(senderId, msg)
                rednet.send(senderId, reply, PROTOCOL)
            else
                rednet.send(senderId, { ok = false, err = reason }, PROTOCOL)
            end
        end
    end
end

return rednetHandler