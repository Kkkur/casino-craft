-- bank/server/casino_net.lua
-- Handles the CASINO_NET protocol on the bank server computer.
-- Runs as a parallel thread alongside bank/server/rednet.lua.
-- Both share the same wireless modem; rednet multiplexes by protocol so
-- there is no collision (bank uses "bank_protocol", casino uses "CASINO_NET").
--
-- Persistent state lives in casino_data.json:
--   machines: table keyed by computer ID string, each entry:
--     { id, label, game, rigFactor, plays, chipsIn, chipsOut, online, lastSeen }
--   net_chips: cumulative house profit in chips, all-time across reboots
--
-- Loss prevention:
--   panicBelow    (default -200): if net_chips drops below this, enter panic
--   recoveryAbove (default  300): if net_chips rises above this while in panic, exit
--   In panic: every machine gets rigFactor=1.0 pushed to it immediately.
--   On recovery: each machine gets its stored rigFactor pushed back.

local casinoNet = {}

local PROTOCOL       = "CASINO_NET"
local DATA_FILE      = "casino_data.json"
local DEFAULT_PANIC  = -200
local DEFAULT_RECOV  =  300

-- injected via casinoNet.init()
local _log           = nil
local _panicBelow    = DEFAULT_PANIC
local _recoveryAbove = DEFAULT_RECOV

-- runtime state
local _machines      = {}   -- keyed by tostring(id)
local _netChips      = 0
local _inPanic       = false

-- -------------------------------------------------------------------------- --
-- Persistence
-- -------------------------------------------------------------------------- --

local function saveData()
    local data = {
        machines  = _machines,
        net_chips = _netChips,
    }
    local f = fs.open(DATA_FILE, "w")
    if not f then
        if _log then _log.error("[CasinoNet] Cannot write " .. DATA_FILE) end
        return
    end
    f.write(textutils.serialiseJSON(data))
    f.close()
end

local function loadData()
    if not fs.exists(DATA_FILE) then return end
    local f = fs.open(DATA_FILE, "r")
    if not f then return end
    local raw  = f.readAll()
    f.close()
    local data = textutils.unserialiseJSON(raw)
    if not data then
        if _log then _log.warn("[CasinoNet] Corrupt " .. DATA_FILE .. ", starting fresh.") end
        return
    end
    _machines = data.machines  or {}
    _netChips = data.net_chips or 0
    if _log then
        _log.info("[CasinoNet] Loaded casino_data.json. net_chips=" .. _netChips
            .. " machines=" .. (function()
                local n = 0
                for _ in pairs(_machines) do n = n + 1 end
                return n
            end)())
    end
end

-- -------------------------------------------------------------------------- --
-- Loss prevention
-- -------------------------------------------------------------------------- --

local function pushConfig(id, machine)
    local rf = _inPanic and 1.0 or (machine.rigFactor or 0.7)
    rednet.send(id, {
        type      = "config",
        id        = id,
        rigFactor = rf,
    }, PROTOCOL)
    if _log then
        _log.info("[CasinoNet] Pushed rigFactor=" .. rf .. " to machine " .. tostring(id))
    end
end

local function enterPanic()
    if _inPanic then return end
    _inPanic = true
    if _log then _log.warn("[CasinoNet] ENTERING PANIC. net_chips=" .. _netChips) end
    for key, machine in pairs(_machines) do
        if machine.online then
            pushConfig(tonumber(key), machine)
        end
    end
end

local function exitPanic()
    if not _inPanic then return end
    _inPanic = false
    if _log then _log.info("[CasinoNet] Exiting panic. net_chips=" .. _netChips) end
    for key, machine in pairs(_machines) do
        if machine.online then
            pushConfig(tonumber(key), machine)
        end
    end
end

local function checkThresholds()
    if not _inPanic and _netChips < _panicBelow then
        enterPanic()
    elseif _inPanic and _netChips >= _recoveryAbove then
        exitPanic()
    end
end

-- -------------------------------------------------------------------------- --
-- Handlers
-- -------------------------------------------------------------------------- --

local function handleRegister(senderId, msg)
    local key     = tostring(senderId)
    local existing = _machines[key]
    _machines[key] = {
        id        = senderId,
        label     = msg.label     or (existing and existing.label)     or "Unknown",
        game      = msg.game      or (existing and existing.game)      or "unknown",
        rigFactor = msg.rigFactor or (existing and existing.rigFactor) or 0.7,
        plays     = existing and existing.plays    or 0,
        chipsIn   = existing and existing.chipsIn  or 0,
        chipsOut  = existing and existing.chipsOut or 0,
        online    = true,
        lastSeen  = os.epoch("utc"),
    }
    saveData()

    -- Reply with config: panic overrides rigFactor if active
    local replyRF = _inPanic and 1.0 or _machines[key].rigFactor
    rednet.send(senderId, {
        type      = "register_ack",
        id        = senderId,
        rigFactor = replyRF,
    }, PROTOCOL)

    if _log then
        _log.info("[CasinoNet] Registered machine " .. tostring(senderId)
            .. " label='" .. _machines[key].label .. "'"
            .. " rigFactor=" .. replyRF
            .. (_inPanic and " (PANIC)" or ""))
    end
end

local function handleHandResult(senderId, msg)
    local key     = tostring(senderId)
    local machine = _machines[key]
    if not machine then
        -- Machine registered before we booted; create a stub entry
        _machines[key] = {
            id = senderId, label = "Unknown", game = "unknown",
            rigFactor = 0.7, plays = 0, chipsIn = 0, chipsOut = 0,
            online = true, lastSeen = os.epoch("utc"),
        }
        machine = _machines[key]
    end

    local bet    = tonumber(msg.bet)    or 0
    local payout = tonumber(msg.payout) or 0
    local profit = bet - payout   -- positive = house gained, negative = house lost

    machine.plays    = machine.plays   + 1
    machine.chipsIn  = machine.chipsIn  + bet
    machine.chipsOut = machine.chipsOut + payout
    machine.lastSeen = os.epoch("utc")
    _netChips        = _netChips + profit

    saveData()
    checkThresholds()

    rednet.send(senderId, {
        type = "hand_result_ack",
        id   = senderId,
    }, PROTOCOL)

    if _log then
        _log.info("[CasinoNet] hand_result from " .. tostring(senderId)
            .. " result=" .. tostring(msg.result)
            .. " bet=" .. bet .. " payout=" .. payout
            .. " profit=" .. profit
            .. " net_chips=" .. _netChips)
    end
end

local function handlePing(senderId)
    local key = tostring(senderId)
    if _machines[key] then
        _machines[key].lastSeen = os.epoch("utc")
        _machines[key].online   = true
    end
    rednet.send(senderId, { type = "pong", id = senderId }, PROTOCOL)
end

-- handleMessage: forward a server-authored message to one or all machines.
-- msg.target = "all" broadcasts to all online machines.
-- msg.target = <id number> sends to that specific machine.
local function handleMessage(senderId, msg)
    local payload = {
        type     = "message",
        title    = msg.title    or "Server",
        msg      = msg.msg      or "",
        color    = msg.color    or "gold",
        duration = msg.duration,
    }
    if msg.target == "all" then
        for key, machine in pairs(_machines) do
            if machine.online then
                rednet.send(tonumber(key), payload, PROTOCOL)
            end
        end
        if _log then _log.info("[CasinoNet] Broadcast message to all online machines.") end
    else
        local targetId = tonumber(msg.target)
        if targetId then
            rednet.send(targetId, payload, PROTOCOL)
            if _log then _log.info("[CasinoNet] Sent message to machine " .. tostring(targetId)) end
        end
    end
    -- ack back to the sender (could be a CLI command or admin tool)
    rednet.send(senderId, { type = "ack" }, PROTOCOL)
end

-- -------------------------------------------------------------------------- --
-- Public accessors (used by monitor.lua for the casino dashboard)
-- -------------------------------------------------------------------------- --

function casinoNet.getMachines()  return _machines  end
function casinoNet.getNetChips()  return _netChips  end
function casinoNet.isInPanic()    return _inPanic   end
function casinoNet.getPanicBelow()    return _panicBelow    end
function casinoNet.getRecoveryAbove() return _recoveryAbove end

-- -------------------------------------------------------------------------- --
-- Init and run
-- -------------------------------------------------------------------------- --

function casinoNet.init(cfg, logger)
    _log          = logger
    _panicBelow   = (cfg and cfg.panicBelow)    or DEFAULT_PANIC
    _recoveryAbove = (cfg and cfg.recoveryAbove) or DEFAULT_RECOV

    loadData()

    -- Mark all previously-online machines as offline until they re-register
    for _, machine in pairs(_machines) do
        machine.online = false
    end

    -- Re-enter panic if net_chips was already below threshold before reboot
    if _netChips < _panicBelow then
        _inPanic = true
        if _log then
            _log.warn("[CasinoNet] Resuming panic state on boot. net_chips=" .. _netChips)
        end
    end

    if _log then
        _log.info("[CasinoNet] Init complete."
            .. " panicBelow=" .. _panicBelow
            .. " recoveryAbove=" .. _recoveryAbove
            .. " inPanic=" .. tostring(_inPanic))
    end
end

function casinoNet.run()
    -- Modem is already opened by rednet.lua; no need to open again.
    if _log then _log.info("[CasinoNet] Listening on protocol '" .. PROTOCOL .. "'") end

    -- Periodic online/offline timeout: mark machines offline if not seen in 30s
    local heartbeatTimer = os.startTimer(15)
    local OFFLINE_AFTER  = 30000  -- ms

    while true do
        local ev, p1, p2, p3 = os.pullEvent()

        if ev == "rednet_message" then
            local senderId = p1
            local msg      = p2
            local protocol = p3

            -- Only handle CASINO_NET messages; bank_protocol messages are
            -- handled by rednet.lua and will also appear here as rednet_message.
            if protocol == PROTOCOL and type(msg) == "table" then
                local t = msg.type

                if t == "register" then
                    handleRegister(senderId, msg)

                elseif t == "hand_result" then
                    handleHandResult(senderId, msg)

                elseif t == "ping" then
                    handlePing(senderId)

                elseif t == "message" then
                    handleMessage(senderId, msg)

                elseif t == "ack" then
                    -- machine acknowledged a config push, nothing to do
                else
                    if _log then
                        _log.warn("[CasinoNet] Unknown message type '" .. tostring(t)
                            .. "' from " .. tostring(senderId))
                    end
                end
            end

        elseif ev == "timer" and p1 == heartbeatTimer then
            local now = os.epoch("utc")
            for _, machine in pairs(_machines) do
                if machine.online and (now - machine.lastSeen) > OFFLINE_AFTER then
                    machine.online = false
                    if _log then
                        _log.info("[CasinoNet] Machine " .. tostring(machine.id)
                            .. " marked offline (no heartbeat).")
                    end
                end
            end
            heartbeatTimer = os.startTimer(15)
        end
    end
end

return casinoNet