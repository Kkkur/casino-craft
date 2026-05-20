-- Main blackjack machine logic. Runs the game loop, talks to the monitor,
-- and coordinates with the manager via net_client, barrel_handler, and player_detector.

local BJ     = dofile("games/blackjack/blackjack.lua")
local UI     = dofile("games/blackjack/bj_ui.lua")
local Barrel = dofile("games/libraries/barrel_handler.lua")
local Net    = dofile("games/libraries/net_client.lua")
local Det    = dofile("games/libraries/player_detector.lua")

-- Dynamic configuration populated entirely by machine_config.txt or the manager server
local CFG = {
    managerId          = nil,
    machineLabel       = "Blackjack Table", -- Fallback text used until network registration syncs
    betAmount          = 2,                 -- Fallback minimum bet until network registration syncs
    numDecks           = 6,
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
    UI.init(mon)

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
    -- If the user skipped the detector setup, terminate this parallel loop immediately
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

local function payoutAmount(result, bet)
    if result == "blackjack" then return bet + math.floor(bet * 1.5) end
    if result == "win"       then return bet * 2 end
    if result == "push"      then return bet end
    return 0
end

local function gameLoop()
    local deck = BJ.shuffle(BJ.newDeck(CFG.numDecks))

    local uiState = {
        phase      = "betting",
        player     = {},
        dealer     = {},
        bet        = CFG.betAmount,
        queueChips = 0,
        playerName = nil, 
        result     = nil,
        payout     = 0,
    }

    local function redraw()
        uiState.queueChips = shared.queueChips
        uiState.bet        = CFG.betAmount
        uiState.playerName = shared.playerName 
        UI.draw(uiState)
    end

    local function checkShoe()
        if #deck < 52 then
            deck = BJ.shuffle(BJ.newDeck(CFG.numDecks))
        end
    end

    local function bettingPhase()
        uiState.phase  = "betting"
        uiState.player = {}
        uiState.dealer = {}
        uiState.result = nil
        uiState.payout = 0

        local drawTimer = os.startTimer(0.5)
        redraw()

        while not shared.shutdown do
            local ev, p1, p2, p3 = os.pullEvent()
            if ev == "timer" and p1 == drawTimer then
                redraw()
                drawTimer = os.startTimer(0.5)
            elseif ev == "monitor_touch" then
                local action = UI.hitTest(p2, p3)
                if action == "deal" and shared.queueChips >= CFG.betAmount then
                    local moved = Barrel.takeBet(CFG.betAmount)
                    if moved >= CFG.betAmount then
                        return true
                    end
                end
                redraw()
            end
        end
        return false
    end

    local totalBet = CFG.betAmount

    local function playingPhase(gameState)
        uiState.phase  = "playing"
        uiState.player = gameState.player
        uiState.dealer = gameState.dealer
        redraw()

        while not shared.shutdown do
            local ev, p1, p2, p3 = os.pullEvent()
            if ev ~= "monitor_touch" then goto continue end
            local action = UI.hitTest(p2, p3)

            if action == "hit" then
                BJ.playerHit(gameState)
                uiState.player = gameState.player
                redraw()
                if gameState.phase == "done" then return gameState end

            elseif action == "stand" then
                BJ.playerStand(gameState)
                return gameState

            elseif action == "double" then
                if shared.queueChips >= CFG.betAmount then
                    local moved = Barrel.takeBet(CFG.betAmount)
                    if moved >= CFG.betAmount then
                        totalBet = totalBet + CFG.betAmount
                        BJ.playerDouble(gameState)
                        return gameState
                    end
                end

            elseif action == "split" then
                if shared.queueChips >= CFG.betAmount then
                    local moved = Barrel.takeBet(CFG.betAmount)
                    if moved >= CFG.betAmount then
                        totalBet = totalBet + CFG.betAmount
                        local h1 = {gameState.player[1], BJ.deal(gameState.deck)}
                        gameState.player = h1
                        uiState.player   = h1
                    end
                end
            end
            ::continue::
        end
        return gameState
    end

    local function donePhase(gameState)
        local chips = payoutAmount(gameState.result, totalBet)

        uiState.phase  = "done"
        uiState.player = gameState.player
        uiState.dealer = gameState.dealer
        uiState.result = gameState.result
        uiState.payout = chips
        redraw()

        if chips > 0 then
            Barrel.returnToPlayer(chips)
        end

        local loggingName = shared.playerName or "Unknown"
        Net.reportHand(gameState.result, totalBet, loggingName)

        local timer = os.startTimer(10)
        while true do
            local ev, p1 = os.pullEvent()
            if ev == "monitor_touch" then break end
            if ev == "timer" and p1 == timer then break end
        end
    end

    while not shared.shutdown do
        checkShoe()
        shared.gameActive = false

        local ok = bettingPhase()
        if not ok then break end

        shared.gameActive = true
        totalBet = CFG.betAmount
        local gameState = BJ.newGame(deck, CFG.betAmount)
        BJ.startDeal(gameState)

        local natural = BJ.checkNatural(gameState)
        if not natural then
            gameState = playingPhase(gameState)
        end

        if gameState.phase ~= "done" then
            BJ.playerStand(gameState)
        end

        donePhase(gameState)
        shared.gameActive = false
    end
end

local function main()
    math.randomseed(os.time())

    loadConfig()

    Net.init(CFG.managerId, "blackjack", CFG.machineLabel)

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
    mon.write("  Ready! Bet: " .. CFG.betAmount .. " chips")
    os.sleep(1)

    parallel.waitForAny(
        function() coinListener()   end,
        function() playerListener() end, 
        function() gameLoop()       end,
        function() rednetListener() end
    )
end

main()