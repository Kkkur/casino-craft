-- bank/baltop/init.lua

local bank = require("libraries/bank/BankLib")

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

local function draw(top)
    mon.clear()
    mon.setBackgroundColor(colours.black)

    fillLine(1, colours.grey)
    centered("\4 BALTOP \4", 1, colours.white, colours.grey)

    if not top or #top == 0 then
        centered("No balances yet", 3, colours.grey)
        return
    end

    for i, entry in ipairs(top) do
        local row = i + 1
        if row > H then break end

        local rank = i <= 3 and medals[i] or (tostring(i) .. ".")
        local fg   = i <= 3 and medalColors[i] or colours.white
        local name = entry.player or entry.name or "unknown"
        if #name > W - 8 then name = name:sub(1, W - 9) .. "~" end
        local bal  = tostring(entry.balance)

        fillLine(row, colours.black)
        writeAt(2,        row, rank, fg)
        writeAt(5,        row, name, fg)
        writeAt(W - #bal, row, bal,  colours.lime)
    end
end

peripheral.find("modem", rednet.open)

while true do
    local top = bank.top(H - 1)
    draw(top)
    os.sleep(refreshInterval)
end