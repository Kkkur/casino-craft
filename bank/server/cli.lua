-- bank/server/cli.lua
-- Admin CLI. Output goes through logger.raw so it prints without level/tag prefix.
-- Prompt is cleared before any print and redrawn after to avoid double-prompt.

local cli = {}

local _rednet   = nil
local _vault    = nil
local _profiles = nil
local _ledger   = nil
local _log      = nil
local _cfgFile  = "bank_config.json"

local _PROMPT       = "server> "
local _promptActive = false   -- true while readline is waiting for input
local _history      = {}

-- ─── Output ───────────────────────────────────────────────────────────────────
-- Clears the prompt line, prints, then redraws the prompt.
-- This prevents double-prompt when logger or other coroutines print mid-input.

local function rawOut(msg, color)
    if _promptActive then
        local _, h = term.getSize()
        term.setCursorPos(1, h)
        term.clearLine()
    end
    term.setTextColor(color or colours.white)
    print(tostring(msg))
    term.setTextColor(colours.white)
    if _promptActive then
        term.setTextColor(colours.white)
        term.write(_PROMPT)
    end
end

local function ok(msg)   rawOut("[OK]  " .. msg, colours.lime)      end
local function warn(msg) rawOut("[!!!] " .. msg, colours.yellow)    end
local function err(msg)  rawOut("[ERR] " .. msg, colours.red)       end
local function info(msg) rawOut("      " .. msg, colours.lightGrey) end

-- ─── Config helpers ───────────────────────────────────────────────────────────

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

-- ─── Commands ─────────────────────────────────────────────────────────────────

local commands = {}

commands["help"] = {
    desc = "Show this help",
    run  = function(_args)
        local names = {}
        for k in pairs(commands) do table.insert(names, k) end
        table.sort(names)
        info("=== Bank Server CLI ===")
        for _, name in ipairs(names) do
            info(string.format("  %-24s %s", name, commands[name].desc))
        end
    end,
}

commands["whitelist add"] = {
    desc = "Add a computer ID to the whitelist",
    run  = function(args)
        local id = tonumber(args[1])
        if not id then err("Usage: whitelist add <id>"); return end
        _rednet.addWhitelist(id)
        local cfg = loadCfg()
        if cfg then
            cfg.whitelist = cfg.whitelist or {}
            local found = false
            for _, v in ipairs(cfg.whitelist) do if v == id then found = true; break end end
            if not found then table.insert(cfg.whitelist, id) end
            saveCfg(cfg)
        end
        ok("ID " .. id .. " added to whitelist.")
    end,
}

commands["whitelist remove"] = {
    desc = "Remove a computer ID from the whitelist",
    run  = function(args)
        local id = tonumber(args[1])
        if not id then err("Usage: whitelist remove <id>"); return end
        _rednet.removeWhitelist(id)
        local cfg = loadCfg()
        if cfg and cfg.whitelist then
            local new = {}
            for _, v in ipairs(cfg.whitelist) do if v ~= id then table.insert(new, v) end end
            cfg.whitelist = new
            saveCfg(cfg)
        end
        ok("ID " .. id .. " removed from whitelist.")
    end,
}

commands["whitelist list"] = {
    desc = "List all whitelisted computer IDs",
    run  = function(_args)
        local list = _rednet.getWhitelist()
        if #list == 0 then warn("Whitelist is empty."); return end
        table.sort(list)
        info("Whitelisted IDs (" .. #list .. "):")
        for _, id in ipairs(list) do info("  " .. tostring(id)) end
    end,
}

commands["balance"] = {
    desc = "Show a player's balance",
    run  = function(args)
        local player = args[1]
        if not player then err("Usage: balance <player>"); return end
        local bal = _profiles.getBalance(player)
        ok(player .. " -> " .. tostring(bal) .. " coins")
    end,
}

commands["give"] = {
    desc = "Add coins to a player's balance",
    run  = function(args)
        local player = args[1]
        local amount = tonumber(args[2])
        if not player or not amount or amount <= 0 then
            err("Usage: give <player> <amount>"); return
        end
        local after = _profiles.add(player, amount)
        _ledger.record(player, "admin_give", amount, after - amount, after)
        ok("Gave " .. amount .. " coins to " .. player .. ". Balance: " .. after)
    end,
}

commands["take"] = {
    desc = "Remove coins from a player's balance",
    run  = function(args)
        local player = args[1]
        local amount = tonumber(args[2])
        if not player or not amount or amount <= 0 then
            err("Usage: take <player> <amount>"); return
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
    desc = "Set a player's balance",
    run  = function(args)
        local player = args[1]
        local amount = tonumber(args[2])
        if not player or not amount or amount < 0 then
            err("Usage: set <player> <amount>"); return
        end
        local before = _profiles.getBalance(player)
        _profiles.setBalance(player, amount)
        _ledger.record(player, "admin_set", amount, before, amount)
        ok("Set " .. player .. " -> " .. amount .. " (was " .. before .. ")")
    end,
}

commands["top"] = {
    desc = "Show richest players",
    run  = function(args)
        local limit = tonumber(args[1]) or 10
        local list  = _profiles.top(limit)
        if #list == 0 then warn("No profiles found."); return end
        info("Top " .. #list .. " players:")
        for i, entry in ipairs(list) do
            info(string.format("  %2d. %-20s %d coins", i, entry.player, entry.balance))
        end
    end,
}

commands["vault"] = {
    desc = "Show vault coin count and free space",
    run  = function(_args)
        local coins = _vault.coinCount()
        local free  = _vault.freeSpace()
        ok("Vault coins: " .. coins)
        ok("Vault free:  " .. free .. " slots")
    end,
}

commands["reconcile"] = {
    desc = "Run a reconciliation check",
    run  = function(_args)
        local sum           = _profiles.sumAll()
        local float         = _rednet.getGameFloat()
        local ok2, exp, act = _vault.reconcile(sum, float)
        if ok2 then
            ok("Reconcile OK. vault=" .. act .. " profiles=" .. sum .. " gameFloat=" .. float)
        else
            err("MISMATCH! vault=" .. act .. " expected=" .. exp
                .. " delta=" .. (act - exp)
                .. " (profiles=" .. sum .. " gameFloat=" .. float .. ")")
            _ledger.recordReconcile(exp, act)
        end
    end,
}

commands["reconcile reset"] = {
    desc = "Reset game float (use after adding coins to vault)",
    run  = function(args)
        local old   = _rednet.getGameFloat()
        local value = tonumber(args[1]) or 0
        _rednet.resetGameFloat(value)
        _ledger.recordSecurity("RECONCILE_RESET",
            "gameFloat " .. old .. " -> " .. value .. " by admin")
        ok("Game float reset: " .. old .. " -> " .. value)
    end,
}

commands["alerts"] = {
    desc = "Show recent security alerts",
    run  = function(_args)
        local list = _rednet.getAlerts()
        if #list == 0 then ok("No alerts."); return end
        info("Security alerts (" .. #list .. "):")
        for _, a in ipairs(list) do
            local t = math.floor(a.ts / 1000)
            info("  [" .. t .. "] " .. a.msg)
        end
    end,
}

commands["alerts clear"] = {
    desc = "Clear all security alerts",
    run  = function(_args)
        _rednet.clearAlerts()
        ok("Alerts cleared.")
    end,
}

commands["id"] = {
    desc = "Show this computer's ID",
    run  = function(_args)
        ok("Computer ID: " .. os.getComputerID())
    end,
}

-- ─── Readline ─────────────────────────────────────────────────────────────────

local function readline()
    local buf     = {}
    local histPos = #_history + 1

    _promptActive = true
    term.setTextColor(colours.white)
    term.write(_PROMPT)
    term.setCursorBlink(true)

    while true do
        local ev, p1 = os.pullEvent()

        if ev == "char" then
            table.insert(buf, p1)
            term.write(p1)

        elseif ev == "key" then
            if p1 == keys.enter then
                _promptActive = false
                term.setCursorBlink(false)
                print("")
                local line = table.concat(buf)
                if line ~= "" then table.insert(_history, line) end
                return line

            elseif p1 == keys.backspace then
                if #buf > 0 then
                    table.remove(buf)
                    local cx, cy = term.getCursorPos()
                    term.setCursorPos(cx - 1, cy)
                    term.write(" ")
                    term.setCursorPos(cx - 1, cy)
                end

            elseif p1 == keys.up then
                if histPos > 1 then
                    histPos = histPos - 1
                    local _, cy = term.getCursorPos()
                    term.setCursorPos(#_PROMPT + 1, cy)
                    term.write(string.rep(" ", #buf))
                    term.setCursorPos(#_PROMPT + 1, cy)
                    buf = {}
                    for ch in (_history[histPos] or ""):gmatch(".") do
                        table.insert(buf, ch)
                    end
                    term.write(table.concat(buf))
                end

            elseif p1 == keys.down then
                histPos = math.min(histPos + 1, #_history + 1)
                local _, cy = term.getCursorPos()
                term.setCursorPos(#_PROMPT + 1, cy)
                term.write(string.rep(" ", #buf))
                term.setCursorPos(#_PROMPT + 1, cy)
                buf = {}
                for ch in (_history[histPos] or ""):gmatch(".") do
                    table.insert(buf, ch)
                end
                term.write(table.concat(buf))
            end

        elseif ev == "term_resize" then
            local _, h = term.getSize()
            term.setCursorPos(1, h)
            term.clearLine()
            term.write(_PROMPT .. table.concat(buf))

        elseif ev == "terminate" then
            _promptActive = false
            term.setCursorBlink(false)
            return nil
        end
    end
end

-- ─── Dispatch ─────────────────────────────────────────────────────────────────

local function dispatch(line)
    line = line:match("^%s*(.-)%s*$")
    if line == "" then return end

    if line == "exit" or line == "quit" then
        warn("CLI closed. Server still running.")
        return "exit"
    end

    local first, rest      = line:match("^(%S+)%s*(.*)")
    local second, restrest = (rest or ""):match("^(%S+)%s*(.*)")
    local twoWord          = first and second and (first .. " " .. second)
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

-- ─── Public API ───────────────────────────────────────────────────────────────

function cli.init(rednetHandler, vaultMod, profilesMod, ledgerMod, logger)
    _rednet   = rednetHandler
    _vault    = vaultMod
    _profiles = profilesMod
    _ledger   = ledgerMod
    _log      = logger
end

function cli.run()
    if _log then _log.info("CLI ready — type 'help' for commands") end

    while true do
        local line = readline()
        if not line then
            if _log then _log.info("CLI terminated.") end
            return
        end
        if dispatch(line) == "exit" then
            return
        end
    end
end

return cli