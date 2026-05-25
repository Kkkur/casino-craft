-- blackjack/bj_startup.lua
-- Boot script for blackjack machines.

local CONFIG_FILE = "machine_config.txt"

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then return nil end
    local f = io.open(CONFIG_FILE, "r")
    if not f then return nil end
    local cfg = {}
    for line in f:lines() do
        local k, v = line:match("^(.-)=(.+)$")
        if k then cfg[k] = tonumber(v) or v end
    end
    f:close()
    return cfg
end

--  Boot 

term.setBackgroundColor(colours.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colours.yellow)
print("=== BLACKJACK MACHINE BOOT ===")
term.setTextColor(colours.white)

local cfg = loadConfig()
if not cfg or not cfg.gameType then
    term.setTextColor(colours.red)
    print("ERROR: No config found.")
    print("Run bootstrap.lua to set up this machine.")
    return
end

term.setTextColor(colours.lime)
print("Config OK — launching...")
os.sleep(1)

shell.run("games/blackjack/bj_machine.lua")