-- bank/baltop/init.lua

local logger   = dofile("libraries/logger/logger.lua")
logger.init("baltop", "bank/baltop/logs")

local bank     = dofile("libraries/bank/BankLib.lua")
local Currency = dofile("libraries/currencylib.lua")

local CONFIG_FILE = "bank_config.json"

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then
        error("baltop: missing " .. CONFIG_FILE .. ", run bootstrap first")
    end
    local f = fs.open(CONFIG_FILE, "r")
    if not f then error("baltop: cannot open " .. CONFIG_FILE) end
    local data = textutils.unserialiseJSON(f.readAll())
    f.close()
    if not data then error("baltop: corrupt " .. CONFIG_FILE) end
    return data
end

local cfg = loadConfig()

local monitorPeripheral = cfg.monitorSide   or error("baltop: missing monitorSide in config")
local refreshInterval   = cfg.baltopRefresh or 5

local mon = peripheral.wrap(monitorPeripheral)
if not mon then error("baltop: cannot wrap monitor: " .. monitorPeripheral) end

mon.setTextScale(1)
local W, H = mon.getSize()

local medals      = { "\1", "\2", "\3" }
local medalColors = { colours.yellow, colours.lightGrey, colours.orange }

local function fillLine(y, bg)
    mon.setCursorPos(1, y)
    mon.setBackgroundColor(bg)
    mon.write(string.rep(" ", W))
    mon.setBackgroundColor(colours.black)
end

local function writeAt(x, y, text, fg, bg)
    mon.setCursorPos(x, y)
    mon.setBackgroundColor(bg or colours.black)
    mon.setTextColor(fg)
    local maxLen = W - x + 1
    if #text > maxLen then text = text:sub(1, maxLen) end
    mon.write(text)
    mon.setBackgroundColor(colours.black)
    mon.setTextColor(colours.white)
end

local function centered(text, y, fg, bg)
    local x = math.floor((W - #text) / 2) + 1
    if x < 1 then x = 1 end
    writeAt(x, y, text, fg, bg)
end

-- Each entry occupies 2 rows: name+chips on row 1, spur value on row 2
local function draw(top)
    mon.clear()
    mon.setBackgroundColor(colours.black)

    -- Header (row 1)
    fillLine(1, colours.grey)
    local rate = "1chip=" .. Currency.format(Currency.CHIP_VALUE_SPURS, 1)
    local title = "\4 BALTOP \4"
    centered(title, 1, colours.white, colours.grey)
    -- rate hint, right-aligned in header
    local rx = W - #rate
    if rx >= math.floor((W - #title) / 2) + #title + 2 then
        writeAt(rx, 1, rate, colours.lightGrey, colours.grey)
    end

    if not top or #top == 0 then
        centered("No balances yet", 3, colours.grey)
        return
    end

    -- Each entry = 2 screen rows; start at row 2
    local maxEntries = math.floor((H - 1) / 2)

    for i, entry in ipairs(top) do
        if i > maxEntries then break end

        local baseRow = 1 + (i - 1) * 2 + 1   -- row for name/chips
        local subRow  = baseRow + 1             -- row for spur conversion

        local rank   = i <= 3 and medals[i] or (tostring(i) .. ".")
        local rankFg = i <= 3 and medalColors[i] or colours.white
        local name   = entry.player or entry.name or "unknown"
        local chips  = entry.balance

        -- Truncate name to leave room for chip count on same row
        local chipsStr = tostring(chips) .. " chips"
        local maxName  = W - #chipsStr - 5
        if #name > maxName then name = name:sub(1, maxName - 1) .. "~" end

        -- Row 1: rank  name  <chips>
        fillLine(baseRow, colours.black)
        writeAt(2, baseRow, rank, rankFg)
        writeAt(5, baseRow, name, rankFg)
        writeAt(W - #chipsStr, baseRow, chipsStr, colours.lime)

        -- Row 2: indented spur conversion
        if subRow <= H then
            fillLine(subRow, colours.black)
            local spurs    = Currency.chipsToSpurs(chips)
            local spurStr  = "  \187 " .. Currency.format(spurs, 3)
            writeAt(2, subRow, spurStr, colours.cyan)
        end
    end
end

logger.info("Baltop ready. monitor=" .. monitorPeripheral
    .. " refresh=" .. refreshInterval .. "s"
    .. " chip=" .. Currency.CHIP_VALUE_SPURS .. "sp")

peripheral.find("modem", rednet.open)

while true do
    local top, err = bank.top(math.floor((H - 1) / 2))
    if not top or #top == 0 then
        logger.warn("top() returned empty or nil: " .. tostring(err))
    else
        logger.debug("Baltop refreshed: " .. #top .. " entries")
    end
    draw(top)
    os.sleep(refreshInterval)
end