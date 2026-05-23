-- libraries/games/ChipsLib.lua
-- Chip selector UI — reusable for Blackjack, Poker, etc.
-- Renders a row of clickable chip buttons and manages current bet

local ChipsLib = {}
ChipsLib.__index = ChipsLib

-- Chip denominations and their colors
local CHIPS = {
    { value=1,   label="1",   bg=0xCCCCCC, fg=0x111111, border=0x888888 },
    { value=5,   label="5",   bg=0xCC2222, fg=0xFFFFFF, border=0xFF4444 },
    { value=10,  label="10",  bg=0x2244CC, fg=0xFFFFFF, border=0x4466FF },
    { value=25,  label="25",  bg=0x228822, fg=0xFFFFFF, border=0x44AA44 },
    { value=100, label="100", bg=0x111111, fg=0xFFDD44, border=0x555522 },
    { value=500, label="500", bg=0x882288, fg=0xFFFFFF, border=0xBB44BB },
}

local CHIP_W = 26
local CHIP_H = 18

function ChipsLib.new(ui, x, y, onBetChange)
    local self        = setmetatable({}, ChipsLib)
    self.ui           = ui
    self.x            = x
    self.y            = y
    self.bet          = 0
    self.onBetChange  = onBetChange  -- callback(newBet)
    self.chipIds      = {}
    return self
end

-- Register chip buttons with UILib and draw them
function ChipsLib:draw()
    local ui = self.ui
    for i, chip in ipairs(CHIPS) do
        local id = "chip_" .. chip.value
        local cx = self.x + (i-1) * (CHIP_W + 4)
        self.chipIds[id] = chip.value

        -- Draw chip decorations behind the button
        ui:rect(cx, self.y, CHIP_W, CHIP_H, chip.bg)
        ui:border(cx, self.y, CHIP_W, CHIP_H, chip.border, 2)
        ui:border(cx+3, self.y+3, CHIP_W-6, CHIP_H-6, chip.border, 1)
        ui:textCentered(cx, self.y+4, CHIP_W, chip.label, chip.fg, chip.bg, 1)

        -- Register with UILib for hit testing
        ui:button(id, {
            x=cx, y=self.y, w=CHIP_W, h=CHIP_H,
            label=chip.label,
            bg=chip.bg, fg=chip.fg, borderColor=chip.border,
        })
    end
end

-- Call from your onButton handler; returns true if it consumed the event
function ChipsLib:handleButton(id, balance)
    local value = self.chipIds[id]
    if not value then return false end
    if self.bet + value <= balance then
        self.bet = self.bet + value
        if self.onBetChange then self.onBetChange(self.bet) end
    end
    return true
end

-- Clear button: remove last chip denomination added
function ChipsLib:clearBet(amount)
    self.bet = math.max(0, self.bet - (amount or self.bet))
    if self.onBetChange then self.onBetChange(self.bet) end
end

function ChipsLib:getBet()    return self.bet end
function ChipsLib:resetBet()  self.bet = 0; if self.onBetChange then self.onBetChange(0) end end

function ChipsLib:isChipButton(id)
    return self.chipIds[id] ~= nil
end

return ChipsLib