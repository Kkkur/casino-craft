-- bank/server/rednet.lua

local rednetHandler = {}

local profiles = dofile("/bank/server/profiles.lua")
local ledger   = dofile("/bank/server/ledger.lua")
local vault    = nil   -- injected via init() — must use the already-initialised instance

local PROTOCOL = "bank_protocol"
local HOSTNAME = "bank_server"

-- security state
local _token     = nil
local _whitelist = {}
local _rates     = {}
local _locked    = {}
local _alerts    = {}
local _log       = nil   -- logger injected from init.lua

local RATE_LIMIT   = 3
local LOCKOUT_SECS = 10
local COIN_ITEM    = "createdeco:brass_coin"

local function L() return _log end

function rednetHandler.init(token, whitelist, logger, vaultMod)
    _token   = token
    _log     = logger
    vault    = vaultMod
    _whitelist = {}
    for _, id in ipairs(whitelist or {}) do
        _whitelist[id] = true
    end
    if _log then
        _log.info("Rednet: token=" .. (token and "set" or "none")
            .. " whitelist=" .. #(whitelist or {}) .. " IDs")
    end
end

function rednetHandler.addWhitelist(computerID)
    _whitelist[computerID] = true
    if _log then _log.info("Whitelist: added ID " .. tostring(computerID)) end
end

function rednetHandler.removeWhitelist(computerID)
    _whitelist[computerID] = nil
    if _log then _log.info("Whitelist: removed ID " .. tostring(computerID)) end
end

function rednetHandler.getWhitelist()
    local list = {}
    for id in pairs(_whitelist) do table.insert(list, id) end
    return list
end

function rednetHandler.getAlerts() return _alerts end

function rednetHandler.clearAlerts()
    _alerts = {}
    if _log then _log.info("Security alerts cleared by admin") end
end

local function pushAlert(msg)
    if _log then _log.warn("ALERT: " .. msg) end
    table.insert(_alerts, { ts = os.epoch("utc"), msg = msg })
    while #_alerts > 50 do table.remove(_alerts, 1) end
end

local function autoUnlock(id)
    local unlockAt = _locked[id]
    if not unlockAt then return false end
    if os.epoch("utc") >= unlockAt then
        _locked[id] = nil
        _rates[id]  = nil
        if _log then _log.info("Rate lock expired, auto-unlocked ID " .. tostring(id)) end
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
    if now - r.windowStart >= 1000 then
        r.count = 1
        r.windowStart = now
        return true
    end
    r.count = r.count + 1
    return r.count <= RATE_LIMIT
end

local function validateRequest(senderId, msg)
    local id = msg.computerID

    if not id or id ~= senderId then
        ledger.recordSecurity("ID_MISMATCH", tostring(senderId))
        pushAlert("ID mismatch: claimed=" .. tostring(id) .. " actual=" .. tostring(senderId))
        return false, "id_mismatch"
    end

    if not _whitelist[id] then
        ledger.recordSecurity("NOT_WHITELISTED", tostring(id))
        pushAlert("Non-whitelisted machine: " .. tostring(id))
        return false, "not_whitelisted"
    end

    if autoUnlock(id) then
        ledger.recordSecurity("LOCKED_OUT", tostring(id))
        pushAlert("Locked machine attempted request: " .. tostring(id))
        return false, "locked"
    end

    if _token and msg.token ~= _token then
        ledger.recordSecurity("BAD_TOKEN", tostring(id))
        pushAlert("Bad token from machine: " .. tostring(id))
        return false, "bad_token"
    end

    if not checkRate(id) then
        _locked[id] = os.epoch("utc") + (LOCKOUT_SECS * 1000)
        ledger.recordSecurity("RATE_LIMITED", tostring(id))
        pushAlert("Rate limit exceeded, locked machine: " .. tostring(id))
        return false, "rate_limited"
    end

    return true
end

local function reconcile()
    local sum          = profiles.sumAll()
    local ok, exp, act = vault.reconcile(sum, COIN_ITEM)
    if not ok then
        ledger.recordReconcile(exp, act)
        pushAlert("RECONCILE FAIL: expected=" .. exp .. " actual=" .. act .. " delta=" .. (act - exp))
    else
        if _log then _log.debug("Reconcile OK. coins=" .. act) end
    end
end

local function handle(senderId, msg)
    local action = msg.action
    local player = msg.player
    local amount = msg.amount

    if _log then
        _log.debug("Request from ID " .. tostring(senderId)
            .. " action=" .. tostring(action)
            .. " player=" .. tostring(player)
            .. " amount=" .. tostring(amount))
    end

    if action == "ping" then
        return { ok = true, pong = true }

    elseif action == "get" and player then
        local bal = profiles.getBalance(player)
        ledger.record(player, "get", nil, bal, bal)
        return { ok = true, balance = bal }

    elseif action == "add" and player and amount then
        local before = profiles.getBalance(player)
        local after  = profiles.add(player, amount)
        if not after then return { ok = false, err = "error" } end
        ledger.record(player, "add", amount, before, after)
        if _log then _log.info("add " .. tostring(amount) .. " → " .. player .. " balance=" .. after) end
        reconcile()
        return { ok = true, balance = after }

    elseif action == "remove" and player and amount then
        local before     = profiles.getBalance(player)
        local after, err = profiles.remove(player, amount)
        if not after then
            if _log then _log.warn("remove " .. tostring(amount) .. " from " .. player .. " FAILED: " .. tostring(err)) end
            return { ok = false, err = err or "insufficient" }
        end
        ledger.record(player, "remove", amount, before, after)
        if _log then _log.info("remove " .. tostring(amount) .. " → " .. player .. " balance=" .. after) end
        reconcile()
        return { ok = true, balance = after }

    elseif action == "set" and player and amount then
        local before = profiles.getBalance(player)
        profiles.setBalance(player, amount)
        ledger.record(player, "set", amount, before, amount)
        if _log then _log.info("set " .. player .. " balance=" .. amount .. " (was " .. before .. ")") end
        reconcile()
        return { ok = true, balance = amount }

    elseif action == "top" then
        local list = profiles.top(msg.limit or 10)
        return { ok = true, top = list }

    else
        if _log then _log.warn("Unknown action '" .. tostring(action) .. "' from ID " .. tostring(senderId)) end
        return { ok = false, err = "unknown_action" }
    end
end

function rednetHandler.run()
    peripheral.find("modem", rednet.open)
    pcall(rednet.unhost, PROTOCOL)
    rednet.host(PROTOCOL, HOSTNAME)
    if _log then
        _log.info("Listening as '" .. HOSTNAME .. "' on '" .. PROTOCOL .. "'")
        _log.info("Computer ID: " .. os.getComputerID())
    end

    -- Actions that are public read-only and skip auth entirely
    local PUBLIC_ACTIONS = { top = true }

    while true do
        local senderId, msg = rednet.receive(PROTOCOL)
        if type(msg) == "table" then
            if _log then _log.net("RECV", senderId, PROTOCOL, msg.action or "?") end

            local reply
            if PUBLIC_ACTIONS[msg.action] then
                -- no auth required for public reads
                reply = handle(senderId, msg)
            else
                local ok, reason = validateRequest(senderId, msg)
                if ok then
                    reply = handle(senderId, msg)
                else
                    if _log then _log.warn("Rejected ID " .. tostring(senderId) .. ": " .. tostring(reason)) end
                    reply = { ok = false, err = reason }
                end
            end

            rednet.send(senderId, reply, PROTOCOL)
            if _log then _log.net("SEND", senderId, PROTOCOL, reply.ok and "ok" or "err:" .. tostring(reply.err)) end
        end
    end
end

return rednetHandler