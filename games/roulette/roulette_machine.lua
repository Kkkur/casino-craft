-- Main roulette machine logic. Runs the game loop, handles wheel animations,
-- and coordinates with the manager via net_client, barrel_handler, and player_detector.

local ROULETTE    = dofile("games/roulette/roulette.lua")
local ROULETTE_UI = dofile("games/roulette/roulette_ui.lua")
local Barrel      = dofile("games/libraries/barrel_handler.lua")
local Net         = dofile("games/libraries/net_client.lua")
local Det         = dofile("games/libraries/player_detector.lua")

-- Dynamic configuration populated entirely by machine_config.txt or the manager server
local CFG = {
    managerId          = nil,
    machineLabel       = "Roulette Wheel",  -- Fallback text used until network registration syncs
    betAmount          = 2,                 -- Fallback value for base chip values
    playerBarrelName   = nil,
    sharedBarrelName   = nil,
    playerDetectorName = nil,
    monitorName        = nil,
}

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

local shared = {
    queueChips = 0,
    playerName = nil, 
    gameActive = false,
    shutdown   = false,
}

local function initPeripherals()
    -- Ensure required peripherals were supplied by the bootstrap file
    assert(CFG.monitorName, "Critical Configuration Error: monitorSide is missing from machine_config.txt")
    assert(CFG.playerBarrelName, "Critical Configuration Error: playerBarrel is missing from machine_config.txt")
    assert(CFG.sharedBarrelName, "Critical Configuration Error: sharedBarrel is missing from machine_config.txt")

    local mon = peripheral.wrap(CFG.monitorName)
    assert(mon, "Peripheral Error: Monitor '" .. CFG.monitorName .. "' could not be found on the network.")
    ROULETTE_UI.init(mon)

    Barrel.init(CFG.playerBarrelName, CFG.sharedBarrelName)

    -- Player detector configuration is optional or can be explicitly skipped by setting it to "none"
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

local function coinListener()
    while not shared.shutdown do
        shared.queueChips = Barrel.countPlayerChips()
        os.sleep(0.25)
    end
end

local function playerListener()
    if not CFG.playerDetectorName or CFG.playerDetectorName == "none" then return end
    
    while not shared.shutdown do
        local currentUser = Det.getClosestPlayer(5)
        shared.playerName = currentUser
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

local function gameLoop()
    -- Instantiate roulette data components
    -- Note: UI libraries are now fed through uiState models containing bankrolls and radar tracking
    local gameState = ROULETTE.newGame(0, "CasinoGuest")
    local strip = ROULETTE_UI.getWheelStrip()
    local currentWheelIndex = 1

    local function refreshState()
        gameState.queueChips = shared.queueChips
        gameState.playerName = shared.playerName or "Guest"
        -- Keep fallback internal limits tied together
        if gameState.balance ~= shared.queueChips then
            gameState.balance = shared.queueChips
        end
    end

    while not shared.shutdown do
        refreshState()
        ROULETTE_UI.draw(gameState)

        if gameState.phase == "spinning" then
            shared.gameActive = true
            
            -- Extract total cumulative wagers committed on the board Layout Matrix before clearing
            local totalWagered = ROULETTE.getTotalBet(gameState) or 0
            
            -- Handle exact token mechanics via barrel wrappers
            local verifiedBet = Barrel.takeBet(totalWagered)
            
            if verifiedBet < totalWagered then
                -- Guard condition: rollback table execution if coin counting mismatched
                Net.log("warn", "Insufficent raw physical inventory chips inside barrel mechanism.")
                ROULETTE.clearBets(gameState)
                gameState.phase = "betting"
                shared.gameActive = false
                goto continue
            end

            -- Find where the target winning number sits on the wheel array
            local targetIdx = 1
            for idx, val in ipairs(strip) do
                if val == gameState.winningNumber then 
                    targetIdx = idx 
                    break 
                end
            end

            local fullRotationsSteps = #strip * 2
            local distanceToTarget = (targetIdx - currentWheelIndex) % #strip
            local totalSteps = fullRotationsSteps + distanceToTarget

            -- Spin Animation Sequence
            for step = 1, totalSteps do
                gameState.spinTick = step
                currentWheelIndex = (currentWheelIndex % #strip) + 1
                gameState.activeSpinNumber = strip[currentWheelIndex]
                
                refreshState()
                ROULETTE_UI.draw(gameState)

                -- Cinematic Brake Physics
                local stepsRemaining = totalSteps - step
                if stepsRemaining <= 15 then
                    local brakeFactor = 16 - stepsRemaining
                    os.sleep(0.04 + (brakeFactor * 0.03))
                else
                    os.sleep(0.04)
                end
            end

            currentWheelIndex = targetIdx
            gameState.activeSpinNumber = gameState.winningNumber
            
            -- Process wins/losses values
            local initialChips = gameState.balance
            ROULETTE.resolveGame(gameState)
            local netPayout = gameState.lastPayout or 0
            
            refreshState()
            ROULETTE_UI.draw(gameState)

            -- Dispatch payouts through barrel automation if earnings exist
            if netPayout > 0 then
                Barrel.returnToPlayer(netPayout)
            end

            -- Transmit hand metrics directly up to tracking telemetry
            local loggingName = shared.playerName or "Unknown"
            local logOutcome = (netPayout > totalWagered) and "win" or ((netPayout == totalWagered) and "push" or "loss")
            Net.reportHand(logOutcome, totalWagered, loggingName)
            
            shared.gameActive = false
        else
            -- Standard Event Touch Monitoring
            local event, side, x, y = os.pullEvent()
            if event == "monitor_touch" then
                if gameState.phase == "results" then
                    ROULETTE.resetTable(gameState)
                else
                    local action = ROULETTE_UI.hitTest(x, y)
                    if action then
                        if action:sub(1, 4) == "bet:" then
                            -- Pass dynamic base amounts if configurations require alterations
                            ROULETTE.handleBetClick(gameState, action:sub(5), CFG.betAmount)
                        elseif action == "clear" then
                            ROULETTE.clearBets(gameState)
                        elseif action == "spin" then
                            if ROULETTE.getTotalBet(gameState) > 0 then
                                ROULETTE.startSpin(gameState)
                            end
                        end
                    end
                end
            elseif event == "timer" then
                -- Forces render loops to stay responsive even if player sits idle
                refreshState()
                ROULETTE_UI.draw(gameState)
            end
        end
        ::continue::
    end
end

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
        function() coinListener()   end,
        function() playerListener() end, 
        function() gameLoop()       end,
        function() rednetListener() end
    )
end

main()