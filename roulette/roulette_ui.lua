-- Renders roulette game perfectly scaled for 100x38 with all controls positioned at the bottom

local ROULETTE_UI = {}

-- Colour palette
local C = {
    bg         = colours.black,
    felt       = colours.green,
    feltDark   = colours.lime,
    text       = colours.white,
    dimText    = colours.grey,
    numRed     = colours.red,
    numBlack   = colours.gray,
    numGreen   = colours.lime,
    chipGold   = colours.yellow,
    win        = colours.lime,
    loss       = colours.red,
    btnBg      = colours.grey,
    btnText    = colours.white,
    btnSpin    = colours.green,
    btnClear   = colours.red,
    queueText  = colours.yellow,
    header     = colours.black,
    headerText = colours.yellow,
    wheelWood  = colours.brown,
}

local mon
local W, H


local function getNumberColor(num)
    if num == 0 then return C.numGreen end
    -- If the number is odd, it's Red. If it's even, it's Black.
    if num % 2 ~= 0 then 
        return C.numRed 
    else 
        return C.numBlack 
    end
end

-- Helpers
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

local function centreInZone(xStart, xEnd, y, text, fgCol, bgCol)
    local zoneW = xEnd - xStart + 1
    local x = xStart + math.floor((zoneW - #text) / 2)
    writeAt(x, y, text, fgCol, bgCol)
end

-- Buttons & Click Targets
ROULETTE_UI.buttons = {}

local function drawButton(x, y, w, h, label, bgCol, fgCol)
    fill(x, y, w, h, bgCol)
    local textY = y + math.floor((h - 1) / 2)
    local padded = string.rep(" ", math.floor((w - #label)/2)) .. label
    padded = (padded .. string.rep(" ", w - #padded)):sub(1, w)
    writeAt(x, textY, padded, fgCol, bgCol)
end

local function makeButton(x, y, w, h, label, action, bgCol, fgCol)
    drawButton(x, y, w, h, label, bgCol or C.btnBg, fgCol or C.btnText)
    ROULETTE_UI.buttons[#ROULETTE_UI.buttons+1] = {
        action = action,
        x = x, y = y, w = w, h = h
    }
end

-- Layout Rendering Sections

local function drawHeader(queueChips, playerName)
    fill(1, 1, W, 2, C.header)
    writeAt(3, 1, " \x04 CASINO ROULETTE LIVE ", C.headerText, C.header)
    local qStr = "Chips In Queue: " .. queueChips .. " "
    writeAt(W - #qStr - 2, 1, qStr, C.queueText, C.header)
    if playerName then
        writeAt(3, 2, "Active Player: " .. playerName, C.dimText, C.header)
    end
end

-- Upper Row, Left-Center Side: Widescreen Betting Board
local function drawWidescreenBoard(currentBets)
    local startX = 4 -- Starts comfortably out from the left screen boundary
    local startY = 5
    local cellW = 4   
    local cellH = 4   

    -- 1. Zero Box
    local zeroBg = C.numGreen
    if currentBets["0"] then zeroBg = C.chipGold end
    makeButton(startX, startY, 4, cellH * 3 + 2, "0", "bet:0", zeroBg, C.text)

    -- 2. Numbers Grid (12 columns wide, 3 rows high)
    for num = 1, 36 do
        local colIdx = (num - 1) % 3             
        local rowIdx = math.floor((num - 1) / 3)  
        
        local cx = startX + 4 + 1 + (rowIdx * (cellW + 1))
        local cy = startY + ((2 - colIdx) * cellH)

        local cellBg = getNumberColor(num)
        local textCol = C.text
        if currentBets["num_" .. num] then
            cellBg = C.chipGold
            textCol = C.bg
        end

        local label = tostring(num)
        if num < 10 then label = " " .. label end
        makeButton(cx, cy, cellW, cellH, label, "bet:num_" .. num, cellBg, textCol)
    end

    -- 3. Outside Dozen Bars
    local dozY = startY + (cellH * 3) + 1
    local dozW = 19 
    local dozens = {
        {lbl = "1st 12", act = "doz1"},
        {lbl = "2nd 12", act = "doz2"},
        {lbl = "3rd 12", act = "doz3"}
    }
    for i, doz in ipairs(dozens) do
        local dx = startX + 5 + ((i - 1) * (dozW + 1))
        local bgCol = C.btnBg
        local fgCol = C.text
        if currentBets[doz.act] then bgCol = C.chipGold; fgCol = C.bg end
        makeButton(dx, dozY, dozW, 3, doz.lbl, "bet:" .. doz.act, bgCol, fgCol)
    end

    -- 4. Even/Odd, Red/Black, High/Low Bars
    local outY = dozY + 4
    local outW = 9
    local outsideOptions = {
        {lbl = "1-18",  act = "low",   bg = C.btnBg,    fg = C.text},
        {lbl = "EVEN",  act = "even",  bg = C.btnBg,    fg = C.text},
        {lbl = "RED",   act = "red",   bg = C.numRed,   fg = C.text},
        {lbl = "BLACK", act = "black", bg = C.numBlack, fg = C.text},
        {lbl = "ODD",   act = "odd",   bg = C.btnBg,    fg = C.text},
        {lbl = "19-36", act = "high",  bg = C.btnBg,    fg = C.text}
    }
    for i, opt in ipairs(outsideOptions) do
        local ox = startX + 5 + ((i - 1) * (outW + 1))
        local displayBg = opt.bg
        local displayFg = opt.fg
        if currentBets[opt.act] then displayBg = C.chipGold; displayFg = C.bg end
        makeButton(ox, outY, outW, 3, opt.lbl, "bet:" .. opt.act, displayBg, displayFg)
    end
end

-- Upper Row, Far Right Side: Mechanical Roulette Wheel
local function drawRealWheel(activeNumber, phase)
    local wheelW = 21
    local wheelH = 19
    local wx = W - wheelW - 4 -- Snaps perfectly flush alongside the board edge
    local wy = 5
    
    -- Outer Ring Rim
    fill(wx, wy, wheelW, wheelH, C.wheelWood)
    fill(wx + 2, wy + 1, wheelW - 4, wheelH - 2, C.bg)
    
    -- Axle spokes
    for i = 2, wheelH - 3 do
        writeAt(wx + 10, wy + i, "|", C.dimText, C.bg)
    end
    writeAt(wx + 3, wy + 9, "-------[   ]-------", C.dimText, C.bg)

    -- Center Winning Slot Window
    if activeNumber then
        local numColor = getNumberColor(activeNumber)
        local lbl = tostring(activeNumber)
        if activeNumber < 10 then lbl = "  " .. lbl .. "  " else lbl = " " .. lbl .. " " end
        drawButton(wx + 8, wy + 8, 5, 3, lbl, numColor, C.text)
    else
        drawButton(wx + 8, wy + 8, 5, 3, "IDLE", C.btnBg, C.dimText)
    end
    
    -- Status Banner
    local statusStr = "PLACE BETS"
    local statusColor = C.text
    if phase == "spinning" then statusStr = "SPINNING..."; statusColor = C.chipGold
    elseif phase == "results" then statusStr = "WINNER!"; statusColor = C.win end
    centreInZone(wx, wx + wheelW - 1, wy + wheelH, statusStr, statusColor, C.felt)
end

-- Bottom Row: Controls, Tips, and Results lined up horizontally
local function drawBottomPanel(canSpin, hasBets, state)
    local panelY = H - 4
    local btnW = 16
    local btnH = 3
    local phase = state.phase or "betting"

    -- 1. Left Side: CLEAR BETS
    if hasBets and phase == "betting" then
        makeButton(4, panelY, btnW, btnH, " CLEAR BETS ", "clear", C.btnClear, C.text)
    else
        drawButton(4, panelY, btnW, btnH, " CLEAR BETS ", C.btnBg, C.dimText)
    end

    -- 2. Left-Center: Info Text Tips Box
    local tx = 23
    writeAt(tx, panelY,     "• Tap layout to place chips", C.text, C.felt)
    writeAt(tx, panelY + 1, "• Payout calculation is automatic", C.text, C.felt)
    writeAt(tx, panelY + 2, "• High risk pays up to 35:1", C.chipGold, C.felt)

    -- 3. Right-Center: Active Win/Loss Results Overlay Box
    if phase == "results" then
        local rx = 58
        local rw = 20
        fill(rx, panelY, rw, btnH, C.header)
        
        local c = getNumberColor(state.winningNumber)
        writeAt(rx + 2, panelY + 1, "WIN: ", C.text, C.header)
        drawButton(rx + 7, panelY + 1, 4, 1, tostring(state.winningNumber), c, C.text)

        if state.payout and state.payout > 0 then
            writeAt(rx + 13, panelY + 1, " +" .. state.payout .. " \x13", C.win, C.header)
        else
            writeAt(rx + 13, panelY + 1, " LOSE ", C.loss, C.header)
        end
    end

    -- 4. Right Side: SPIN BUTTON
    local sx = W - btnW - 4
    if canSpin and hasBets and phase == "betting" then
        makeButton(sx, panelY, btnW, btnH, " SPIN WHEEL \x10 ", "spin", C.btnSpin, C.bg)
    else
        drawButton(sx, panelY, btnW, btnH, " SPIN WHEEL \x10 ", C.btnBg, C.dimText)
    end
end

-- Public API

function ROULETTE_UI.init(monitor)
    mon = monitor
    mon.setTextScale(0.5) 
    W, H = mon.getSize()
    mon.clear()
end

function ROULETTE_UI.getSize()
    return W, H
end

function ROULETTE_UI.draw(state)
    ROULETTE_UI.buttons = {}
    
    -- Main green felt layout table skin background
    fill(1, 3, W, H - 2, C.felt)

    local phase = state.phase or "betting" 
    local queue = state.queueChips or 0
    local bets  = state.bets or {}

    local hasBets = false
    for _ in pairs(bets) do hasBets = true break end

    drawHeader(queue, state.playerName)

    -- Render layout modules split cleanly into top and bottom tracks
    local activeNum = (phase == "spinning") and state.activeSpinNumber or state.winningNumber
    drawWidescreenBoard(bets)
    drawRealWheel(activeNum, phase)
    drawBottomPanel(queue >= 0, hasBets, state)
end

function ROULETTE_UI.hitTest(x, y)
    for _, btn in ipairs(ROULETTE_UI.buttons) do
        if x >= btn.x and x < btn.x + btn.w
        and y >= btn.y and y < btn.y + btn.h then
            return btn.action
        end
    end
    return nil
end

return ROULETTE_UI