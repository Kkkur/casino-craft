-- Renders roulette game perfectly scaled for 100x38 with optimized contrast and alignment

local ROULETTE_UI = {}

-- Colour palette (FIXED: Reverted all color keys to correct British spelling 'colours')
local C = {
    bg         = colours.black,
    felt       = colours.green,
    feltDark   = colours.lime,
    text       = colours.white,
    dimText    = colours.grey,     
    numRed     = colours.red,
    numBlack   = colours.grey,     
    numGreen   = colours.lime,
    chipGold   = colours.yellow,
    win        = colours.lime,
    loss       = colours.red,
    btnBg      = colours.lightGrey, 
    btnText    = colours.black,    
    btnSpin    = colours.lime,     
    btnClear   = colours.red,
    queueText  = colours.yellow,
    header     = colours.black,
    headerText = colours.yellow,
    wheelWood  = colours.brown,
    wheelInner = colours.black,     
}

local mon
local W, H

-- Sequential alternating layout mapping
local WHEEL_STRIP = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
    19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36
}

-- Custom alternating rule (Odd = Red, Even = Grey)
local function getNumberColor(num)
    if num == 0 then return C.numGreen end
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

ROULETTE_UI.buttons = {}

local function drawCellButton(x, y, w, h, line1, line2, bgCol, fgCol1, fgCol2)
    fill(x, y, w, h, bgCol)
    fgCol1 = fgCol1 or C.text
    fgCol2 = fgCol2 or fgCol1

    if line1 and line1 ~= "" then
        local pad1 = math.floor((w - #line1) / 2)
        writeAt(x + pad1, y + 1, line1, fgCol1, bgCol)
    end
    
    if line2 and line2 ~= "" then
        local pad2 = math.floor((w - #line2) / 2)
        writeAt(x + pad2, y + 2, line2, fgCol2, bgCol)
    end
end

local function makeButton(x, y, w, h, action, label1, label2, bgCol, fgCol1, fgCol2)
    drawCellButton(x, y, w, h, label1, label2, bgCol or C.btnBg, fgCol1 or C.btnText, fgCol2)
    ROULETTE_UI.buttons[#ROULETTE_UI.buttons+1] = {
        action = action,
        x = x, y = y, w = w, h = h
    }
end

local function drawHeader(queueChips, playerName)
    fill(1, 1, W, 2, C.header)
    writeAt(3, 1, " \x04 CASINO ROULETTE LIVE ", C.headerText, C.header)
    local qStr = "Chips In Queue: " .. queueChips .. " "
    writeAt(W - #qStr - 2, 1, qStr, C.queueText, C.header)
    if playerName then
        writeAt(3, 2, "Active Player: " .. playerName, colours.lightGrey, C.header)
    end
end

local function drawWidescreenBoard(currentBets)
    local startX = 4 
    local startY = 5
    local cellW = 4   
    local cellH = 4   
    local zeroW = 5 

    local function getBetLabel(val)
        if not val or val == 0 or val == "none" then return "" end
        if val == 1 then return "[1]" end
        if val == 2 then return "[2]" end
        if val == 4 then return "[4]" end
        if val == "max" then return "[MX]" end
        return ""
    end

    -- 1. Zero Box
    local zBetVal = currentBets["0"]
    local zBg = zBetVal and C.chipGold or C.numGreen
    local zFg = zBetVal and C.btnText or C.text 
    local zBetStr = getBetLabel(zBetVal)
    
    fill(startX, startY, zeroW, cellH * 3 + 2, zBg)
    centreInZone(startX, startX+zeroW-1, startY + 5, "0", zFg, zBg)
    if zBetStr ~= "" then
        centreInZone(startX, startX+zeroW-1, startY + 7, zBetStr, C.btnText, C.chipGold)
    end
    ROULETTE_UI.buttons[#ROULETTE_UI.buttons+1] = {
        action = "bet:0", x = startX, y = startY, w = zeroW, h = cellH * 3 + 2
    }

    -- 2. Numbers Grid
    for num = 1, 36 do
        local colIdx = (num - 1) % 3             
        local rowIdx = math.floor((num - 1) / 3)  
        
        local cx = startX + zeroW + 1 + (rowIdx * (cellW + 1))
        local cy = startY + ((2 - colIdx) * cellH)

        local betVal = currentBets["num_" .. num]
        local cellBg = betVal and C.chipGold or getNumberColor(num)
        local numFg  = betVal and C.btnText or C.text
        local betStr = getBetLabel(betVal)

        makeButton(cx, cy, cellW, cellH, "bet:num_" .. num, tostring(num), betStr, cellBg, numFg, C.btnText)
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
        local dx = startX + zeroW + 1 + ((i - 1) * (dozW + 1))
        local betVal = currentBets[doz.act]
        local bgCol = betVal and C.chipGold or C.btnBg
        local fgCol = C.btnText 
        local displayStr = betVal and (doz.lbl .. " " .. getBetLabel(betVal)) or doz.lbl
        
        makeButton(dx, dozY, dozW, 3, "bet:" .. doz.act, displayStr, "", bgCol, fgCol, fgCol)
    end

    -- 4. Outside Options
    local outY = dozY + 4
    local outW = 9
    local outsideOptions = {
        {lbl = "1-18",  act = "low",   bg = C.btnBg,        fg = C.btnText},
        {lbl = "EVEN",  act = "even",  bg = C.btnBg,        fg = C.btnText},
        {lbl = "RED",   act = "red",   bg = colours.red,    fg = C.text},
        {lbl = "BLACK", act = "black", bg = colours.grey,   fg = C.text}, 
        {lbl = "ODD",   act = "odd",   bg = C.btnBg,        fg = C.btnText},
        {lbl = "19-36", act = "high",  bg = C.btnBg,        fg = C.btnText}
    }
    for i, opt in ipairs(outsideOptions) do
        local ox = startX + zeroW + 1 + ((i - 1) * (outW + 1))
        local betVal = currentBets[opt.act]
        local displayBg = betVal and C.chipGold or opt.bg
        local displayFg = betVal and C.btnText or opt.fg 
        local displayStr = betVal and (opt.lbl .. " " .. getBetLabel(betVal)) or opt.lbl

        makeButton(ox, outY, outW, 3, "bet:" .. opt.act, displayStr, "", displayBg, displayFg, displayFg)
    end
end

-- Upper Row, Far Right Side: Real Sequential Strip Tracker
local function drawRealWheel(activeNumber, phase, tick, payout, hasBets)
    local wheelW = 21
    local wheelH = 19
    local wx = W - wheelW - 4 
    local wy = 5
    tick = tick or 0
    payout = payout or 0
    
    fill(wx, wy, wheelW, wheelH, C.wheelWood)
    fill(wx + 2, wy + 1, wheelW - 4, wheelH - 2, C.wheelInner) 
    
    -- Mechanical Axle Spokes
    local frames = {
        [0] = { "|", "/", "-", "\\", "|", "/", "-", "\\" },
        [1] = { "/", "-", "\\", "|", "/", "-", "\\", "|" },
        [2] = { "-", "\\", "|", "/", "-", "\\", "|", "/" },
        [3] = { "\\", "|", "/", "-", "\\", "|", "/", "-" }
    }
    local pattern = frames[tick % 4]
    for i = 2, wheelH - 3 do
        writeAt(wx + 10, wy + i, pattern[1], C.text, C.wheelInner) 
    end
    writeAt(wx + 3, wy + 9, string.rep(pattern[3], 5) .. "[   ]" .. string.rep(pattern[3], 5), C.text, C.wheelInner)

    if activeNumber then
        local baseIdx = 1
        
        for idx, val in ipairs(WHEEL_STRIP) do
            if val == activeNumber then 
                baseIdx = idx 
                break 
            end
        end

        local len = #WHEEL_STRIP
        local prevIdx = (baseIdx - 2 + len) % len + 1
        local nextIdx = (baseIdx % len) + 1

        local prevNum   = WHEEL_STRIP[prevIdx]
        local centerNum = WHEEL_STRIP[baseIdx]
        local nextNum   = WHEEL_STRIP[nextIdx]

        fill(wx + 6, wy + 6, 9, 7, C.wheelInner)

        -- Top Line
        local topStr = tostring(prevNum)
        if prevNum < 10 then topStr = " " .. topStr end
        writeAt(wx + 9, wy + 7, topStr, C.text, getNumberColor(prevNum))

        -- Center Focused Line (FIXED: Fixed spacing syntax bug here)
        local midStr = tostring(centerNum)
        if centerNum < 10 then midStr = " " .. midStr end
        
        local arrowCol = C.chipGold
        local textCol = C.text
        if phase == "results" and hasBets then
            arrowCol = (payout > 0) and C.win or C.loss
            if getNumberColor(centerNum) == colours.lime then
                textCol = colours.black
            else
                textCol = C.text
            end
        end
        writeAt(wx + 6, wy + 9, "> " .. midStr .. " <", arrowCol, getNumberColor(centerNum))

        -- Bottom Line
        local botStr = tostring(nextNum)
        if nextNum < 10 then botStr = " " .. botStr end
        writeAt(wx + 9, wy + 11, botStr, C.text, getNumberColor(nextNum))
    else
        drawCellButton(wx + 8, wy + 8, 5, 3, "IDLE", "", C.btnBg, colours.black, colours.black)
    end
    
    -- Status footer context
    local statusStr = "PLACE BETS"
    local statusColor = C.text
    if phase == "spinning" then 
        statusStr = "SPINNING..."
        statusColor = C.chipGold
    elseif phase == "results" then 
        if not hasBets then
            statusStr = "NO BETS"
            statusColor = colours.lightGrey
        elseif payout > 0 then
            statusStr = "YOU WON!"
            statusColor = C.win
        else
            statusStr = "YOU LOST"
            statusColor = C.loss
        end
    end
    centreInZone(wx, wx + wheelW - 1, wy + wheelH, statusStr, statusColor, C.felt)
end

local function drawBottomPanel(canSpin, hasBets, state)
    local panelY = H - 4
    local btnW = 16
    local btnH = 3
    local phase = state.phase or "betting"

    if hasBets and phase == "betting" then
        makeButton(4, panelY, btnW, btnH, "clear", " CLEAR BETS ", "", C.btnClear, C.text, C.text)
    else
        drawCellButton(4, panelY, btnW, btnH, " CLEAR BETS ", "", C.btnBg, colours.grey, colours.grey)
    end

    local tx = 23
    writeAt(tx, panelY,     "• Tap layout to place chips", C.text, C.felt)
    writeAt(tx, panelY + 1, "• Payout calculation is automatic", C.text, C.felt)
    writeAt(tx, panelY + 2, "• High risk pays up to 35:1", C.chipGold, C.felt)

    -- Net Value Cash flow Panel
    if phase == "results" then
        local rx = 58
        local rw = 22
        fill(rx, panelY, rw, btnH, C.header)
        
        local c = getNumberColor(state.winningNumber)
        local numFg = (c == colours.lime) and colours.black or C.text
        writeAt(rx + 1, panelY + 1, "NUM:", C.text, C.header)
        drawCellButton(rx + 5, panelY + 1, 4, 1, tostring(state.winningNumber), "", c, numFg, numFg)

        local totalBetAmount = 0
        local function getChipValue(v)
            if v == 1 then return 1 elseif v == 2 then return 2 elseif v == 4 then return 4 elseif v == "max" then return 10 end
            return 0
        end
        if state.bets then
            for _, val in pairs(state.bets) do totalBetAmount = totalBetAmount + getChipValue(val) end
        end

        if not hasBets then
            writeAt(rx + 10, panelY + 1, "  NO BETS", colours.lightGrey, C.header)
        elseif state.payout and state.payout > 0 then
            local netProfit = state.payout - totalBetAmount
            writeAt(rx + 10, panelY + 1, "WON +" .. netProfit .. " \x13", C.win, C.header)
        else
            writeAt(rx + 10, panelY + 1, "LOST -" .. totalBetAmount .. " \x15", C.loss, C.header)
        end
    end

    local sx = W - btnW - 4
    if canSpin and hasBets and phase == "betting" then
        makeButton(sx, panelY, btnW, btnH, "spin", " SPIN WHEEL \x10 ", "", C.btnSpin, colours.black, colours.black)
    else
        drawCellButton(sx, panelY, btnW, btnH, " SPIN WHEEL \x10 ", "", C.btnBg, colours.grey, colours.grey)
    end
end

function ROULETTE_UI.getWheelStrip()
    return WHEEL_STRIP
end

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
    fill(1, 3, W, H - 2, C.felt)

    local phase = state.phase or "betting"  
    local queue = state.queueChips or 0
    local bets  = state.bets or {}

    local hasBets = false
    for _ in pairs(bets) do hasBets = true break end

    drawHeader(queue, state.playerName)

    local activeNum = (phase == "spinning") and state.activeSpinNumber or state.winningNumber
    drawWidescreenBoard(bets)
    drawRealWheel(activeNum, phase, state.spinTick or 0, state.payout, hasBets)
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