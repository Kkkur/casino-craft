-- bootstrap_leaderboard.lua
-- Runs on the RELAY PC as the startup script.
-- First boot: asks for manager PC ID and which game leaderboard to display, saves to config.json.
-- Every boot: redownloads the leaderboard display script and runs it.

local CONFIG_FILE = "config.json"
local BASE_URL    = "https://raw.githubusercontent.com/Kkkur/casino-craft/refs/heads/main/leaderboard-display/"

-- Leaderboard files per game. Only blackjack is live; others are placeholders.
local GAME_FILES = {
    blackjack = "leaderboard_display.lua",
    roulette  = "leaderboard_roulette.lua",
    dice      = "leaderboard_dice.lua",
    slots     = "leaderboard_slots.lua",
    crash     = "leaderboard_crash.lua",
}

local GAME_WORKING = {
    blackjack = true,
}

local GAME_LIST = { "blackjack", "roulette", "dice", "slots", "crash" }

-- -------------------------------------------------------------------------- --

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

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then return nil end
    local f = io.open(CONFIG_FILE, "r")
    if not f then return nil end
    local raw = f:read("*a")
    f:close()
    local ok, data = pcall(textutils.unserialiseJSON, raw)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

local function saveConfig(cfg)
    local f = io.open(CONFIG_FILE, "w")
    if not f then
        log("ERROR: could not write " .. CONFIG_FILE)
        return false
    end
    f:write(textutils.serialiseJSON(cfg))
    f:close()
    return true
end

local function setupConfig()
    term.setTextColor(colours.yellow)
    print("=== LEADERBOARD RELAY SETUP ===")
    term.setTextColor(colours.white)

    -- Manager PC ID
    local managerId = tonumber(ask("Manager computer rednet ID"))
    if not managerId then
        log("Invalid ID, aborting.")
        return nil
    end

    -- Game type
    print("Available leaderboard types:")
    for i, name in ipairs(GAME_LIST) do
        local tag = GAME_WORKING[name] and "" or " (coming soon)"
        print("  [" .. i .. "] " .. name .. tag)
    end
    local choice = tonumber(ask("Choose game"))
    if not choice or not GAME_LIST[choice] then
        log("Invalid choice, aborting.")
        return nil
    end
    local gameType = GAME_LIST[choice]

    if not GAME_WORKING[gameType] then
        term.setTextColor(colours.orange)
        print("Warning: " .. gameType .. " leaderboard is not yet available.")
        print("The download will likely fail. Continue anyway? (y/n)")
        term.setTextColor(colours.white)
        local confirm = io.read()
        if confirm ~= "y" and confirm ~= "Y" then
            log("Aborted.")
            return nil
        end
    end

    return {
        managerId = managerId,
        gameType  = gameType,
    }
end

local function download(filename)
    local url = BASE_URL .. filename .. "?t=" .. os.epoch("utc")
    log("Downloading " .. filename .. "...")
    local response = http.get(url, nil, true)
    if not response then
        log("FAILED: could not reach " .. url)
        return false
    end
    local content = response.readAll()
    response.close()
    local f = io.open(filename, "w")
    if not f then
        log("FAILED: could not write " .. filename)
        return false
    end
    f:write(content)
    f:close()
    return true
end

-- -------------------------------------------------------------------------- --
-- MAIN

term.setBackgroundColor(colours.black)
term.clear()
term.setCursorPos(1, 1)

local cfg = loadConfig()

if not cfg then
    log("No config found, running first-boot setup...")
    cfg = setupConfig()
    if not cfg then
        log("Setup incomplete, halting. Reboot to try again.")
        return
    end
    saveConfig(cfg)
    log("Config saved to " .. CONFIG_FILE)
else
    log("Config loaded. Manager ID: " .. cfg.managerId .. ", Game: " .. cfg.gameType)
end

-- Open wireless modem
local modem = peripheral.find("modem", function(_, m)
    return m.isWireless and m.isWireless()
end)
if modem then
    rednet.open(peripheral.getName(modem))
    log("Wireless modem opened.")
else
    log("Warning: no wireless modem found.")
end

-- Download the leaderboard display for the configured game
local filename = GAME_FILES[cfg.gameType]
if not filename then
    log("No file defined for game type: " .. tostring(cfg.gameType))
    return
end

if fs.exists(filename) then
    fs.delete(filename)
end

if not download(filename) then
    log("Download failed, halting.")
    return
end

log("Launching " .. filename .. "...")
shell.run(filename)