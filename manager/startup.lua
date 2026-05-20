-- startup.lua
-- Auto-updater

local BASE_URL = "https://raw.githubusercontent.com/Kkkur/casino-craft/refs/heads/feature/manager-autoupdater/manager/"

local FILES = {
    "startup.lua",
    "manager.lua",
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
    local current = ""
    for part in path:gmatch("[^/]+") do
        if current == "" then
            current = part
        else
            current = current .. "/" .. part
        end
        -- stop before the filename (no extension-less final segment check needed;
        -- we just won't mkdir the last segment which has a dot in it)
    end
    -- rebuild properly: only create up to the parent dir
    local dir = path:match("^(.*)/[^/]+$")
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
end

local function download(file)
    local url  = BASE_URL .. file
    local dest = file

    -- delete existing file
    if fs.exists(dest) then
        fs.delete(dest)
    end

    -- ensure parent directory exists
    ensureDir(dest)

    local ok = shell.run("wget", url, dest)
    return ok
end

-- MAIN UPDATE

log("Starting update...")

local failed = {}

for _, file in ipairs(FILES) do
    log("Fetching: " .. file)
    local ok = download(file)
    if not ok then
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