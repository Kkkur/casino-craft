-- ========================================================================== --
--  Blackjack Machine Controller
--  Coordinates the game loop, UI animations, barrel I/O, and manager netcode.
-- ========================================================================== --

local BJ     = dofile("games/blackjack/blackjack.lua")
local UI     = dofile("games/blackjack/bj_ui.lua")
local Barrel = dofile("games/libraries/barrel_handler.lua")
local Net    = dofile("games/libraries/net_client.lua")
local Det    = dofile("games/libraries/player_detector.lua")

-- -------------------------------------------------------------------------- --
-- Configuration & State
-- -------------------------------------------------------------------------- --

local CFG = {
    managerId          = nil,
    machineLabel       = "Blackjack Table",
    betAmount          = 2,
    numDecks           = 6,
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
    
    UI.init(mon)
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
-- Game Logic Helpers
-- -------------------------------------------------------------------------- --

local function calculatePayout(result, bet)
    if result == "blackjack" then return bet + math.floor(bet * 1.5) end
    if result == "win"       then return bet * 2 end
    if result == "push"      then return bet end
    return 0
end

-- -------------------------------------------------------------------------- --
-- Main Game Loop
-- -------------------------------------------------------------------------- --

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

    local function refreshState()
        uiState.queueChips = shared.queueChips
        uiState.bet        = CFG.betAmount
        uiState.playerName = shared.playerName or "Guest"
    end

    while not shared.shutdown do
        -- Ensure fresh deck
        if #deck < 52 then deck = BJ.shuffle(BJ.newDeck(CFG.numDecks)) end
        
        -- Betting Phase
        uiState.phase  = "betting"
        uiState.player = {}
        uiState.dealer = {}
        uiState.result = nil
        uiState.payout = 0
        
        local betPlaced = false
        while not betPlaced and not shared.shutdown do
            refreshState()
            UI.draw(uiState)
            
            local ev, p1, p2, p3 = os.pullEvent()
            if ev == "monitor_touch" then
                local action = UI.hitTest(p2, p3)
                if action == "deal" and shared.queueChips >= CFG.betAmount then
                    if Barrel.takeBet(CFG.betAmount) >= CFG.betAmount then
                        betPlaced = true
                    end
                end
            end
        end
        if shared.shutdown then break end

        -- Playing Phase
        shared.gameActive = true
        local totalBet = CFG.betAmount
        local gameState = BJ.newGame(deck, CFG.betAmount)
        BJ.startDeal(gameState)

        uiState.phase = "playing"
        uiState.player = gameState.player
        uiState.dealer = gameState.dealer
        
        if not BJ.checkNatural(gameState) then
            while gameState.phase == "playing" and not shared.shutdown do
                refreshState()
                UI.draw(uiState)
                
                local ev, p1, p2, p3 = os.pullEvent()
                if ev == "monitor_touch" then
                    local action = UI.hitTest(p2, p3)
                    if action == "hit" then
                        BJ.playerHit(gameState)
                    elseif action == "stand" then
                        BJ.playerStand(gameState)
                    elseif action == "double" and shared.queueChips >= CFG.betAmount then
                        if Barrel.takeBet(CFG.betAmount) >= CFG.betAmount then
                            totalBet = totalBet + CFG.betAmount
                            BJ.playerDouble(gameState)
                        end
                    elseif action == "split" and shared.queueChips >= CFG.betAmount then
                        if Barrel.takeBet(CFG.betAmount) >= CFG.betAmount then
                            totalBet = totalBet + CFG.betAmount
                            gameState.player = {gameState.player[1], BJ.deal(gameState.deck)}
                        end
                    end
                end
                uiState.player = gameState.player
            end
        end

        -- Resolution Phase
        if gameState.phase ~= "done" then BJ.playerStand(gameState) end
        
        local payout = calculatePayout(gameState.result, totalBet)
        uiState.phase  = "done"
        uiState.result = gameState.result
        uiState.payout = payout
        UI.draw(uiState)

        if payout > 0 then Barrel.returnToPlayer(payout) end
        Net.reportHand(gameState.result, totalBet, shared.playerName or "Guest")

        -- Wait for user to acknowledge results
        local timer = os.startTimer(10)
        while true do
            local ev, p1 = os.pullEvent()
            if ev == "monitor_touch" or (ev == "timer" and p1 == timer) then break end
        end
        
        shared.gameActive = false
    end
end

-- -------------------------------------------------------------------------- --
-- Boot
-- -------------------------------------------------------------------------- --

local function main()
    math.randomseed(os.clock() * 1000)
    for i = 1, 10 do math.random() end

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
    mon.write("  Ready! Game Type: Blackjack")
    os.sleep(1)

    parallel.waitForAny(coinListener, playerListener, gameLoop, rednetListener)
end

main()