-- libraries/games/UILib.lua
-- Universal 2D UI library for Tom's Peripherals GPU
-- Shared across all casino game machines

local UILib = {}
UILib.__index = UILib

--  Constructor 

function UILib.new(gpu, size)
    local self = setmetatable({}, UILib)
    self.gpu     = gpu   -- peripheral IS the drawing context, no createWindow needed
    self.ctx     = gpu   -- alias so existing ctx calls work unchanged
    self.size    = size or 64
    self.buttons      = {}   -- id -> button data
    self.buttonOrder  = {}   -- ordered list of ids for deterministic hit testing

    gpu.refreshSize()
    gpu.setSize(self.size)

    self.sw, self.sh = gpu.getSize()  -- returns px, py, blocks_x, blocks_y, res

    -- 1-based coordinate system
    self.x0 = 1
    self.y0 = 1
    self.x1 = self.sw
    self.y1 = self.sh

    self.topBar = {
        enabled     = false,
        height      = 14,
        title       = "",
        player      = "Guest",
        chips       = 0,
        chipsUnit   = "c",
        titleColor  = 0xC9A84C,
        playerColor = 0xFFFFFF,
        chipsColor  = 0xFFDD44,
        bg          = 0x000000,
        borderColor = 0xC9A84C,
    }

    gpu.fill(0x000000)
    gpu.sync()

    return self
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function UILib:safe(x, y, w, h)
    local x2 = clamp(x,     self.x0, self.x1)
    local y2 = clamp(y,     self.y0, self.y1)
    local w2 = clamp(x+w-1, self.x0, self.x1) - x2 + 1
    local h2 = clamp(y+h-1, self.y0, self.y1) - y2 + 1
    return x2, y2, math.max(1, w2), math.max(1, h2)
end

function UILib:safeXY(x, y)
    return clamp(x, self.x0, self.x1), clamp(y, self.y0, self.y1)
end

--  Primitives 

function UILib:clear(color)  self.gpu.fill(color or 0x000000) end
function UILib:sync() self.gpu.sync() end

function UILib:rect(x, y, w, h, color)
    local sx, sy, sw, sh = self:safe(x, y, w, h)
    self.gpu.filledRectangle(sx, sy, sw, sh, color)
end

function UILib:border(x, y, w, h, color, thickness)
    thickness = thickness or 1
    for i = 0, thickness - 1 do
        local sx, sy = self:safeXY(x+i,       y+i)
        local ex, ey = self:safeXY(x+w-i*2-1, y+h-i*2-1)
        self.gpu.rectangle(sx, sy, ex-sx+1, ey-sy+1, color)
    end
end

function UILib:text(x, y, str, fg, bg, size)
    local sx, sy = self:safeXY(x, y)
    self.ctx.drawText(sx, sy, str, fg or 0xFFFFFF, bg or 0x000000, size or 1)
end

function UILib:textCentered(x, y, w, str, fg, bg, size)
    local tw = self.ctx.getTextLength(str, size or 1) or (#str * 6)
    local tx = x + math.floor((w - tw) / 2)
    self:text(tx, y, str, fg, bg, size)
end

function UILib:line(x1, y1, x2, y2, color)
    local sx1, sy1 = self:safeXY(x1, y1)
    local sx2, sy2 = self:safeXY(x2, y2)
    self.gpu.line(sx1, sy1, sx2, sy2, color)
end

--  Panels & Labels 

function UILib:panel(x, y, w, h, bg, borderColor, thickness)
    self:rect(x, y, w, h, bg or 0x1a1a1a)
    if borderColor then self:border(x, y, w, h, borderColor, thickness or 1) end
end

function UILib:pill(x, y, label, value, bg, fg, valFg)
    bg    = bg    or 0x333333
    fg    = fg    or 0xAAAAAA
    valFg = valFg or 0xFFDD44
    local str    = label .. ": " .. tostring(value)
    local tw     = self.gpu.getTextLength(str) or (#str * 6)
    local pw, ph = tw + 8, 12
    self:rect(x, y, pw, ph, bg)
    self:border(x, y, pw, ph, 0x555555)
    self:text(x+4, y+2, label .. ": ", fg, bg)
    local lw = self.gpu.getTextLength(label .. ": ") or 0
    self:text(x+4+lw, y+2, tostring(value), valFg, bg)
end

function UILib:infoPanel(x, y, w, h, label, value, bg, fg, labelFg)
    bg      = bg      or 0x1a1a1a
    fg      = fg      or 0xFFFFFF
    labelFg = labelFg or 0xAAAAAA
    self:panel(x, y, w, h, bg, 0x444444)
    self:textCentered(x, y+3,  w, label,          labelFg, bg)
    self:textCentered(x, y+13, w, tostring(value), fg,      bg)
end

--  Top Bar 

function UILib:setTopBar(opts)
    for k, v in pairs(opts) do self.topBar[k] = v end
    self.topBar.enabled = true
    self.y0 = self.topBar.height + 1  -- e.g. height=14 → y0=15
end

function UILib:updateTopBar(opts)
    for k, v in pairs(opts) do
        self.topBar[k] = v
    end
end

function UILib:drawTopBar()
    local tb = self.topBar
    if not tb.enabled then return end
    local h  = tb.height

    self.ctx.filledRectangle(1, 1, self.sw, h, tb.bg)
    self.ctx.filledRectangle(1, h, self.sw, 1, tb.borderColor)

    local ty = math.floor((h - 8) / 2)

    self.ctx.drawText(4, ty, tb.title, tb.titleColor, tb.bg, 1)

    local pStr = "Player: " .. tostring(tb.player)
    local ptw  = self.ctx.getTextLength(pStr, 1)
    self.ctx.drawText(math.floor((self.sw - ptw) / 2), ty, pStr, tb.playerColor, tb.bg, 1)

    local cStr = "Chips: " .. tostring(tb.chips) .. tb.chipsUnit
    local ctw  = self.ctx.getTextLength(cStr, 1)
    self.ctx.drawText(self.sw - ctw - 4, ty, cStr, tb.chipsColor, tb.bg, 1)
end

--  Buttons 

function UILib:button(id, opts)
    if not self.buttons[id] then
        table.insert(self.buttonOrder, id)
    end
    self.buttons[id] = {
        x           = opts.x,
        y           = opts.y,
        w           = opts.w,
        h           = opts.h,
        label       = opts.label       or id,
        bg          = opts.bg          or 0x334488,
        fg          = opts.fg          or 0xFFFFFF,
        borderColor = opts.borderColor or 0x6688CC,
        disabledBg  = opts.disabledBg  or 0x2a2a2a,
        disabledFg  = opts.disabledFg  or 0x555555,
        size        = opts.size        or 1,
        enabled     = true,
    }
    self:drawButton(id)
end

function UILib:clearButtons()
    self.buttons     = {}
    self.buttonOrder = {}
end

function UILib:drawButton(id)
    local b = self.buttons[id]
    if not b then return end
    local bg = b.enabled and b.bg or b.disabledBg
    local fg = b.enabled and b.fg or b.disabledFg
    local bc = b.enabled and b.borderColor or 0x444444
    self:rect(b.x, b.y, b.w, b.h, bg)
    self:border(b.x, b.y, b.w, b.h, bc)
    self:textCentered(b.x, b.y + math.floor(b.h/2) - 4, b.w, b.label, fg, bg, b.size)
end

function UILib:setButtonEnabled(id, enabled)
    if self.buttons[id] then
        self.buttons[id].enabled = enabled
        self:drawButton(id)
    end
end

function UILib:flashButton(id, flashBg, duration)
    local b = self.buttons[id]
    if not b or not b.enabled then return end
    local orig = b.bg
    b.bg = flashBg or 0x6688FF
    self:drawButton(id); self:sync()
    sleep(duration or 0.12)
    b.bg = orig
    self:drawButton(id); self:sync()
end

function UILib:hitButton(x, y)
    -- Overlays block all input while active.
    if self:hasOverlay() then return nil end
    for _, id in ipairs(self.buttonOrder) do
        local b = self.buttons[id]
        if b and b.enabled
        and x >= b.x and x <= b.x + b.w
        and y >= b.y and y <= b.y + b.h then
            return id
        end
    end
end

--  Event loop 

function UILib:handleEvent(handlers)
    local e, p, x, y, s = os.pullEvent()
    if e == "tm_monitor_touch" then
        local id = self:hitButton(x, y)
        if id and handlers.onButton then
            self:flashButton(id)
            handlers.onButton(id)
        elseif handlers.onTouch then
            handlers.onTouch(x, y, s)
        end
    elseif e == "key"    and handlers.onKey    then handlers.onKey(p)
    elseif e == "key_up" and handlers.onKeyUp  then handlers.onKeyUp(p)
    elseif e == "char"   and handlers.onChar   then handlers.onChar(p)
    end
end

function UILib:getSize() return self.sw, self.sh end

-- -------------------------------------------------------------------------- --
--  Overlay system
--
--  Three overlay types:
--    "error"   - red border, blocks all input, auto or manual dismiss
--    "message" - color-configurable border, blocks all input
--    "toast"   - small non-blocking strip at bottom, auto-dismiss only
--
--  drawOverlay() must be called at the end of every machine redraw(), before
--  sync(). GameLib's session runner enforces this by wrapping redraw.
--
--  While any blocking overlay (error or message) is active, hitButton()
--  returns nil so the game loop receives no input events.
-- -------------------------------------------------------------------------- --

local OVERLAY_COLORS = {
    red    = { border = 0xCC2222, bg = 0x1a0000, title = 0xFF4444 },
    orange = { border = 0xFF6600, bg = 0x1a0a00, title = 0xFF9944 },
    gold   = { border = 0xC9A84C, bg = 0x1a1500, title = 0xFFDD44 },
    green  = { border = 0x22CC44, bg = 0x001a08, title = 0x44FF88 },
    blue   = { border = 0x2244CC, bg = 0x00081a, title = 0x4488FF },
}
local DEFAULT_OVERLAY_COLOR = "gold"

local function resolveColor(name)
    return OVERLAY_COLORS[name] or OVERLAY_COLORS[DEFAULT_OVERLAY_COLOR]
end

-- Internal overlay state, stored on the instance.
local function initOverlayState(self)
    if not self._overlay then
        self._overlay = {
            kind        = nil,    -- "error" | "message" | "toast" | nil
            title       = "",
            msg         = "",
            colorName   = "gold",
            dismissTimer = nil,
        }
    end
end

-- Returns true if any overlay is currently active.
function UILib:hasOverlay()
    return self._overlay ~= nil and self._overlay.kind ~= nil
end

-- Returns true specifically if a blocking overlay (error or message) is up.
function UILib:isBlocked()
    if not self._overlay then return false end
    return self._overlay.kind == "error" or self._overlay.kind == "message"
end

-- Show a red error box. Blocks all input.
-- duration: seconds before auto-dismiss, or nil for permanent.
function UILib:showError(title, msg, duration)
    initOverlayState(self)
    self._overlay.kind      = "error"
    self._overlay.title     = title or "ERROR"
    self._overlay.msg       = msg   or ""
    self._overlay.colorName = "red"
    self._overlay.dismissTimer = duration and os.startTimer(duration) or nil
end

-- Show a blocking message box with a named color.
-- color: "red" | "orange" | "gold" | "green" | "blue"
-- duration: seconds before auto-dismiss, or nil for permanent.
function UILib:showMessage(title, msg, color, duration)
    initOverlayState(self)
    self._overlay.kind      = "message"
    self._overlay.title     = title or ""
    self._overlay.msg       = msg   or ""
    self._overlay.colorName = color or DEFAULT_OVERLAY_COLOR
    self._overlay.dismissTimer = duration and os.startTimer(duration) or nil
end

-- Show a non-blocking toast at the bottom of the screen.
-- Always auto-dismisses; duration defaults to 4 seconds.
function UILib:showToast(msg, color, duration)
    initOverlayState(self)
    self._overlay.kind      = "toast"
    self._overlay.msg       = msg or ""
    self._overlay.colorName = color or "gold"
    self._overlay.dismissTimer = os.startTimer(duration or 4)
end

-- Dismiss whatever overlay is currently showing.
function UILib:clearOverlay()
    if self._overlay then
        self._overlay.kind         = nil
        self._overlay.dismissTimer = nil
    end
end

-- Call this from the listener thread's timer handler.
-- Returns true if the timer matched and the overlay was cleared.
function UILib:handleOverlayTimer(timerId)
    if self._overlay
    and self._overlay.dismissTimer == timerId then
        self:clearOverlay()
        return true
    end
    return false
end

-- Draw the active overlay on top of whatever is already on screen.
-- Call at the very end of every redraw(), before sync().
function UILib:drawOverlay()
    if not self:hasOverlay() then return end
    local ov = self._overlay

    if ov.kind == "toast" then
        -- Small strip pinned to the bottom of the playfield.
        local toastH = 14
        local toastY = self.sh - toastH - 2
        local toastX = 10
        local toastW = self.sw - 20
        local col    = resolveColor(ov.colorName)
        self:rect(toastX, toastY, toastW, toastH, col.bg)
        self:border(toastX, toastY, toastW, toastH, col.border, 1)
        self:textCentered(toastX, toastY + 3, toastW, ov.msg, 0xFFFFFF, col.bg, 1)
        return
    end

    -- Blocking overlay (error or message): centered panel.
    local col    = resolveColor(ov.colorName)
    local panW   = math.min(self.sw - 20, 160)
    local panH   = 40
    local panX   = math.floor((self.sw - panW) / 2)
    local panY   = math.floor((self.sh - panH) / 2)

    -- Dark scrim behind the panel so the game is visually obscured.
    -- Draw a semi-transparent feel by overlaying a dark rect at 60% width
    -- on each side; full blackout is cleaner on pixel GPUs.
    self:rect(0, 0, self.sw, self.sh, 0x000000)

    -- Panel itself.
    self:rect(panX, panY, panW, panH, col.bg)
    self:border(panX, panY, panW, panH, col.border, 2)

    -- Title row.
    self:textCentered(panX, panY + 6, panW, ov.title, col.title, col.bg, 1)

    -- Message row (word-wrapped to panel width if needed).
    -- For simplicity we truncate to one line; multi-line can be added later.
    local maxChars = math.floor(panW / 6)
    local display  = #ov.msg > maxChars and ov.msg:sub(1, maxChars - 3) .. "..." or ov.msg
    self:textCentered(panX, panY + 20, panW, display, 0xCCCCCC, col.bg, 1)

    -- Small dismiss hint at the bottom of the panel.
    self:textCentered(panX, panY + 32, panW, "[ server or timeout ]", 0x555555, col.bg, 1)
end

return UILib