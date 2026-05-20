-- ========================================================================== --
--  Blackjack UI Rendering
--  Handles card layouts, player zones, and game buttons.
-- ========================================================================== --

local BJ   = dofile("games/blackjack/blackjack.lua")
local UI   = dofile("games/libraries/ui_lib.lua")

local BJ_UI = {}

local CARD_W = 5
local CARD_H = 5


-- -------------------------------------------------------------------------- --
-- Helpers
-- -------------------------------------------------------------------------- --

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
        UI.writeAt(x, y,   "+---+", UI.C.cardBorder, UI.C.cardBack)
        UI.writeAt(x, y+1, "| ? |", UI.C.dimText,    UI.C.cardBack)
        UI.writeAt(x, y+2, "|   |", UI.C.dimText,    UI.C.cardBack)
        UI.writeAt(x, y+3, "| ? |", UI.C.dimText,    UI.C.cardBack)
        UI.writeAt(x, y+4, "+---+", UI.C.cardBorder, UI.C.cardBack)
        return
    end

    local sc  = suitColour(card.suit)
    local sym = suitSymbol(card.suit)
    local rk  = (#card.rank == 1) and (card.rank .. " ") or card.rank

    UI.fill(x, y, CARD_W, CARD_H, UI.C.cardFace)
    UI.writeAt(x, y,   "+---+", UI.C.cardBorder, UI.C.cardFace)
    UI.writeAt(x, y+4, "+---+", UI.C.cardBorder, UI.C.cardFace)

    UI.bg(UI.C.cardFace) UI.fg(sc)
    UI.cur(x+1, y+1) UI.getMonitor().write(rk)
    UI.cur(x+3, y+1) UI.getMonitor().write(sym)
    
    UI.writeAt(x, y+2, "|   |", UI.C.cardBorder, UI.C.cardFace)
    
    UI.cur(x+1, y+3) UI.getMonitor().write(sym)
    UI.cur(x+3, y+3)
    UI.getMonitor().write(rk:reverse()) -- Quick align for bottom rank
    
    UI.writeAt(x,   y+1, "|", UI.C.cardBorder, UI.C.cardFace)
    UI.writeAt(x+4, y+1, "|", UI.C.cardBorder, UI.C.cardFace)
    UI.writeAt(x,   y+3, "|", UI.C.cardBorder, UI.C.cardFace)
    UI.writeAt(x+4, y+3, "|", UI.C.cardBorder, UI.C.cardFace)
end

local function drawHand(hand, y, hideHole)
    local n      = #hand
    local totalW = n * CARD_W + (n - 1)
    local startX = math.floor((UI.W - totalW) / 2) + 1
    for i, card in ipairs(hand) do
        drawCard(startX + (i - 1) * (CARD_W + 1), y, card, i == 2 and hideHole)
    end
end

-- -------------------------------------------------------------------------- --
-- Scene Components
-- -------------------------------------------------------------------------- --

local function drawDealerZone(dealerHand, hideHole)
    local val = hideHole and "" or (" " .. tostring(BJ.handValue(dealerHand)))
    UI.writeAt(2, 3, "  DEALER " .. val, UI.C.dimText, UI.C.felt)
    if #dealerHand > 0 then drawHand(dealerHand, 4, hideHole) end
end

local function drawPlayerZone(playerHand, playerName)
    local val = BJ.handValue(playerHand)
    local col = (val > 21) and UI.C.loss or UI.C.dimText
    local label = playerName and ("  " .. playerName .. "  " .. val) or ("  YOU  " .. val)
    UI.writeAt(2, UI.H - 7, label, col, UI.C.felt)
    if #playerHand > 0 then drawHand(playerHand, UI.H - 6, false) end
end

local function drawBettingPrompt(bet, queueChips)
    UI.centreAt(8,  "Place bet then press DEAL", UI.C.text, UI.C.felt)
    UI.centreAt(9,  "Bet: " .. bet .. " chips",   UI.C.chipGold, UI.C.felt)
    if queueChips < bet then
        UI.centreAt(10, "Need " .. (bet - queueChips) .. " more", UI.C.loss, UI.C.felt)
    else
        UI.centreAt(10, "Ready! (" .. queueChips .. " available)", UI.C.win, UI.C.felt)
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
    
    local bannerY = math.floor(UI.H / 2)
    UI.centreAt(bannerY, "  " .. entry[1] .. "  ", (entry[2] == UI.C.loss) and colours.white or UI.C.bg, entry[2])
    if payout and payout > 0 then
        UI.centreAt(bannerY + 1, "+ " .. payout .. " chips", UI.C.win, UI.C.felt)
    end
end

-- -------------------------------------------------------------------------- --
-- Public API
-- -------------------------------------------------------------------------- --

function BJ_UI.init(monitor)
    UI.init(monitor)
end

function BJ_UI.draw(state)
    UI.clearButtons()
    UI.clear()

    local phase = state.phase or "betting"
    UI.drawHeader("BLACKJACK", state.queueChips, state.playerName)
    UI.drawCheckerboard(1, 3, UI.W, UI.H - 2, UI.C.felt, UI.C.feltDark)

    if phase == "betting" then
        drawBettingPrompt(state.bet, state.queueChips)
        local btnW = 14
        local bx   = math.floor((UI.W - btnW) / 2) + 1
        if state.queueChips >= state.bet then
            UI.makeButton(bx, UI.H - 1, btnW, "  DEAL HAND  ", "deal", colours.lime, colours.black)
        else
            UI.drawButtonInert(bx, UI.H - 1, btnW, "  DEAL HAND  ", colours.grey, colours.grey)
        end
        return
    end

    if state.dealer and #state.dealer > 0 then drawDealerZone(state.dealer, phase == "playing") end
    if state.player and #state.player > 0 then drawPlayerZone(state.player, state.playerName) end

    if phase == "playing" then
        local btnY, btnW, gap = math.floor(UI.H / 2), 10, 3
        local btns = { {label="  HIT  ", action="hit", bg=UI.C.btnHit}, {label=" STAND ", action="stand", bg=UI.C.btnStand} }
        if BJ.canDouble(state.player) and state.queueChips >= state.bet then
            table.insert(btns, {label="DOUBLE ", action="double", bg=UI.C.btnDouble})
        end
        
        local startX = math.floor((UI.W - (#btns * (btnW + gap) - gap)) / 2) + 1
        for i, b in ipairs(btns) do
            UI.makeButton(startX + (i - 1) * (btnW + gap), btnY, btnW, b.label, b.action, b.bg, UI.C.btnText)
        end
    elseif phase == "done" then
        drawResult(state.result, state.payout)
        UI.centreAt(UI.H - 1, "  TAP anywhere to continue  ", UI.C.dimText, UI.C.felt)
    end
end

function BJ_UI.hitTest(x, y)
    return UI.hitTest(x, y)
end

return BJ_UI