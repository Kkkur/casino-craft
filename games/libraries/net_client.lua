-- ========================================================================== --
--  Casino Network Client
--  Handles manager registration, live hand reporting, and configuration sync.
-- ========================================================================== --

local Net = {}

local PROTOCOL     = "CASINO_NET"
local LOG_PROTOCOL = "CASINO_LOG"

local managerId    = nil
local gameType     = nil
local machineLabel = nil

-- -------------------------------------------------------------------------- --
-- Initialization
-- -------------------------------------------------------------------------- --

function Net.init(id, game, label)
    managerId    = id
    gameType     = game
    machineLabel = label or ("Machine#" .. os.getComputerID())
end

-- -------------------------------------------------------------------------- --
-- Messaging API
-- -------------------------------------------------------------------------- --

function Net.log(level, msg)
    local formattedMsg = "[" .. level .. "] " .. tostring(msg)
    print(formattedMsg)
    
    if managerId then
        rednet.send(managerId, {
            type = "log",
            line = "[" .. machineLabel .. "][" .. os.getComputerID() .. "] " .. formattedMsg,
        }, LOG_PROTOCOL)
    end
end

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

function Net.reportHand(result, bet, playerName)
    if not managerId then return end
    
    rednet.send(managerId, {
        type   = "hand_result",
        game   = gameType,
        player = playerName or "Guest",
        result = result,
        bet    = bet,
    }, PROTOCOL)
end

-- -------------------------------------------------------------------------- --
-- Listener Loop
-- -------------------------------------------------------------------------- --

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
                break
            end
        end
    end
end

return Net