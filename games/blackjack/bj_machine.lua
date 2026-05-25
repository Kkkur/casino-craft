-- games/blackjack/bj_machine.lua
-- Blackjack machine -- main entry point
-- GPU rendering via UILib/CardsLib/ChipsLib
-- Balance managed via BankLib
-- Session/peripheral/network via GameLib + PDLib

local BJ      = dofile("/games/blackjack/blackjack.lua")
local UI      = dofile("/libraries/games/UILib.lua")
local Cards   = dofile("/libraries/games/CardsLib.lua")
local Chips   = dofile("/libraries/games/ChipsLib.lua")
local Bank    = dofile("/libraries/bank/BankLib.lua")
local Logger  = dofile("/libraries/logger/logger.lua")
local GameLib = dofile("/libraries/games/GameLib.lua")

--  Layout config

local LAYOUT = {
    topBarHeight   = 14,
    barHeight      = 26,
    dealerY        = 22,
    dealerLabelY   = 20,
    playerY        = 115,
    playerLabelY   = 113,
    scoreOffsetX   = -28,
    cardOffsetX    = 22,
    dividerY       = 100,
    btnY           = 0,
    btnH           = 18,
    btnW           = 34,
    chipBarOffsetY = 4,
    feltInsetX     = 20,
    feltInsetTop   = 4,
    feltInsetBot   = 10,
    resultW        = 110,
    resultY        = 90,
    noAccountY     = 70,
    idleY          = 88,
}

--  Colors

local C = {
    felt     = 0x1a6b35,
    feltDark = 0x155a2c,
    feltEdge = 0x0f4020,
    gold     = 0xC9A84C,
    darkBar  = 0x111111,
    white    = 0xFFFFFF,
    yellow   = 0xFFDD44,
    gray     = 0x888888,
    red      = 0xCC2222,
}

--  Shared state
-- Shared table is passed to GameLib threads. GameLib writes currentPlayer and
-- shutdown. The machine game loop reads them.

local shared = {
    shutdown     = false,
    currentPlayer = nil,   -- written by PDLib listener thread
    rigFactor    = 0.7,    -- overwritten by GameLib.register and netListener
    betRefunded  = false,  -- set true by netListener mid-hand refund
}

--  Module-level handles (set in main)

local gpu    = nil
local PDLib  = nil
local ui     = nil

--  Derived layout (set in initLayout)

local sw, sh
local BAR_Y
local cw, ch

local function initLayout()
    sw, sh = ui:getSize()
    BAR_Y  = sh - LAYOUT.barHeight
    cw, ch = Cards.cardSize()
end

local function handX(n)
    local totalW = cw + (n - 1) * LAYOUT.cardOffsetX
    return math.floor((sw - totalW) / 2)
end

--  Bank helpers

local function getPlayerBalance(name)
    local bal, err = Bank.getBalance(name)
    if not bal then Logger.warn("getBalance failed: " .. tostring(err)) end
    return bal, err
end

local function deductBet(name, amount)
    local bal, err = Bank.remove(name, amount, "game")
    if not bal then Logger.error("Bank.remove failed: " .. tostring(err)) end
    return bal, err
end

local function creditWin(name, amount)
    local bal, err = Bank.add(name, amount, "game")
    if not bal then Logger.error("Bank.add failed: " .. tostring(err)) end
    return bal, err
end

--  Game state

local deck, playerHand, dealerHand
local balance    = 0
local bet        = 0
local gameState  = "idle"
local resultMsg  = ""
local playerName = "Guest"
local chipsUI    = nil

-- currentBet() is used by GameLib.netListener for mid-hand refunds.
local function currentBet() return bet end

local function newRound()
    playerHand = {}
    dealerHand = {}
    chipsUI:resetBet()
    bet       = 0
    gameState = "betting"
    resultMsg = ""
end

local function checkShoe(cfg)
    if not deck or #deck < 52 then
        deck = BJ.newDeck(cfg.numDecks or 6)
        BJ.shuffle(deck)
        Logger.info("Shoe reshuffled (" .. tostring(cfg.numDecks or 6) .. " decks)")
    end
end

local function dealCard(faceUp)
    local card = BJ.deal(deck)
    card.faceUp = (faceUp ~= false)
    return card
end

local function startDeal()
    if bet == 0 then return end
    local newBal, err = deductBet(playerName, bet)
    if not newBal then resultMsg = "BANK ERROR"; gameState = "result"; return end
    balance = newBal
    table.insert(playerHand, dealCard(true))
    table.insert(dealerHand, dealCard(true))
    table.insert(playerHand, dealCard(true))
    table.insert(dealerHand, dealCard(false))
    gameState = "playing"
end

local function doHit()
    table.insert(playerHand, dealCard(true))
    if BJ.isBust(playerHand) then
        dealerHand[2].faceUp = true
        gameState = "result"; resultMsg = "BUST!"
        GameLib.reportHand(playerName, "loss", bet, 0, Logger)
    end
end

local function doStand()
    dealerHand[2].faceUp = true
    gameState = "dealer"
end

local function doDouble()
    if balance < bet then return end
    local newBal, err = deductBet(playerName, bet)
    if not newBal then return end
    balance = newBal
    bet     = bet * 2
    table.insert(playerHand, dealCard(true))
    if BJ.isBust(playerHand) then
        dealerHand[2].faceUp = true
        gameState = "result"; resultMsg = "BUST!"
        GameLib.reportHand(playerName, "loss", bet, 0, Logger)
        return
    end
    doStand()
end

local function doDealerPlay()
    while BJ.dealerShouldHit(dealerHand) do
        table.insert(dealerHand, dealCard(true))
    end
    local result, mult = BJ.resolveHand(playerHand, dealerHand)
    local payout = BJ.calcPayout(bet, mult)
    if     result == "blackjack" then resultMsg = "BLACKJACK!"
    elseif result == "win"       then resultMsg = "YOU WIN!"
    elseif result == "push"      then resultMsg = "PUSH"
    else                              resultMsg = "DEALER WINS"
    end
    if payout > 0 then
        local newBal = creditWin(playerName, payout)
        if newBal then balance = newBal end
    end
    GameLib.reportHand(playerName, result, bet, payout, Logger)
    gameState = "result"
end

--  Drawing

local function drawFelt()
    local L = LAYOUT
    ui:rect(0, ui.y0, sw, sh - ui.y0, C.felt)
    ui:rect(L.feltInsetX, ui.y0 + L.feltInsetTop,
            sw - L.feltInsetX*2,
            sh - ui.y0 - LAYOUT.barHeight - L.feltInsetTop - L.feltInsetBot,
            C.feltDark)
    ui:border(L.feltInsetX+2, ui.y0 + L.feltInsetTop+2,
              sw - (L.feltInsetX+2)*2,
              sh - ui.y0 - LAYOUT.barHeight - (L.feltInsetTop+2) - (L.feltInsetBot+2),
              C.feltEdge, 1)
end

local function drawBottomBar()
    ui:rect(0, BAR_Y, sw, LAYOUT.barHeight, C.darkBar)
    ui:rect(0, BAR_Y, sw, 1, C.gold)
end

local function drawDivider()
    ui:rect(30, LAYOUT.dividerY, sw - 60, 1, C.feltEdge)
end

local function drawLabels()
    ui:text(4, LAYOUT.dealerLabelY, "DEALER", C.gold, C.felt, 1)
    ui:text(4, LAYOUT.playerLabelY, "YOU",    C.gold, C.felt, 1)
end

local function drawHands()
    if #dealerHand > 0 then
        local dx = handX(#dealerHand)
        Cards.drawHand(ui, dx, LAYOUT.dealerY, dealerHand, LAYOUT.cardOffsetX)
        local allUp = true
        for _, c in ipairs(dealerHand) do if not c.faceUp then allUp = false end end
        if allUp then Cards.drawScore(ui, dx + LAYOUT.scoreOffsetX, LAYOUT.dealerY, dealerHand) end
    end
    if #playerHand > 0 then
        local px = handX(#playerHand)
        Cards.drawHand(ui, px, LAYOUT.playerY, playerHand, LAYOUT.cardOffsetX)
        Cards.drawScore(ui, px + LAYOUT.scoreOffsetX, LAYOUT.playerY, playerHand)
    end
end

local function drawChips()
    local totalW = 6 * (26 + 4) - 4
    chipsUI.x = math.floor((sw - totalW) / 2)
    chipsUI.y = BAR_Y + LAYOUT.chipBarOffsetY
    chipsUI:draw()
end

local function drawActionButtons()
    local btnY = BAR_Y + LAYOUT.btnY
    local btnH = LAYOUT.btnH
    local btnW = LAYOUT.btnW

    if gameState == "playing" then
        ui:button("hit",   { label="HIT",   x=sw-btnW*3-8, y=btnY, w=btnW, h=btnH, bg=0x225599, borderColor=0x4488CC })
        ui:button("stand", { label="STAND", x=sw-btnW*2-4, y=btnY, w=btnW, h=btnH, bg=0x882222, borderColor=0xCC4444 })
        if #playerHand == 2 and balance >= bet then
            ui:button("double", { label="2x", x=sw-btnW, y=btnY, w=btnW, h=btnH, bg=0x886600, borderColor=0xFFAA00 })
        end
    elseif gameState == "result" then
        ui:button("again", { label="DEAL", x=sw-40, y=btnY, w=36, h=btnH, bg=0x226622, borderColor=C.gold })
    end
end

local function drawInfo()
    if bet > 0 then
        ui:pill(4, BAR_Y + LAYOUT.btnY, "BET", "$" .. bet, C.darkBar, C.gray, 0xFF8844)
    end
end

local function drawResult()
    if gameState ~= "result" or resultMsg == "" then return end
    local rw = LAYOUT.resultW
    local rx = math.floor((sw - rw) / 2)
    local ry = LAYOUT.resultY
    ui:rect(rx, ry, rw, 16, 0x111111)
    ui:border(rx, ry, rw, 16, C.gold, 1)
    ui:textCentered(rx, ry + 4, rw, resultMsg, C.yellow, 0x111111, 1)
end

local function drawNoAccount()
    local rw = sw - 40
    local rx = 20
    local ry = LAYOUT.noAccountY
    ui:rect(rx, ry, rw, 36, 0x1a0000)
    ui:border(rx, ry, rw, 36, C.red, 1)
    ui:textCentered(rx, ry+4,  rw, "NO ACCOUNT FOUND",      0xFF4444, 0x1a0000, 1)
    ui:textCentered(rx, ry+14, rw, tostring(playerName),    C.gray,   0x1a0000, 1)
    ui:textCentered(rx, ry+24, rw, "Visit ATM to register", C.gray,   0x1a0000, 1)
end

local function drawIdleScreen()
    ui:textCentered(0, LAYOUT.idleY,      sw, "BLACKJACK",          C.gold, C.feltDark, 1)
    ui:textCentered(0, LAYOUT.idleY + 14, sw, "Waiting for player", C.gray, C.feltDark, 1)
end

local function redraw()
    ui:clearButtons()
    ui:updateTopBar({ chips = balance, player = playerName })
    ui:drawTopBar()
    drawFelt()
    drawDivider()
    drawBottomBar()

    if gameState == "idle" then
        drawIdleScreen()

    elseif gameState == "no_account" then
        drawNoAccount()

    elseif gameState == "betting" then
        drawLabels()
        drawChips()
        drawInfo()
        if bet > 0 then
            ui:button("deal", {
                label="DEAL", x=sw-40, y=BAR_Y+LAYOUT.btnY, w=36, h=LAYOUT.btnH,
                bg=0x226622, borderColor=C.gold
            })
            ui:button("clrbet", {
                label="CLR", x=4, y=BAR_Y+LAYOUT.btnY, w=28, h=LAYOUT.btnH,
                bg=0x552222, borderColor=0x884444
            })
        end

    else
        drawLabels()
        drawHands()
        drawActionButtons()
        drawInfo()
        drawResult()
    end

    ui:drawOverlay()
    ui:sync()
end

--  Input

local function onButton(id, cfg)
    if gameState == "betting" then
        if chipsUI:isChipButton(id) then
            chipsUI:handleButton(id, balance)
            bet = chipsUI:getBet()
            redraw()
        elseif id == "clrbet" then
            chipsUI:resetBet(); bet = 0; redraw()
        elseif id == "deal" and bet > 0 then
            checkShoe(cfg); startDeal(); redraw()
            if gameState == "playing" and BJ.isBlackjack(playerHand) then
                doStand(); doDealerPlay(); redraw()
            end
        end

    elseif gameState == "playing" then
        if id == "hit" then
            doHit(); redraw()
        elseif id == "stand" then
            doStand(); redraw(); sleep(0.4); doDealerPlay(); redraw()
        elseif id == "double" then
            doDouble(); redraw()
            if gameState == "dealer" then sleep(0.4); doDealerPlay(); redraw() end
        end

    elseif gameState == "result" then
        if id == "again" then
            local bal, err = getPlayerBalance(playerName)
            if not bal then gameState = "no_account"
            else balance = bal; newRound() end
            redraw()
        end
    end
end

--  Game loop

-- gameLoop runs the session lifecycle. It waits for PDLib to fire a
-- playerClick (via shared.currentPlayer being set by the PDLib listener
-- thread), fetches the player's balance, runs the inner hand loop, and
-- resets to idle on departure or override.

local function gameLoop(cfg)
    while not shared.shutdown do
        -- Wait for a player session
        local detected = PDLib.getCurrentPlayer()
        if not detected then
            playerName = "Guest"; balance = 0; gameState = "idle"
            redraw()
            repeat
                os.sleep(0.25)
                detected = PDLib.getCurrentPlayer()
            until detected or shared.shutdown
            if shared.shutdown then break end
        end

        playerName = detected
        PDLib.setGameActive(false)  -- not in a hand yet

        -- If the server pushed a mid-session bet refund while we were idle,
        -- clear the flag.
        shared.betRefunded = false

        local bal, err = getPlayerBalance(playerName)
        if not bal then
            gameState = "no_account"; balance = 0; redraw()
            -- Wait until the player is gone or replaced
            repeat os.sleep(0.5)
            until PDLib.getCurrentPlayer() ~= playerName or shared.shutdown
        else
            balance = bal
            BJ.rigFactor = shared.rigFactor
            newRound()
            redraw()

            PDLib.setGameActive(false)

            while not shared.shutdown do
                -- Check for player departure / override between hands
                local current = PDLib.getCurrentPlayer()
                if current ~= playerName and gameState == "betting" then
                    break
                end

                -- Check if the server refunded our bet mid-hand and showed an
                -- overlay -- break out of the hand loop to return to idle
                if shared.betRefunded then
                    shared.betRefunded = false
                    bet = 0
                    gameState = "idle"
                    PDLib.setGameActive(false)
                    break
                end

                local e, p, x, y = os.pullEvent()

                if e == "tm_monitor_touch" then
                    local btnId = ui:hitButton(x, y)
                    if btnId then
                        ui:flashButton(btnId)
                        -- Keep rigFactor in sync before each button action
                        BJ.rigFactor = shared.rigFactor
                        -- Mark game active when a hand is in progress
                        if gameState == "playing" or gameState == "dealer" then
                            PDLib.setGameActive(true)
                        end
                        onButton(btnId, cfg)
                        -- After the hand resolves, mark game inactive
                        if gameState == "result" or gameState == "betting" then
                            PDLib.setGameActive(false)
                        end
                        PDLib.resetIdleTimer()
                    end

                elseif e == "timer" then
                    if ui:handleOverlayTimer(p) then
                        redraw()
                    end

                elseif e == "key" and p == keys.q then
                    shared.shutdown = true
                end
            end
        end
    end
end

--  Main

local function main()
    math.randomseed(os.time())
    Logger.init("blackjack", "games/blackjack/logs")

    local cfg = GameLib.loadConfig("machine_config.txt")
    -- Defaults for fields not in the config file
    cfg.machineLabel = cfg.machineLabel or "Blackjack #1"
    cfg.numDecks     = cfg.numDecks     or 6
    cfg.rigFactor    = cfg.rigFactor    or 0.7
    cfg.game         = cfg.game         or "blackjack"

    -- Apply local rigFactor into shared so the net listener can update it
    shared.rigFactor = cfg.rigFactor
    BJ.rigFactor     = cfg.rigFactor

    -- Init peripherals (GPU, PDLib, modem)
    gpu, PDLib = GameLib.initPeripherals(cfg)

    ui = UI.new(gpu, 64)

    initLayout()

    ui:setTopBar({
        title  = "Blackjack",
        player = "Guest",
        chips  = 0,
        height = LAYOUT.topBarHeight,
    })

    chipsUI = Chips.new(ui, 0, 0, function(newBet) bet = newBet end)

    -- Connect to bank (blocks until connected, shows status on screen)
    GameLib.connectBank(Bank, ui, sw, sh, Logger)

    -- Registration (non-blocking fallback if server is absent)
    local serverRigFactor = GameLib.register(cfg, cfg.rigFactor, Logger)
    shared.rigFactor = serverRigFactor
    BJ.rigFactor     = serverRigFactor

    -- Boot splash
    ui:drawTopBar()
    ui:rect(0, ui.y0, sw, sh - ui.y0, 0x000000)
    ui:textCentered(0, math.floor(sh/2) - 6, sw, cfg.machineLabel, C.gold, 0x000000, 1)
    ui:textCentered(0, math.floor(sh/2) + 4, sw, "Ready",          C.gray, 0x000000, 1)
    ui:sync()
    os.sleep(1.5)

    parallel.waitForAny(
        function() gameLoop(cfg) end,
        function()
            GameLib.netListener(shared, ui, Bank, currentBet, Logger)
        end,
        function()
            PDLib.listenerThread(shared, {
                onPlayerClick = function(username, prev)
                    -- If a different player overrides mid-session, PDLib has
                    -- already updated getCurrentPlayer(). The game loop will
                    -- detect the mismatch on its next iteration.
                    shared.currentPlayer = username
                    Logger.info("Player click: " .. tostring(username)
                        .. (prev and (" (prev: " .. prev .. ")") or ""))
                end,
                onPlayerLeave = function(username)
                    Logger.info("Player left: " .. tostring(username))
                end,
                onIdleTimeout = function(username)
                    Logger.info("Idle timeout: " .. tostring(username))
                    -- currentPlayer is already nil inside PDLib at this point
                    shared.currentPlayer = nil
                end,
            })
        end
    )

    Logger.info("Machine shut down cleanly.")
end

main()