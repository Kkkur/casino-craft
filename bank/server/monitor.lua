-- bank/server/monitor.lua

local monitor = {}

local ledger   = dofile("/bank/server/ledger.lua")
local profiles = dofile("/bank/server/profiles.lua")
local Currency = dofile("/libraries/currencylib.lua")

local rednetHandler = nil
local _log          = nil
local _vault        = nil
local _casinoNet    = nil

function monitor.setRednet(rh)    rednetHandler = rh end
function monitor.setVault(v)      _vault = v         end
function monitor.setCasinoNet(cn) _casinoNet = cn    end

local _mon  = nil
local _W    = 0
local _H    = 0
local _tab  = "ledger"
local _buttons = {}

local TAB_LEDGER   = "ledger"
local TAB_SECURITY = "security"

function monitor.init(peripheralName, logger)
    _log = logger
    _mon = peripheral.wrap(peripheralName)
    if not _mon then
        if _log then _log.error("Cannot wrap monitor: '" .. tostring(peripheralName) .. "'") end
        error("monitor: could not wrap '" .. tostring(peripheralName) .. "'")
    end
    _mon.setTextScale(0.5)
    _W, _H = _mon.getSize()
    -- Right panel starts just past the midpoint, with a 1-column divider gap.
    _splitX = math.floor(_W / 2) + 2
    if _log then _log.info("Monitor init: " .. peripheralName .. " size=" .. _W .. "x" .. _H .. " splitX=" .. _splitX) end
end

-- draw primitives 

local function fill(y, bg)
    _mon.setCursorPos(1, y)
    _mon.setBackgroundColor(bg)
    _mon.write(string.rep(" ", _W))
    _mon.setBackgroundColor(colours.black)
end

local function writeAt(x, y, text, fg, bg)
    _mon.setCursorPos(x, y)
    _mon.setBackgroundColor(bg or colours.black)
    _mon.setTextColor(fg)
    local maxLen = _W - x + 1
    if #text > maxLen then text = text:sub(1, maxLen) end
    _mon.write(text)
    _mon.setBackgroundColor(colours.black)
    _mon.setTextColor(colours.white)
end

local function centered(text, y, fg, bg)
    local x = math.floor((_W - #text) / 2) + 1
    if x < 1 then x = 1 end
    writeAt(x, y, text, fg, bg or colours.black)
end

local function regBtn(label, x1, y1, x2, y2)
    _buttons[label] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
end

local function drawBtn(label, x, y, w, bg, fg)
    fg = fg or colours.white
    _mon.setCursorPos(x, y)
    _mon.setBackgroundColor(bg)
    _mon.setTextColor(fg)
    local pad = math.floor((w - #label) / 2)
    _mon.write(string.rep(" ", pad) .. label .. string.rep(" ", w - pad - #label))
    _mon.setBackgroundColor(colours.black)
    _mon.setTextColor(colours.white)
    regBtn(label, x, y, x + w - 1, y)
end

-- Like writeAt but clamps text to not exceed column maxX (1-based inclusive).
local function writeAtC(x, y, text, fg, bg, maxX)
    maxX = maxX or _W
    local maxLen = maxX - x + 1
    if maxLen <= 0 then return end
    if #text > maxLen then text = text:sub(1, maxLen) end
    writeAt(x, y, text, fg, bg)
end

-- casino dashboard drawn in the right half of the monitor.
-- lx: first column of the right panel (1-based).
local function drawCasinoDashboard(lx)
    if not _casinoNet then return end

    local rw       = _W - lx + 1
    local machines = _casinoNet.getMachines()
    local netChips = _casinoNet.getNetChips()
    local inPanic  = _casinoNet.isInPanic()

    local function rfill(y, bg)
        _mon.setCursorPos(lx, y)
        _mon.setBackgroundColor(bg)
        _mon.write(string.rep(" ", rw))
        _mon.setBackgroundColor(colours.black)
    end

    -- Header row 1 (replaces the full-width bank header on this half)
    rfill(1, colours.grey)
    local hdr = "\5 CASINO \5"
    _mon.setCursorPos(lx + math.floor((rw - #hdr) / 2), 1)
    _mon.setBackgroundColor(colours.grey)
    _mon.setTextColor(colours.white)
    _mon.write(hdr)
    _mon.setBackgroundColor(colours.black)

    -- Status row 2: net_chips and panic state
    rfill(2, colours.black)
    local netStr    = "Net: " .. netChips .. "c"
    local statusStr = inPanic and "PANIC" or "NORMAL"
    local statusFg  = inPanic and colours.red or colours.lime
    local function writeR(x, y, text, fg)
        if x > _W then return end
        _mon.setCursorPos(x, y)
        _mon.setBackgroundColor(colours.black)
        _mon.setTextColor(fg)
        local maxLen = _W - x + 1
        if #text > maxLen then text = text:sub(1, maxLen) end
        _mon.write(text)
        _mon.setBackgroundColor(colours.black)
        _mon.setTextColor(colours.white)
    end
    writeR(lx + 1, 2, netStr, colours.yellow)
    writeR(_W - #statusStr, 2, statusStr, statusFg)

    -- Column header row 3
    rfill(3, colours.grey)
    writeR(lx + 1, 3, "MACHINE", colours.lightGrey)
    writeR(lx + 10, 3, "PLY",    colours.lightGrey)
    writeR(lx + 14, 3, "IN",     colours.lightGrey)
    writeR(lx + 19, 3, "OUT",    colours.lightGrey)
    writeR(lx + 24, 3, "NET",    colours.lightGrey)

    -- Machine rows starting at row 4
    local row = 4
    local sorted = {}
    for _, m in pairs(machines) do table.insert(sorted, m) end
    table.sort(sorted, function(a, b) return (a.label or "") < (b.label or "") end)

    for _, m in ipairs(sorted) do
        if row > _H - 1 then break end
        rfill(row, colours.black)

        local dotFg = m.online and colours.lime or colours.grey
        local net   = m.chipsIn - m.chipsOut
        local netFg = net >= 0 and colours.lime or colours.red

        _mon.setCursorPos(lx + 1, row)
        _mon.setBackgroundColor(colours.black)
        _mon.setTextColor(dotFg)
        _mon.write("\7")

        local label = (m.label or "?"):sub(1, 8)
        writeR(lx + 3,  row, label,              colours.cyan)
        writeR(lx + 12, row, tostring(m.plays),   colours.white)
        writeR(lx + 16, row, tostring(m.chipsIn),  colours.white)
        writeR(lx + 21, row, tostring(m.chipsOut), colours.white)
        writeR(lx + 26, row, tostring(net),        netFg)

        row = row + 1
    end

    for y = row, _H - 1 do rfill(y, colours.black) end
end

-- vertical divider between left and right panels
local function drawDivider(lx)
    for y = 1, _H do
        _mon.setCursorPos(lx - 1, y)
        _mon.setBackgroundColor(colours.grey)
        _mon.write(" ")
        _mon.setBackgroundColor(colours.black)
    end
end

-- header 

local function drawHeader()
    fill(1, colours.grey)
    centered("\4 BANK SERVER \4", 1, colours.white, colours.grey)
end

-- tab bar 

local function drawTabs()
    fill(2, colours.black)
    local half = math.floor(_W / 2)
    local lBg = (_tab == TAB_LEDGER)   and colours.cyan or colours.grey
    local sBg = (_tab == TAB_SECURITY) and colours.cyan or colours.grey
    local lFg = (_tab == TAB_LEDGER)   and colours.black or colours.white
    local sFg = (_tab == TAB_SECURITY) and colours.black or colours.white
    drawBtn("LEDGER",   1,        2, half,      lBg, lFg)
    drawBtn("SECURITY", half + 1, 2, _W - half, sBg, sFg)
end

-- ledger tab 

local function drawLedgerTab()
    local lines = ledger.tail(_H - 4)
    local row   = 3
    fill(row, colours.grey)
    writeAt(2, row, "TIME", colours.lightGrey, colours.grey)
    writeAt(8, row, "PLAYER", colours.lightGrey, colours.grey)
    writeAt(18, row, "ACTION  AMT  BEFORE→AFTER", colours.lightGrey, colours.grey)
    row = row + 1
    for y = row, _H - 1 do fill(y, colours.black) end
    for _, line in ipairs(lines) do
        if row > _H - 1 then break end
        local parts = {}
        for part in line:gmatch("[^|]+") do
            table.insert(parts, part:match("^%s*(.-)%s*$"))
        end
        if parts[2] == "SECURITY" then
            local short = (parts[3] or "") .. " " .. (parts[4] or "")
            writeAt(2, row, short, colours.orange)
        elseif parts[2] == "RECONCILE" then
            local short = (parts[3] or "") .. " " .. (parts[4] or "") .. " " .. (parts[5] or "")
            writeAt(2, row, short, colours.red)
        else
            local ts     = (parts[1] or ""):sub(-6)
            local player = (parts[2] or ""):sub(1, 8)
            local action = (parts[3] or ""):sub(1, 6)
            local amt    = parts[4] or ""
            local before = parts[5] or ""
            local after  = parts[6] or ""
            local fg = colours.white
            if action == "add"    then fg = colours.lime   end
            if action == "remove" then fg = colours.red    end
            if action == "set"    then fg = colours.yellow end
            writeAt(2,  row, ts,     colours.lightGrey)
            writeAt(8,  row, player, colours.cyan)
            writeAt(18, row, action, fg)
            writeAt(26, row, amt,    colours.white)
            writeAt(31, row, before, colours.grey)
            writeAt(37, row, after,  fg)
        end
        row = row + 1
    end
end

-- security tab 

local function drawSecurityTab()
    local alerts = rednetHandler.getAlerts()
    local row    = 3
    fill(row, colours.grey)
    local wl    = rednetHandler.getWhitelist()
    writeAt(2, row, "Whitelisted: " .. #wl .. " machine(s)", colours.white, colours.grey)
    row = row + 1
    fill(row, colours.black)
    drawBtn("CLEAR ALERTS", math.floor((_W - 14) / 2) + 1, row, 14, colours.red, colours.white)
    row = row + 1
    if #alerts == 0 then
        fill(row, colours.black)
        centered("No alerts", row, colours.grey)
        row = row + 1
    else
        for i = #alerts, 1, -1 do
            if row > _H - 1 then break end
            local a  = alerts[i]
            local ts = tostring(a.ts):sub(-6)
            fill(row, colours.black)
            writeAt(2,  row, ts,    colours.lightGrey)
            writeAt(10, row, a.msg, colours.orange)
            row = row + 1
        end
    end
    for y = row, _H - 1 do fill(y, colours.black) end
end

-- _splitX is the first column of the right (casino) panel.
-- Computed once in monitor.init() after we know _W.
local _splitX = 1

local function drawStatusBar()
    fill(_H, colours.grey)
    local top1  = profiles.top(1)
    local chips = 0
    if _vault then pcall(function() chips = _vault.coinCount() end) end
    local spurs   = Currency.chipsToSpurs(chips)
    local vStr    = "Vault: " .. chips .. "c | " .. Currency.format(spurs, 2)
    local balStr  = #top1 > 0 and ("Top: " .. top1[1].player .. " " .. top1[1].balance .. "c") or "No balances"
    -- truncate balStr so it stays in the left half
    local maxLeft = _splitX - 3
    if #balStr > maxLeft then balStr = balStr:sub(1, maxLeft) end
    writeAt(2,          _H, balStr, colours.white, colours.grey)
    writeAt(_W - #vStr, _H, vStr,  colours.lime,  colours.grey)
end

-- full redraw

local function redraw()
    _mon.clear()
    _mon.setBackgroundColor(colours.black)
    _buttons = {}

    -- Left half: existing bank tabs (header, tab bar, content, status bar).
    -- Drawing functions use _W internally; we temporarily narrow _W so text
    -- does not bleed into the right panel, then restore it.
    local fullW = _W
    _W = _splitX - 2   -- leave one column gap for the divider

    drawHeader()
    drawTabs()
    if _tab == TAB_LEDGER then drawLedgerTab()
    else drawSecurityTab() end
    drawStatusBar()

    _W = fullW

    -- Divider and right half.
    drawDivider(_splitX)
    drawCasinoDashboard(_splitX)
end

-- touch handler 

local function handleTouch(x, y)
    for label, b in pairs(_buttons) do
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
            if label == "LEDGER" then
                _tab = TAB_LEDGER
                if _log then _log.debug("Monitor: switched to Ledger tab") end
            elseif label == "SECURITY" then
                _tab = TAB_SECURITY
                if _log then _log.debug("Monitor: switched to Security tab") end
            elseif label == "CLEAR ALERTS" then
                rednetHandler.clearAlerts()
                ledger.recordSecurity("ALERTS_CLEARED", "admin via monitor")
            end
            redraw()
            return
        end
    end
end

-- run loop 

function monitor.run()
    if not _mon then error("monitor: call monitor.init() first") end
    redraw()
    local refreshTimer = os.startTimer(2)
    while true do
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "monitor_touch" then
            handleTouch(p2, p3)
        elseif ev == "timer" and p1 == refreshTimer then
            redraw()
            refreshTimer = os.startTimer(2)
        end
    end
end

return monitor