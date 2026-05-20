-- bj_machine.lua
-- Main blackjack machine logic. Runs the game loop, talks to the monitor,
-- and coordinates with the manager via net_client and barrel_handler.

local BJ     = dofile("blackjack.lua")
local UI     = dofile("bj_ui.lua")
local Barrel = dofile("../games/libraries/barrel_handler.lua")
local Net    = dofile("../games/libraries/net_client.lua")

local CFG = {
    managerId        = nil,
    machineLabel     = "Blackjack #1",
    betAmount        = 2,
    numDecks         = 6,
    playerBarrelName = "minecraft:barrel_2",
    sharedBarrelName = "minecraft:barrel_5",
    monitorName      = nil,
}

local function loadConfig()
    if not fs.exists("machine_config.txt") then return end
    local f = io.open("machine_config.txt", "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^(.-)=(.+)$")
        if k then
            if k == "managerId"    then CFG.managerId        = tonumber(v) end
            if k == "monitorSide"  then CFG.monitorName      = v end
            if k == "playerBarrel" then CFG.playerBarrelName = v end
            if k == "sharedBarrel" then CFG.sharedBarrelName = v end
            if k == "label"        then CFG.machineLabel     = v end
        end
    end
    f:close()
end

-- If no label is saved yet, ask on the terminal so the manager can identify this machine.
local function promptLabel()
    if fs.exists("machine_config.txt") then return end
    term.setTextColor(colours.cyan)
    io.write("Machine name (e.g. Blackjack): ")
    term.setTextColor(colours.white)
    local input = io.read()
    if input and input ~= "" then
        CFG.machineLabel = input
        local f = io.open("machine_config.txt", "w")
        if f then
            f:write("label=" .. input .. "\n")
            f:close()
        end
    end
end

local shared = {
    queueChips = 0,
    gameActive = false,
    shutdown   = false,
}

local function initPeripherals()
    local mon
    if CFG.monitorName then
        mon = peripheral.wrap(CFG.monitorName)
        assert(mon, "Monitor '" .. CFG.monitorName .. "' not found.")
    else
        mon = peripheral.find("monitor")
        assert(mon, "No monitor found.")
    end
    UI.init(mon)

    Barrel.init(CFG.playerBarrelName, CFG.sharedBarrelName)

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
        result     = nil,
        payout     = 0,
    }

    local function redraw()
        uiState.queueChips = shared.queueChips
        uiState.bet        = CFG.betAmount
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

        while not shared.shutdown do
            redraw()
            local ev = {os.pullEvent()}
            if ev[1] == "monitor_touch" then
                local action = UI.hitTest(ev[3], ev[4])
                if action == "deal" and shared.queueChips >= CFG.betAmount then
                    local moved = Barrel.takeBet(CFG.betAmount)
                    if moved >= CFG.betAmount then
                        return true
                    end
                end
            end
        end
        return false
    end

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

        Net.reportHand(gameState.result, totalBet, "Unknown")

        local deadline = os.clock() + 10
        while os.clock() < deadline do
            redraw()
            local ev = {os.pullEvent()}
            if ev[1] == "monitor_touch" then break end
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

    promptLabel()
    loadConfig()

    if not CFG.managerId then
        local f = io.open("manager_id.txt", "r")
        if f then
            CFG.managerId = tonumber(f:read("*l"))
            f:close()
        end
    end

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
        function() gameLoop()       end,
        function() rednetListener() end
    )
end

main()