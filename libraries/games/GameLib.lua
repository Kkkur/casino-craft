-- libraries/games/GameLib.lua
-- Shared infrastructure for all casino game machines.
-- Owns: config parsing, peripheral init, bank connection, machine registration,
-- hand reporting, server push listener, and session lifecycle.

local GameLib = {}

local CASINO_NET     = "CASINO_NET"
local CONNECT_SLEEP  = 2    -- seconds between bank connect retries
local REG_TIMEOUT    = 30   -- seconds to wait for registration ack
local REPORT_RETRIES = 2    -- hand report retries before giving up

-- -------------------------------------------------------------------------- --
-- Config
-- -------------------------------------------------------------------------- --

-- loadConfig(path)
-- Parses a key=value text file. Values that look like numbers are kept as
-- numbers; everything else is a string. Booleans "true"/"false" are converted.
-- Returns a table. Empty or missing file returns {}.
function GameLib.loadConfig(path)
    local cfg = {}
    if not fs.exists(path) then return cfg end
    local f = io.open(path, "r")
    if not f then return cfg end
    for line in f:lines() do
        local k, v = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
        if k and k ~= "" and v ~= nil then
            if v == "true"  then cfg[k] = true
            elseif v == "false" then cfg[k] = false
            else
                local n = tonumber(v)
                cfg[k] = n ~= nil and n or v
            end
        end
    end
    f:close()
    return cfg
end

-- -------------------------------------------------------------------------- --
-- Peripheral init
-- -------------------------------------------------------------------------- --

-- initPeripherals(cfg)
-- Wraps the GPU peripheral, initialises PDLib, opens the wireless modem.
-- cfg fields used: monitorSide, detectorSide
-- Returns gpu peripheral (the raw peripheral object).
-- Errors hard if the GPU cannot be found.
function GameLib.initPeripherals(cfg)
    -- GPU
    local gpu
    if cfg.monitorSide and cfg.monitorSide ~= "" then
        gpu = peripheral.wrap(cfg.monitorSide)
    end
    if not gpu then
        gpu = peripheral.find("gpu")
    end
    assert(gpu and gpu.refreshSize, "[GameLib] GPU peripheral not found. Check monitorSide in machine_config.txt.")

    -- Player detector
    local PDLib = dofile("/libraries/games/PDLib.lua")
    PDLib.init(cfg.detectorSide or "")

    -- Wireless modem
    peripheral.find("modem", function(name, m)
        if m.isWireless and m.isWireless() then
            rednet.open(name)
            return true
        end
    end)

    return gpu, PDLib
end

-- -------------------------------------------------------------------------- --
-- Bank connection
-- -------------------------------------------------------------------------- --

-- connectBank(bank, ui, sw, sh, logger)
-- Retries BankLib.connect() forever with a 2-second delay between attempts.
-- Draws a simple "Connecting..." message on the GPU while waiting.
-- Returns nothing (blocks until connected).
function GameLib.connectBank(bank, ui, sw, sh, logger)
    local attempt = 0
    while true do
        local ok, err = bank.connect()
        if ok then
            if logger then logger.info("[GameLib] Bank connected.") end
            return
        end
        attempt = attempt + 1
        if logger then logger.warn("[GameLib] Bank connect failed (" .. tostring(err) .. "), attempt " .. attempt) end
        if ui and sw and sh then
            ui:clear(0x000000)
            ui:textCentered(0, math.floor(sh/2) - 8, sw, "Connecting to bank...", 0xC9A84C, 0x000000, 1)
            ui:textCentered(0, math.floor(sh/2) + 4, sw, "Attempt " .. attempt,   0x888888, 0x000000, 1)
            ui:sync()
        end
        os.sleep(CONNECT_SLEEP)
    end
end

-- -------------------------------------------------------------------------- --
-- Registration
-- -------------------------------------------------------------------------- --

-- register(cfg, rigFactor, logger)
-- Sends a register message on CASINO_NET and waits up to REG_TIMEOUT seconds
-- for a config reply. Returns the rigFactor to use (from server if provided,
-- else the local cfg value). On timeout returns the local value and continues
-- in degraded mode (no stats reporting will work, but the game runs).
--
-- cfg fields used: machineLabel (string), game (string)
-- rigFactor: the local default (number, e.g. 0.7)
function GameLib.register(cfg, rigFactor, logger)
    local label = cfg.machineLabel or "Unknown Machine"
    local game  = cfg.game         or "unknown"
    local myID  = os.getComputerID()

    rednet.broadcast({
        type      = "register",
        id        = myID,
        game      = game,
        label     = label,
        rigFactor = rigFactor,
    }, CASINO_NET)

    if logger then logger.info("[GameLib] Registration sent as '" .. label .. "'") end

    local deadline = os.startTimer(REG_TIMEOUT)
    while true do
        local ev, p1, p2 = os.pullEvent()
        if ev == "rednet_message" and type(p2) == "table"
        and p2.type == "register_ack" and p2.id == myID then
            os.cancelTimer(deadline)
            -- ack may carry a panic rigFactor from the server
            local rf = p2.rigFactor or rigFactor
            if logger then logger.info("[GameLib] Registered. rigFactor=" .. tostring(rf)) end
            -- send our own ack back so the server knows we got it
            rednet.send(p1, { type = "ack", id = myID }, CASINO_NET)
            return rf
        elseif ev == "timer" and p1 == deadline then
            if logger then logger.warn("[GameLib] Registration timeout, running in degraded mode.") end
            return rigFactor
        end
    end
end

-- -------------------------------------------------------------------------- --
-- Hand reporting
-- -------------------------------------------------------------------------- --

-- reportHand(player, result, bet, payout, logger)
-- Sends a hand_result message to whoever we registered with (broadcast on
-- CASINO_NET). Retries up to REPORT_RETRIES times on timeout, then gives up
-- silently so a dead server never freezes mid-hand.
--
-- result: "win" | "loss" | "push" | "blackjack"
-- bet: integer chips wagered
-- payout: integer chips paid back to player (0 for loss)
function GameLib.reportHand(player, result, bet, payout, logger)
    local myID = os.getComputerID()
    local msg  = {
        type    = "hand_result",
        id      = myID,
        player  = player or "Unknown",
        result  = result,
        bet     = bet    or 0,
        payout  = payout or 0,
    }

    for attempt = 1, REPORT_RETRIES + 1 do
        rednet.broadcast(msg, CASINO_NET)
        local timer = os.startTimer(3)
        while true do
            local ev, p1, p2 = os.pullEvent()
            if ev == "rednet_message" and type(p2) == "table"
            and p2.type == "hand_result_ack" and p2.id == myID then
                os.cancelTimer(timer)
                return true
            elseif ev == "timer" and p1 == timer then
                if logger then
                    logger.warn("[GameLib] reportHand timeout (attempt " .. attempt .. ")")
                end
                break
            end
        end
        if attempt > REPORT_RETRIES then break end
    end

    if logger then logger.warn("[GameLib] reportHand gave up after retries") end
    return false
end

-- -------------------------------------------------------------------------- --
-- Server push listener thread
-- -------------------------------------------------------------------------- --

-- netListener(shared, ui, bank, getCurrentBet, logger)
-- Runs as a parallel thread alongside the game loop.
-- Handles inbound CASINO_NET pushes from the server:
--   {type="config", rigFactor=...}      -- update rig factor live
--   {type="message", ...}               -- show blocking overlay, refund bet if active
--   {type="clear_message"}              -- dismiss overlay
--   {type="shutdown"}                   -- set shared.shutdown
--
-- shared:       table with at least { shutdown=false, rigFactor=number }
-- ui:           UILib instance
-- bank:         BankLib module (for mid-hand refunds)
-- getCurrentBet(): callable that returns the current active bet (0 if none)
-- logger:       optional logger module
function GameLib.netListener(shared, ui, bank, getCurrentBet, logger)
    local myID = os.getComputerID()

    while not shared.shutdown do
        local ev, senderId, msg = os.pullEvent("rednet_message")
        if type(msg) ~= "table" then goto continue end
        -- Only handle CASINO_NET pushes (BankLib uses bank_protocol).
        -- rednet_message does not carry the protocol in CC, so we use msg.type
        -- to distinguish; bank replies never have a casino-style type field.
        local t = msg.type
        if not t then goto continue end

        if t == "config" then
            if msg.rigFactor ~= nil then
                shared.rigFactor = msg.rigFactor
                if logger then logger.info("[GameLib] rigFactor updated to " .. tostring(msg.rigFactor)) end
            end
            rednet.send(senderId, { type = "ack", id = myID }, CASINO_NET)

        elseif t == "message" then
            -- Refund any in-progress bet before blocking the UI.
            local activeBet = getCurrentBet and getCurrentBet() or 0
            if activeBet > 0 and shared.currentPlayer then
                bank.add(shared.currentPlayer, activeBet, "game")
                shared.betRefunded = true
            end
            ui:showMessage(
                msg.title    or "Server Message",
                msg.msg      or "",
                msg.color    or "gold",
                msg.duration
            )
            rednet.send(senderId, { type = "ack", id = myID }, CASINO_NET)

        elseif t == "clear_message" then
            ui:clearOverlay()
            rednet.send(senderId, { type = "ack", id = myID }, CASINO_NET)

        elseif t == "shutdown" then
            shared.shutdown = true
            if logger then logger.info("[GameLib] Shutdown command received from server.") end
            rednet.send(senderId, { type = "ack", id = myID }, CASINO_NET)
        end

        ::continue::
    end
end

return GameLib