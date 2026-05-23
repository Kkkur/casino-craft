-- bootstrap.lua
-- Run normally for full setup, or with --update for silent file refresh

local BASE_URL   = "https://raw.githubusercontent.com/Kkkur/casino-craft/refs/heads/develop/"
local CONFIG_FILE = "machine_config.txt"

local GAME_TYPES = {
    {
        id    = "blackjack",
        label = "Blackjack Table",
        files = {
            "blackjack/blackjack.lua",
            "blackjack/bj_machine.lua",
            "blackjack/bj_startup.lua",
            "libraries/games/UILib.lua",
            "libraries/games/CardsLib.lua",
            "libraries/games/ChipsLib.lua",
            "libraries/bank/BankLib.lua",
            "libraries/logger/logger.lua",
            "libraries/currencylib.lua",
        },
        startup = "blackjack/bj_startup.lua",
        peripherals = {
            {
                label    = "Player Detector",
                versions = { "playerDetector", "player_detector" },
                key      = "detectorSide",
                optional = false,
            },
            {
                label    = "GPU Monitor",
                versions = { "gpu" },
                key      = "monitorSide",
                optional = false,
            },
        },
    },
}

--  Config 

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then return {} end
    local f = io.open(CONFIG_FILE, "r")
    if not f then return {} end
    local cfg = {}
    for line in f:lines() do
        local k, v = line:match("^(.-)=(.+)$")
        if k then cfg[k] = tonumber(v) or v end
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

--  UI helpers 

local function clear()
    term.setBackgroundColor(colours.black)
    term.clear()
    term.setCursorPos(1, 1)
end

local function printColor(color, msg)
    term.setTextColor(color)
    print(msg)
    term.setTextColor(colours.white)
end

local function printOk(msg)   printColor(colours.lime,      "[OK]  " .. msg) end
local function printErr(msg)  printColor(colours.red,       "[ERR] " .. msg) end
local function printWarn(msg) printColor(colours.yellow,    "[!!!] " .. msg) end
local function printInfo(msg) printColor(colours.lightGrey, "      " .. msg) end

local function prompt(msg, default)
    term.setTextColor(colours.cyan)
    if default ~= nil then
        io.write(msg .. " [" .. tostring(default) .. "]: ")
    else
        io.write(msg .. ": ")
    end
    term.setTextColor(colours.white)
    local input = io.read()
    if input == nil or input == "" then return default end
    return input
end

local function header(mode)
    term.setTextColor(colours.yellow)
    print("================================")
    if mode == "update" then
        print("   CASINO MACHINE UPDATER")
    else
        print("   CASINO MACHINE BOOTSTRAP")
    end
    print("================================")
    term.setTextColor(colours.white)
end

--  HTTP download 

local function downloadFile(filename, silent)
    local url = BASE_URL .. filename
    if not silent then io.write("  " .. filename .. "... ") end

    local ok, res = pcall(http.get, url)
    if not ok or not res then
        if not silent then printColor(colours.red, "FAILED (request error)") end
        return false, "request failed"
    end

    if res.getResponseCode and res.getResponseCode() ~= 200 then
        local code = res.getResponseCode()
        res.close()
        if not silent then printColor(colours.red, "FAILED (HTTP " .. code .. ")") end
        return false, "HTTP " .. code
    end

    local content = res.readAll()
    res.close()

    if not content or #content == 0 then
        if not silent then printColor(colours.red, "FAILED (empty)") end
        return false, "empty response"
    end

    -- Ensure parent directories exist
    local dir = fs.getDir(filename)
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    local f = io.open(filename, "w")
    if not f then
        if not silent then printColor(colours.red, "WRITE ERROR") end
        return false, "write error"
    end
    f:write(content)
    f:close()

    if not silent then
        term.setTextColor(colours.lime)
        print("OK (" .. #content .. " bytes)")
        term.setTextColor(colours.white)
    end
    return true
end

local function downloadAll(files, silent)
    if not silent then
        term.setTextColor(colours.cyan)
        print("\nDownloading " .. #files .. " file(s) from GitHub:")
        term.setTextColor(colours.white)
    end
    local failed = {}
    for _, filename in ipairs(files) do
        local ok, err = downloadFile(filename, silent)
        if not ok then failed[#failed + 1] = { file = filename, err = err } end
    end
    return failed
end

--  Peripheral detection 

local function findAllMatching(versions)
    local found = {}
    local vset  = {}
    for _, v in ipairs(versions) do vset[v] = true end
    for _, name in ipairs(peripheral.getNames()) do
        if vset[peripheral.getType(name)] then
            found[#found + 1] = { name = name, typeName = peripheral.getType(name) }
        end
    end
    return found
end

local function detectPeripherals(gameType, savedCfg)
    term.setTextColor(colours.cyan)
    print("\nChecking peripherals...")
    term.setTextColor(colours.white)

    local result = {}
    for _, periph in ipairs(gameType.peripherals or {}) do
        local matches = findAllMatching(periph.versions)

        if #matches == 1 then
            result[periph.key] = matches[1].name
            printOk(periph.label .. ": " .. matches[1].name)

        elseif #matches > 1 then
            printWarn("Multiple " .. periph.label .. " found:")
            for i, m in ipairs(matches) do
                printInfo("[" .. i .. "] " .. m.name .. " (" .. m.typeName .. ")")
            end
            local defaultIdx = 1
            if savedCfg[periph.key] then
                for i, m in ipairs(matches) do
                    if m.name == savedCfg[periph.key] then defaultIdx = i; break end
                end
            end
            local choice = tonumber(prompt("Which " .. periph.label .. " to use?", defaultIdx))
            if choice and matches[choice] then
                result[periph.key] = matches[choice].name
                printOk(periph.label .. ": " .. matches[choice].name)
            else
                result[periph.key] = matches[1].name
                printWarn("Invalid choice, using: " .. matches[1].name)
            end

        else
            if periph.optional then
                printWarn(periph.label .. " not found (optional — skipping)")
                result[periph.key] = nil
            else
                printErr(periph.label .. " not found! (required)")
                printErr("Tried types: " .. table.concat(periph.versions, ", "))
                return nil
            end
        end
    end
    return result
end

--  Game type selection 

local function selectGameType(savedId)
    if savedId then
        for _, gt in ipairs(GAME_TYPES) do
            if gt.id == savedId then
                local ans = prompt("Saved machine type: " .. gt.label .. " — use this? [Y/n]", "y")
                if ans:lower() ~= "n" then return gt end
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

--  Write startup shim 

local function writeStartup(startupFile)
    local f = io.open("startup.lua", "w")
    if not f then printErr("Could not write startup.lua!"); return false end
    -- Startup runs bootstrap in update mode first, then launches the game
    f:write('shell.run("bootstrap.lua", "--update")\n')
    f:write('shell.run("' .. startupFile .. '")\n')
    f:close()
    printOk("startup.lua written")
    return true
end

--  UPDATE MODE 
-- Called automatically by startup.lua on every boot.
-- Silently re-downloads all files, then exits so startup continues to the game.

local function runUpdate()
    local cfg = loadConfig()
    if not cfg.gameType then
        -- No config at all — can't update, just continue booting
        return
    end

    local gameType
    for _, gt in ipairs(GAME_TYPES) do
        if gt.id == cfg.gameType then gameType = gt; break end
    end
    if not gameType then return end

    term.setTextColor(colours.yellow)
    print("[Updater] Checking for updates...")
    term.setTextColor(colours.white)

    local failed = downloadAll(gameType.files, false)

    if #failed == 0 then
        term.setTextColor(colours.lime)
        print("[Updater] All files up to date.")
        term.setTextColor(colours.white)
    else
        term.setTextColor(colours.red)
        print("[Updater] " .. #failed .. " file(s) failed to update:")
        term.setTextColor(colours.white)
        for _, f in ipairs(failed) do
            printInfo(f.file .. " (" .. f.err .. ")")
        end
        printWarn("Continuing with existing files.")
    end

    os.sleep(1)
end

--  FULL BOOTSTRAP MODE 

local function runBootstrap()
    local savedCfg = loadConfig()
    local isUpdate = (savedCfg.gameType ~= nil)

    clear()
    header(isUpdate and "update" or "bootstrap")

    if isUpdate then
        printInfo("Existing config found. This will update all files and re-detect peripherals.")
        printInfo("Press Enter to continue or Ctrl+T to abort.")
        io.read()
    end

    -- Game type
    local gameType = selectGameType(savedCfg.gameType)
    if not gameType then return end

    -- Peripheral detection
    local periphCfg = detectPeripherals(gameType, savedCfg)
    if not periphCfg then
        printErr("Required peripheral(s) missing. Fix hardware and re-run bootstrap.")
        return
    end

    -- Download all files
    local failed = downloadAll(gameType.files, false)
    if #failed > 0 then
        printErr("Failed to download:")
        for _, f in ipairs(failed) do printInfo(f.file .. " (" .. f.err .. ")") end
        printErr("Bootstrap incomplete. Fix the above and try again.")
        return
    end
    printOk("All " .. #gameType.files .. " file(s) downloaded.")

    -- Save config (only on full success)
    local newCfg = { gameType = gameType.id }
    for k, v in pairs(periphCfg) do newCfg[k] = v end
    saveConfig(newCfg)
    printOk("Config saved.")

    -- Write startup shim
    if not writeStartup(gameType.startup) then return end

    term.setTextColor(colours.yellow)
    print("\n================================")
    print("  Bootstrap complete!")
    print("  Rebooting in 3 seconds...")
    print("================================")
    term.setTextColor(colours.white)
    os.sleep(3)
    os.reboot()
end

--  Entry point 

local args = { ... }
if args[1] == "--update" then
    runUpdate()
else
    runBootstrap()
end