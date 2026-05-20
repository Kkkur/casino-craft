-- net_client.lua
-- Handles all communication between a game machine and the casino manager.
--
-- How to use:
--   local Net = dofile("../libraries/net_client.lua")
--   Net.init(managerId, "blackjack", "Table #1")
--   Net.register()
--   Net.reportHand("win", 2, "Steve")
--   Net.listenForConfig(function(cfg) ... end)

local Net = {}

local PROTOCOL     = "CASINO_NET"
local LOG_PROTOCOL = "CASINO_LOG"

local managerId    = nil
local gameType     = nil
local machineLabel = nil

-- Call this once before anything else.
-- id is the manager computer ID, game is e.g. "blackjack", label is the machine name.
function Net.init(id, game, label)
    managerId    = id
    gameType     = game
    machineLabel = label
end

-- Logs a message to the terminal and also forwards it to the manager if connected.
function Net.log(level, msg)
    print("[" .. level .. "] " .. tostring(msg))
    if managerId then
        rednet.send(managerId, {
            type = "log",
            line = "[" .. (machineLabel or "?") .. "#" .. os.getComputerID() .. "] [" .. level .. "] " .. tostring(msg),
        }, LOG_PROTOCOL)
    end
end

-- Registers this machine with the manager and waits for a config response.
-- Returns the config table from the manager, or nil on timeout.
-- Optionally pass a winPercent to suggest to the manager.
function Net.register(winPercent)
    if not managerId then return nil end
    rednet.send(managerId, {
        type       = "register",
        game       = gameType,
        label      = machineLabel,
        winPercent = winPercent or 30,
    }, PROTOCOL)
    local sid, msg = rednet.receive(PROTOCOL, 10)
    if sid == managerId and type(msg) == "table" and msg.type == "config" then
        return msg
    end
    return nil
end

-- Reports the result of a completed hand/round to the manager.
-- result is one of: "win", "loss", "push", "blackjack"
-- bet is the chip count wagered, playerName is the player's username string.
function Net.reportHand(result, bet, playerName)
    if not managerId then return end
    rednet.send(managerId, {
        type   = "hand_result",
        game   = gameType,
        player = playerName or "Unknown",
        result = result,
        bet    = bet,
    }, PROTOCOL)
end

-- Blocking listener loop, runs as a parallel thread.
-- onConfig is a callback function(cfg) called whenever the manager sends new config.
-- onShutdown is an optional callback called if the manager sends a shutdown message.
-- Run this with parallel.waitForAny alongside your game loop.

function Net.listenForConfig(onConfig, onShutdown)
    if not managerId then
        while true do os.sleep(5) end
    end
    while true do
        local sid, msg = rednet.receive(PROTOCOL, 2)
        if sid == managerId and type(msg) == "table" then
            if msg.type == "config" and onConfig then
                onConfig(msg)
            elseif msg.type == "shutdown" and onShutdown then
                onShutdown()
                return
            end
        end
    end
end

return Net