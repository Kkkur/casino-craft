-- ========================================================================== --
--  Roulette UI Rendering
--  Renders roulette game perfectly scaled for 100x38.
--  Uses ui_lib for shared primitives and a window-based back-buffer to
--  eliminate the flicker that occurred when drawing directly to the monitor
--  on every spin tick.
-- ========================================================================== --

local UI = dofile("games/libraries/ui_lib.lua")

local ROULETTE_UI = {}

-- Roulette-specific colour aliases that have no equivalent in ui_lib.
-- Everything that maps to an existing ui_lib colour references UI.C directly.
local C = {
    felt       = colours.green,
    feltDark   = colours.lime,
    numRed     = colours.red,
    numBlack   = colours.grey,
    numGreen   = colours.lime,
    chipGold   = UI.C.chipGold,
    win        = UI.C.win,
    loss       = UI.C.loss,
    btnBg      = colours.lightGrey,
    btnText    = colours.black,
    btnSpin    = colours.lime,
    btnClear   = colours.red,
    queueText  = UI.C.queueText,
    header     = UI.C.header,
    headerText = UI.C.headerText,
    text       = UI.C.text,
    dimText    = UI.C.dimText,
    wheelWood  = colours.brown,
    wheelInner = colours.black,
}

-- Back-buffer: a window() created over the physical monitor.
-- All draw calls target `buf`; UI.getMonitor() still returns the raw mon.
local mon, buf

local WHEEL_STRIP = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
    19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36
}

-- -------------------------------------------------------------------------- --
-- Buffer helpers (thin wrappers so local code stays readable)
-- -------------------------------------------------------------------------- --

local function bg(col)   buf.setBackgroundColor(col) end
local function fg(col)   buf.setTextColor(col)       end
local function cur(x, y) buf.setCursorPos(x, y)      end

local function fill(x, y, w, h, col)
    bg(col)
    local row = string.rep(" ", w)
    for dy = 0, h - 1 do
        cur(x, y + dy)
        buf.write(row)
    end
end

local function writeAt(x, y, text, fgCol, bgCol)
    if bgCol then bg(bgCol) end
    if fgCol then fg(fgCol) end
    cur(x, y)
    buf.write(text)
end

local function centreInZone(xStart, xEnd, y, text, fgCol, bgCol)
    local zoneW = xEnd - xStart + 1
    local x = xStart + math.floor((zoneW - #text) / 2)
    writeAt(x, y, text, fgCol, bgCol)
end

-- -------------------------------------------------------------------------- --
-- Helpers
-- -------------------------------------------------------------------------- --

local function getNumberColor(num)
    if num == 0 then return C.numGreen end
    return (num % 2 ~= 0) and C.numRed or C.numBlack
end

-- -------------------------------------------------------------------------- --
-- Buttons
-- -------------------------------------------------------------------------- --

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
    table.insert(ROULETTE_UI.buttons, {action = action, x = x, y = y, w = w, h = h})
end

-- -------------------------------------------------------------------------- --
-- Scene components
-- -------------------------------------------------------------------------- --

local function drawHeader(queueChips, playerName)
    -- Reuse ui_lib's header layout via raw buf writes so we stay on the buffer.
    fill(1, 1, UI.W, 2, C.header)
    writeAt(3, 1, " \x04 CASINO ROULETTE LIVE ", C.headerText, C.header)
    local qStr = "Chips In Queue: " .. queueChips .. " "
    writeAt(UI.W - #qStr - 2, 1, qStr, C.queueText, C.header)
    if playerName then
        writeAt(3, 2, "Active Player: " .. playerName, C.dimText, C.header)
    end
end

local function drawWidescreenBoard(currentBets)
    local startX, startY, cellW, cellH, zeroW = 4, 5, 4, 4, 5

    local function getBetLabel(val)
        if not val or val == 0 or val == "none" then return ""
        elseif val < 10 then return "[" .. val .. " ]"
        else return "[" .. val .. "]" end
    end

    -- Zero box
    local zBetVal = currentBets["0"]
    local zBg  = zBetVal and C.chipGold or C.numGreen
    local zFg  = zBetVal and C.btnText  or C.text
    local zBetStr = getBetLabel(zBetVal)

    fill(startX, startY, zeroW, cellH * 3, zBg)
    centreInZone(startX, startX + zeroW - 1, startY + 5, "0", zFg, zBg)
    if zBetStr ~= "" then
        centreInZone(startX, startX + zeroW - 1, startY + 7, zBetStr, C.btnText, C.chipGold)
    end
    table.insert(ROULETTE_UI.buttons, {action = "bet:0", x = startX, y = startY, w = zeroW, h = cellH * 3 + 2})

    -- Numbers grid
    for num = 1, 36 do
        local colIdx = (num - 1) % 3
        local rowIdx = math.floor((num - 1) / 3)
        local cx = startX + zeroW + 1 + (rowIdx * (cellW + 1))
        local cy = startY + ((2 - colIdx) * cellH)

        local betVal  = currentBets["num_" .. num]
        local cellBg  = betVal and C.chipGold or getNumberColor(num)
        local numFg   = betVal and C.btnText  or C.text
        local betStr  = getBetLabel(betVal)

        makeButton(cx, cy, cellW, cellH, "bet:num_" .. num, tostring(num), betStr, cellBg, numFg, C.btnText)
    end

    -- Dozen bars
    local dozY = startY + (cellH * 3) + 1
    local dozW = 19
    local dozens = {
        {lbl = "1st 12", act = "doz1"},
        {lbl = "2nd 12", act = "doz2"},
        {lbl = "3rd 12", act = "doz3"},
    }
    for i, doz in ipairs(dozens) do
        local dx = startX + zeroW + 1 + ((i - 1) * (dozW + 1))
        local betVal = currentBets[doz.act]
        local bgCol  = betVal and C.chipGold or C.btnBg
        local displayStr = betVal and (doz.lbl .. " " .. getBetLabel(betVal)) or doz.lbl
        makeButton(dx, dozY, dozW, 3, "bet:" .. doz.act, displayStr, "", bgCol, C.btnText, C.btnText)
    end

    -- Outside options
    local outY = dozY + 4
    local outW = 9
    local outsideOptions = {
        {lbl = "1-18",  act = "low",   bg = C.btnBg,    fg = C.btnText},
        {lbl = "EVEN",  act = "even",  bg = C.btnBg,    fg = C.btnText},
        {lbl = "RED",   act = "red",   bg = C.numRed,   fg = C.text},
        {lbl = "BLACK", act = "black", bg = C.numBlack, fg = C.text},
        {lbl = "ODD",   act = "odd",   bg = C.btnBg,    fg = C.btnText},
        {lbl = "19-36", act = "high",  bg = C.btnBg,    fg = C.btnText},
    }
    for i, opt in ipairs(outsideOptions) do
        local ox = startX + zeroW + 1 + ((i - 1) * (outW + 1))
        local betVal = currentBets[opt.act]
        local displayBg  = betVal and C.chipGold or opt.bg
        local displayFg  = betVal and C.btnText  or opt.fg
        local displayStr = betVal and (opt.lbl .. " " .. getBetLabel(betVal)) or opt.lbl
        makeButton(ox, outY, outW, 3, "bet:" .. opt.act, displayStr, "", displayBg, displayFg, displayFg)
    end
end

local function drawRealWheel(activeNumber, phase, tick)
    local wheelW, wheelH = 21, 19
    local wx, wy = UI.W - wheelW - 4, 5
    tick = tick or 0

    fill(wx, wy, wheelW, wheelH, C.wheelWood)
    fill(wx + 2, wy + 1, wheelW - 4, wheelH - 2, C.wheelInner)

    local frames = {
        [0] = {"|", "/", "-", "\\", "|", "/", "-", "\\"},
        [1] = {"/", "-", "\\", "|", "/", "-", "\\", "|"},
        [2] = {"-", "\\", "|", "/", "-", "\\", "|", "/"},
        [3] = {"\\", "|", "/", "-", "\\", "|", "/", "-"},
    }
    local pattern = frames[tick % 4]
    for i = 2, wheelH - 3 do
        writeAt(wx + 10, wy + i, pattern[1], C.text, C.wheelInner)
    end
    writeAt(wx + 3, wy + 9,
        string.rep(pattern[3], 5) .. "[   ]" .. string.rep(pattern[3], 5),
        C.text, C.wheelInner)

    if activeNumber then
        local baseIdx = 1
        local len = #WHEEL_STRIP
        for idx, val in ipairs(WHEEL_STRIP) do
            if val == activeNumber then baseIdx = idx break end
        end

        local prevNum   = WHEEL_STRIP[(baseIdx - 2 + len) % len + 1]
        local centerNum = WHEEL_STRIP[baseIdx]
        local nextNum   = WHEEL_STRIP[(baseIdx % len) + 1]

        fill(wx + 6, wy + 6, 9, 7, C.wheelInner)
        local topStr = (prevNum   < 10 and " " or "") .. prevNum
        local midStr = (centerNum < 10 and " " or "") .. centerNum
        local botStr = (nextNum   < 10 and " " or "") .. nextNum

        writeAt(wx + 9, wy + 7,  topStr, C.text, getNumberColor(prevNum))
        writeAt(wx + 7, wy + 9,  "> " .. midStr .. " <",
            (phase == "results" and C.text or C.chipGold), getNumberColor(centerNum))
        writeAt(wx + 9, wy + 11, botStr, C.text, getNumberColor(nextNum))
    end

    local statusStr =
        (phase == "spinning" and "SPINNING...") or
        (phase == "results"  and "CLICK ANYWHERE TO RESTART") or
        "PLACE BETS"
    centreInZone(wx, wx + wheelW - 1, wy + wheelH + 1,
        statusStr, (phase == "spinning" and C.chipGold or C.text), C.felt)
end

local function drawBottomPanel(hasBets, state)
    local panelY = UI.H - 4
    local btnW   = 16
    local btnH   = 3
    local phase  = state.phase or "betting"

    -- Clear bets button
    if hasBets and phase == "betting" then
        makeButton(4, panelY, btnW, btnH, "clear",
            " CLEAR BETS ", "", C.btnClear, C.text, C.text)
    else
        drawCellButton(4, panelY, btnW, btnH,
            " CLEAR BETS ", "", C.btnBg, colours.grey, colours.grey)
    end

    -- Hint text
    local tx = 22
    writeAt(tx, panelY,     "- Tap layout to place chips",                  C.text,     C.felt)
    writeAt(tx, panelY + 1, "- You can click multiple time to cycle wages", C.text,     C.felt)
    writeAt(tx, panelY + 2, "- High risk pays up to 35:1",                  C.chipGold, C.felt)

    -- Results panel
    if phase == "results" then
        local rx, rw = 58, 22
        fill(rx, panelY, rw, btnH, C.header)
        writeAt(rx + 1, panelY + 1, "NUM:", C.text, C.header)
        local nc = getNumberColor(state.winningNumber)
        local formattedNum = (state.winningNumber < 10 and " " or "") .. state.winningNumber .. " "
        writeAt(rx + 5, panelY + 1, formattedNum,
            (nc == C.numGreen and colours.black or C.text), nc)

        local totalBet = 0
        for _, val in pairs(state.bets) do totalBet = totalBet + (val or 0) end

        if not hasBets then
            writeAt(rx + 10, panelY + 1, "  NO BETS", colours.lightGrey, C.header)
        else
            local net = (state.lastPayout or 0) - totalBet
            if net > 0 then
                writeAt(rx + 10, panelY + 1, "WON +" .. net .. " \x13", C.win, C.header)
            elseif net < 0 then
                writeAt(rx + 10, panelY + 1, "LOST -" .. math.abs(net) .. " \x15", C.loss, C.header)
            else
                writeAt(rx + 10, panelY + 1, "PUSH +0", colours.lightGrey, C.header)
            end
        end
    end

    -- Spin button
    local sx = UI.W - btnW - 4
    if hasBets and phase == "betting" then
        makeButton(sx, panelY, btnW, btnH, "spin",
            " SPIN WHEEL \x10 ", "", C.btnSpin, C.btnText, C.btnText)
    else
        drawCellButton(sx, panelY, btnW, btnH,
            " SPIN WHEEL \x10 ", "", C.btnBg, colours.grey, colours.grey)
    end
end

-- -------------------------------------------------------------------------- --
-- Public API
-- -------------------------------------------------------------------------- --

function ROULETTE_UI.getWheelStrip() return WHEEL_STRIP end

function ROULETTE_UI.init(monitor)
    mon = monitor
    mon.setTextScale(0.5)
    UI.W, UI.H = mon.getSize()

    -- Create a full-screen back-buffer window on top of the physical monitor.
    -- Drawing into `buf` is identical to drawing into `mon` from the caller's
    -- perspective, but nothing appears on screen until buf.setVisible(true) is
    -- called.  We toggle visibility once per frame (see ROULETTE_UI.draw).
    buf = window.create(mon, 1, 1, UI.W, UI.H, false)

    mon.clear()
end

function ROULETTE_UI.getSize() return UI.W, UI.H end

function ROULETTE_UI.draw(state)
    -- Hide the buffer while we rebuild it so the monitor stays static.
    buf.setVisible(false)

    ROULETTE_UI.buttons = {}

    -- Background felt
    bg(C.felt)
    buf.clear()
    fill(1, 3, UI.W, UI.H - 2, C.felt)

    drawHeader(state.queueChips or 0, state.playerName)
    drawWidescreenBoard(state.bets or {})

    local spinNum = (state.phase == "spinning") and state.activeSpinNumber or state.winningNumber
    drawRealWheel(spinNum, state.phase or "betting", state.spinTick or 0)

    local hasBets = ROULETTE.getTotalBets ~= nil
        and ROULETTE.getTotalBets(state) > 0
        or next(state.bets or {}) ~= nil
    drawBottomPanel(hasBets, state)

    -- Flip the back-buffer to the screen in one atomic blit.
    buf.setVisible(true)
end

function ROULETTE_UI.hitTest(x, y)
    for _, btn in ipairs(ROULETTE_UI.buttons) do
        if x >= btn.x and x < btn.x + btn.w and
           y >= btn.y and y < btn.y + btn.h then
            return btn.action
        end
    end
    return nil
end

return ROULETTE_UI