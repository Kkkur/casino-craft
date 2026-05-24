-- blackjack/bj_machine.lua
-- Blackjack machine — main entry point
-- GPU rendering via UILib/CardsLib/ChipsLib
-- Balance managed via BankLib (no physical barrels)

local BJ     = require("blackjack")
local UI     = dofile("/libraries/games/UILib.lua")
local Cards  = dofile("/libraries/games/CardsLib.lua")
local Chips  = dofile("/libraries/games/ChipsLib.lua")
local Bank   = dofile("/libraries/bank/BankLib.lua")
local Logger = dofile("/libraries/logger/logger.lua")

--  Layout config —

local LAYOUT = {
    -- Top bar
    topBarHeight   = 14,    -- height of the top bar strip

    -- Bottom action bar
    barHeight      = 26,    -- height of the bottom bar

    -- Dealer hand position
    dealerY        = 22,    -- y position of dealer cards top edge
    dealerLabelY   = 20,    -- y position of "DEALER" label

    -- Player hand position
    playerY        = 115,   -- y position of player cards top edge
    playerLabelY   = 113,   -- y position of "YOU" label

    -- Score bubble x offset from hand start (negative = left of cards)
    scoreOffsetX   = -28,

    -- Card overlap (pixels between card left edges)
    cardOffsetX    = 22,

    -- Divider line y position (between dealer and player zones)
    dividerY       = 100,

    -- Bottom bar button layout
    btnY           = 0,     -- y offset WITHIN the bottom bar (added to barY)
    btnH           = 18,    -- button height
    btnW           = 34,    -- standard button width

    -- Chip row: auto-centered horizontally, y offset within bottom bar
    chipBarOffsetY = 4,     -- y offset from top of bottom bar

    -- Felt inner oval margins
    feltInsetX     = 20,    -- horizontal inset for darker oval
    feltInsetTop   = 4,     -- top inset for darker oval
    feltInsetBot   = 10,    -- bottom inset for darker oval (above bar)

    -- Result banner
    resultW        = 110,   -- width of result banner
    resultY        = 90,    -- y position of result banner

    -- No-account panel
    noAccountY     = 70,    -- y position of no-account error panel

    -- Idle screen text y
    idleY          = 88,    -- y of "BLACKJACK" on idle screen
}

--  Machine config 

local CFG = {
    managerId    = nil,
    machineLabel = "Blackjack #1",
    numDecks     = 6,
    detectorName = nil,
    monitorName  = nil,
}

local CONFIG_FILE = "machine_config.txt"

local function loadMachineConfig()
    if not fs.exists(CONFIG_FILE) then return end
    local f = io.open(CONFIG_FILE, "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^(.-)=(.+)$")
        if k then
            if k == "managerId"    then CFG.managerId    = tonumber(v)      end
            if k == "detectorSide" then CFG.detectorName = v                end
            if k == "monitorSide"  then CFG.monitorName  = v                end
            if k == "machineLabel" then CFG.machineLabel = v                end
            if k == "numDecks"     then CFG.numDecks     = tonumber(v) or 6 end
        end
    end
    f:close()
end

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

local shared = {
    shutdown      = false,
    gameActive    = false,
    currentPlayer = nil,
}

--  Peripherals 

local detector = nil
local gpu      = nil
local ui       = nil

local function initPeripherals()
    -- GPU peripheral
    if CFG.monitorName then
        gpu = peripheral.wrap(CFG.monitorName)
    else
        gpu = peripheral.find("gpu") or peripheral.wrap("top")
    end
    assert(gpu and gpu.refreshSize, "GPU peripheral not found!")

    -- Player detector (required — provides player name for BankLib)
    if CFG.detectorName then
        detector = peripheral.wrap(CFG.detectorName)
    else
        detector = peripheral.find("playerDetector") or peripheral.find("player_detector")
    end
    assert(detector, "Player detector not found! Re-run bootstrap.")

    -- Wireless modem
    local modem = peripheral.find("modem", function(_, m)
        return m.isWireless and m.isWireless()
    end)
    if modem then rednet.open(peripheral.getName(modem)) end

    ui = UI.new(gpu, 64)
end

--  Derived layout (computed once after ui is ready) 

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
    if not bal then Logger.warn("getBalance failed for " .. tostring(name) .. ": " .. tostring(err)) end
    return bal, err
end

local function deductBet(name, amount)
    local bal, err = Bank.remove(name, amount)
    if not bal then Logger.error("Bank.remove failed: " .. tostring(err)) end
    return bal, err
end

local function creditWin(name, amount)
    local bal, err = Bank.add(name, amount)
    if not bal then Logger.error("Bank.add failed: " .. tostring(err)) end
    return bal, err
end

--  Player detector thread 

local DETECT_RANGE = 2

local function detectNearbyPlayer()
    local ok, players = pcall(detector.getPlayersInRange, DETECT_RANGE)
    if not ok or type(players) ~= "table" then return nil end
    return players[1] or nil
end

local function playerDetectorThread()
    while not shared.shutdown do
        -- Always refresh the detected player, even during an active game,
        -- so the game loop can react to the player leaving mid-round.
        shared.currentPlayer = detectNearbyPlayer()
        os.sleep(2)
    end
end

--  Rednet 

local function remoteLog(level, msg)
    Logger.log(level, msg)
    if CFG.managerId then
        rednet.send(CFG.managerId, {
            type = "log",
            line = "[BJ#" .. os.getComputerID() .. "] [" .. level .. "] " .. tostring(msg),
        }, "CASINO_LOG")
    end
end

local function reportHand(result, bet, name)
    if not CFG.managerId then return end
    rednet.send(CFG.managerId, {
        type = "hand_result", game = "blackjack",
        player = name or "Unknown", result = result, bet = bet,
    }, "CASINO_NET")
end

local function registerWithManager()
    if not CFG.managerId then return end
    rednet.send(CFG.managerId, {
        type = "register", game = "blackjack", label = CFG.machineLabel,
    }, "CASINO_NET")
    local sid, msg = rednet.receive("CASINO_NET", 10)
    if sid == CFG.managerId and type(msg) == "table" and msg.type == "config" then
        if msg.machineLabel then CFG.machineLabel = msg.machineLabel end
        if msg.numDecks     then CFG.numDecks     = msg.numDecks     end
    end
end

local function rednetListener()
    while not shared.shutdown do
        if CFG.managerId then
            local sid, msg = rednet.receive("CASINO_NET", 2)
            if sid == CFG.managerId and type(msg) == "table" then
                if msg.type == "config" then
                    if msg.machineLabel then CFG.machineLabel = msg.machineLabel end
                    if msg.numDecks     then CFG.numDecks     = msg.numDecks     end
                end
                if msg.type == "shutdown" then shared.shutdown = true end
            end
        else
            os.sleep(2)
        end
    end
end

--  Game state 

local deck, playerHand, dealerHand
local balance    = 0
local bet        = 0
local gameState  = "idle"
local resultMsg  = ""
local playerName = "Guest"
local chipsUI    = nil

local function newRound()
    playerHand = {}
    dealerHand = {}
    chipsUI:resetBet()
    bet       = 0
    gameState = "betting"
    resultMsg = ""
end

local function checkShoe()
    if not deck or #deck < 52 then
        deck = BJ.newDeck(CFG.numDecks)
        BJ.shuffle(deck)
        remoteLog("INFO", "Shoe reshuffled (" .. CFG.numDecks .. " decks)")
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
        reportHand("loss", bet, playerName)
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
        reportHand("loss", bet, playerName)
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
    reportHand(result, bet, playerName)
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
    ui.buttons = {}
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

    ui:sync()
end

--  Input 

local function onButton(id)
    if gameState == "betting" then
        if chipsUI:isChipButton(id) then
            chipsUI:handleButton(id, balance)
            bet = chipsUI:getBet()
            redraw()
        elseif id == "clrbet" then
            chipsUI:resetBet(); bet = 0; redraw()
        elseif id == "deal" and bet > 0 then
            checkShoe(); startDeal(); redraw()
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

local function gameLoop()
    while not shared.shutdown do
        local detected = shared.currentPlayer
        if not detected then
            playerName = "Guest"; balance = 0; gameState = "idle"; redraw()
            repeat os.sleep(0.5); detected = shared.currentPlayer
            until detected or shared.shutdown
            if shared.shutdown then break end
        end

        playerName = detected
        shared.gameActive = true

        local bal, err = getPlayerBalance(playerName)
        if not bal then
            gameState = "no_account"; balance = 0; redraw()
            repeat os.sleep(1)
            until shared.currentPlayer ~= playerName or shared.shutdown
            shared.gameActive = false
        else
            balance = bal; newRound(); redraw()

            while not shared.shutdown do
                if shared.currentPlayer ~= playerName then break end
                local e, p, x, y = os.pullEvent()
                if e == "tm_monitor_touch" then
                    local btnId = ui:hitButton(x, y)
                    if btnId then ui:flashButton(btnId); onButton(btnId) end
                elseif e == "key" and p == keys.q then
                    shared.shutdown = true
                end
            end

            shared.gameActive = false
        end
    end
end

--  Main 

local function main()
    math.randomseed(os.time())
    Logger.init("blackjack", "blackjack/logs")
    loadMachineConfig()

    if not CFG.managerId then
        local f = io.open("manager_id.txt", "r")
        if f then CFG.managerId = tonumber(f:read("*l")); f:close() end
    end

    initPeripherals()
    initLayout()

    ui:setTopBar({
        title  = "Blackjack",
        player = "Guest",
        chips  = 0,
        height = LAYOUT.topBarHeight,
    })

    chipsUI = Chips.new(ui, 0, 0, function(newBet) bet = newBet end)

    local bankOk, bankErr = Bank.connect()
    if not bankOk then
        remoteLog("WARN", "Bank connect failed: " .. tostring(bankErr))
    end

    registerWithManager()

    -- Boot splash
    ui:drawTopBar()
    ui:rect(0, ui.y0, sw, sh - ui.y0, 0x000000)
    ui:textCentered(0, math.floor(sh/2) - 6, sw, CFG.machineLabel, C.gold, 0x000000, 1)
    ui:textCentered(0, math.floor(sh/2) + 4, sw, "Ready",          C.gray, 0x000000, 1)
    ui:sync()
    os.sleep(1.5)

    parallel.waitForAny(
        function() gameLoop()             end,
        function() rednetListener()       end,
        function() playerDetectorThread() end
    )

    Logger.info("Machine shut down cleanly.")
end

main()