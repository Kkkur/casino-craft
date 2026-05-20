-- Lives at the root of every game machine as the default startup script.
-- On first boot it walks you through setup and saves everything to machine_config.txt.
-- On every boot after that it loads the saved config, wgets the latest files, and launches the game.

local CONFIG_FILE = "machine_config.txt"
local BASE_URL    = "https://raw.githubusercontent.com/Kkkur/casino-craft/refs/heads/feature/libraries/"

-- Files each game type needs, relative to BASE_URL.
-- Add new game types here as they are built.
local GAME_FILES = {
    blackjack = {
        "games/libraries/barrel_handler.lua",
        "games/libraries/net_client.lua",
        "games/libraries/ui_lib.lua",
        "games/libraries/player_detector.lua",
        "games/blackjack/blackjack.lua",
        "games/blackjack/bj_ui.lua",
        "games/blackjack/bj_machine.lua",
    },
}

-- The file to run after updating, per game type.
local GAME_ENTRY = {
    blackjack = "games/blackjack/bj_machine.lua",
}

local function log(msg)
    print("[bootstrap] " .. msg)
end

local function ask(question, default)
    term.setTextColor(colours.cyan)
    if default then
        io.write(question .. " [" .. tostring(default) .. "]: ")
    else
        io.write(question .. ": ")
    end
    term.setTextColor(colours.white)
    local input = io.read()
    if not input or input == "" then return default end
    return input
end

-- Config is stored as simple key=value lines.

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then return {} end
    local f = io.open(CONFIG_FILE, "r")
    if not f then return {} end
    local cfg = {}
    for line in f:lines() do
        local k, v = line:match("^(.-)=(.+)$")
        if k then
            cfg[k] = tonumber(v) or v
        end
    end
    f:close()
    return cfg
end

local function saveConfig(cfg)
    local f = io.open(CONFIG_FILE, "w")
    if not f then
        log("ERROR: could not write " .. CONFIG_FILE)
        return false
    end
    for k, v in pairs(cfg) do
        f:write(tostring(k) .. "=" .. tostring(v) .. "\n")
    end
    f:close()
    return true
end

-- Walks through all questions needed for first boot or fills gaps if something is missing.
-- Only asks about things that are not already in cfg.

local function setupConfig(cfg)
    term.setTextColor(colours.yellow)
    print("=== CASINO MACHINE SETUP ===")
    term.setTextColor(colours.white)

    -- Manager ID
    if not cfg.managerId then
        local id = tonumber(ask("Manager computer ID"))
        if not id then
            log("Invalid manager ID, aborting.")
            return nil
        end
        cfg.managerId = id
    end

    -- Game type
    if not cfg.gameType then
        print("Available game types:")
        local types = {}
        for k in pairs(GAME_FILES) do
            types[#types + 1] = k
            print("  [" .. #types .. "] " .. k)
        end
        local choice = tonumber(ask("Choose game type"))
        if not choice or not types[choice] then
            log("Invalid choice, aborting.")
            return nil
        end
        cfg.gameType = types[choice]
    end

    -- Machine label
    if not cfg.label then
        local label = ask("Machine name (e.g. Blackjack Table 1)")
        if not label then
            log("No label entered, aborting.")
            return nil
        end
        cfg.label = label
    end

    -- Monitor
    if not cfg.monitorSide then
        local monitors = {}
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "monitor" then
                monitors[#monitors + 1] = name
            end
        end
        if #monitors == 0 then
            log("No monitor found, please attach one and reboot.")
            return nil
        elseif #monitors == 1 then
            cfg.monitorSide = monitors[1]
            log("Monitor auto-detected: " .. monitors[1])
        else
            print("Multiple monitors found:")
            for i, name in ipairs(monitors) do
                print("  [" .. i .. "] " .. name)
            end
            local choice = tonumber(ask("Choose monitor"))
            if not choice or not monitors[choice] then
                log("Invalid choice, aborting.")
                return nil
            end
            cfg.monitorSide = monitors[choice]
        end
    end

    -- Player Detector
    if not cfg.playerDetector then
        local num = ask("Player detector number (e.g. 1 for advancedperipherals:player_detector_1)")
        num = tonumber(num)
        if not num then
            log("Invalid detector number, aborting.")
            return nil
        end
        cfg.playerDetector = "player_detector_" .. num
        
        local found = false
        for _, name in ipairs(peripheral.getNames()) do
            if name == cfg.playerDetector then found = true; break end
        end
        if not found then
            log("Warning: " .. cfg.playerDetector .. " not visible on network right now.")
        else
            log("Player detector confirmed: " .. cfg.playerDetector)
        end
    end

    -- Player deposit barrel
    if not cfg.playerBarrel then
        local num = ask("Deposit barrel number (e.g. 2 for minecraft:barrel_2)")
        num = tonumber(num)
        if not num then
            log("Invalid barrel number, aborting.")
            return nil
        end
        cfg.playerBarrel = "minecraft:barrel_" .. num
        local found = false
        for _, name in ipairs(peripheral.getNames()) do
            if name == cfg.playerBarrel then found = true; break end
        end
        if not found then
            log("Warning: " .. cfg.playerBarrel .. " not visible on network right now.")
            log("Make sure the wired modem is connected before starting the game.")
        else
            log("Deposit barrel confirmed: " .. cfg.playerBarrel)
        end
    end

    -- Shared casino reserve barrel
    if not cfg.sharedBarrel then
        local num = ask("Shared reserve barrel number (e.g. 5 for minecraft:barrel_5)")
        num = tonumber(num)
        if not num then
            log("Invalid barrel number, aborting.")
            return nil
        end
        cfg.sharedBarrel = "minecraft:barrel_" .. num
        local found = false
        for _, name in ipairs(peripheral.getNames()) do
            if name == cfg.sharedBarrel then found = true; break end
        end
        if not found then
            log("Warning: " .. cfg.sharedBarrel .. " not visible on network right now.")
        else
            log("Reserve barrel confirmed: " .. cfg.sharedBarrel)
        end
    end

    return cfg
end

-- Checks if any required config keys are missing and triggers re-ask for those only.
local function validateConfig(cfg)
    local required = { "managerId", "gameType", "label", "monitorSide", "playerDetector", "playerBarrel", "sharedBarrel" }
    local missing = false
    for _, key in ipairs(required) do
        if not cfg[key] then
            missing = true
            break
        end
    end
    if missing then
        log("Some config is missing, running setup...")
        return setupConfig(cfg)
    end
    return cfg
end

-- Downloads a file from GitHub, always replacing whatever is there.
local function download(remotePath, localPath)
    local url = BASE_URL .. remotePath .. "?t=" .. os.epoch("utc")
    
    -- Fetch the data directly via HTTP
    local response = http.get(url, nil, true) -- true = binary mode
    if not response then
        log("FAILED: Could not connect to " .. url)
        return false
    end
    
    local content = response.readAll()
    response.close()
    
    -- Ensure directory exists
    local dir = localPath:match("^(.*)/[^/]+$")
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    
    -- Write the file
    local f = io.open(localPath, "w")
    if not f then 
        log("FAILED: Could not open " .. localPath .. " for writing")
        return false 
    end
    f:write(content)
    f:close()
    
    return true
end

-- Downloads all files for the given game type.
local function updateFiles(gameType)
    local files = GAME_FILES[gameType]
    if not files then
        log("Unknown game type: " .. tostring(gameType))
        return false
    end

    log("Updating " .. #files .. " file(s) for " .. gameType .. "...")
    local failed = {}
    for _, path in ipairs(files) do
        log("Fetching: " .. path)
        -- Save to the same relative path so dofile paths match the repo structure
        if not download(path, path) then
            log("FAILED: " .. path)
            failed[#failed + 1] = path
        end
    end

    if #failed > 0 then
        log("WARNING: " .. #failed .. " file(s) failed to download.")
        for _, f in ipairs(failed) do
            log("  - " .. f)
        end
        return false
    end

    log("All files updated.")
    return true
end

-- MAIN

-- Parse arguments. Usage: bootstrap -noupdate (skips downloading files, just launches)
local args = {...}
local noUpdate = false
for _, arg in ipairs(args) do
    if arg == "-noupdate" then noUpdate = true end
end

term.setBackgroundColor(colours.black)
term.clear()
term.setCursorPos(1, 1)

local cfg = loadConfig()
local firstBoot = (next(cfg) == nil)

if firstBoot then
    log("First boot detected, starting setup...")
    cfg = setupConfig(cfg or {})
else
    cfg = validateConfig(cfg)
end

if not cfg then
    log("Setup incomplete, halting. Reboot to try again.")
    return
end

saveConfig(cfg)
log("Config saved.")

-- Open wireless modem before launching so the game has rednet ready
local modem = peripheral.find("modem", function(_, m)
    return m.isWireless and m.isWireless()
end)
if modem then
    rednet.open(peripheral.getName(modem))
    log("Wireless modem opened.")
else
    log("Warning: no wireless modem found.")
end

-- Update all game files from GitHub (skip with -noupdate arg)
if noUpdate then
    log("Skipping update (-noupdate).")
else
    updateFiles(cfg.gameType)
end

-- Write peripheral and barrel config into machine_config.txt so the game can read it
-- (already saved above but we re-save here in case updateFiles touched anything)
saveConfig(cfg)

-- Launch the game
local entry = GAME_ENTRY[cfg.gameType]
if not entry then
    log("No entry point defined for game type: " .. tostring(cfg.gameType))
    return
end

if not fs.exists(entry) then
    log("Entry file not found: " .. entry .. ", update may have failed.")
    return
end

log("Launching " .. entry .. "...")
shell.run(entry)