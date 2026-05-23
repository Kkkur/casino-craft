-- logger.lua
-- Persistent logger for the casino manager

local logger = {}

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

function logger.init()
    ensureDir()
    rotateLogs()
    local f = fs.open(LATEST, "w")
    if f then
        f.writeLine("=== Casino Manager Log - Session start (day " .. os.day() .. " " .. timestamp() .. ") ===")
        f.close()
    end
    logger.info("logger initialised. Logs in: " .. LOG_DIR)
end

function logger.log(level, msg)
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

function logger.info(msg)  logger.log("INFO",  msg) end
function logger.warn(msg)  logger.log("WARN",  msg) end
function logger.error(msg) logger.log("ERROR", msg) end
function logger.debug(msg) logger.log("DEBUG", msg) end

function logger.logNet(senderId, protocol, msg)
    local msgType = type(msg) == "table" and (msg.type or "?") or tostring(msg)
    logger.debug("NET <- ID " .. tostring(senderId) .. " [" .. tostring(protocol) .. "] type=" .. msgType)
end

function logger.logSend(targetId, protocol, msg)
    local msgType = type(msg) == "table" and (msg.type or "?") or tostring(msg)
    logger.debug("NET -> ID " .. tostring(targetId) .. " [" .. tostring(protocol) .. "] type=" .. msgType)
end

return logger
