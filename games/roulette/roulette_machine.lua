-- ========================================================================== --
--  Roulette Machine Controller
--  Coordinates the game loop, UI animations, barrel I/O, and manager netcode.
-- ========================================================================== --

local ROULETTE    = dofile("games/roulette/roulette.lua")
local ROULETTE_UI = dofile("games/roulette/roulette_ui.lua")
local Barrel      = dofile("games/libraries/barrel_handler.lua")
local Net         = dofile("games/libraries/net_client.lua")
local Det         = dofile("games/libraries/player_detector.lua")

-- -------------------------------------------------------------------------- --
-- Configuration & State
-- -------------------------------------------------------------------------- --

local CFG = {
    managerId          = nil,
    machineLabel       = "Roulette Wheel",
    betAmount          = 2,
    playerBarrelName   = nil,
    sharedBarrelName   = nil,
    playerDetectorName = nil,
    monitorName        = nil,
}

local shared = {
    queueChips = 0,
    playerName = nil, 
    gameActive = false,
    shutdown   = false,
}

-- -------------------------------------------------------------------------- --
-- Initialization
-- -------------------------------------------------------------------------- --

local function loadConfig()
    if not fs.exists("machine_config.txt") then 
        error("machine_config.txt missing! Please run bootstrap.lua first.")
    end
    
    local f = io.open("machine_config.txt", "r")
    if not f then return end
    
    for line in f:lines() do
        local k, v = line:match("^(.-)=(.+)$")
        if k then
            if k == "managerId"      then CFG.managerId         = tonumber(v) end
            if k == "monitorSide"    then CFG.monitorName       = v end
            if k == "playerBarrel"   then CFG.playerBarrelName  = v end
            if k == "sharedBarrel"   then CFG.sharedBarrelName  = v end
            if k == "playerDetector" then CFG.playerDetectorName = v end
            if k == "label"          then CFG.machineLabel      = v end
        end
    end
    f:close()
end

local function initPeripherals()
    assert(CFG.monitorName, "Missing monitorSide in machine_config.txt")
    assert(CFG.playerBarrelName, "Missing playerBarrel in machine_config.txt")
    assert(CFG.sharedBarrelName, "Missing sharedBarrel in machine_config.txt")

    local mon = peripheral.wrap(CFG.monitorName)
    assert(mon, "Monitor '" .. CFG.monitorName .. "' not found on the network.")
    
    ROULETTE_UI.init(mon)
    Barrel.init(CFG.playerBarrelName, CFG.sharedBarrelName)

    if CFG.playerDetectorName and CFG.playerDetectorName ~= "none" then
        Det.init(CFG.playerDetectorName)
    end

    local modem = peripheral.find("modem", function(_, m)
        return m.isWireless and m.isWireless()
    end)
    
    if modem and CFG.managerId then
        rednet.open(peripheral.getName(modem))
    end

    return mon
end

-- -------------------------------------------------------------------------- --
-- Helper Functions
-- -------------------------------------------------------------------------- --

local function getLiveTotalBet(state)
    local total = 0
    if type(state.bets) == "table" then
        for _, amt in pairs(state.bets) do
            if type(amt) == "number" then 
                total = total + amt 
            end
        end
    end
    return total
end

-- -------------------------------------------------------------------------- --
-- Background Listeners
-- -------------------------------------------------------------------------- --

local function coinListener()
    while not shared.shutdown do
        shared.queueChips = Barrel.countPlayerChips()
        os.sleep(0.25)
    end
end

local function playerListener()
    if not CFG.playerDetectorName or CFG.playerDetectorName == "none" then return end
    
    while not shared.shutdown do
        shared.playerName = Det.getClosestPlayer(5)
        os.sleep(0.5) 
    end
end

local function rednetListener()
    Net.listenForConfig(
        function(cfg)
            if cfg.betAmount    then CFG.betAmount    = cfg.betAmount    end
            if cfg.machineLabel then CFG.machineLabel = cfg.machineLabel end
        end,
        function()
            shared.shutdown = true
        end
    )
end

-- -------------------------------------------------------------------------- --
-- Main Game Loop
-- -------------------------------------------------------------------------- --

local function gameLoop()
    local gameState = ROULETTE.newGame(0, "CasinoGuest")
    local strip = ROULETTE_UI.getWheelStrip()
    local currentWheelIndex = 1

    local function refreshState()
        gameState.queueChips = shared.queueChips
        gameState.playerName = shared.playerName or "Guest"
        if gameState.balance ~= shared.queueChips then
            gameState.balance = shared.queueChips
        end
    end

    while not shared.shutdown do
        refreshState()
        ROULETTE_UI.draw(gameState)

        if gameState.phase == "spinning" then
            shared.gameActive = true
            
            local totalWagered = getLiveTotalBet(gameState)
            local verifiedBet  = Barrel.takeBet(totalWagered)
            
            -- Guard condition: rollback table execution if coin counting mismatched
            if verifiedBet < totalWagered then
                Net.log("warn", "Insufficient physical chips inside barrel mechanism.")
                ROULETTE.clearBets(gameState)
                gameState.phase = "betting"
                shared.gameActive = false
                goto continue
            end

            -- Locate target number on the physical wheel strip
            local targetIdx = 1
            for idx, val in ipairs(strip) do
                if val == gameState.winningNumber then 
                    targetIdx = idx 
                    break 
                end
            end

            local fullRotationsSteps = #strip * 2
            local distanceToTarget   = (targetIdx - currentWheelIndex) % #strip
            local totalSteps         = fullRotationsSteps + distanceToTarget

            -- Spin Animation Sequence
            for step = 1, totalSteps do
                gameState.spinTick = step
                currentWheelIndex  = (currentWheelIndex % #strip) + 1
                gameState.activeSpinNumber = strip[currentWheelIndex]
                
                refreshState()
                ROULETTE_UI.draw(gameState)

                -- Cinematic brake physics
                local stepsRemaining = totalSteps - step
                if stepsRemaining <= 15 then
                    local brakeFactor = 16 - stepsRemaining
                    os.sleep(0.04 + (brakeFactor * 0.03))
                else
                    os.sleep(0.04)
                end
            end

            -- Lock in final state
            currentWheelIndex = targetIdx
            gameState.activeSpinNumber = gameState.winningNumber
            
            ROULETTE.resolveGame(gameState)
            local netPayout = gameState.lastPayout or 0
            
            refreshState()
            ROULETTE_UI.draw(gameState)

            -- Dispatch payouts
            if netPayout > 0 then
                Barrel.returnToPlayer(netPayout)
            end

            -- Transmit telemetry
            local loggingName = shared.playerName or "Unknown"
            local logOutcome  = (netPayout > totalWagered) and "win" or ((netPayout == totalWagered) and "push" or "loss")
            
            Net.reportHand(logOutcome, totalWagered, loggingName)
            shared.gameActive = false

        else
            -- Betting phase touch monitoring
            local event, side, x, y = os.pullEvent()
            
            if event == "monitor_touch" then
                if gameState.phase == "results" then
                    ROULETTE.resetTable(gameState)
                else
                    local action = ROULETTE_UI.hitTest(x, y)
                    if action then
                        if action:sub(1, 4) == "bet:" then
                            ROULETTE.handleBetClick(gameState, action:sub(5), CFG.betAmount)
                        elseif action == "clear" then
                            ROULETTE.clearBets(gameState)
                        elseif action == "spin" then
                            if getLiveTotalBet(gameState) > 0 then
                                ROULETTE.startSpin(gameState)
                            end
                        end
                    end
                end
            elseif event == "timer" then
                -- Keeps the UI fresh for incoming players/chips while idle
                refreshState()
                ROULETTE_UI.draw(gameState)
            end
        end
        ::continue::
    end
end

-- -------------------------------------------------------------------------- --
-- Boot
-- -------------------------------------------------------------------------- --

local function main()
    math.randomseed(os.time())
    loadConfig()

    Net.init(CFG.managerId, "roulette", CFG.machineLabel)
    local mon = initPeripherals()

    mon.setBackgroundColor(colours.black)
    mon.clear()
    mon.setCursorPos(1, 1)
    mon.setTextColor(colours.yellow)
    mon.write("  Connecting to manager...")

    local cfg = Net.register()
    if cfg then
        if cfg.betAmount    then CFG.betAmount    = cfg.betAmount    end
        if cfg.machineLabel then CFG.machineLabel = cfg.machineLabel end
    end

    mon.setCursorPos(1, 2)
    mon.setTextColor(colours.lime)
    mon.write("  Ready! Game Type: Roulette")
    os.sleep(1)

    parallel.waitForAny(
        coinListener,
        playerListener, 
        gameLoop,
        rednetListener
    )
end

main()