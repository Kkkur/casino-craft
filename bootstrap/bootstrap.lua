-- bootstrap.lua

local PROTOCOL  = "CASINO_FS"
local LOG_PROTO = "CASINO_LOG"
local TIMEOUT   = 10

local GAME_TYPES = {
    {
        id      = "blackjack",
        label   = "Blackjack Table",
        files   = {
            "blackjack.lua",
            "bj_ui.lua",
            "bj_machine.lua",
            "bj_startup.lua",
            "player_detector.lua",
        },
        startup    = "bj_startup.lua",
        peripherals = {
            {
                label    = "Player Detector",
                versions = { "playerDetector", "player_detector" },
                key      = "detectorSide",
                optional = true,   -- machine runs without it, names show as Unknown
            },
            {
                label    = "Monitor",
                versions = { "monitor" },
                key      = "monitorSide",
                optional = false,
            },
        },
    },
}

-- Config file (persists manager ID, game type, peripheral sides) 
local CONFIG_FILE = "machine_config.txt"

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then return {} end
    local f = io.open(CONFIG_FILE, "r")
    if not f then return {} end
    local cfg = {}
    for line in f:lines() do
        local k, v = line:match("^(.-)=(.+)$")
        if k then
            -- Restore numbers as numbers
            cfg[k] = tonumber(v) or v
        end
    end
    f:close()
    return cfg
end

local function saveConfig(cfg)
    local f = io.open(CONFIG_FILE, "w")
    if not f then return false end
    for k, v in pairs(cfg) do
        f:write(tostring(k) .. "=" .. tostring(v) .. "\n")
    end
    f:close()
    return true
end

-- Remote logger 
local managerId = nil
local logBuffer = {}

local function timestamp()
    local t = os.time()
    local h = math.floor(t)
    local m = math.floor((t - h) * 60)
    return string.format("%02d:%02d", h % 24, m)
end

local function remoteLog(level, msg)
    local line = "[" .. timestamp() .. "] [BOOTSTRAP/" .. level .. "] (ID "
                 .. os.getComputerID() .. ") " .. tostring(msg)
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
    if managerId then
        rednet.send(managerId, { type = "log", line = line }, LOG_PROTO)
    else
        logBuffer[#logBuffer+1] = line
    end
end

local function flushLogBuffer()
    if managerId and #logBuffer > 0 then
        for _, line in ipairs(logBuffer) do
            rednet.send(managerId, { type = "log", line = line }, LOG_PROTO)
        end
        logBuffer = {}
    end
end

local function logInfo(msg)  remoteLog("INFO",  msg) end
local function logWarn(msg)  remoteLog("WARN",  msg) end
local function logErr(msg)   remoteLog("ERROR", msg) end
local function logDebug(msg) remoteLog("DEBUG", msg) end

-- UI helpers 
local function clear()
    term.setBackgroundColor(colours.black)
    term.clear()
    term.setCursorPos(1,1)
end

local function header(isUpdate)
    term.setTextColor(colours.yellow)
    print("================================")
    if isUpdate then
        print("   CASINO MACHINE UPDATER")
    else
        print("   CASINO MACHINE BOOTSTRAP")
    end
    print("================================")
    term.setTextColor(colours.white)
end

local function printOk(msg)
    term.setTextColor(colours.lime)
    print("[OK]  " .. msg)
    term.setTextColor(colours.white)
end

local function printErr(msg)
    term.setTextColor(colours.red)
    print("[ERR] " .. msg)
    term.setTextColor(colours.white)
end

local function printWarn(msg)
    term.setTextColor(colours.yellow)
    print("[!!!] " .. msg)
    term.setTextColor(colours.white)
end

local function printInfo(msg)
    term.setTextColor(colours.lightGrey)
    print("      " .. msg)
    term.setTextColor(colours.white)
end

local function prompt(msg, default)
    term.setTextColor(colours.cyan)
    if default ~= nil then
        io.write(msg .. " [" .. tostring(default) .. "]: ")
    else
        io.write(msg .. ": ")
    end
    term.setTextColor(colours.white)
    local input = io.read()
    if input == "" then return default end
    return input
end

--  Modem 
local function openModem()
    for _, side in ipairs({"top","bottom","left","right","front","back"}) do
        if peripheral.getType(side) == "modem" then
            local m = peripheral.wrap(side)
            if m and m.isWireless and m.isWireless() then
                rednet.open(side)
                logDebug("Modem opened on: " .. side)
                return true
            end
        end
    end
    printErr("No wireless modem found!")
    return false
end

--  Manager ID 
local function getManagerId(saved)
    if saved then
        local ans = prompt("Saved manager ID: " .. saved .. " — use this? [Y/n]", "y")
        if ans:lower() == "y" or ans == "" then
            return saved
        end
    end
    local id = tonumber(prompt("Enter manager computer ID"))
    if not id then
        printErr("Invalid ID.")
        return nil
    end
    return id
end

--  Game type 
local function selectGameType(savedId)
    -- If we have a saved game type, find it
    if savedId then
        for _, gt in ipairs(GAME_TYPES) do
            if gt.id == savedId then
                local ans = prompt("Saved machine type: " .. gt.label .. " — use this? [Y/n]", "y")
                if ans:lower() == "y" or ans == "" then
                    return gt
                end
                break
            end
        end
    end
    term.setTextColor(colours.cyan)
    print("\nSelect machine type:")
    term.setTextColor(colours.white)
    for i, gt in ipairs(GAME_TYPES) do
        print("  [" .. i .. "] " .. gt.label)
    end
    local n = tonumber(prompt("Choice"))
    if not n or not GAME_TYPES[n] then
        printErr("Invalid choice.")
        return nil
    end
    return GAME_TYPES[n]
end

-- Peripheral detection 
-- Tries to find a peripheral by any of its known type names
local function findPeripheralName(versions)
    for _, typeName in ipairs(versions) do
        local p = peripheral.find(typeName)
        if p then
            return peripheral.getName(p), typeName
        end
    end
    return nil, nil
end

-- Scans all sides and connected peripherals for any matching type name
local function findAllMatching(versions)
    local found = {}
    local versionSet = {}
    for _, v in ipairs(versions) do versionSet[v] = true end

    for _, name in ipairs(peripheral.getNames()) do
        local t = peripheral.getType(name)
        if versionSet[t] then
            found[#found+1] = { name = name, typeName = t }
        end
    end
    return found
end

-- Checks and validates all required peripherals for a game type.
local function detectPeripherals(gameType, savedCfg)
    term.setTextColor(colours.cyan)
    print("\nChecking peripherals...")
    term.setTextColor(colours.white)

    local result = {}

    for _, periph in ipairs(gameType.peripherals or {}) do
        local savedSide = savedCfg[periph.key]

        -- First, try finding it automatically
        local matches = findAllMatching(periph.versions)

        if #matches == 1 then
            -- Exactly one found use it automatically
            result[periph.key] = matches[1].name
            printOk(periph.label .. ": " .. matches[1].name
                .. " (" .. matches[1].typeName .. ")")
            logInfo("Auto-detected " .. periph.label .. ": " .. matches[1].name)

        elseif #matches > 1 then
            -- Multiple found, ask which one to use
            term.setTextColor(colours.yellow)
            print("  Multiple " .. periph.label .. " peripherals found:")
            term.setTextColor(colours.white)
            for i, m in ipairs(matches) do
                print("    [" .. i .. "] " .. m.name .. " (" .. m.typeName .. ")")
            end

            -- Default to saved side if its still in the list
            local defaultIdx = nil
            if savedSide then
                for i, m in ipairs(matches) do
                    if m.name == savedSide then defaultIdx = i; break end
                end
            end
            defaultIdx = defaultIdx or 1

            local choice = tonumber(prompt("Which " .. periph.label
                .. " to use?", defaultIdx))
            if choice and matches[choice] then
                result[periph.key] = matches[choice].name
                printOk(periph.label .. ": " .. matches[choice].name)
                logInfo("Selected " .. periph.label .. ": " .. matches[choice].name)
            else
                printWarn("Invalid choice, using first: " .. matches[1].name)
                result[periph.key] = matches[1].name
            end

        else
            -- None found at all
            if periph.optional then
                printWarn(periph.label .. " not found (optional — will run without it).")
                logWarn("Optional peripheral not found: " .. periph.label)
                result[periph.key] = nil
            else
                printErr(periph.label .. " not found! (required)")
                logErr("Required peripheral missing: " .. periph.label
                    .. " (tried: " .. table.concat(periph.versions, ", ") .. ")")
                return nil
            end
        end
    end

    return result
end

--  Download 
-- Always overwrites 
-- bootstrap always refreshes every file to the latest version on the manager.
local function downloadFile(id, filename)
    io.write("  " .. filename .. "... ")
    logDebug("Requesting: " .. filename)

    rednet.send(id, { type = "request", file = filename }, PROTOCOL)
    local sid, msg = rednet.receive(PROTOCOL, TIMEOUT)

    if not sid then
        print("TIMEOUT")
        logErr("Timeout: " .. filename)
        return false
    end
    if sid ~= id then
        print("WRONG SENDER (got " .. sid .. ")")
        logErr("Wrong sender for " .. filename .. ": got ID " .. sid)
        return false
    end
    if type(msg) ~= "table" then
        print("BAD RESPONSE")
        logErr("Non-table response for " .. filename)
        return false
    end
    if msg.type ~= "file_response" and msg.type ~= "file" then
        print("BAD TYPE (" .. tostring(msg.type) .. ")")
        logErr("Unexpected response type for " .. filename .. ": " .. tostring(msg.type))
        return false
    end
    if not msg.ok then
        print("FAILED (" .. tostring(msg.err) .. ")")
        logErr("Server error for " .. filename .. ": " .. tostring(msg.err))
        return false
    end
    if not msg.content then
        print("NO CONTENT")
        logErr("No content in response for " .. filename)
        return false
    end

    -- Always write, even if file already exists
    local f = io.open(filename, "w")
    if not f then
        print("WRITE ERROR")
        logErr("Cannot write: " .. filename)
        return false
    end
    f:write(msg.content)
    f:close()

    term.setTextColor(colours.lime)
    print("OK (" .. #msg.content .. " bytes)")
    term.setTextColor(colours.white)
    logInfo("Downloaded: " .. filename .. " (" .. #msg.content .. " bytes)")
    return true
end

local function downloadAll(id, files)
    term.setTextColor(colours.cyan)
    print("\nDownloading " .. #files .. " file(s) from manager #" .. id .. ":")
    term.setTextColor(colours.white)
    local failed = {}
    for _, filename in ipairs(files) do
        if not downloadFile(id, filename) then
            failed[#failed+1] = filename
        end
    end
    return failed
end

--  Write startup 
local function writeStartup(startupFile)
    local f = io.open("startup.lua", "w")
    if not f then
        printErr("Could not write startup.lua!")
        logErr("Failed to write startup.lua")
        return false
    end
    f:write('shell.run("' .. startupFile .. '")\n')
    f:close()
    printOk("startup.lua -> " .. startupFile)
    logInfo("startup.lua written, launches: " .. startupFile)
    return true
end

--  Main 
local savedCfg  = loadConfig()
local isUpdate  = (savedCfg.managerId ~= nil)

-- Wipe the config file immediately so stale peripheral/barrel names for a clean instalattion 
if fs.exists(CONFIG_FILE) then
    fs.delete(CONFIG_FILE)
end

clear()
header(isUpdate)

if isUpdate then
    printInfo("Existing config found. Re-running will update all files.")
    printInfo("Press Enter to continue or Ctrl+T to abort.")
    io.read()
end

logInfo("Bootstrap started on computer ID: " .. os.getComputerID())

-- Step 1: Manager ID
managerId = getManagerId(savedCfg.managerId)
if not managerId then return end
logInfo("Manager ID: " .. managerId)

-- Step 2: Game type
local gameType = selectGameType(savedCfg.gameType)
if not gameType then return end
logInfo("Game type: " .. gameType.label)

-- Step 3: Open modem
if not openModem() then return end
flushLogBuffer()

-- Step 4: Ping manager
io.write("\nPinging manager... ")
logDebug("Sending ping to ID " .. managerId)
rednet.send(managerId, { type = "ping" }, PROTOCOL)
local sid, pongMsg = rednet.receive(PROTOCOL, 5)
if not sid then
    printErr("No response from manager ID " .. managerId .. " (timeout)")
    logErr("Ping timed out")
    return
end
term.setTextColor(colours.lime)
print("Online!")
term.setTextColor(colours.white)
logInfo("Manager responded to ping.")

-- Step 5: Detect peripherals
local periphCfg = detectPeripherals(gameType, savedCfg)
if not periphCfg then
    printErr("Required peripheral(s) missing. Fix hardware and re-run bootstrap.")
    logErr("Bootstrap aborted — peripheral check failed.")
    return
end

-- Step 6: Barrel config 
local SHARED_BARREL = "minecraft:barrel_5"

local function promptBarrelConfig(savedCfg)
    term.setTextColor(colours.cyan)
    print("\nBarrel configuration (wired network):")
    term.setTextColor(colours.white)
    printInfo("Shared chip barrel is always: " .. SHARED_BARREL)

    -- Try to guess default from saved config
    local savedNum = nil
    if savedCfg.playerBarrel then
        savedNum = savedCfg.playerBarrel:match("minecraft:barrel_(%d+)")
    end

    local num = prompt("Deposit barrel number (e.g. 2 for minecraft:barrel_2)", savedNum)
    num = tonumber(num)
    if not num then
        printErr("Invalid barrel number.")
        return nil
    end

    local playerBarrel = "minecraft:barrel_" .. num

    -- Verify both barrels are visible on the wired network
    local allNames = peripheral.getNames()
    local nameSet  = {}
    for _, n in ipairs(allNames) do nameSet[n] = true end

    if not nameSet[playerBarrel] then
        printWarn(playerBarrel .. " not found on network right now.")
        printWarn("Make sure the wired modem is connected before starting the machine.")
        logWarn("Deposit barrel not currently visible: " .. playerBarrel)
    else
        printOk("Deposit barrel: " .. playerBarrel)
        logInfo("Deposit barrel confirmed: " .. playerBarrel)
    end

    if not nameSet[SHARED_BARREL] then
        printWarn(SHARED_BARREL .. " (shared chips) not found on network right now.")
        logWarn("Shared chip barrel not currently visible: " .. SHARED_BARREL)
    else
        printOk("Shared chip barrel:  " .. SHARED_BARREL)
        logInfo("Shared chip barrel confirmed: " .. SHARED_BARREL)
    end

    return playerBarrel, SHARED_BARREL
end

local playerBarrel, sharedBarrel = promptBarrelConfig(savedCfg)
if not playerBarrel then
    printErr("Barrel setup failed. Fix config and re-run bootstrap.")
    logErr("Bootstrap aborted — barrel config failed.")
    return
end

-- Step 7: Download all files (always overwrites)
local failed = downloadAll(managerId, gameType.files)

if #failed > 0 then
    printErr("Failed to download:")
    for _, fname in ipairs(failed) do
        printInfo(fname)
        logErr("Missing: " .. fname)
    end
    printErr("Bootstrap incomplete. Fix manager and try again.")
    logErr("Bootstrap FAILED — " .. #failed .. " file(s) missing.")
    return
end
printOk("All " .. #gameType.files .. " file(s) downloaded.")
logInfo("All files downloaded OK.")

-- Step 8: Save unified config
local newCfg = {
    managerId    = managerId,
    gameType     = gameType.id,
    playerBarrel = playerBarrel,
    sharedBarrel = sharedBarrel,
}
for k, v in pairs(periphCfg) do
    newCfg[k] = v
end
saveConfig(newCfg)
printOk("Config saved to " .. CONFIG_FILE)
logInfo("Config saved.")

-- Keep manager_id.txt for backward compatibility with bj_machine.lua
local f = io.open("manager_id.txt", "w")
f:write(tostring(managerId) .. "\n")
f:close()
logInfo("manager_id.txt written for compatibility.")

-- Step 9: Write startup shim
writeStartup(gameType.startup)

logInfo("Bootstrap complete. Rebooting.")
term.setTextColor(colours.yellow)
print("\n================================")
if isUpdate then
    print("  Update complete!")
else
    print("  Bootstrap complete!")
end
print("  Rebooting in 3 seconds...")
print("================================")
term.setTextColor(colours.white)
os.sleep(3)
os.reboot()