-- blackjack/bj_startup.lua
-- Boot script for blackjack machines.

local REQUIRED_FILES = {
    -- Engine
    "blackjack/blackjack.lua",
    "blackjack/bj_machine.lua",
    -- Shared game libraries
    "libraries/games/UILib.lua",
    "libraries/games/CardsLib.lua",
    "libraries/games/ChipsLib.lua",
    -- Casino infrastructure
    "libraries/bank/BankLib.lua",
    "libraries/logger/logger.lua",
    "libraries/currencylib.lua",
}

local function exists(path)
    return fs.exists(path)
end

local function checkFiles()
    local missing = {}
    for _, f in ipairs(REQUIRED_FILES) do
        if not exists(f) then
            missing[#missing+1] = f
        end
    end
    return missing
end

local function readManagerId()
    if not exists("manager_id.txt") then return nil end
    local f = io.open("manager_id.txt", "r")
    if not f then return nil end
    local id = tonumber(f:read("*l"))
    f:close()
    return id
end

-- ─── Boot ─────────────────────────────────────────────────────────────────────

term.setBackgroundColor(colours.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colours.yellow)
print("=== BLACKJACK MACHINE BOOT ===")
term.setTextColor(colours.white)

-- Check manager ID
local managerId = readManagerId()
if not managerId then
    term.setTextColor(colours.red)
    print("ERROR: manager_id.txt not found or invalid.")
    print("Run bootstrap.lua first to set up this machine.")
    return
end
term.setTextColor(colours.lime)
print("Manager ID: " .. managerId)

-- Check required files
term.setTextColor(colours.white)
print("Checking files...")
local missing = checkFiles()
if #missing > 0 then
    term.setTextColor(colours.red)
    print("Missing files:")
    for _, f in ipairs(missing) do
        print("  - " .. f)
    end
    print("Re-run bootstrap.lua to download missing files.")
    return
end
term.setTextColor(colours.lime)
print("All files present.")

-- Brief pause then launch
term.setTextColor(colours.yellow)
print("Starting blackjack machine in 2 seconds...")
os.sleep(2)

shell.run("bj_machine.lua")