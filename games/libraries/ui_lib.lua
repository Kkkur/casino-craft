-- ui_lib.lua
-- Shared monitor rendering toolkit for all casino game UIs.
--
-- How to use:
--   local UI = dofile("../libraries/ui_lib.lua")
--   UI.init(peripheral.find("monitor"))
--   UI.fill(1, 1, UI.W, 1, UI.C.header)
--   UI.writeAt(2, 3, "Hello", UI.C.text, UI.C.felt)
--   UI.makeButton(5, 10, 12, "DEAL", "deal", UI.C.btnHit, UI.C.btnText)
--   UI.drawHeader("BLACKJACK", 4, "Steve")
--   local action = UI.hitTest(x, y)

local UI = {}

-- The monitor peripheral. Set by UI.init().
local mon = nil

-- Monitor dimensions. Read these after UI.init().
UI.W = 0
UI.H = 0

-- Colour palette used across all game UIs.
-- Games can override individual values after dofile if needed.
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
    btnHit      = colours.green,
    btnStand    = colours.red,
    btnDouble   = colours.orange,
    btnSplit    = colours.cyan,
    queueText   = colours.yellow,
    header      = colours.black,
    headerText  = colours.yellow,
}

-- Button registry. Cleared on every draw call via UI.clearButtons().
local buttons = {}

-- Call once with a monitor peripheral before drawing anything.
-- Sets up text scale and reads the monitor size into UI.W and UI.H.
function UI.init(monitor)
    assert(monitor, "ui_lib: no monitor passed to UI.init()")
    mon = monitor
    mon.setTextScale(0.5)
    UI.W, UI.H = mon.getSize()
    mon.clear()
end

-- Returns the raw monitor peripheral in case a game needs direct access.
function UI.getMonitor()
    return mon
end

-- Clears the entire monitor with the background colour.
function UI.clear()
    mon.setBackgroundColor(UI.C.bg)
    mon.clear()
end

-- Low level colour setters. Use these instead of calling mon directly.
function UI.bg(col)   mon.setBackgroundColor(col) end
function UI.fg(col)   mon.setTextColor(col)       end
function UI.cur(x, y) mon.setCursorPos(x, y)      end

-- Fills a rectangle with a solid background colour.
function UI.fill(x, y, w, h, col)
    UI.bg(col)
    local row = string.rep(" ", w)
    for dy = 0, h - 1 do
        UI.cur(x, y + dy)
        mon.write(row)
    end
end

-- Writes text at a specific position with optional fg and bg colours.
function UI.writeAt(x, y, text, fgCol, bgCol)
    if bgCol then UI.bg(bgCol) end
    if fgCol then UI.fg(fgCol) end
    UI.cur(x, y)
    mon.write(text)
end

-- Writes text centred horizontally on a given row.
function UI.centreAt(y, text, fgCol, bgCol)
    local x = math.floor((UI.W - #text) / 2) + 1
    UI.writeAt(x, y, text, fgCol, bgCol)
end

-- Truncates a string to maxLen characters.
function UI.clamp(s, maxLen)
    if #s > maxLen then return s:sub(1, maxLen) end
    return s
end

-- Button system.
-- Buttons are stored per-frame and checked with UI.hitTest().
-- Call UI.clearButtons() at the start of each draw, or it piles up.

function UI.clearButtons()
    buttons = {}
end

-- Draws a button and registers it for hit testing.
-- action is a string returned by UI.hitTest() when this button is tapped.
function UI.makeButton(x, y, w, label, action, bgCol, fgCol)
    local padded = string.rep(" ", math.floor((w - #label) / 2)) .. label
    padded = padded .. string.rep(" ", w - #padded)
    padded = padded:sub(1, w)
    UI.writeAt(x, y, padded, fgCol or UI.C.btnText, bgCol or UI.C.btnBg)
    buttons[#buttons + 1] = {
        x      = x,
        y      = y,
        w      = w,
        h      = 1,
        action = action,
    }
end

-- Draws a button visually but does NOT register it for hit testing.
-- Use this for disabled buttons.
function UI.drawButtonInert(x, y, w, label, bgCol, fgCol)
    local padded = string.rep(" ", math.floor((w - #label) / 2)) .. label
    padded = padded .. string.rep(" ", w - #padded)
    padded = padded:sub(1, w)
    UI.writeAt(x, y, padded, fgCol or UI.C.dimText, bgCol or UI.C.btnBg)
end

-- Checks if a monitor touch at (x, y) hit any registered button.
-- Returns the action string of the button, or nil if nothing was hit.
function UI.hitTest(x, y)
    for _, btn in ipairs(buttons) do
        if x >= btn.x and x < btn.x + btn.w
        and y >= btn.y and y < btn.y + btn.h then
            return btn.action
        end
    end
    return nil
end

-- Draws the shared top header row used by all games.
-- title is the game name shown on the left, e.g. "BLACKJACK".
-- queueChips is the number of chips currently in the deposit barrel.
-- playerName is optional, shown in the middle if provided.
function UI.drawHeader(title, queueChips, playerName)
    UI.fill(1, 1, UI.W, 1, UI.C.header)

    -- Left side: game title with a heart symbol
    UI.fg(UI.C.headerText)
    UI.bg(UI.C.header)
    UI.cur(1, 1)
    mon.write(" \x03 " .. title .. " ")

    -- Right side: chip queue count
    local qStr = "Queue: " .. (queueChips or 0) .. " chip" .. ((queueChips == 1) and "" or "s") .. " "
    UI.writeAt(UI.W - #qStr + 1, 1, qStr, UI.C.queueText, UI.C.header)

    -- Middle: player name if we have one
    if playerName and playerName ~= "" then
        local pStr = UI.clamp("  " .. playerName .. "  ", 20)
        local px   = math.floor((UI.W - #pStr) / 2) + 1
        UI.writeAt(px, 1, pStr, UI.C.dimText, UI.C.header)
    end
end

return UI