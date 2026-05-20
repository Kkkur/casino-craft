-- leaderboard_display.lua
-- Runs on the RELAY PC. Receives leaderboard

local PROTOCOL   = "CASINO_LEADERBOARD"
local MON_NAME   = nil   

-- Color palette  
local C = {
    black   = colours.black,
    white   = colours.white,
    yellow  = colours.yellow,
    lime    = colours.lime,
    red     = colours.red,
    cyan    = colours.cyan,
    orange  = colours.orange,
    purple  = colours.purple,
    pink    = colours.pink,
    grey    = colours.grey,
    lgrey   = colours.lightGrey,
}

-- Init 
local mon
if MON_NAME then
    mon = peripheral.wrap(MON_NAME)
else
    mon = peripheral.find("monitor")
end
assert(mon, "No monitor found! Connect a monitor and re-run.")

-- Open wireless rednet
local modem = peripheral.find("modem", function(_, m)
    return m.isWireless and m.isWireless()
end)
assert(modem, "No wireless modem found!")
rednet.open(peripheral.getName(modem))

mon.setTextScale(0.5)   -- 0.5 = maximum density on advanced monitors
local W, H = mon.getSize()

-- Drawing helpers 
local function cls()
    mon.setBackgroundColor(C.black)
    mon.clear()
end

local function at(x, y, text, fg, bg)
    mon.setCursorPos(x, y)
    mon.setTextColor(fg or C.white)
    mon.setBackgroundColor(bg or C.black)
    mon.write(text)
end

local function atR(x, y, text, fg, bg)
    at(x - #text + 1, y, text, fg, bg)
end

local function fit(s, w)
    s = tostring(s)
    if #s > w then return s:sub(1, w) end
    return s .. string.rep(" ", w - #s)
end

-- Separator line
local function sep(y, char, fg)
    at(1, y, string.rep(char or "-", W), fg or C.grey)
end

-- Render 
local function render(data)
    cls()

    -- Header 
    local title = "\4 BLACKJACK LEADERBOARD \4"
    at(math.floor((W - #title) / 2) + 1, 1, title, C.yellow)
    sep(2, "-", C.grey)

    -- Column headers 
    local HDR_Y = 3
    at(1,  HDR_Y, " # ", C.lgrey)
    at(4,  HDR_Y, fit("Player", 14), C.lgrey)
    at(18, HDR_Y, " W  ", C.lime)
    at(22, HDR_Y, " L  ", C.red)
    at(26, HDR_Y, "BJ ", C.pink)
    at(29, HDR_Y, fit("  Net", 8), C.cyan)
    at(37, HDR_Y, " WR%", C.orange)
    sep(4, "-", C.grey)

    -- Player rows 
    local players = data.players or {}
    for i, p in ipairs(players) do
        local y    = 4 + i
        if y > H - 4 then break end

        -- Rank colour
        local rankFg = C.lgrey
        if i == 1 then rankFg = C.yellow  end
        if i == 2 then rankFg = C.orange  end
        if i == 3 then rankFg = C.lgrey   end

        -- Net profit colour
        local net   = p.net or 0
        local netFg = net >= 0 and C.lime or C.red
        local netS  = (net >= 0 and "+" or "") .. tostring(net)

        -- Win rate colour
        local wr    = p.winRate or 0
        local wrFg  = wr >= 50 and C.lime or (wr >= 35 and C.orange or C.red)

        -- Blackjack marker
        local bjS   = (p.blackjacks and p.blackjacks > 0)
            and tostring(p.blackjacks) or "-"

        at(1,  y, fit(tostring(i), 2),           rankFg)
        at(1,  y, i == 1 and "\30" or " ",        rankFg)   -- trophy char for #1
        at(3,  y, fit(p.username or "?", 15),    C.white)
        at(18, y, fit(tostring(p.wins   or 0), 4), C.lime)
        at(22, y, fit(tostring(p.losses or 0), 4), C.red)
        at(26, y, fit(bjS, 3),                    C.pink)
        at(29, y, fit(netS, 8),                   netFg)
        at(37, y, fit(tostring(wr) .. "%", 5),    wrFg)
    end

    --  Footer 
    local footerY = H - 2
    sep(footerY - 1, "-", C.grey)

    local totalHands = data.totalHands or 0
    local houseEdge  = data.houseEdge  or 0
    local heFg       = houseEdge >= 0 and C.lime or C.red
    local heS        = (houseEdge >= 0 and "+" or "") .. tostring(houseEdge)

    at(1,       footerY,     "Hands: " .. tostring(totalHands), C.lgrey)
    at(1,       footerY + 1, "House: " .. heS,                  heFg)
    atR(W,      footerY,     tostring(data.timestamp or ""),     C.cyan)
    atR(W,      footerY + 1, "by chips won",                    C.grey)

    sep(H, "-", C.grey)
end

-- Idle or waiting screen 
local function idle()
    cls()
    local msg = "\4 Awaiting data... \4"
    at(math.floor((W - #msg)/2)+1, math.floor(H/2), msg, C.grey)
end

-- Main loop 
print("Leaderboard relay ready. Listening on protocol: " .. PROTOCOL)
idle()

while true do
    local _, msg = rednet.receive(PROTOCOL, 30)
    if msg and type(msg) == "table" and msg.type == "leaderboard_update" then
        render(msg)
    else
        mon.setCursorPos(W - 7, H)
        mon.setTextColor(C.grey)
        mon.setBackgroundColor(C.black)
        mon.write(textutils.formatTime(os.time(), false))
    end
end