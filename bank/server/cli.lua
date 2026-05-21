-- bank/server/cli.lua
-- Admin command-line interface (runs on the computer terminal, not the monitor)

local cli = {}

local _rednet  = nil
local _vault   = nil
local _profiles= nil
local _ledger  = nil
local _log     = nil
local _cfg     = nil
local _cfgFile = "bank_config.json"

-- ── helpers ───────────────────────────────────────────────────────────────────

local function print(...)
    _G.print(...)   -- explicit global so shadowing this file's local doesn't matter
end

local COL = {
    reset  = "\27[0m",
    bold   = "\27[1m",
    green  = "\27[32m",
    yellow = "\27[33m",
    red    = "\27[31m",
    cyan   = "\27[36m",
    grey   = "\27[90m",
}

local function c(colour, text)
    return colour .. text .. COL.reset
end

local function ok(msg)   _G.print(c(COL.green,  "[OK] ") .. msg) end
local function warn(msg) _G.print(c(COL.yellow, "[WARN] ") .. msg) end
local function err(msg)  _G.print(c(COL.red,    "[ERR] ") .. msg) end
local function info(msg) _G.print(c(COL.cyan,   "  ") .. msg) end

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

-- ── command handlers ──────────────────────────────────────────────────────────

local commands = {}

-- help
commands["help"] = {
    desc = "Show this help",
    usage = "help",
    run = function(_args)
        _G.print(c(COL.bold, "\n=== Bank Server CLI ==="))
        local names = {}
        for k in pairs(commands) do table.insert(names, k) end
        table.sort(names)
        for _, name in ipairs(names) do
            local cmd = commands[name]
            _G.print(string.format("  %-22s %s", c(COL.cyan, name), cmd.desc))
        end
        _G.print("")
    end,
}

-- whitelist add <id>
commands["whitelist add"] = {
    desc  = "Add a computer ID to the whitelist",
    usage = "whitelist add <computerID>",
    run = function(args)
        local id = tonumber(args[1])
        if not id then err("Usage: whitelist add <computerID>") return end
        _rednet.addWhitelist(id)
        -- persist to config
        local cfg = loadCfg()
        if cfg then
            cfg.whitelist = cfg.whitelist or {}
            local found = false
            for _, v in ipairs(cfg.whitelist) do if v == id then found = true break end end
            if not found then table.insert(cfg.whitelist, id) end
            saveCfg(cfg)
        end
        ok("Computer ID " .. id .. " added to whitelist and saved to config.")
    end,
}

-- whitelist remove <id>
commands["whitelist remove"] = {
    desc  = "Remove a computer ID from the whitelist",
    usage = "whitelist remove <computerID>",
    run = function(args)
        local id = tonumber(args[1])
        if not id then err("Usage: whitelist remove <computerID>") return end
        _rednet.removeWhitelist(id)
        -- persist to config
        local cfg = loadCfg()
        if cfg and cfg.whitelist then
            local new = {}
            for _, v in ipairs(cfg.whitelist) do if v ~= id then table.insert(new, v) end end
            cfg.whitelist = new
            saveCfg(cfg)
        end
        ok("Computer ID " .. id .. " removed from whitelist and saved to config.")
    end,
}

-- whitelist list
commands["whitelist list"] = {
    desc  = "Show all whitelisted computer IDs",
    usage = "whitelist list",
    run = function(_args)
        local list = _rednet.getWhitelist()
        if #list == 0 then
            warn("Whitelist is empty.")
        else
            _G.print(c(COL.bold, "Whitelisted IDs (" .. #list .. "):"))
            table.sort(list)
            for _, id in ipairs(list) do
                info(tostring(id))
            end
        end
    end,
}

-- balance <player>
commands["balance"] = {
    desc  = "Show a player's balance",
    usage = "balance <player>",
    run = function(args)
        local player = args[1]
        if not player then err("Usage: balance <player>") return end
        local bal = _profiles.getBalance(player)
        ok(player .. " → " .. c(COL.yellow, tostring(bal)) .. " coins")
    end,
}

-- give <player> <amount>
commands["give"] = {
    desc  = "Add coins to a player's balance",
    usage = "give <player> <amount>",
    run = function(args)
        local player = args[1]
        local amount = tonumber(args[2])
        if not player or not amount or amount <= 0 then
            err("Usage: give <player> <amount>")
            return
        end
        local after = _profiles.add(player, amount)
        _ledger.record(player, "admin_give", amount, after - amount, after)
        ok("Gave " .. amount .. " coins to " .. player .. ". New balance: " .. after)
    end,
}

-- take <player> <amount>
commands["take"] = {
    desc  = "Remove coins from a player's balance",
    usage = "take <player> <amount>",
    run = function(args)
        local player = args[1]
        local amount = tonumber(args[2])
        if not player or not amount or amount <= 0 then
            err("Usage: take <player> <amount>")
            return
        end
        local before = _profiles.getBalance(player)
        local after, e = _profiles.remove(player, amount)
        if not after then
            err("Failed: " .. tostring(e) .. " (balance=" .. before .. ")")
        else
            _ledger.record(player, "admin_take", amount, before, after)
            ok("Took " .. amount .. " coins from " .. player .. ". New balance: " .. after)
        end
    end,
}

-- set <player> <amount>
commands["set"] = {
    desc  = "Set a player's balance to an exact amount",
    usage = "set <player> <amount>",
    run = function(args)
        local player = args[1]
        local amount = tonumber(args[2])
        if not player or not amount or amount < 0 then
            err("Usage: set <player> <amount>")
            return
        end
        local before = _profiles.getBalance(player)
        _profiles.setBalance(player, amount)
        _ledger.record(player, "admin_set", amount, before, amount)
        ok("Set " .. player .. "'s balance to " .. amount .. " (was " .. before .. ")")
    end,
}

-- top [limit]
commands["top"] = {
    desc  = "Show richest players",
    usage = "top [limit]",
    run = function(args)
        local limit = tonumber(args[1]) or 10
        local list  = _profiles.top(limit)
        if #list == 0 then warn("No profiles found.") return end
        _G.print(c(COL.bold, "Top " .. #list .. " players:"))
        for i, entry in ipairs(list) do
            _G.print(string.format("  %2d. %-20s %s coins",
                i,
                c(COL.cyan, entry.player),
                c(COL.yellow, tostring(entry.balance))))
        end
    end,
}

-- vault
commands["vault"] = {
    desc  = "Show vault coin count and free space",
    usage = "vault",
    run = function(_args)
        local coins = _vault.coinCount()
        local free  = _vault.freeSpace()
        ok("Vault coins : " .. c(COL.yellow, tostring(coins)))
        ok("Vault free  : " .. tostring(free) .. " slots")
    end,
}

-- reconcile
commands["reconcile"] = {
    desc  = "Run a balance reconciliation check",
    usage = "reconcile",
    run = function(_args)
        local sum        = _profiles.sumAll()
        local ok2, exp, act = _vault.reconcile(sum)
        if ok2 then
            ok("Reconcile OK. Vault=" .. act .. " Profiles=" .. exp)
        else
            err("MISMATCH! Vault=" .. act .. " Profiles=" .. exp .. " Delta=" .. (act - exp))
            _ledger.recordReconcile(exp, act)
        end
    end,
}

-- alerts
commands["alerts"] = {
    desc  = "Show recent security alerts",
    usage = "alerts",
    run = function(_args)
        local list = _rednet.getAlerts()
        if #list == 0 then
            ok("No alerts.")
        else
            _G.print(c(COL.bold, "Security Alerts (" .. #list .. "):"))
            for _, a in ipairs(list) do
                local t = math.floor(a.ts / 1000)
                _G.print("  " .. c(COL.grey, "[" .. t .. "]") .. " " .. c(COL.red, a.msg))
            end
        end
    end,
}

-- alerts clear
commands["alerts clear"] = {
    desc  = "Clear all security alerts",
    usage = "alerts clear",
    run = function(_args)
        _rednet.clearAlerts()
        ok("Alerts cleared.")
    end,
}

-- id
commands["id"] = {
    desc  = "Show this computer's ID",
    usage = "id",
    run = function(_args)
        ok("This computer's ID: " .. c(COL.bold, tostring(os.getComputerID())))
    end,
}

-- ── parallel-safe readline ────────────────────────────────────────────────────
--
-- _G.read() in CC suspends the entire coroutine scheduler until Enter is
-- pressed, which means log lines printed by rednet/monitor coroutines are
-- silently dropped or deferred.  This implementation rebuilds the line
-- char-by-char using os.pullEvent, so control yields back to the scheduler
-- between every keystroke.

local KEY_ENTER     = keys.enter
local KEY_BACKSPACE = keys.backspace
local KEY_UP        = keys.up
local KEY_DOWN      = keys.down

local _history = {}

local function readline(promptStr)
    _G.write(promptStr)
    local buf     = {}
    local histPos = #_history + 1   -- one past end = "current" slot

    while true do
        local ev, p1 = os.pullEvent()

        if ev == "char" then
            table.insert(buf, p1)
            _G.write(p1)

        elseif ev == "key" then
            if p1 == KEY_ENTER then
                _G.print("")
                local line = table.concat(buf)
                if line ~= "" then
                    table.insert(_history, line)
                end
                return line

            elseif p1 == KEY_BACKSPACE then
                if #buf > 0 then
                    table.remove(buf)
                    _G.write("\8 \8")
                end

            elseif p1 == KEY_UP then
                if histPos > 1 then
                    histPos = histPos - 1
                    local cur = table.concat(buf)
                    for _ = 1, #cur do _G.write("\8 \8") end
                    buf = {}
                    local entry = _history[histPos] or ""
                    for ch in entry:gmatch(".") do table.insert(buf, ch) end
                    _G.write(entry)
                end

            elseif p1 == KEY_DOWN then
                if histPos <= #_history then
                    histPos = histPos + 1
                    local cur = table.concat(buf)
                    for _ = 1, #cur do _G.write("\8 \8") end
                    buf = {}
                    local entry = _history[histPos] or ""
                    for ch in entry:gmatch(".") do table.insert(buf, ch) end
                    _G.write(entry)
                end
            end

        elseif ev == "terminate" then
            return nil
        end
    end
end

-- ── dispatch ──────────────────────────────────────────────────────────────────

local function dispatch(line)
    line = line:match("^%s*(.-)%s*$")   -- trim
    if line == "" then return end

    if line == "exit" or line == "quit" then
        warn("CLI closed. Server still running.")
        return "exit"
    end

    local first, rest     = line:match("^(%S+)%s*(.*)")
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
    local ok3, e = pcall(cmd.run, args)
    if not ok3 then err("Command error: " .. tostring(e)) end
end

-- ── public API ────────────────────────────────────────────────────────────────

function cli.init(rednetHandler, vaultMod, profilesMod, ledgerMod, logger)
    _rednet   = rednetHandler
    _vault    = vaultMod
    _profiles = profilesMod
    _ledger   = ledgerMod
    _log      = logger
end

function cli.run()
    _G.print(c(COL.bold .. COL.cyan, "\n[ Bank Server CLI ready — type 'help' for commands ]\n"))

    while true do
        local line = readline("server> ")
        if not line then
            -- terminate event — keep server running, just re-show prompt
        elseif dispatch(line) == "exit" then
            break
        end
    end
end

return cli