-- bank/server/monitor.lua

local monitor = {}

local ledger        = require("bank/server/ledger")
local rednetHandler = require("bank/server/rednet")
local profiles      = require("bank/server/profiles")

-- monitor is 5 wide 3 tall at scale 0.5 → 26x57 chars approx
-- we let getSize() decide at runtime
local _mon  = nil
local _W    = 0
local _H    = 0

local _tab     = "ledger"   -- "ledger" or "security"
local _buttons = {}

local TAB_LEDGER   = "ledger"
local TAB_SECURITY = "security"

function monitor.init(peripheralName)
    _mon = peripheral.wrap(peripheralName)
    if not _mon then
        error("monitor: could not wrap '" .. tostring(peripheralName) .. "'")
    end
    _mon.setTextScale(0.5)
    _W, _H = _mon.getSize()
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
    -- truncate so we never overrun the width
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

--  header 

local function drawHeader()
    fill(1, colours.grey)
    centered("\4 BANK SERVER \4", 1, colours.white, colours.grey)
end

-- tab bar 

local function drawTabs()
    fill(2, colours.black)
    local half = math.floor(_W / 2)

    local lBg = (_tab == TAB_LEDGER)   and colours.cyan  or colours.grey
    local sBg = (_tab == TAB_SECURITY) and colours.cyan  or colours.grey
    local lFg = (_tab == TAB_LEDGER)   and colours.black or colours.white
    local sFg = (_tab == TAB_SECURITY) and colours.black or colours.white

    drawBtn("LEDGER",   1,        2, half,      lBg, lFg)
    drawBtn("SECURITY", half + 1, 2, _W - half, sBg, sFg)
end

-- ledger tab 

local function drawLedgerTab()
    local lines = ledger.tail(_H - 4)
    local row   = 3

    -- column header
    fill(row, colours.grey)
    writeAt(2, row, "TIMESTAMP", colours.lightGrey, colours.grey)
    local ph = "PLAYER"
    writeAt(math.floor(_W / 4), row, ph, colours.lightGrey, colours.grey)
    local ah = "ACTION  AMT  BEFORE  AFTER"
    writeAt(_W - #ah, row, ah, colours.lightGrey, colours.grey)
    row = row + 1

    for y = row, _H - 1 do
        fill(y, colours.black)
    end

    for _, line in ipairs(lines) do
        if row > _H - 1 then break end
        -- parse: ts | player | action | amount | before | after
        local parts = {}
        for part in line:gmatch("[^|]+") do
            table.insert(parts, part:match("^%s*(.-)%s*$"))
        end

        if parts[2] == "SECURITY" then
            -- security line in ledger shown dimmed orange
            local short = (parts[3] or "") .. " " .. (parts[4] or "")
            writeAt(2, row, short, colours.orange)
        elseif parts[2] == "RECONCILE" then
            local short = (parts[3] or "") .. " " .. (parts[4] or "") .. " " .. (parts[5] or "")
            writeAt(2, row, short, colours.red)
        else
            local ts     = (parts[1] or ""):sub(-6)   -- last 6 digits of epoch
            local player = (parts[2] or ""):sub(1, 8)
            local action = (parts[3] or ""):sub(1, 6)
            local amt    = parts[4] or ""
            local before = parts[5] or ""
            local after  = parts[6] or ""

            local fg = colours.white
            if action == "add"    then fg = colours.lime   end
            if action == "remove" then fg = colours.red    end
            if action == "set"    then fg = colours.yellow end

            writeAt(2,                           row, ts,     colours.lightGrey)
            writeAt(10,                          row, player, colours.cyan)
            writeAt(20,                          row, action, fg)
            writeAt(28,                          row, amt,    colours.white)
            writeAt(33,                          row, before, colours.grey)
            writeAt(39,                          row, after,  fg)
        end
        row = row + 1
    end
end

-- security tab 

local function drawSecurityTab()
    local alerts = rednetHandler.getAlerts()
    local row    = 3

    -- whitelist summary line
    fill(row, colours.grey)
    local wl    = rednetHandler.getWhitelist()
    local wlStr = "Whitelisted: " .. #wl .. " machine(s)"
    writeAt(2, row, wlStr, colours.white, colours.grey)
    row = row + 1

    -- clear button
    fill(row, colours.black)
    drawBtn("CLEAR ALERTS", math.floor((_W - 14) / 2) + 1, row, 14, colours.red, colours.white)
    row = row + 1

    -- alerts
    if #alerts == 0 then
        fill(row, colours.black)
        centered("No alerts", row, colours.grey)
        row = row + 1
    else
        -- newest first, already ordered that way from rednet
        for i = #alerts, 1, -1 do
            if row > _H - 1 then break end
            local a   = alerts[i]
            local ts  = tostring(a.ts):sub(-6)
            local msg = a.msg or ""
            fill(row, colours.black)
            writeAt(2,  row, ts,  colours.lightGrey)
            writeAt(10, row, msg, colours.orange)
            row = row + 1
        end
    end

    -- fill remaining rows
    for y = row, _H - 1 do fill(y, colours.black) end
end

-- status bar 

local function drawStatusBar()
    fill(_H, colours.grey)
    local top1  = profiles.top(1)
    local coins = 0
    -- get vault coin count via vault module if available
    local ok, vaultMod = pcall(require, "bank.server.vault")
    if ok then
        local c = pcall(function() coins = vaultMod.coinCount() end)
    end
    local balStr = #top1 > 0 and ("Top: " .. top1[1].player .. " " .. top1[1].balance .. "c") or "No balances"
    local vStr   = "Vault: " .. tostring(coins) .. "c"
    writeAt(2,            _H, balStr, colours.white, colours.grey)
    writeAt(_W - #vStr,   _H, vStr,  colours.lime,  colours.grey)
end

-- full redraw 

local function redraw()
    _mon.clear()
    _mon.setBackgroundColor(colours.black)
    _buttons = {}

    drawHeader()
    drawTabs()

    if _tab == TAB_LEDGER then
        drawLedgerTab()
    else
        drawSecurityTab()
    end

    drawStatusBar()
end

-- touch handler 

local function handleTouch(x, y)
    for label, b in pairs(_buttons) do
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
            if label == "LEDGER" then
                _tab = TAB_LEDGER
            elseif label == "SECURITY" then
                _tab = TAB_SECURITY
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