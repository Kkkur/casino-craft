-- bank/server/cli.lua
-- Admin CLI for the bank server.
-- All output goes through rawOut so it appears without level/tag noise.
-- Tab completion uses libraries/autocomplete.lua with the bank profile.
-- Terminate signal exits CLI cleanly; init.lua keeps rednet/monitor alive.

local cli = {}

local _rednet   = nil
local _vault    = nil
local _profiles = nil
local _ledger   = nil
local _log      = nil
local _ac       = nil   -- autocomplete module, loaded lazily in init

local _cfgFile  = "bank_config.json"
local _PROMPT   = "server> "
local _promptActive = false
local _history  = {}

-- ── Output ────────────────────────────────────────────────────────────────────

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
        term.write(_PROMPT)
    end
end

local function ok(msg)   rawOut("[OK]  " .. msg, colours.lime)      end
local function warn(msg) rawOut("[!!!] " .. msg, colours.yellow)    end
local function err(msg)  rawOut("[ERR] " .. msg, colours.red)       end
local function info(msg) rawOut("      " .. msg, colours.lightGrey) end

-- ── Player name normalisation ─────────────────────────────────────────────────

local function norm(player)
    return player and player:lower() or player
end

-- ── Config helpers ────────────────────────────────────────────────────────────

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

-- ── Commands ──────────────────────────────────────────────────────────────────

local commands = {}

commands["help"] = {
    desc = "Show this help",
    run  = function(_args)
        local names = {}
        for k in pairs(commands) do table.insert(names, k) end
        table.sort(names)
        info("=== Bank Server CLI ===")
        for _, name in ipairs(names) do
            info(string.format("  %-26s %s", name, commands[name].desc))
        end
    end,
}

-- whitelist

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

-- balance / give / take / set

commands["balance"] = {
    desc = "Show a player's balance  (alias: bal)",
    run  = function(args)
        local player = norm(args[1])
        if not player then err("Usage: balance <player>"); return end
        local bal = _profiles.getBalance(player)
        ok(player .. " -> " .. tostring(bal) .. " coins")
    end,
}
commands["bal"] = commands["balance"]

commands["give"] = {
    desc = "Add coins to a player's balance",
    run  = function(args)
        local player = norm(args[1])
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
        local player = norm(args[1])
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
        local player = norm(args[1])
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

-- account management

commands["account add"] = {
    desc = "Create a player account with zero balance",
    run  = function(args)
        local player = norm(args[1])
        if not player then err("Usage: account add <player>"); return end
        _profiles.get(player)   -- creates if absent
        ok("Account created: " .. player)
    end,
}

commands["account remove"] = {
    desc = "Delete a player account permanently",
    run  = function(args)
        local player = norm(args[1])
        if not player then err("Usage: account remove <player>"); return end
        local bal = _profiles.getBalance(player)
        if bal > 0 then
            warn("Player has " .. bal .. " coins. Use 'account remove " .. player .. " confirm' to force.")
            if norm(args[2]) ~= "confirm" then return end
        end
        local success, reason = _profiles.delete(player)
        if success then
            _ledger.record(player, "admin_delete", nil, bal, nil)
            ok("Account deleted: " .. player)
        else
            err("Delete failed: " .. tostring(reason))
        end
    end,
}

commands["account list"] = {
    desc = "List all player accounts",
    run  = function(_args)
        local names = _profiles.list()
        if #names == 0 then warn("No accounts found."); return end
        info("Accounts (" .. #names .. "):")
        for _, name in ipairs(names) do
            local bal = _profiles.getBalance(name)
            info(string.format("  %-20s %d coins", name, bal))
        end
    end,
}

commands["account flush"] = {
    desc = "Delete ALL player accounts (irreversible)",
    run  = function(args)
        if norm(args[1]) ~= "confirm" then
            warn("This will wipe every account. Type: account flush confirm")
            return
        end
        local count = _profiles.flush()
        _ledger.record("SERVER", "admin_flush", nil, nil, nil)
        ok("Flushed " .. count .. " accounts.")
    end,
}

-- leaderboard

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

-- vault

commands["vault"] = {
    desc = "Show vault coin count and free space",
    run  = function(_args)
        local coins = _vault.coinCount()
        local free  = _vault.freeSpace()
        ok("Vault coins: " .. coins)
        ok("Vault free:  " .. free .. " slots")
    end,
}

-- reconcile

commands["reconcile"] = {
    desc = "Run a reconciliation check",
    run  = function(_args)
        local sum            = _profiles.sumAll()
        local float          = _rednet.getGameFloat()
        local ok2, exp, act  = _vault.reconcile(sum, float)
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
    desc = "Reset game float to 0 (or a given value)",
    run  = function(args)
        local old   = _rednet.getGameFloat()
        local value = tonumber(args[1]) or 0
        _rednet.resetGameFloat(value)
        _ledger.recordSecurity("RECONCILE_RESET",
            "gameFloat " .. old .. " -> " .. value .. " by admin")
        ok("Game float reset: " .. old .. " -> " .. value)
    end,
}

-- security alerts

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

-- misc

commands["id"] = {
    desc = "Show this computer's ID",
    run  = function(_args)
        ok("Computer ID: " .. os.getComputerID())
    end,
}

-- ── Autocomplete profile ──────────────────────────────────────────────────────

local function buildACProfile()
    local cmdNames = {}
    for k in pairs(commands) do table.insert(cmdNames, k) end

    -- player name resolver: reads profiles list
    local function playerNames(_argIndex)
        local ok2, names = pcall(function() return _profiles.list() end)
        return ok2 and names or {}
    end

    -- commands that take a player name as their first argument
    local playerCmds = {
        "balance", "bal", "give", "take", "set",
        "account add", "account remove",
    }
    local resolvers = {}
    for _, cmd in ipairs(playerCmds) do
        resolvers[cmd] = playerNames
    end

    return { commands = cmdNames, resolvers = resolvers }
end

-- ── Readline ──────────────────────────────────────────────────────────────────

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

            elseif p1 == keys.tab then
                if _ac then
                    local input     = table.concat(buf)
                    local completed = _ac.complete(input)
                    if completed ~= input then
                        -- redraw the input line with the completed text
                        local _, cy = term.getCursorPos()
                        term.setCursorPos(#_PROMPT + 1, cy)
                        term.write(string.rep(" ", #buf))
                        term.setCursorPos(#_PROMPT + 1, cy)
                        buf = {}
                        for ch in completed:gmatch(".") do
                            table.insert(buf, ch)
                        end
                        term.write(completed)
                    end
                end

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

-- ── Dispatch ──────────────────────────────────────────────────────────────────

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

-- ── Public API ────────────────────────────────────────────────────────────────

function cli.init(rednetHandler, vaultMod, profilesMod, ledgerMod, logger)
    _rednet   = rednetHandler
    _vault    = vaultMod
    _profiles = profilesMod
    _ledger   = ledgerMod
    _log      = logger

    -- load autocomplete; soft-fail so CLI still works if file is absent
    local ok2, ac = pcall(dofile, "/libraries/autocomplete.lua")
    if ok2 and ac then
        _ac = ac
        _ac.init(buildACProfile())
    end
end

function cli.run()
    if _log then _log.info("CLI ready. Type 'help' for commands. Tab to autocomplete.") end

    while true do
        local line = readline()
        if not line then
            -- terminate received: exit cleanly, let init.lua keep the server alive
            if _log then _log.info("CLI terminated.") end
            return
        end
        if dispatch(line) == "exit" then
            return
        end
    end
end

return cli