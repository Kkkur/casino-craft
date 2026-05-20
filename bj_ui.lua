-- bj_ui.lua
-- Renders blackjack game

local BJ_UI = {}

-- Colour palette 
local C = {
    bg         = colours.black,
    felt       = colours.green,
    feltDark   = colours.lime,
    text       = colours.white,
    dimText    = colours.grey,
    cardFace   = colours.white,
    cardBack   = colours.blue,
    cardBorder = colours.lightGrey,
    suitRed    = colours.red,
    suitBlack  = colours.black,
    chipGold   = colours.yellow,
    win        = colours.lime,
    loss       = colours.red,
    push       = colours.yellow,
    blackjack  = colours.yellow,
    btnBg      = colours.grey,
    btnHover   = colours.lightGrey,
    btnText    = colours.white,
    btnHit     = colours.green,
    btnStand   = colours.red,
    btnDouble  = colours.orange,
    btnSplit   = colours.cyan,
    queueBg    = colours.grey,
    queueText  = colours.yellow,
    header     = colours.black,
    headerText = colours.yellow,
}

local mon
local W, H

--  Helpers 

local function bg(col)       mon.setBackgroundColor(col) end
local function fg(col)       mon.setTextColor(col)       end
local function cur(x, y)     mon.setCursorPos(x, y)      end

local function fill(x, y, w, h, col)
    bg(col)
    local row = string.rep(" ", w)
    for dy = 0, h-1 do
        cur(x, y+dy)
        mon.write(row)
    end
end

local function writeAt(x, y, text, fgCol, bgCol)
    if bgCol then bg(bgCol) end
    if fgCol then fg(fgCol) end
    cur(x, y)
    mon.write(text)
end

local function centreAt(y, text, fgCol, bgCol)
    local x = math.floor((W - #text) / 2) + 1
    writeAt(x, y, text, fgCol, bgCol)
end

local function clamp(s, maxLen)
    if #s > maxLen then return s:sub(1, maxLen) end
    return s
end

-- Suit colours 

local function suitColour(suit)
    if suit == "H" or suit == "D" then return C.suitRed end
    return C.suitBlack
end

local function suitSymbol(suit)
    if suit == "S" then return "\x06" end  -- spade  (CC char)
    if suit == "H" then return "\x03" end  -- heart
    if suit == "D" then return "\x04" end  -- diamond
    if suit == "C" then return "\x05" end  -- club
    return suit
end

local CARD_W = 5
local CARD_H = 5

local function drawCard(x, y, card, faceDown)
    if faceDown then
        -- Card back
        fill(x, y, CARD_W, CARD_H, C.cardBack)
        writeAt(x, y,   "+---+", C.cardBorder, C.cardBack)
        writeAt(x, y+1, "| ? |", C.dimText,    C.cardBack)
        writeAt(x, y+2, "|   |", C.dimText,    C.cardBack)  
        writeAt(x, y+3, "| ? |", C.dimText,    C.cardBack)
        writeAt(x, y+4, "+---+", C.cardBorder, C.cardBack)
        return
    end

    local rank = card.rank
    local suit = card.suit
    local sc   = suitColour(suit)
    local sym  = suitSymbol(suit)

    local rankL = rank
    if #rank == 1 then rankL = rank .. " " end

    fill(x, y, CARD_W, CARD_H, C.cardFace)
    writeAt(x, y,   "+---+", C.cardBorder, C.cardFace)
    writeAt(x, y+4, "+---+", C.cardBorder, C.cardFace)

    bg(C.cardFace) fg(sc)
    cur(x+1, y+1) mon.write(rankL)
    cur(x+3, y+1) mon.write(sym)
    writeAt(x,   y+2, "|   |", C.cardBorder, C.cardFace)
    cur(x+1, y+3) mon.write(sym)
    cur(x+3, y+3)
    if #rank == 1 then mon.write(" "..rank) else mon.write(rank) end
    writeAt(x,   y+1, "|", C.cardBorder, C.cardFace)
    writeAt(x+4, y+1, "|", C.cardBorder, C.cardFace)
    writeAt(x,   y+3, "|", C.cardBorder, C.cardFace)
    writeAt(x+4, y+3, "|", C.cardBorder, C.cardFace)
end

local function drawHand(hand, y, hideHole)
    local n     = #hand
    local total = n * CARD_W + (n-1)   -- 1 gap between cards
    local startX = math.floor((W - total) / 2) + 1
    for i, card in ipairs(hand) do
        local faceDown = (i == 2 and hideHole)
        drawCard(startX + (i-1)*(CARD_W+1), y, card, faceDown)
    end
    return startX, total
end

-- Buttons 

BJ_UI.buttons = {}

local function drawButton(x, y, w, label, bgCol, fgCol)
    local padded = string.rep(" ", math.floor((w - #label)/2)) .. label
    padded = padded .. string.rep(" ", w - #padded)
    padded = padded:sub(1, w)
    writeAt(x, y, padded, fgCol or C.btnText, bgCol or C.btnBg)
end

local function makeButton(x, y, w, label, action, bgCol, fgCol)
    drawButton(x, y, w, label, bgCol, fgCol)
    BJ_UI.buttons[#BJ_UI.buttons+1] = {
        label  = label,
        x      = x, y = y,
        w      = w, h = 1,
        action = action,
    }
end

-- Sections 

local function drawHeader(queueChips, playerName)
    fill(1, 1, W, 1, C.header)
    fg(C.headerText) bg(C.header)
    cur(1, 1)
    mon.write(" \x03 BLACKJACK ")
    local qStr = "Queue: " .. queueChips .. " chip" .. (queueChips == 1 and "" or "s") .. " "
    writeAt(W - #qStr + 1, 1, qStr, C.queueText, C.header)
    if playerName then
        local pStr = "  " .. playerName .. "  "
        writeAt(13, 1, clamp(pStr, 20), C.dimText, C.header)
    end
end

local function drawFelt()
    fill(1, 2, W, 1, C.felt)
    fill(1, 3, W, H-2, C.felt)
end

local function drawDealerZone(dealerHand, hideHole)
    local val = ""
    if not hideHole then
        local BJ = require("blackjack")
        val = tostring(BJ.handValue(dealerHand))
    end
    writeAt(2, 3, "  DEALER  " .. val, C.dimText, C.felt)
    if #dealerHand > 0 then
        drawHand(dealerHand, 4, hideHole)
    end
end

local function drawPlayerZone(playerHand)
    local BJ  = require("blackjack")
    local val = BJ.handValue(playerHand)
    local col = C.dimText
    if val > 21 then col = C.loss end
    local labelY = H - 7
    local handY  = H - 6
    writeAt(2, labelY, "  YOU  " .. val, col, C.felt)
    if #playerHand > 0 then
        drawHand(playerHand, handY, false)
    end
end

local function drawResult(result, payout)
    local msgs = {
        win       = {" YOU WIN! ",        C.win},
        loss      = {" BUST / LOSE ",     C.loss},
        push      = {" PUSH ",            C.push},
        blackjack = {" BLACKJACK! \x03 ", C.blackjack},
    }
    local entry = msgs[result]
    if not entry then return end
    local msg, col = entry[1], entry[2]
    local bannerY = math.floor(H / 2)
    centreAt(bannerY,   "  " .. msg .. "  ", col == C.loss and colours.white or C.bg, col)
    if payout and payout > 0 then
        centreAt(bannerY+1, "+ " .. payout .. " chips", C.win, C.felt)
    end
end

local function drawBettingPrompt(bet, queueChips)
    centreAt(8,  "Insert chips then press DEAL",    C.text,     C.felt)
    centreAt(9,  "Bet: " .. bet .. " chip" .. (bet==1 and "" or "s"), C.chipGold, C.felt)
    if queueChips < bet then
        centreAt(10, "Need " .. (bet-queueChips) .. " more chip(s)", C.loss, C.felt)
    else
        centreAt(10, "Ready!  " .. queueChips .. " queued", C.win, C.felt)
    end
end

local function drawActionButtons(state)
    local BJ   = require("blackjack")
    local hand  = state.player
    local bet   = state.bet
    local queue = state.queueChips or 0

    local btnY  = math.floor(H / 2)
    local btnW  = 10
    local gap   = 3

    local btns = {}
    btns[#btns+1] = {label="  HIT  ", action="hit",    bg=colours.lime}
    btns[#btns+1] = {label=" STAND ", action="stand",  bg=C.btnStand}
    if BJ.canDouble(hand) and queue >= bet then
        btns[#btns+1] = {label="DOUBLE ", action="double", bg=C.btnDouble}
    end
    if BJ.canSplit(hand) then
        btns[#btns+1] = {label=" SPLIT ", action="split",  bg=C.btnSplit}
    end

    local totalW = #btns * (btnW + gap) - gap
    local startX = math.floor((W - totalW) / 2) + 1

    for i, b in ipairs(btns) do
        local bx = startX + (i-1)*(btnW+gap)
        makeButton(bx, btnY, btnW, b.label, b.action, b.bg, C.btnText)
    end
end

local function drawDealButton(enabled)
    local btnY = H - 1
    local btnW = 14
    local bx   = math.floor((W - btnW) / 2) + 1
    if enabled then
        makeButton(bx, btnY, btnW, "  DEAL HAND  ", "deal", colours.lime, colours.black)
    else
        drawButton(bx, btnY, btnW, "  DEAL HAND  ", colours.grey, colours.grey)
    end
end

local function drawHoldNotice()
    centreAt(H-1, "  BUFFER FLUSH IN PROGRESS...  ", C.loss, C.bg)
end

local function drawWaitNext()
    centreAt(H-1, "  TAP anywhere to continue  ", C.dimText, C.felt)
end

-- Public API 

function BJ_UI.init(monitor)
    mon = monitor
    mon.setTextScale(0.5)
    W, H = mon.getSize()
    mon.clear()
end

function BJ_UI.getSize()
    return W, H
end

function BJ_UI.draw(state)
    BJ_UI.buttons = {}
    mon.setBackgroundColor(C.bg)
    mon.clear()

    local phase = state.phase or "betting"
    local queue = state.queueChips or 0

    drawHeader(queue, state.playerName)
    drawFelt()

    if phase == "flush" then
        centreAt(math.floor(H/2),   "  Buffer full - flushing chips  ", C.loss,   C.bg)
        centreAt(math.floor(H/2)+1, "  Games paused, please wait...  ", C.dimText, C.bg)
        drawHoldNotice()
        return
    end

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
        drawPlayerZone(state.player)
    end

    if phase == "playing" then
        drawActionButtons(state)
    elseif phase == "done" then
        drawResult(state.result, state.payout)
        drawWaitNext()
    end
end

function BJ_UI.hitTest(x, y)
    for _, btn in ipairs(BJ_UI.buttons) do
        if x >= btn.x and x < btn.x + btn.w
        and y >= btn.y and y < btn.y + btn.h then
            return btn.action
        end
    end
    return nil
end

return BJ_UI