-- bank/atm/ui.lua

local ui = {}

local _mon  = nil
local _W    = 0
local _H    = 0

local _buttons = {}

local C = {
    bg         = colours.black,
    header     = colours.white,
    headerBg   = colours.grey,
    player     = colours.yellow,
    balance    = colours.lime,
    barrel     = colours.cyan,
    vault      = colours.blue,
    dimText    = colours.lightGrey,
    separator  = colours.grey,
    btnDeposit = colours.green,
    btnWithdraw= colours.red,
    btnPlus    = colours.green,
    btnMinus   = colours.red,
    btnPreset  = colours.grey,
    btnActive  = colours.purple,
    feedOk     = colours.lime,
    feedWarn   = colours.orange,
    feedErr    = colours.red,
    amount     = colours.white,
}

function ui.init(peripheralName, scale)
    _mon = peripheral.wrap(peripheralName)
    if not _mon then
        error("atm/ui: could not wrap '" .. tostring(peripheralName) .. "'")
    end
    _mon.setTextScale(scale or 1)
    _W, _H = _mon.getSize()
end

function ui.getSize()
    return _W, _H
end

-- primitives 

local function fillLine(y, bg)
    _mon.setCursorPos(1, y)
    _mon.setBackgroundColor(bg or C.bg)
    _mon.write(string.rep(" ", _W))
    _mon.setBackgroundColor(C.bg)
end

local function writeAt(x, y, text, fg, bg)
    _mon.setCursorPos(x, y)
    _mon.setBackgroundColor(bg or C.bg)
    _mon.setTextColor(fg or C.header)
    local maxLen = _W - x + 1
    if #text > maxLen then text = text:sub(1, maxLen) end
    _mon.write(text)
    _mon.setBackgroundColor(C.bg)
    _mon.setTextColor(colours.white)
end

local function centered(text, y, fg, bg)
    local x = math.floor((_W - #text) / 2) + 1
    if x < 1 then x = 1 end
    writeAt(x, y, text, fg, bg)
end

local function separator(y)
    _mon.setCursorPos(1, y)
    _mon.setTextColor(C.separator)
    _mon.setBackgroundColor(C.bg)
    _mon.write(string.rep("\140", _W))
    _mon.setTextColor(colours.white)
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
    _mon.setBackgroundColor(C.bg)
    _mon.setTextColor(colours.white)
    regBtn(label, x, y, x + w - 1, y)
end

-- sections 

function ui.drawHeader()
    fillLine(1, C.headerBg)
    centered("\4 COIN TERMINAL \4", 1, C.header, C.headerBg)
end

function ui.drawPlayer(playerName, credits)
    fillLine(2, C.bg)
    fillLine(3, C.bg)
    if not playerName then
        centered("No player nearby",     2, C.dimText)
        centered("Stand within range",   3, C.dimText)
        return
    end
    local name = playerName
    if #name > 12 then name = name:sub(1, 11) .. "~" end
    local balStr = tostring(credits) .. " coins"
    writeAt(2, 2, "\26 " .. name, C.player)
    writeAt(_W - #balStr, 2, balStr, C.balance)
    fillLine(3, C.separator)
    centered("[ balance ]", 3, C.dimText, C.separator)
end

function ui.drawStorageInfo(barrelCount, vaultCount)
    separator(4)
    fillLine(5, C.bg)
    local inStr  = "BARREL: " .. tostring(barrelCount)
    local stStr  = "VAULT: "  .. tostring(vaultCount)
    writeAt(2,            5, inStr, C.barrel)
    writeAt(_W - #stStr,  5, stStr, C.vault)
    separator(6)
end

function ui.drawAmountControls(amount, presets)
    fillLine(7, C.bg)
    fillLine(9, C.bg)

    local mid = math.floor(_W / 2)
    drawBtn("-", mid - 4, 7, 4, C.btnMinus)
    local amtStr = tostring(amount)
    local amtX   = mid - math.floor(#amtStr / 2) + 1
    writeAt(amtX, 7, amtStr, C.amount)
    drawBtn("+", mid + 2, 7, 4, C.btnPlus)

    local btnW   = 4
    local total  = (#presets * btnW) + (#presets - 1)
    local startX = math.floor((_W - total) / 2) + 1
    local x      = startX
    for _, preset in ipairs(presets) do
        local label = tostring(preset)
        local bg    = (preset == amount) and C.btnActive or C.btnPreset
        drawBtn(label, x, 9, btnW, bg)
        x = x + btnW + 1
    end
end

function ui.drawFeedback(feedback)
    fillLine(8, C.bg)
    if not feedback then return end
    local msg = feedback.msg
    if #msg > _W - 2 then msg = msg:sub(1, _W - 2) end
    centered(msg, 8, feedback.color)
end

function ui.drawActionButtons()
    separator(10)
    local half = math.floor(_W / 2)
    drawBtn("DEPOSIT",  1,        _H, half,      C.btnDeposit)
    drawBtn("WITHDRAW", half + 1, _H, _W - half, C.btnWithdraw)
end

-- full redraw 

function ui.redraw(state)
    _mon.clear()
    _mon.setBackgroundColor(C.bg)
    _buttons = {}

    ui.drawHeader()
    ui.drawPlayer(state.playerName, state.credits)
    ui.drawStorageInfo(state.barrelCount, state.vaultCount)
    ui.drawAmountControls(state.amount, state.presets)
    ui.drawFeedback(state.feedback)
    ui.drawActionButtons()
end

--  touch 

-- returns the label of the button hit, or nil
function ui.hitTest(x, y)
    for label, b in pairs(_buttons) do
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
            return label
        end
    end
    return nil
end

return ui