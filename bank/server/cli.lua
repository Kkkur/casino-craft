-- bank/server/cli.lua
-- Admin command-line interface (runs on the computer terminal, not the monitor)

local cli = {}

local _rednet   = nil
local _vault    = nil
local _profiles = nil
local _ledger   = nil
local _log      = nil
local _cfgFile  = "bank_config.json"

--  CC-native colour helpers 
-- CC terminals don't support ANSI codes; use term.setTextColor instead.

local function cprint(col, msg)
    term.setTextColor(col)
    _G.print(msg)
    term.setTextColor(colours.white)
end

local function ok(msg)   cprint(colours.lime,   "[OK] "   .. msg) end
local function warn(msg) cprint(colours.yellow,  "[WARN] " .. msg) end
local function err(msg)  cprint(colours.red,     "[ERR] "  .. msg) end
local function info(msg) cprint(colours.cyan,    "  "      .. msg) end

--  config helpers 

local function saveCfg(cfg)
    local f = fs.open(_cfgFile, "w")
    if not f then return false end
    f.write(textutils.serialiseJSON(cfg))
    f.close()
    return true
end

local function loadCfg()
    if not fs.exists(_cfgFile) then return nil end
    local f = fs.open(_cfgFile, "r")
    if not f then return nil end
    local data = textutils.unserialiseJSON(f.readAll())
    f.close()
    return data
end

--  command handlers 

local commands = {}

commands["help"] = {
    desc = "Show this help",
    usage = "help",
    run = function(_args)
        _G.print("")
        cprint(colours.yellow, "=== Bank Server CLI ===")
        local names = {}
        for k in pairs(commands) do table.insert(names, k) end
        table.sort(names)
        for _, name in ipairs(names) do
            local cmd = commands[name]
            term.setTextColor(colours.cyan)
            _G.write(string.format("  %-22s", name))
            term.setTextColor(colours.white)
            _G.print(cmd.desc)
        end
        _G.print("")
    end,
}

commands["whitelist add"] = {
    desc  = "Add a computer ID to the whitelist",
    usage = "whitelist add <computerID>",
    run = function(args)
        local id = tonumber(args[1])
        if not id then err("Usage: whitelist add <computerID>") return end
        _rednet.addWhitelist(id)
        local cfg = loadCfg()
        if cfg then
            cfg.whitelist = cfg.whitelist or {}
            local found = false
            for _, v in ipairs(cfg.whitelist) do if v == id then found = true break end end
            if not found then table.insert(cfg.whitelist, id) end
            saveCfg(cfg)
        end
        ok("Computer ID " .. id .. " added to whitelist and saved.")
    end,
}

commands["whitelist remove"] = {
    desc  = "Remove a computer ID from the whitelist",
    usage = "whitelist remove <computerID>",
    run = function(args)
        local id = tonumber(args[1])
        if not id then err("Usage: whitelist remove <computerID>") return end
        _rednet.removeWhitelist(id)
        local cfg = loadCfg()
        if cfg and cfg.whitelist then
            local new = {}
            for _, v in ipairs(cfg.whitelist) do if v ~= id then table.insert(new, v) end end
            cfg.whitelist = new
            saveCfg(cfg)
        end
        ok("Computer ID " .. id .. " removed from whitelist and saved.")
    end,
}

commands["whitelist list"] = {
    desc  = "Show all whitelisted computer IDs",
    usage = "whitelist list",
    run = function(_args)
        local list = _rednet.getWhitelist()
        if #list == 0 then
            warn("Whitelist is empty.")
        else
            cprint(colours.yellow, "Whitelisted IDs (" .. #list .. "):")
            table.sort(list)
            for _, id in ipairs(list) do info(tostring(id)) end
        end
    end,
}

commands["balance"] = {
    desc  = "Show a player's balance",
    usage = "balance <player>",
    run = function(args)
        local player = args[1]
        if not player then err("Usage: balance <player>") return end
        local bal = _profiles.getBalance(player)
        term.setTextColor(colours.lime)
        _G.write("[OK] ")
        term.setTextColor(colours.white)
        _G.write(player .. " -> ")
        term.setTextColor(colours.yellow)
        _G.print(tostring(bal) .. " coins")
        term.setTextColor(colours.white)
    end,
}

commands["give"] = {
    desc  = "Add coins to a player's balance",
    usage = "give <player> <amount>",
    run = function(args)
        local player = args[1]
        local amount = tonumber(args[2])
        if not player or not amount or amount <= 0 then
            err("Usage: give <player> <amount>") return
        end
        local after = _profiles.add(player, amount)
        _ledger.record(player, "admin_give", amount, after - amount, after)
        ok("Gave " .. amount .. " coins to " .. player .. ". Balance: " .. after)
    end,
}

commands["take"] = {
    desc  = "Remove coins from a player's balance",
    usage = "take <player> <amount>",
    run = function(args)
        local player = args[1]
        local amount = tonumber(args[2])
        if not player or not amount or amount <= 0 then
            err("Usage: take <player> <amount>") return
        end
        local before = _profiles.getBalance(player)
        local after, e = _profiles.remove(player, amount)
        if not after then
            err("Failed: " .. tostring(e) .. " (balance=" .. before .. ")")
        else
            _ledger.record(player, "admin_take", amount, before, after)
            ok("Took " .. amount .. " coins from " .. player .. ". Balance: " .. after)
        end
    end,
}

commands["set"] = {
    desc  = "Set a player's balance to an exact amount",
    usage = "set <player> <amount>",
    run = function(args)
        local player = args[1]
        local amount = tonumber(args[2])
        if not player or not amount or amount < 0 then
            err("Usage: set <player> <amount>") return
        end
        local before = _profiles.getBalance(player)
        _profiles.setBalance(player, amount)
        _ledger.record(player, "admin_set", amount, before, amount)
        ok("Set " .. player .. " balance to " .. amount .. " (was " .. before .. ")")
    end,
}

commands["top"] = {
    desc  = "Show richest players",
    usage = "top [limit]",
    run = function(args)
        local limit = tonumber(args[1]) or 10
        local list  = _profiles.top(limit)
        if #list == 0 then warn("No profiles found.") return end
        cprint(colours.yellow, "Top " .. #list .. " players:")
        for i, entry in ipairs(list) do
            term.setTextColor(colours.white)
            _G.write(string.format("  %2d. ", i))
            term.setTextColor(colours.cyan)
            _G.write(string.format("%-20s", entry.player))
            term.setTextColor(colours.yellow)
            _G.print(tostring(entry.balance) .. " coins")
        end
        term.setTextColor(colours.white)
    end,
}

commands["vault"] = {
    desc  = "Show vault coin count and free space",
    usage = "vault",
    run = function(_args)
        local coins = _vault.coinCount()
        local free  = _vault.freeSpace()
        ok("Vault coins : " .. coins)
        ok("Vault free  : " .. free .. " slots")
    end,
}

commands["reconcile"] = {
    desc  = "Run a balance reconciliation check",
    usage = "reconcile",
    run = function(_args)
        local sum           = _profiles.sumAll()
        local ok2, exp, act = _vault.reconcile(sum)
        if ok2 then
            ok("Reconcile OK. Vault=" .. act .. " Profiles=" .. exp)
        else
            err("MISMATCH! Vault=" .. act .. " Profiles=" .. exp .. " Delta=" .. (act - exp))
            _ledger.recordReconcile(exp, act)
        end
    end,
}

commands["alerts"] = {
    desc  = "Show recent security alerts",
    usage = "alerts",
    run = function(_args)
        local list = _rednet.getAlerts()
        if #list == 0 then
            ok("No alerts.")
        else
            cprint(colours.yellow, "Security Alerts (" .. #list .. "):")
            for _, a in ipairs(list) do
                local t = math.floor(a.ts / 1000)
                term.setTextColor(colours.lightGrey)
                _G.write("  [" .. t .. "] ")
                term.setTextColor(colours.red)
                _G.print(a.msg)
            end
            term.setTextColor(colours.white)
        end
    end,
}

commands["alerts clear"] = {
    desc  = "Clear all security alerts",
    usage = "alerts clear",
    run = function(_args)
        _rednet.clearAlerts()
        ok("Alerts cleared.")
    end,
}

commands["id"] = {
    desc  = "Show this computer's ID",
    usage = "id",
    run = function(_args)
        ok("This computer's ID: " .. os.getComputerID())
    end,
}

--  sticky prompt 
--
-- The last terminal row is reserved for "server> <input>".
-- We hook _G.print so that whenever the logger or any other coroutine prints,
-- we:  1) clear the prompt row  2) move cursor to row H-1  3) let the print
-- happen (which may scroll)  4) redraw the prompt on the new last row.
--
-- This works regardless of what term object other coroutines hold.

local PROMPT   = "server> "
local _buf     = {}
local _history = {}
local _origPrint = _G.print   -- save before hooking

local function termH() local _, h = term.getSize() return h end

local function clearPromptRow()
    local h = termH()
    term.setCursorPos(1, h)
    term.clearLine()
end

local function drawPrompt()
    local h = termH()
    term.setCursorPos(1, h)
    term.setTextColor(colours.white)
    term.write(PROMPT .. table.concat(_buf))
end

-- Hooked print: bounce output above the prompt row, then redraw
local function hookedPrint(...)
    clearPromptRow()
    local h = termH()
    term.setCursorPos(1, h - 1)
    _origPrint(...)
    drawPrompt()
end

local function installHook()   _G.print = hookedPrint  end
local function uninstallHook() _G.print = _origPrint   end

--  readline 

local KEY_ENTER     = keys.enter
local KEY_BACKSPACE = keys.backspace
local KEY_UP        = keys.up
local KEY_DOWN      = keys.down

local function readline()
    _buf = {}
    local histPos = #_history + 1

    clearPromptRow()
    drawPrompt()
    term.setCursorBlink(true)

    while true do
        local ev, p1 = os.pullEvent()

        if ev == "char" then
            table.insert(_buf, p1)
            drawPrompt()

        elseif ev == "key" then
            if p1 == KEY_ENTER then
                local line = table.concat(_buf)
                -- echo submitted command into scroll area
                clearPromptRow()
                local h = termH()
                term.setCursorPos(1, h - 1)
                term.setTextColor(colours.lightGrey)
                _origPrint(PROMPT .. line)
                term.setTextColor(colours.white)
                if line ~= "" then table.insert(_history, line) end
                term.setCursorBlink(false)
                return line

            elseif p1 == KEY_BACKSPACE then
                if #_buf > 0 then
                    table.remove(_buf)
                    -- clear trailing char then redraw
                    local h = termH()
                    term.setCursorPos(1, h)
                    term.clearLine()
                    drawPrompt()
                end

            elseif p1 == KEY_UP then
                if histPos > 1 then
                    histPos = histPos - 1
                    _buf = {}
                    for ch in (_history[histPos] or ""):gmatch(".") do
                        table.insert(_buf, ch)
                    end
                    clearPromptRow()
                    drawPrompt()
                end

            elseif p1 == KEY_DOWN then
                histPos = math.min(histPos + 1, #_history + 1)
                _buf = {}
                for ch in (_history[histPos] or ""):gmatch(".") do
                    table.insert(_buf, ch)
                end
                clearPromptRow()
                drawPrompt()
            end

        elseif ev == "term_resize" then
            clearPromptRow()
            drawPrompt()

        elseif ev == "terminate" then
            term.setCursorBlink(false)
            return nil
        end
    end
end

--  dispatch 

local function dispatch(line)
    line = line:match("^%s*(.-)%s*$")
    if line == "" then return end

    if line == "exit" or line == "quit" then
        warn("CLI closed. Server still running.")
        return "exit"
    end

    local first, rest      = line:match("^(%S+)%s*(.*)")
    local second, restrest = (rest or ""):match("^(%S+)%s*(.*)")
    local twoWord = first and second and (first .. " " .. second)
    local cmd, argStr

    if twoWord and commands[twoWord] then
        cmd    = commands[twoWord]
        argStr = restrest or ""
    elseif first and commands[first] then
        cmd    = commands[first]
        argStr = rest or ""
    else
        err("Unknown command: '" .. line .. "'  (try 'help')")
        return
    end

    local args = {}
    for token in argStr:gmatch("%S+") do table.insert(args, token) end
    local ok2, e = pcall(cmd.run, args)
    if not ok2 then err("Command error: " .. tostring(e)) end
end

--  public API 

function cli.init(rednetHandler, vaultMod, profilesMod, ledgerMod, logger)
    _rednet   = rednetHandler
    _vault    = vaultMod
    _profiles = profilesMod
    _ledger   = ledgerMod
    _log      = logger
end

function cli.run()
    installHook()

    _origPrint("")
    _origPrint("[ Bank Server CLI ready - type 'help' for commands ]")
    _origPrint("")

    while true do
        local line = readline()
        if not line then
            -- terminate signal — keep server running
        elseif dispatch(line) == "exit" then
            break
        end
    end

    uninstallHook()
end

return cli