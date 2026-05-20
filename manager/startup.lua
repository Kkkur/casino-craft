-- startup.lua
-- Auto-updater: deletes and re-fetches all files from GitHub, then launches manager.lua

local BASE_URL = "https://raw.githubusercontent.com/Kkkur/casino-craft/refs/heads/feature/manager-autoupdater/manager/"

local FILES = {
    "manager.lua",
    "dependencies/currency.lua",
    "dependencies/data.lua",
    "dependencies/fileserver.lua",
    "dependencies/logger.lua",
    "dependencies/rednet_manager.lua",
    "dependencies/ui.lua",
    "dependencies/leaderboards/leaderboard.lua",
}

local function log(msg)
    print("[updater] " .. msg)
end

local function ensureDir(path)
    local dir = path:match("^(.*)/[^/]+$")
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
end

local function download(file)
    if fs.exists(file) then fs.delete(file) end
    ensureDir(file)
    return shell.run("wget", BASE_URL .. file, file)
end

-- UPDATE

log("Starting update...")

local failed = {}

for _, file in ipairs(FILES) do
    log("Fetching: " .. file)
    if not download(file) then
        log("FAILED: " .. file)
        table.insert(failed, file)
    end
end

if #failed > 0 then
    log("WARNING: " .. #failed .. " file(s) failed:")
    for _, f in ipairs(failed) do
        log("  - " .. f)
    end
else
    log("All files updated.")
end

-- LAUNCH

log("Launching manager.lua...")
shell.run("manager.lua")