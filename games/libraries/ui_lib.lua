-- ========================================================================== --
--  UI Library
--  Shared rendering primitives and button management for casino games.
-- ========================================================================== --

local UI = {}

local mon     = nil
local buttons = {}

UI.W, UI.H = 0, 0

UI.C = {
    bg          = colours.black,
    felt        = colours.green,
    feltDark    = colours.lime,
    text        = colours.white,
    dimText     = colours.grey,
    cardFace    = colours.white,
    cardBack    = colours.blue,
    cardBorder  = colours.lightGrey,
    suitRed     = colours.red,
    suitBlack   = colours.black,
    chipGold    = colours.yellow,
    win         = colours.lime,
    loss        = colours.red,
    push        = colours.yellow,
    blackjack   = colours.yellow,
    btnBg       = colours.grey,
    btnText     = colours.white,
    btnHit      = colours.lime,
    btnStand    = colours.red,
    btnDouble   = colours.orange,
    btnSplit    = colours.cyan,
    queueText   = colours.yellow,
    header      = colours.black,
    headerText  = colours.yellow,
}
-- -------------------------------------------------------------------------- --
-- Initialization & Core Access
-- -------------------------------------------------------------------------- --

function UI.init(monitor)
    assert(monitor, "UI.init: No monitor provided")
    mon = monitor
    mon.setTextScale(0.5)
    UI.W, UI.H = mon.getSize()
    mon.clear()
end

function UI.getMonitor() return mon end

-- -------------------------------------------------------------------------- --
-- Rendering Primitives
-- -------------------------------------------------------------------------- --

function UI.bg(col)   mon.setBackgroundColor(col) end
function UI.fg(col)   mon.setTextColor(col)       end
function UI.cur(x, y) mon.setCursorPos(x, y)      end

function UI.clear()
    mon.setBackgroundColor(UI.C.bg)
    mon.clear()
end

function UI.fill(x, y, w, h, col)
    UI.bg(col)
    local row = string.rep(" ", w)
    for dy = 0, h - 1 do
        UI.cur(x, y + dy)
        mon.write(row)
    end
end

function UI.writeAt(x, y, text, fgCol, bgCol)
    if bgCol then UI.bg(bgCol) end
    if fgCol then UI.fg(fgCol) end
    UI.cur(x, y)
    mon.write(text)
end

function UI.centreAt(y, text, fgCol, bgCol)
    UI.writeAt(math.floor((UI.W - #text) / 2) + 1, y, text, fgCol, bgCol)
end

function UI.clamp(s, maxLen)
    return (#s > maxLen) and s:sub(1, maxLen) or s
end

-- -------------------------------------------------------------------------- --
-- Button System
-- -------------------------------------------------------------------------- --

function UI.clearButtons() buttons = {} end

function UI.makeButton(x, y, w, label, action, bgCol, fgCol)
    local padding = w - #label
    local left    = math.floor(padding / 2)
    local right   = padding - left
    local text    = string.rep(" ", left) .. label .. string.rep(" ", right)
    
    UI.writeAt(x, y, text:sub(1, w), fgCol or UI.C.btnText, bgCol or UI.C.btnBg)
    table.insert(buttons, {x = x, y = y, w = w, h = 1, action = action})
end

function UI.drawButtonInert(x, y, w, label, bgCol, fgCol)
    local padding = w - #label
    local left    = math.floor(padding / 2)
    local right   = padding - left
    local text    = string.rep(" ", left) .. label .. string.rep(" ", right)
    
    UI.writeAt(x, y, text:sub(1, w), fgCol or UI.C.dimText, bgCol or UI.C.btnBg)
end

function UI.hitTest(x, y)
    for _, btn in ipairs(buttons) do
        if x >= btn.x and x < btn.x + btn.w and y == btn.y then
            return btn.action
        end
    end
    return nil
end

-- -------------------------------------------------------------------------- --
-- Shared Elements
-- -------------------------------------------------------------------------- --

function UI.drawHeader(title, queueChips, playerName)
    UI.fill(1, 1, UI.W, 1, UI.C.header)
    UI.fg(UI.C.headerText)
    UI.bg(UI.C.header)
    UI.cur(1, 1)
    mon.write(" \x03 " .. title .. " ")

    local qStr = "Queue: " .. (queueChips or 0) .. " chips "
    UI.writeAt(UI.W - #qStr + 1, 1, qStr, UI.C.queueText, UI.C.header)

    if playerName and playerName ~= "" then
        local pStr = UI.clamp("  " .. playerName .. "  ", 20)
        UI.centreAt(1, pStr, UI.C.dimText, UI.C.header)
    end
end

return UI