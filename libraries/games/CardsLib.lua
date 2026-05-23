-- libraries/games/CardsLib.lua
-- Card deck, hand management, and pixel-art rendering
-- Universal: Blackjack, Poker, etc.

local CardsLib = {}

--  Constants 

local SUITS = { "S", "H", "D", "C" }
local RANKS = { "A","2","3","4","5","6","7","8","9","10","J","Q","K" }

local SUIT_COLOR = { S=0x1a1aCC, H=0xCC1a1a, D=0xCC1a1a, C=0x1a1aCC }

local CARD_W = 30
local CARD_H = 40

-- Pip positions per rank (normalized 0-1 within card content area)
local PIPS = {
    ["A"]  = { {0.5,0.5} },
    ["2"]  = { {0.5,0.25}, {0.5,0.75} },
    ["3"]  = { {0.5,0.2}, {0.5,0.5}, {0.5,0.8} },
    ["4"]  = { {0.25,0.25},{0.75,0.25},{0.25,0.75},{0.75,0.75} },
    ["5"]  = { {0.25,0.2},{0.75,0.2},{0.5,0.5},{0.25,0.8},{0.75,0.8} },
    ["6"]  = { {0.25,0.2},{0.75,0.2},{0.25,0.5},{0.75,0.5},{0.25,0.8},{0.75,0.8} },
    ["7"]  = { {0.25,0.2},{0.75,0.2},{0.5,0.37},{0.25,0.55},{0.75,0.55},{0.25,0.8},{0.75,0.8} },
    ["8"]  = { {0.25,0.18},{0.75,0.18},{0.5,0.36},{0.25,0.5},{0.75,0.5},{0.5,0.64},{0.25,0.82},{0.75,0.82} },
    ["9"]  = { {0.25,0.18},{0.75,0.18},{0.25,0.38},{0.75,0.38},{0.5,0.5},{0.25,0.62},{0.75,0.62},{0.25,0.82},{0.75,0.82} },
    ["10"] = { {0.25,0.15},{0.75,0.15},{0.5,0.3},{0.25,0.45},{0.75,0.45},{0.25,0.55},{0.75,0.55},{0.5,0.7},{0.25,0.85},{0.75,0.85} },
    ["J"]  = nil,
    ["Q"]  = nil,
    ["K"]  = nil,
}

--  Deck 

function CardsLib.newDeck()
    local deck = {}
    for _, suit in ipairs(SUITS) do
        for _, rank in ipairs(RANKS) do
            table.insert(deck, { rank=rank, suit=suit, faceUp=true })
        end
    end
    return deck
end

function CardsLib.shuffle(deck)
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

function CardsLib.deal(deck)
    return table.remove(deck)
end

--  Hand value (Blackjack) 

function CardsLib.handValue(hand)
    local total, aces = 0, 0
    for _, c in ipairs(hand) do
        if c.faceUp then
            if     c.rank == "A"                              then aces=aces+1; total=total+11
            elseif c.rank=="J" or c.rank=="Q" or c.rank=="K" then total=total+10
            else   total = total + tonumber(c.rank)
            end
        end
    end
    while total > 21 and aces > 0 do total=total-10; aces=aces-1 end
    return total
end

function CardsLib.isBust(hand)      return CardsLib.handValue(hand) > 21 end
function CardsLib.isBlackjack(hand) return #hand==2 and CardsLib.handValue(hand)==21 end

--  Rendering 

function CardsLib.cardSize() return CARD_W, CARD_H end

local function drawBack(ui, x, y)
    ui:rect(x, y, CARD_W, CARD_H, 0xEEEEEE)
    ui:border(x, y, CARD_W, CARD_H, 0x888888, 1)
    ui:border(x+2, y+2, CARD_W-4, CARD_H-4, 0x2233AA, 1)
    local patColor = 0x3344BB
    local ix, iy   = x+4, y+4
    local iw, ih   = CARD_W-8, CARD_H-8
    ui:rect(ix, iy, iw, ih, 0x2233AA)
    for row = 0, ih-1, 3 do
        ui:rect(ix, iy+row, iw, 1, patColor)
    end
    for col = 0, iw-1, 3 do
        ui:rect(ix+col, iy, 1, ih, patColor)
    end
end

local function drawPip(ui, cx, cy, suit, small)
    local sc = SUIT_COLOR[suit]
    if small then
        ui:rect(cx-1, cy-1, 3, 3, sc)
    else
        if suit == "H" or suit == "D" then
            ui:rect(cx,   cy-2, 1, 1, sc)
            ui:rect(cx-1, cy-1, 3, 1, sc)
            ui:rect(cx-2, cy,   5, 1, sc)
            ui:rect(cx-1, cy+1, 3, 1, sc)
            ui:rect(cx,   cy+2, 1, 1, sc)
        else
            ui:rect(cx-2, cy,   5, 1, sc)
            ui:rect(cx,   cy-2, 1, 5, sc)
            ui:rect(cx-1, cy-1, 3, 3, sc)
        end
    end
end

local function drawFront(ui, x, y, card)
    local sc = SUIT_COLOR[card.suit]
    local bg = 0xF5F5F5

    ui:rect(x, y, CARD_W, CARD_H, bg)
    ui:border(x, y, CARD_W, CARD_H, 0x999999, 1)
    ui:border(x+1, y+1, CARD_W-2, CARD_H-2, 0xCCCCCC, 1)

    ui:text(x+2, y+2,  card.rank, sc, bg, 1)
    ui:text(x+2, y+11, card.suit, sc, bg, 1)

    local pips = PIPS[card.rank]
    if not pips then
        ui:textCentered(x, y+14, CARD_W, card.rank, sc, bg, 1)
        ui:border(x+4, y+10, CARD_W-8, CARD_H-20, sc, 1)
    else
        local contentX = x + 4
        local contentY = y + 6
        local contentW = CARD_W - 8
        local contentH = CARD_H - 12
        for _, pip in ipairs(pips) do
            local px = contentX + math.floor(pip[1] * contentW)
            local py = contentY + math.floor(pip[2] * contentH)
            drawPip(ui, px, py, card.suit, (#pips >= 8))
        end
    end

    local rw = ui.gpu.getTextLength(card.rank, 1) or 6
    ui:text(x + CARD_W - rw - 2, y + CARD_H - 10, card.rank, sc, bg, 1)
end

function CardsLib.drawCard(ui, x, y, card)
    if not card.faceUp then
        drawBack(ui, x, y)
    else
        drawFront(ui, x, y, card)
    end
end

function CardsLib.drawHand(ui, x, y, hand, offsetX)
    offsetX = offsetX or 22
    for i, card in ipairs(hand) do
        CardsLib.drawCard(ui, x + (i-1)*offsetX, y, card)
    end
end

function CardsLib.drawScore(ui, x, y, hand)
    local val   = CardsLib.handValue(hand)
    local label = tostring(val)
    local bg, fg = 0x222222, 0xFFFFFF
    if val > 21 then
        bg = 0xAA2222; label = "BUST"
    elseif val == 21 and #hand == 2 then
        bg = 0xAA8800; label = "BJ!"
    end
    local w = 24
    ui:rect(x, y, w, 13, bg)
    ui:border(x, y, w, 13, 0x888888, 1)
    ui:textCentered(x, y+2, w, label, fg, bg, 1)
end

return CardsLib