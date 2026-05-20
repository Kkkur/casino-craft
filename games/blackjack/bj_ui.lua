-- bj_ui.lua
-- Blackjack-specific rendering. Handles cards, zones, buttons, and results.
-- All primitives, colours, and the header come from ui_lib.lua.
--
-- How to use:
--   local BJ_UI = dofile("bj_ui.lua")
--   BJ_UI.init(peripheral.find("monitor"))
--   BJ_UI.draw(state)
--   local action = BJ_UI.hitTest(x, y)
--
-- state table fields:
--   phase      : "betting" | "playing" | "done"
--   player     : table of cards
--   dealer     : table of cards
--   bet        : chip amount
--   queueChips : chips currently in deposit barrel
--   playerName : string or nil (from player_detector)
--   result     : "win" | "loss" | "push" | "blackjack" or nil
--   payout     : chip count paid out

local BJ     = dofile("games/blackjack/blackjack.lua")

local BJ_UI = {}

local CARD_W = 5
local CARD_H = 5

local function suitColour(suit)
    if suit == "H" or suit == "D" then return UI.C.suitRed end
    return UI.C.suitBlack
end

local function suitSymbol(suit)
    if suit == "S" then return "\x06" end
    if suit == "H" then return "\x03" end
    if suit == "D" then return "\x04" end
    if suit == "C" then return "\x05" end
    return suit
end

local function drawCard(x, y, card, faceDown)
    if faceDown then
        UI.fill(x, y, CARD_W, CARD_H, UI.C.cardBack)
        UI.writeAt(x,   y,   "+---+", UI.C.cardBorder, UI.C.cardBack)
        UI.writeAt(x,   y+1, "| ? |", UI.C.dimText,    UI.C.cardBack)
        UI.writeAt(x,   y+2, "|   |", UI.C.dimText,    UI.C.cardBack)
        UI.writeAt(x,   y+3, "| ? |", UI.C.dimText,    UI.C.cardBack)
        UI.writeAt(x,   y+4, "+---+", UI.C.cardBorder, UI.C.cardBack)
        return
    end

    local rank = card.rank
    local suit = card.suit
    local sc   = suitColour(suit)
    local sym  = suitSymbol(suit)
    local rankL = (#rank == 1) and (rank .. " ") or rank

    UI.fill(x, y, CARD_W, CARD_H, UI.C.cardFace)
    UI.writeAt(x, y,   "+---+", UI.C.cardBorder, UI.C.cardFace)
    UI.writeAt(x, y+4, "+---+", UI.C.cardBorder, UI.C.cardFace)

    UI.bg(UI.C.cardFace) UI.fg(sc)
    UI.cur(x+1, y+1) UI.getMonitor().write(rankL)
    UI.cur(x+3, y+1) UI.getMonitor().write(sym)
    UI.writeAt(x, y+2, "|   |", UI.C.cardBorder, UI.C.cardFace)
    UI.cur(x+1, y+3) UI.getMonitor().write(sym)
    UI.cur(x+3, y+3)
    if #rank == 1 then UI.getMonitor().write(" " .. rank) else UI.getMonitor().write(rank) end
    UI.writeAt(x,   y+1, "|", UI.C.cardBorder, UI.C.cardFace)
    UI.writeAt(x+4, y+1, "|", UI.C.cardBorder, UI.C.cardFace)
    UI.writeAt(x,   y+3, "|", UI.C.cardBorder, UI.C.cardFace)
    UI.writeAt(x+4, y+3, "|", UI.C.cardBorder, UI.C.cardFace)
end

local function drawHand(hand, y, hideHole)
    local n      = #hand
    local total  = n * CARD_W + (n - 1)
    local startX = math.floor((UI.W - total) / 2) + 1
    for i, card in ipairs(hand) do
        drawCard(startX + (i - 1) * (CARD_W + 1), y, card, i == 2 and hideHole)
    end
end

local function drawDealerZone(dealerHand, hideHole)
    local val = hideHole and "" or (" " .. tostring(BJ.handValue(dealerHand)))
    UI.writeAt(2, 3, "  DEALER " .. val, UI.C.dimText, UI.C.felt)
    if #dealerHand > 0 then
        drawHand(dealerHand, 4, hideHole)
    end
end

local function drawPlayerZone(playerHand, playerName)
    local val = BJ.handValue(playerHand)
    local col = (val > 21) and UI.C.loss or UI.C.dimText
    local label = playerName and ("  " .. playerName .. "  " .. val) or ("  YOU  " .. val)
    UI.writeAt(2, UI.H - 7, label, col, UI.C.felt)
    if #playerHand > 0 then
        drawHand(playerHand, UI.H - 6, false)
    end
end

local function drawResult(result, payout)
    local msgs = {
        win       = {" YOU WIN! ",        UI.C.win},
        loss      = {" BUST / LOSE ",     UI.C.loss},
        push      = {" PUSH ",            UI.C.push},
        blackjack = {" BLACKJACK! \x03 ", UI.C.blackjack},
    }
    local entry = msgs[result]
    if not entry then return end
    local msg, col = entry[1], entry[2]
    local bannerY  = math.floor(UI.H / 2)
    UI.centreAt(bannerY, "  " .. msg .. "  ", (col == UI.C.loss) and colours.white or UI.C.bg, col)
    if payout and payout > 0 then
        UI.centreAt(bannerY + 1, "+ " .. payout .. " chips", UI.C.win, UI.C.felt)
    end
end

local function drawBettingPrompt(bet, queueChips)
    UI.centreAt(8,  "Insert chips then press DEAL",                          UI.C.text,     UI.C.felt)
    UI.centreAt(9,  "Bet: " .. bet .. " chip" .. (bet == 1 and "" or "s"),   UI.C.chipGold, UI.C.felt)
    if queueChips < bet then
        UI.centreAt(10, "Need " .. (bet - queueChips) .. " more chip(s)", UI.C.loss, UI.C.felt)
    else
        UI.centreAt(10, "Ready!  " .. queueChips .. " queued",            UI.C.win,  UI.C.felt)
    end
end

local function drawActionButtons(playerHand, bet, queueChips)
    local btnY = math.floor(UI.H / 2)
    local btnW = 10
    local gap  = 3

    local btns = {}
    btns[#btns+1] = {label="  HIT  ", action="hit",    bg=UI.C.btnHit}
    btns[#btns+1] = {label=" STAND ", action="stand",  bg=UI.C.btnStand}
    if BJ.canDouble(playerHand) and queueChips >= bet then
        btns[#btns+1] = {label="DOUBLE ", action="double", bg=UI.C.btnDouble}
    end
    if BJ.canSplit(playerHand) then
        btns[#btns+1] = {label=" SPLIT ", action="split",  bg=UI.C.btnSplit}
    end

    local totalW = #btns * (btnW + gap) - gap
    local startX = math.floor((UI.W - totalW) / 2) + 1

    for i, b in ipairs(btns) do
        UI.makeButton(startX + (i - 1) * (btnW + gap), btnY, btnW, b.label, b.action, b.bg, UI.C.btnText)
    end
end

local function drawDealButton(enabled)
    local btnW = 14
    local bx   = math.floor((UI.W - btnW) / 2) + 1
    if enabled then
        UI.makeButton(bx, UI.H - 1, btnW, "  DEAL HAND  ", "deal", colours.lime, colours.black)
    else
        UI.drawButtonInert(bx, UI.H - 1, btnW, "  DEAL HAND  ", colours.grey, colours.grey)
    end
end

-- Public API

function BJ_UI.init(monitor)
    UI.init(monitor)
end

function BJ_UI.draw(state)
    UI.clearButtons()
    UI.clear()

    local phase = state.phase or "betting"
    local queue = state.queueChips or 0

    UI.drawHeader("BLACKJACK", queue, state.playerName)

    UI.fill(1, 2, UI.W, 1,      UI.C.felt)
    UI.fill(1, 3, UI.W, UI.H-2, UI.C.felt)

    if phase == "betting" then
        drawBettingPrompt(state.bet, queue)
        drawDealButton(queue >= state.bet)
        return
    end

    local hideHole = (phase == "playing")

    if state.dealer and #state.dealer > 0 then
        drawDealerZone(state.dealer, hideHole)
    end

    if state.player and #state.player > 0 then
        drawPlayerZone(state.player, state.playerName)
    end

    if phase == "playing" then
        drawActionButtons(state.player, state.bet, queue)
    elseif phase == "done" then
        drawResult(state.result, state.payout)
        UI.centreAt(UI.H - 1, "  TAP anywhere to continue  ", UI.C.dimText, UI.C.felt)
    end
end

function BJ_UI.hitTest(x, y)
    return UI.hitTest(x, y)
end

return BJ_UI