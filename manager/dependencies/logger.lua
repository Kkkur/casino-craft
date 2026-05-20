-- logger.lua
-- Persistent logger for the casino manager

local Logger = {}

local LOG_DIR    = "manager/logs"
local LATEST     = LOG_DIR .. "/latest"
local MAX_OLD    = 5

-- Internal 

local logBuffer = {}

local function ensureDir()
    if not fs.exists(LOG_DIR) then
        fs.makeDir(LOG_DIR)
    end
end

local function getNumberedLogs()
    local list = {}
    for _, name in ipairs(fs.list(LOG_DIR)) do
        local n = tonumber(name)
        if n then
            list[#list+1] = n
        end
    end
    table.sort(list)
    return list
end

local function rotateLogs()
    ensureDir()

    if fs.exists(LATEST) then
        local numbered = getNumberedLogs()
        local nextNum = 1
        if #numbered > 0 then
            nextNum = numbered[#numbered] + 1
        end
        fs.move(LATEST, LOG_DIR .. "/" .. nextNum)
        numbered[#numbered+1] = nextNum

        while #numbered > MAX_OLD do
            fs.delete(LOG_DIR .. "/" .. numbered[1])
            table.remove(numbered, 1)
        end
    end
end

local function timestamp()
    local t = os.time()
    local h = math.floor(t)
    local m = math.floor((t - h) * 60)
    return string.format("%02d:%02d", h % 24, m)
end

local function writeLine(line)
    local f = fs.open(LATEST, "a")
    if f then
        f.writeLine(line)
        f.close()
    end
end

-- Public API 

function Logger.init()
    ensureDir()
    rotateLogs()
    local f = fs.open(LATEST, "w")
    if f then
        f.writeLine("=== Casino Manager Log - Session start (day " .. os.day() .. " " .. timestamp() .. ") ===")
        f.close()
    end
    Logger.info("Logger initialised. Logs in: " .. LOG_DIR)
end

function Logger.log(level, msg)
    local line = "[" .. timestamp() .. "] [" .. level .. "] " .. tostring(msg)
    if level == "ERROR" then
        term.setTextColor(colours.red)
    elseif level == "WARN" then
        term.setTextColor(colours.yellow)
    elseif level == "INFO" then
        term.setTextColor(colours.white)
    else
        term.setTextColor(colours.lightGrey)
    end
    print(line)
    term.setTextColor(colours.white)
    writeLine(line)
end

function Logger.info(msg)  Logger.log("INFO",  msg) end
function Logger.warn(msg)  Logger.log("WARN",  msg) end
function Logger.error(msg) Logger.log("ERROR", msg) end
function Logger.debug(msg) Logger.log("DEBUG", msg) end

function Logger.logNet(senderId, protocol, msg)
    local msgType = type(msg) == "table" and (msg.type or "?") or tostring(msg)
    Logger.debug("NET <- ID " .. tostring(senderId) .. " [" .. tostring(protocol) .. "] type=" .. msgType)
end

function Logger.logSend(targetId, protocol, msg)
    local msgType = type(msg) == "table" and (msg.type or "?") or tostring(msg)
    Logger.debug("NET -> ID " .. tostring(targetId) .. " [" .. tostring(protocol) .. "] type=" .. msgType)
end

return Logger
