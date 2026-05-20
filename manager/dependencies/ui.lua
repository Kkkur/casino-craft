-- ui.lua

local Currency    = dofile("dependencies/currency.lua")
local UI       = {}

-- Color palette
local C = {
    bg          = colors.black,
    header      = colors.yellow,
    headerBg    = colors.gray,
    accent      = colors.orange,
    online      = colors.lime,
    offline     = colors.red,
    disabled    = colors.gray,
    text        = colors.white,
    dimText     = colors.lightGray,
    selected    = colors.cyan,
    selectedBg  = colors.blue,
    profit      = colors.lime,
    loss        = colors.red,
    border      = colors.gray,
    titleBg     = colors.orange,
    titleFg     = colors.black,
    statBg      = colors.gray,
    inputBg     = colors.lightGray,
    inputFg     = colors.black,
    btnBg       = colors.blue,
    btnFg       = colors.white,
    btnAlt      = colors.orange,
    btnAltFg    = colors.black,
    reserve     = colors.cyan,
}

local mon       = nil
local W, H      = 0, 0
local state     = {
    screen       = "list",   
    selectedIdx  = 1,
    machines     = {},
    globalStats  = {},
    scrollOffset = 0,
    statusMsg    = "",
    statusTimer  = 0,
    configField  = 1,        
    configDraft  = {},       
}

function UI.init(monSide)
    if monSide then
        mon = peripheral.wrap(monSide)
    else
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "monitor" then
                mon = peripheral.wrap(name)
                break
            end
        end
    end
    if not mon then error("No monitor found") end
    mon.setTextScale(0.5)
    W, H = mon.getSize()
    mon.setBackgroundColor(C.bg)
    mon.clear()
    return W, H
end

local function setCursor(x, y) mon.setCursorPos(x, y) end
local function setFg(c)        mon.setTextColor(c) end
local function setBg(c)        mon.setBackgroundColor(c) end
local function write(s)        mon.write(s) end

local function fillLine(y, char, fg, bg)
    char = char or " "
    setBg(bg or C.bg)
    setFg(fg or C.text)
    setCursor(1, y)
    write(string.rep(char, W))
end

local function writeAt(x, y, s, fg, bg)
    if bg then setBg(bg) end
    if fg then setFg(fg) end
    setCursor(x, y)
    write(s)
end

local function pad(s, len, right)
    s = tostring(s)
    if #s >= len then return s:sub(1, len) end
    local space = string.rep(" ", len - #s)
    return right and (space .. s) or (s .. space)
end

local function centerStr(s, width)
    width = width or W
    local pad2 = math.floor((width - #s) / 2)
    return string.rep(" ", math.max(0, pad2)) .. s
end

local function drawBox(x, y, w, h, fg, bg)
    setBg(bg or C.bg)
    setFg(fg or C.border)
    setCursor(x, y)
    write("+" .. string.rep("-", w - 2) .. "+")
    for row = y + 1, y + h - 2 do
        setCursor(x, row)
        write("|")
        setCursor(x + w - 1, row)
        write("|")
    end
    setCursor(x, y + h - 1)
    write("+" .. string.rep("-", w - 2) .. "+")
end

-- HEADER (rows 1-2)
local function drawHeader(globalStats)
    fillLine(1, " ", C.titleFg, C.titleBg)
    writeAt(1, 1, centerStr("** CASINO MANAGER **", W), C.titleFg, C.titleBg)

    fillLine(2, " ", C.dimText, C.headerBg)
    local gs = globalStats or state.globalStats


    local onlineStr = "Online: " .. (gs.online or 0) .. "/" .. (gs.total or 0)

    local profit    = gs.profit or 0
    local netStr    = "Net: " .. (profit >= 0 and "+" or "-")
                      .. Currency.format(math.abs(profit))

    local reserve   = gs.reserveSpurs or 0
    local resStr    = "Res: " .. Currency.format(reserve)

    local playsStr  = "Plays: " .. (gs.totalPlays or 0)

    local inner     = W - 2 - #onlineStr - #playsStr
    local gap       = math.floor((inner - #netStr - #resStr) / 3)
    gap             = math.max(1, gap)

    local xOnline   = 2
    local xNet      = xOnline + #onlineStr + gap
    local xRes      = xNet + #netStr + gap
    local xPlays    = W - #playsStr

    if xRes + #resStr >= xPlays then
        xRes = xPlays - #resStr - 1
    end

    writeAt(xOnline, 2, onlineStr, C.online,  C.headerBg)
    writeAt(xNet,    2, netStr,    profit >= 0 and C.profit or C.loss, C.headerBg)
    writeAt(xRes,    2, resStr,    C.reserve,  C.headerBg)
    writeAt(xPlays,  2, playsStr,  C.dimText,  C.headerBg)
end

-- STATUS BAR (last row)
local function drawStatus()
    fillLine(H, " ", C.dimText, C.headerBg)
    local msg = state.statusMsg ~= "" and state.statusMsg or
        "[Q]uit [A]dd [R]efresh  Nav:[Up/Down] [Enter]Select"
    writeAt(2, H, msg:sub(1, W - 2), C.dimText, C.headerBg)
end

-- MACHINE LIST SCREEN

local MACHINE_ROW_H = 4   -- rows per machine card
local LIST_START_Y  = 3   -- after header

local function drawMachineCard(machine, rowY, selected)
    local cardBg  = selected and C.selectedBg or C.bg
    local cardFg  = selected and C.selected   or C.text
    local statFg  = machine.online and C.online or C.offline
    local statStr = machine.online and "ONLINE" or "OFFLINE"
    if not machine.enabled then
        statFg  = C.disabled
        statStr = "DISABLD"
    end

    for dy = 0, MACHINE_ROW_H - 2 do
        fillLine(rowY + dy, " ", cardFg, cardBg)
    end

    local slotTag = string.format("[%02d]", machine.slot)
    local label   = pad(machine.label, W - #slotTag - #statStr - 4)
    writeAt(1, rowY, slotTag .. " " .. label .. " " .. statStr,
        selected and C.selected or C.text, cardBg)
    writeAt(W - #statStr, rowY, statStr, statFg, cardBg)

    local inStr   = "In:"  .. Currency.format(machine.totalIn  or 0, 2)
    local outStr  = "Out:" .. Currency.format(machine.totalOut or 0, 2)
    local profit  = (machine.totalIn or 0) - (machine.totalOut or 0)
    local profStr = "Net:" .. Currency.format(profit, 2)
    local winStr  = "Win:" .. (machine.winPercent or 0) .. "%"

    writeAt(2, rowY + 1, pad(inStr, 18), C.dimText, cardBg)
    writeAt(20, rowY + 1, pad(outStr, 18), C.dimText, cardBg)
    writeAt(38, rowY + 1, pad(profStr, 16), profit >= 0 and C.profit or C.loss, cardBg)
    writeAt(W - #winStr, rowY + 1, winStr, C.accent, cardBg)

    fillLine(rowY + 2, string.rep("-", W), C.border, C.bg)
end

local function drawListScreen()
    local machines   = state.machines
    local visibleRows = math.floor((H - LIST_START_Y - 1) / MACHINE_ROW_H)
    local offset     = state.scrollOffset

    for i = 1, visibleRows do
        local mIdx = i + offset
        local rowY = LIST_START_Y + (i - 1) * MACHINE_ROW_H
        if machines[mIdx] then
            drawMachineCard(machines[mIdx], rowY, mIdx == state.selectedIdx)
        else
            for dy = 0, MACHINE_ROW_H - 1 do
                fillLine(rowY + dy, " ", C.bg, C.bg)
            end
        end
    end

    if #machines > visibleRows then
        local pct = math.floor(offset / (#machines - visibleRows) * (H - LIST_START_Y - 2))
        writeAt(W, LIST_START_Y + pct, "*", C.accent)
    end
end

-- DETAIL SCREEN (single machine)
local function drawDetailScreen()
    local m = state.machines[state.selectedIdx]
    if not m then
        writeAt(2, 4, "No machine selected.", C.dimText)
        return
    end

    local profit = (m.totalIn or 0) - (m.totalOut or 0)
    local houseEdge = m.totalIn > 0
        and string.format("%.1f%%", (profit / m.totalIn) * 100)
        or "N/A"

    local rows = {
        { label = "Label",       value = m.label },
        { label = "Machine ID",  value = tostring(m.id) },
        { label = "Slot",        value = tostring(m.slot) },
        { label = "Status",      value = m.online and "Online" or "Offline",
          color = m.online and C.online or C.offline },
        { label = "Enabled",     value = m.enabled and "Yes" or "No",
          color = m.enabled and C.online or C.disabled },
        { label = "Win %",       value = (m.winPercent or 0) .. "%" },
        { label = "Total Plays", value = tostring(m.totalPlays or 0) },
        { label = "Total In",    value = Currency.formatLong(m.totalIn  or 0) },
        { label = "Total Out",   value = Currency.formatLong(m.totalOut or 0) },
        { label = "Net Profit",  value = Currency.formatLong(profit),
          color = profit >= 0 and C.profit or C.loss },
        { label = "House Edge",  value = houseEdge },
    }

    local y = LIST_START_Y
    for _, row in ipairs(rows) do
        if y >= H - 1 then break end
        fillLine(y, " ", C.text, C.bg)
        local lbl = pad(row.label .. ":", 14)
        writeAt(2, y, lbl, C.dimText)
        writeAt(16, y, row.value, row.color or C.text)
        y = y + 1
    end

    for cy = y, H - 1 do fillLine(cy, " ", C.bg, C.bg) end

    -- Footer hint
    fillLine(H, " ", C.dimText, C.headerBg)
    writeAt(2, H, "[Esc]Back  [C]onfig  [T]oggle  [P]ing  [R]eset Stats", C.dimText, C.headerBg)
end

-- CONFIG SCREEN
local CONFIG_FIELDS = {
    { key = "label",      label = "Label",   type = "string" },
    { key = "winPercent", label = "Win %",   type = "number", min = 1, max = 99 },
    { key = "enabled",    label = "Enabled", type = "bool"   },
}

local function drawConfigScreen()
    local m = state.machines[state.selectedIdx]
    if not m then return end

    writeAt(1, LIST_START_Y, centerStr("CONFIG: " .. m.label, W), C.titleFg, C.titleBg)

    local y = LIST_START_Y + 2
    for i, field in ipairs(CONFIG_FIELDS) do
        local isSel = i == state.configField
        local val   = tostring(state.configDraft[field.key] or "")

        fillLine(y, " ", C.bg, C.bg)
        local lbl = pad(field.label .. ":", 12)
        writeAt(2, y, lbl, isSel and C.selected or C.dimText)

        local valBg = isSel and C.inputBg or C.bg
        local valFg = isSel and C.inputFg or C.text
        writeAt(14, y, pad("[" .. val .. "]", W - 14), valFg, valBg)
        y = y + 2
    end

    fillLine(H, " ", C.dimText, C.headerBg)
    writeAt(2, H, "[Esc]Cancel  [Up/Down]Field  [Enter]Edit  [S]Save", C.dimText, C.headerBg)
end

-- PUBLIC API

function UI.setMachines(machines, globalStats)
    state.machines   = machines
    state.globalStats = globalStats
end

function UI.setStatus(msg, duration)
    state.statusMsg   = msg
    state.statusTimer = duration or 3
end

function UI.getSelectedMachine()
    return state.machines[state.selectedIdx]
end

function UI.getScreen() return state.screen end

function UI.navigate(dir)
    local max = #state.machines
    if max == 0 then return end
    state.selectedIdx = state.selectedIdx + dir
    if state.selectedIdx < 1 then state.selectedIdx = max end
    if state.selectedIdx > max then state.selectedIdx = 1 end

    -- Adjust scroll
    local visibleRows = math.floor((H - LIST_START_Y - 1) / MACHINE_ROW_H)
    if state.selectedIdx <= state.scrollOffset then
        state.scrollOffset = state.selectedIdx - 1
    elseif state.selectedIdx > state.scrollOffset + visibleRows then
        state.scrollOffset = state.selectedIdx - visibleRows
    end
end

function UI.openDetail()
    state.screen = "detail"
end

function UI.openConfig()
    local m = state.machines[state.selectedIdx]
    if not m then return end
    state.screen      = "config"
    state.configField = 1
    state.configDraft = {
        label      = m.label,
        winPercent = m.winPercent,
        enabled    = m.enabled,
    }
end

function UI.closeConfig()
    state.screen = "detail"
end

function UI.backToList()
    state.screen = "list"
end

function UI.getConfigDraft() return state.configDraft end

function UI.configNav(dir)
    state.configField = state.configField + dir
    if state.configField < 1 then state.configField = #CONFIG_FIELDS end
    if state.configField > #CONFIG_FIELDS then state.configField = 1 end
end

function UI.getCurrentConfigField()
    return CONFIG_FIELDS[state.configField]
end

function UI.setConfigDraftValue(key, value)
    state.configDraft[key] = value
end

-- Full redraw
function UI.draw()
    mon.setBackgroundColor(C.bg)
    mon.clear()

    drawHeader(state.globalStats)

    if state.screen == "list" then
        drawListScreen()
        drawStatus()
    elseif state.screen == "detail" then
        drawDetailScreen()
    elseif state.screen == "config" then
        drawConfigScreen()
    end

    -- Status message override on list screen
    if state.screen == "list" and state.statusMsg ~= "" then
        fillLine(H, " ", C.accent, C.headerBg)
        writeAt(2, H, state.statusMsg:sub(1, W - 2), C.accent, C.headerBg)
    end
end

return UI