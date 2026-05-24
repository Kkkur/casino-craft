-- libraries/logger/logger.lua

local logger = {}

local MAX_OLD_LOGS = 5

local _logFile   = nil
local _logDir    = nil
local _tag       = nil
local _debugMode = false

local function ensureDir(dir)
    if not fs.exists(dir) then fs.makeDir(dir) end
end

local function timestamp()
    local t = os.time()
    local h = math.floor(t) % 24
    local m = math.floor((t - math.floor(t)) * 60)
    return string.format("%02d:%02d", h, m)
end

local function epochMs()
    return os.epoch("utc")
end

local function getNumberedLogs(dir)
    local list = {}
    for _, name in ipairs(fs.list(dir)) do
        local n = tonumber(name)
        if n then list[#list + 1] = n end
    end
    table.sort(list)
    return list
end

local function rotateLogs(dir, latest)
    ensureDir(dir)
    if not fs.exists(latest) then return end
    local numbered = getNumberedLogs(dir)
    local nextNum  = (#numbered > 0) and (numbered[#numbered] + 1) or 1
    fs.move(latest, dir .. "/" .. nextNum)
    numbered[#numbered + 1] = nextNum
    while #numbered > MAX_OLD_LOGS do
        fs.delete(dir .. "/" .. numbered[1])
        table.remove(numbered, 1)
    end
end

local function writeToFile(line)
    if not _logFile then return end
    local f = fs.open(_logFile, "a")
    if not f then return end
    f.writeLine(line)
    f.close()
end

local LEVEL_COLORS = {
    INFO  = colours.lime,
    WARN  = colours.yellow,
    ERROR = colours.red,
    DEBUG = colours.lightGrey,
    NET   = colours.cyan,
}

function logger.init(tag, logDir, debug)
    _tag       = tag or "?"
    _debugMode = debug or false
    if logDir then
        _logDir  = logDir
        _logFile = logDir .. "/latest"
        rotateLogs(_logDir, _logFile)
        ensureDir(_logDir)
        local f = fs.open(_logFile, "w")
        if f then
            f.writeLine(string.format(
                "=== [%s] Log session — day %d %s (epoch %d) ===",
                _tag, os.day(), timestamp(), epochMs()
            ))
            f.close()
        end
    end
    logger.info("logger initialised" .. (logDir and (" → " .. logDir) or " (no file)"))
end

function logger.log(level, msg)
    local tag  = _tag and ("[" .. _tag .. "] ") or ""
    local line = string.format("[%s] [%s] %s%s", timestamp(), level, tag, tostring(msg))
    writeToFile(line)
    if level == "DEBUG" and not _debugMode then return end
    local col = LEVEL_COLORS[level] or colours.white
    term.setTextColor(col)
    print(line)
    term.setTextColor(colours.white)
end

-- Raw print: no level/tag prefix on screen, but still written to log file with RAW tag
function logger.raw(msg, color)
    writeToFile(string.format("[%s] [RAW] %s%s", timestamp(), _tag and ("[" .. _tag .. "] ") or "", tostring(msg)))
    term.setTextColor(color or colours.white)
    print(tostring(msg))
    term.setTextColor(colours.white)
end

function logger.info(msg)  logger.log("INFO",  msg) end
function logger.warn(msg)  logger.log("WARN",  msg) end
function logger.error(msg) logger.log("ERROR", msg) end
function logger.debug(msg) logger.log("DEBUG", msg) end

function logger.net(direction, peerId, protocol, msgType)
    local arrow = (direction == "RECV") and "<-" or "->"
    logger.log("NET", string.format(
        "NET %s ID %s [%s] type=%s",
        arrow, tostring(peerId), tostring(protocol), tostring(msgType)
    ))
end

function logger.tail(limit)
    limit = limit or 20
    if not _logFile or not fs.exists(_logFile) then return {} end
    local f = fs.open(_logFile, "r")
    if not f then return {} end
    local lines = {}
    local line  = f.readLine()
    while line do
        table.insert(lines, line)
        line = f.readLine()
    end
    f.close()
    local result = {}
    for i = #lines, math.max(1, #lines - limit + 1), -1 do
        result[#result + 1] = lines[i]
    end
    return result
end

function logger.setDebug(enabled)
    _debugMode = enabled
end

return logger