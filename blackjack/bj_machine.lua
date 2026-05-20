-- bj_machine.lua


local BJ = require("blackjack")
local UI = require("bj_ui")

--  Config 
local CFG = {
    managerId        = nil,
    machineLabel     = "Blackjack #1",
    betAmount        = 2,
    numDecks         = 6,
    playerBarrelName = "minecraft:barrel_5",  -- player deposit
    sharedBarrelName = "minecraft:barrel_4",  -- casino reserve
    detectorName     = nil,
    monitorName      = nil,
}

local function loadMachineConfig()
    local CONFIG_FILE = "machine_config.txt"
    if not fs.exists(CONFIG_FILE) then return end
    local f = io.open(CONFIG_FILE, "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^(.-)=(.+)$")
        if k then
            if k == "managerId"    then CFG.managerId        = tonumber(v) end
            if k == "detectorSide" then CFG.detectorName     = v end
            if k == "monitorSide"  then CFG.monitorName      = v end
            if k == "playerBarrel" then CFG.playerBarrelName = v end
            if k == "sharedBarrel" then CFG.sharedBarrelName = v end
        end
    end
    f:close()
end

--  Shared state 
local shared = {
    queueChips    = 0,
    gameActive    = false,
    shutdown      = false,
    currentPlayer = nil,
}

--  Peripherals 
local detector     = nil
local playerBarrel = nil
local sharedBarrel = nil


local function initPeripherals()
    -- Monitor
    local mon
    if CFG.monitorName then
        mon = peripheral.wrap(CFG.monitorName)
        assert(mon, "Monitor '" .. CFG.monitorName .. "' not found! Re-run bootstrap.")
    else
        mon = peripheral.find("monitor")
        assert(mon, "No monitor found!")
    end
    UI.init(mon)

    -- wired palyer barreel
    playerBarrel = peripheral.wrap(CFG.playerBarrelName)
    assert(playerBarrel, "Player barrel '" .. CFG.playerBarrelName .. "' not found on wired network!")

    -- reservc barrel wired
    sharedBarrel = peripheral.wrap(CFG.sharedBarrelName)
    assert(sharedBarrel, "Shared chip barrel '" .. CFG.sharedBarrelName .. "' not found on wired network!")

    -- Player detector, its optional but always use it, for leaderboards
    if CFG.detectorName then
        detector = peripheral.wrap(CFG.detectorName)
        if not detector then
            print("Warning: detector '" .. CFG.detectorName .. "' not found.")
        end
    else
        detector = peripheral.find("playerDetector")
                or peripheral.find("player_detector")
    end

    -- Wireless modem
    local modem = peripheral.find("modem", function(_, m)
        return m.isWireless and m.isWireless()
    end)
    if modem and CFG.managerId then
        rednet.open(peripheral.getName(modem))
    end

    return mon
end

-- Barrel helpers 
local function countChips(inv)
    local total = 0
    for _, stack in pairs(inv.list()) do
        if stack.name == "createdeco:brass_coin" then
            total = total + stack.count
        end
    end
    return total
end

local function moveCoins(dst, dstName, srcName, amount)
    local src = peripheral.wrap(srcName)
    if not src then return 0 end
    local moved = 0
    for slot, stack in pairs(src.list()) do
        if moved >= amount then break end
        if stack.name == "createdeco:brass_coin" then
            local toMove = math.min(amount - moved, stack.count)
            moved = moved + dst.pullItems(srcName, slot, toMove)
        end
    end
    return moved
end

local function takeBet(amount)
    return moveCoins(sharedBarrel, CFG.sharedBarrelName, CFG.playerBarrelName, amount)
end

local function returnToPlayer(amount)
    return moveCoins(playerBarrel, CFG.playerBarrelName, CFG.sharedBarrelName, amount)
end

local function payoutAmount(result, bet)
    if result == "blackjack" then return bet + math.floor(bet * 1.5) end
    if result == "win"       then return bet * 2 end
    if result == "push"      then return bet end
    return 0
end

-- Rednet helpers 
local function reportHand(result, bet, playerName)
    if not CFG.managerId then return end
    rednet.send(CFG.managerId, {
        type   = "hand_result",
        game   = "blackjack",
        player = playerName or "Unknown",
        result = result,
        bet    = bet,
    }, "CASINO_NET")
end

local function registerWithManager()
    if not CFG.managerId then return end
    rednet.send(CFG.managerId, {
        type       = "register",
        game       = "blackjack",
        label      = CFG.machineLabel,
        winPercent = CFG.winPercent or 30,
    }, "CASINO_NET")
    local sid, msg = rednet.receive("CASINO_NET", 10)
    if sid == CFG.managerId and type(msg) == "table" and msg.type == "config" then
        if msg.betAmount    then CFG.betAmount    = msg.betAmount    end
        if msg.machineLabel then CFG.machineLabel = msg.machineLabel end
    end
end

-- Thread 1: coin listener 
local function coinListener()
    while not shared.shutdown do
        shared.queueChips = countChips(playerBarrel)
        os.sleep(0.25)
    end
end

-- Thread 3: Rednet listener 
local function rednetListener()
    while not shared.shutdown do
        if CFG.managerId then
            local sid, msg = rednet.receive("CASINO_NET", 2)
            if sid == CFG.managerId and type(msg) == "table" then
                if msg.type == "config" then
                    if msg.betAmount    then CFG.betAmount    = msg.betAmount    end
                    if msg.machineLabel then CFG.machineLabel = msg.machineLabel end
                end
                if msg.type == "shutdown" then
                    shared.shutdown = true
                end
            end
        else
            os.sleep(2)
        end
    end
end

-- Thread 4: Player detector 
local PLAYER_DETECT_RANGE = 2

local function remoteLog(level, msg)
    print("[" .. level .. "] " .. tostring(msg))
    if CFG.managerId then
        rednet.send(CFG.managerId, {
            type = "log",
            line = "[BJ#" .. os.getComputerID() .. "] [" .. level .. "] " .. tostring(msg),
        }, "CASINO_LOG")
    end
end

local function detectNearbyPlayer()
    if not detector then return nil end
    local ok, players = pcall(detector.getPlayersInRange, PLAYER_DETECT_RANGE)
    if not ok or type(players) ~= "table" then return nil end
    return players[1] or nil
end

local function playerDetectorThread()
    if not detector then
        while not shared.shutdown do os.sleep(10) end
        return
    end
    while not shared.shutdown do
        if not shared.gameActive then
            local name = detectNearbyPlayer()
            if name ~= shared.currentPlayer then
                shared.currentPlayer = name
            end
        end
        os.sleep(2)
    end
end

--  Thread 2: Game loop 
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
        uiState.playerName = shared.currentPlayer
        UI.draw(uiState)
    end

    local function checkShoe()
        if #deck < 52 then
            deck = BJ.shuffle(BJ.newDeck(CFG.numDecks))
        end
    end

    --  BETTING phase 
    local function bettingPhase()
        uiState.phase  = "betting"
        uiState.player = {}
        uiState.dealer = {}
        uiState.result = nil
        uiState.payout = 0

        while not shared.shutdown do
            redraw()
            local ev = {os.pullEvent()}
            if ev[1] == "monitor_touch" then
                local action = UI.hitTest(ev[3], ev[4])
                if action == "deal" and shared.queueChips >= CFG.betAmount then
                    local moved = takeBet(CFG.betAmount)
                    if moved >= CFG.betAmount then
                        local nearby = detectNearbyPlayer()
                        if nearby then shared.currentPlayer = nearby end
                        return true
                    end
                end
            end
        end
        return false
    end

    --  PLAYING phase 
    local totalBet = CFG.betAmount

    local function playingPhase(gameState)
        uiState.phase  = "playing"
        uiState.player = gameState.player
        uiState.dealer = gameState.dealer

        while not shared.shutdown do
            redraw()
            local ev = {os.pullEvent()}
            if ev[1] ~= "monitor_touch" then goto continue end
            local action = UI.hitTest(ev[3], ev[4])

            if action == "hit" then
                BJ.playerHit(gameState)
                uiState.player = gameState.player
                if gameState.phase == "done" then return gameState end

            elseif action == "stand" then
                BJ.playerStand(gameState)
                return gameState

            elseif action == "double" then
                if shared.queueChips >= CFG.betAmount then
                    local moved = takeBet(CFG.betAmount)
                    if moved >= CFG.betAmount then
                        totalBet = totalBet + CFG.betAmount
                        BJ.playerDouble(gameState)
                        return gameState
                    end
                end

            elseif action == "split" then
                if shared.queueChips >= CFG.betAmount then
                    local moved = takeBet(CFG.betAmount)
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

    --  DONE phase 
    local function donePhase(gameState)
        local playerName = shared.currentPlayer or "Unknown"
        local chips      = payoutAmount(gameState.result, totalBet)

        uiState.phase  = "done"
        uiState.player = gameState.player
        uiState.dealer = gameState.dealer
        uiState.result = gameState.result
        uiState.payout = chips
        redraw()

        if chips > 0 then
            returnToPlayer(chips)
        end

        reportHand(gameState.result, totalBet, playerName)

        -- Wait for tap or 10 seconds before next hand
        local deadline = os.clock() + 10
        while os.clock() < deadline do
            redraw()
            local ev = {os.pullEvent()}
            if ev[1] == "monitor_touch" then break end
        end
    end

    -- Main loop 
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

-- Entry point 
local function main()
    math.randomseed(os.time())

    loadMachineConfig()
    if not CFG.managerId then
        local f = io.open("manager_id.txt", "r")
        if f then
            CFG.managerId = tonumber(f:read("*l"))
            f:close()
        end
    end

    local mon = initPeripherals()

    mon.setBackgroundColor(colours.black)
    mon.clear()
    mon.setCursorPos(1, 1)
    mon.setTextColor(colours.yellow)
    mon.write("  Connecting to manager...")

    registerWithManager()

    mon.setCursorPos(1, 2)
    mon.setTextColor(colours.lime)
    mon.write("  Ready! Bet: " .. CFG.betAmount .. " chips")
    os.sleep(1)

    parallel.waitForAny(
        function() coinListener()         end,
        function() gameLoop()             end,
        function() rednetListener()       end,
        function() playerDetectorThread() end
    )
end

main()