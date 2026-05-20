-- startup.lua
-- Auto-updater

local BASE_URL = "https://raw.githubusercontent.com/Kkkur/casino-craft/refs/heads/feature/manager-autoupdater/manager/"

local FILES = {
    -- core
    "manager.lua",
    -- dependencies
    "dependencies/currency.lua",
    "dependencies/data.lua",
    "dependencies/fileserver.lua",
    "dependencies/logger.lua",
    "dependencies/player_detector.lua",
    "dependencies/rednet_manager.lua",
    "dependencies/ui.lua",
    "dependencies/leaderboards/leaderboard.lua",
}

local function log(msg)
    print("[updater] " .. msg)
end

local function ensureDir(path)
    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    -- build each directory level except the last (filename)
    local current = ""
    for i = 1, #parts - 1 do
        current = current == "" and parts[i] or (current .. "/" .. parts[i])
        if not fs.exists(current) then
            fs.makeDir(current)
        end
    end
end

local function wget(url, dest)
    -- delete old file so wget doesn't prompt
    if fs.exists(dest) then fs.delete(dest) end
    ensureDir(dest)
    local ok = shell.run("wget", url, dest)
    return ok
end

-- MAIN UPDATE

log("Casino Manager updater starting...")
log("Fetching " .. #FILES .. " file(s) from GitHub...")

local failed = {}

for _, file in ipairs(FILES) do
    local url  = BASE_URL .. file
    local dest = file  -- save relative to current dir
    log("Downloading: " .. file)
    local ok = wget(url, dest)
    if not ok then
        log("FAILED: " .. file)
        table.insert(failed, file)
    else
        log("OK: " .. file)
    end
end

-- RESULT

if #failed > 0 then
    log("WARNING: " .. #failed .. " file(s) failed to download:")
    for _, f in ipairs(failed) do
        log("  - " .. f)
    end
    log("Continuing with existing files...")
else
    log("All files updated successfully.")
end

-- LAUNCH MANAGER

log("Launching manager.lua...")
shell.run("manager.lua")