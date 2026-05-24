-- bootstrap/bootstrap_bank.lua
-- Run normally for full setup, or with --update for silent file refresh.

local BASE_URL    = "https://raw.githubusercontent.com/Kkkur/casino-craft/refs/heads/develop/"
local CONFIG_FILE = "bank_config.json"

local MACHINE_TYPES = {
    {
        id      = "server",
        label   = "Bank Server",
        files   = {
            "libraries/logger/logger.lua",
            "libraries/autocomplete.lua",
            "libraries/currencylib.lua",
            "bank/server/init.lua",
            "bank/server/ledger.lua",
            "bank/server/profiles.lua",
            "bank/server/vault.lua",
            "bank/server/rednet.lua",
            "bank/server/monitor.lua",
            "bank/server/cli.lua",
        },
        startup = "bank/server/init.lua",
        peripherals = {
            {
                label    = "Server monitor",
                versions = { "monitor" },
                key      = "monitorSide",
                optional = true,
            },
            {
                label    = "Wireless Modem",
                versions = { "modem" },
                key      = "modemSide",
                optional = false,
                filter   = function(name)
                    local m = peripheral.wrap(name)
                    return m and m.isWireless and m.isWireless()
                end,
            },
        },
        extraSetup = function(cfg, promptFn, printOk, printWarn, printInfo)
            term.setTextColor(colours.cyan)
            print("\nVault:")
            term.setTextColor(colours.white)

            printInfo("Available peripherals on network:")
            for _, n in ipairs(peripheral.getNames()) do
                printInfo("  " .. n .. " (" .. (peripheral.getType(n) or "?") .. ")")
            end

            local allNames = {}
            for _, n in ipairs(peripheral.getNames()) do allNames[n] = true end

            local vaultName = promptFn("Vault peripheral name (e.g. create:item_vault_0)", cfg.vaultPeripheral)
            if not vaultName or vaultName == "" then
                printWarn("No vault name entered.")
                return nil
            end
            if allNames[vaultName] then
                printOk("Vault found: " .. vaultName)
            else
                printWarn(vaultName .. " not visible on network right now. Saved anyway.")
            end
            cfg.vaultPeripheral = vaultName
            cfg.coinItem = promptFn("Coin item ID", cfg.coinItem or "createdeco:brass_coin")

            term.setTextColor(colours.cyan)
            print("\nSecurity:")
            term.setTextColor(colours.white)
            printInfo("The shared token must match on all machines. Leave blank to disable.")
            local token = promptFn("Shared secret token", cfg.token or "")
            cfg.token = (token and token ~= "") and token or nil
            if cfg.token then
                printOk("Token set.")
            else
                printWarn("No token. All whitelisted machines will be accepted.")
            end

            term.setTextColor(colours.cyan)
            print("\nInitial whitelist:")
            term.setTextColor(colours.white)
            printInfo("Whitelist is managed via the server CLI after startup.")
            printInfo("Commands: whitelist add <id>  /  whitelist list  /  whitelist remove <id>")
            printInfo("Enter comma-separated IDs to whitelist now, or leave blank.")
            local idsRaw = promptFn("Computer IDs (e.g. 12,45)", "")
            cfg.whitelist = cfg.whitelist or {}
            if idsRaw and idsRaw ~= "" then
                local seen = {}
                for _, v in ipairs(cfg.whitelist) do seen[v] = true end
                for part in idsRaw:gmatch("[^,]+") do
                    local id = tonumber(part:match("^%s*(.-)%s*$"))
                    if id and not seen[id] then
                        table.insert(cfg.whitelist, id)
                        seen[id] = true
                        printOk("Whitelisted ID: " .. id)
                    elseif id then
                        printWarn("ID " .. id .. " already in list, skipping.")
                    else
                        printWarn("Skipping invalid entry: '" .. part .. "'")
                    end
                end
            end
            printInfo("Total whitelisted IDs: " .. #cfg.whitelist)

            if cfg.monitorSide then
                cfg.monitorScale = tonumber(promptFn("Monitor text scale (0.5-1)", cfg.monitorScale or 0.5))
            end

            return cfg
        end,
    },
    {
        id      = "atm",
        label   = "ATM Terminal",
        files   = {
            "libraries/logger/logger.lua",
            "libraries/currencylib.lua",
            "libraries/bank/BankLib.lua",
            "bank/atm/init.lua",
            "bank/atm/ui.lua",
        },
        startup = "bank/atm/init.lua",
        peripherals = {
            {
                label    = "ATM monitor",
                versions = { "monitor" },
                key      = "monitorSide",
                optional = false,
            },
            {
                label    = "Player detector",
                versions = { "player_detector", "playerDetector" },
                key      = "playerDetector",
                optional = false,
            },
            {
                label    = "Wireless Modem",
                versions = { "modem" },
                key      = "modemSide",
                optional = false,
                filter   = function(name)
                    local m = peripheral.wrap(name)
                    return m and m.isWireless and m.isWireless()
                end,
            },
        },
        extraSetup = function(cfg, promptFn, printOk, printWarn, printInfo)
            term.setTextColor(colours.cyan)
            print("\nBank connection:")
            term.setTextColor(colours.white)
            printInfo("This machine's ID: " .. os.getComputerID())
            printInfo("Make sure this ID is whitelisted on the bank server.")
            cfg.protocol    = promptFn("Rednet protocol name", cfg.protocol    or "bank_protocol")
            cfg.hostname    = promptFn("Rednet hostname",      cfg.hostname    or "bank_server")
            cfg.bankTimeout = tonumber(promptFn("Request timeout (s)", cfg.bankTimeout or 3))

            local serverID = tonumber(promptFn("Bank server computer ID", cfg.serverID or ""))
            if not serverID then
                printWarn("No server ID entered. BankLib will fall back to rednet.lookup.")
            else
                cfg.serverID = serverID
                printOk("Server ID: " .. serverID)
            end

            term.setTextColor(colours.cyan)
            print("\nSecurity:")
            term.setTextColor(colours.white)
            printInfo("Must match the token set on the server.")
            local token = promptFn("Shared secret token", cfg.token or "")
            cfg.token = (token and token ~= "") and token or nil
            if cfg.token then printOk("Token set.") else printWarn("No token set.") end

            term.setTextColor(colours.cyan)
            print("\nPeripherals:")
            term.setTextColor(colours.white)
            printInfo("Available peripherals on network:")
            local allNames = {}
            for _, n in ipairs(peripheral.getNames()) do
                allNames[n] = true
                printInfo("  " .. n .. " (" .. (peripheral.getType(n) or "?") .. ")")
            end

            local vaultName = promptFn("Vault peripheral name (e.g. create:item_vault_0)", cfg.vaultPeripheral)
            if not vaultName or vaultName == "" then
                printWarn("No vault name entered.")
                return nil
            end
            if allNames[vaultName] then printOk("Vault found: " .. vaultName)
            else printWarn(vaultName .. " not visible on network right now. Saved anyway.") end
            cfg.vaultPeripheral = vaultName

            local barrelName = promptFn("Input barrel peripheral name (player deposits coins here)", cfg.inputBarrel)
            if not barrelName or barrelName == "" then
                printWarn("No input barrel name entered.")
                return nil
            end
            if allNames[barrelName] then printOk("Input barrel found: " .. barrelName)
            else printWarn(barrelName .. " not visible on network right now. Saved anyway.") end
            cfg.inputBarrel = barrelName

            cfg.coinItem     = promptFn("Coin item ID",                        cfg.coinItem     or "createdeco:brass_coin")
            cfg.monitorScale = tonumber(promptFn("Monitor text scale (0.5-2)", cfg.monitorScale or 1))
            cfg.playerRange  = tonumber(promptFn("Player detection range (blocks)", cfg.playerRange or 2))

            return cfg
        end,
    },
    {
        id      = "baltop",
        label   = "Baltop Display",
        files   = {
            "libraries/logger/logger.lua",
            "libraries/currencylib.lua",
            "libraries/bank/BankLib.lua",
            "bank/baltop/init.lua",
        },
        startup = "bank/baltop/init.lua",
        peripherals = {
            {
                label    = "Baltop monitor",
                versions = { "monitor" },
                key      = "monitorSide",
                optional = false,
            },
            {
                label    = "Wireless Modem",
                versions = { "modem" },
                key      = "modemSide",
                optional = false,
                filter   = function(name)
                    local m = peripheral.wrap(name)
                    return m and m.isWireless and m.isWireless()
                end,
            },
        },
        extraSetup = function(cfg, promptFn, printOk, printWarn, printInfo)
            term.setTextColor(colours.cyan)
            print("\nBank connection:")
            term.setTextColor(colours.white)
            printInfo("This machine's ID: " .. os.getComputerID())
            printInfo("Make sure this ID is whitelisted on the bank server.")
            cfg.protocol      = promptFn("Rednet protocol name",   cfg.protocol      or "bank_protocol")
            cfg.hostname      = promptFn("Rednet hostname",         cfg.hostname      or "bank_server")
            cfg.bankTimeout   = tonumber(promptFn("Request timeout (s)",   cfg.bankTimeout   or 3))
            cfg.baltopRefresh = tonumber(promptFn("Refresh interval (s)",  cfg.baltopRefresh or 5))

            local serverID = tonumber(promptFn("Bank server computer ID", cfg.serverID or ""))
            if not serverID then
                printWarn("No server ID entered. BankLib will fall back to rednet.lookup.")
            else
                cfg.serverID = serverID
                printOk("Server ID: " .. serverID)
            end

            term.setTextColor(colours.cyan)
            print("\nSecurity:")
            term.setTextColor(colours.white)
            printInfo("Must match the token set on the server.")
            local token = promptFn("Shared secret token", cfg.token or "")
            cfg.token = (token and token ~= "") and token or nil
            if cfg.token then printOk("Token set.") else printWarn("No token set.") end

            return cfg
        end,
    },
}

--  UI helpers 

local function clear()
    term.setBackgroundColor(colours.black)
    term.clear()
    term.setCursorPos(1, 1)
end

local function printColor(color, msg)
    term.setTextColor(color)
    print(msg)
    term.setTextColor(colours.white)
end

local function printOk(msg)   printColor(colours.lime,      "[OK]  " .. msg) end
local function printErr(msg)  printColor(colours.red,       "[ERR] " .. msg) end
local function printWarn(msg) printColor(colours.yellow,    "[!!!] " .. msg) end
local function printInfo(msg) printColor(colours.lightGrey, "      " .. msg) end

local function prompt(msg, default)
    term.setTextColor(colours.cyan)
    if default ~= nil then
        io.write(msg .. " [" .. tostring(default) .. "]: ")
    else
        io.write(msg .. ": ")
    end
    term.setTextColor(colours.white)
    local input = io.read()
    if input == nil or input == "" then return default end
    return input
end

local function header(mode)
    term.setTextColor(colours.yellow)
    print("================================")
    if mode == "update" then
        print("    BANK MACHINE UPDATER")
    else
        print("    BANK MACHINE BOOTSTRAP")
    end
    print("================================")
    term.setTextColor(colours.white)
end

--  Config 

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then return {} end
    local f = io.open(CONFIG_FILE, "r")
    if not f then return {} end
    local raw = f:read("*a")
    f:close()
    local ok, data = pcall(textutils.unserialiseJSON, raw)
    return (ok and type(data) == "table") and data or {}
end

local function saveConfig(cfg)
    local f = io.open(CONFIG_FILE, "w")
    if not f then printErr("Could not write " .. CONFIG_FILE); return false end
    f:write(textutils.serialiseJSON(cfg))
    f:close()
    return true
end

--  HTTP download 

local function downloadFile(filename, silent)
    local url = BASE_URL .. filename
    if not silent then io.write("  " .. filename .. "... ") end

    local ok, res = pcall(http.get, url)
    if not ok or not res then
        if not silent then printColor(colours.red, "FAILED (request error)") end
        return false, "request failed"
    end

    if res.getResponseCode and res.getResponseCode() ~= 200 then
        local code = res.getResponseCode()
        res.close()
        if not silent then printColor(colours.red, "FAILED (HTTP " .. code .. ")") end
        return false, "HTTP " .. code
    end

    local content = res.readAll()
    res.close()

    if not content or #content == 0 then
        if not silent then printColor(colours.red, "FAILED (empty)") end
        return false, "empty response"
    end

    local dir = fs.getDir(filename)
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    local f = io.open(filename, "w")
    if not f then
        if not silent then printColor(colours.red, "WRITE ERROR") end
        return false, "write error"
    end
    f:write(content)
    f:close()

    if not silent then
        term.setTextColor(colours.lime)
        print("OK (" .. #content .. " bytes)")
        term.setTextColor(colours.white)
    end
    return true
end

local function downloadAll(files, silent)
    if not silent then
        term.setTextColor(colours.cyan)
        print("\nDownloading " .. #files .. " file(s) from GitHub:")
        term.setTextColor(colours.white)
    end
    local failed = {}
    for _, filename in ipairs(files) do
        local ok, err = downloadFile(filename, silent)
        if not ok then failed[#failed + 1] = { file = filename, err = err } end
    end
    return failed
end

--  Peripheral detection 

local function findAllMatching(versions, filter)
    local found = {}
    local vset  = {}
    for _, v in ipairs(versions) do vset[v] = true end
    for _, name in ipairs(peripheral.getNames()) do
        if vset[peripheral.getType(name)] then
            if not filter or filter(name) then
                found[#found + 1] = { name = name, typeName = peripheral.getType(name) }
            end
        end
    end
    return found
end

local function detectPeripherals(machineType, savedCfg)
    term.setTextColor(colours.cyan)
    print("\nChecking peripherals...")
    term.setTextColor(colours.white)

    local result = {}

    for _, periph in ipairs(machineType.peripherals or {}) do
        local matches = findAllMatching(periph.versions, periph.filter)

        if #matches == 1 then
            result[periph.key] = matches[1].name
            printOk(periph.label .. ": " .. matches[1].name)

        elseif #matches > 1 then
            printWarn("Multiple " .. periph.label .. " found:")
            for i, m in ipairs(matches) do
                printInfo("[" .. i .. "] " .. m.name .. " (" .. m.typeName .. ")")
            end
            local defaultIdx = 1
            if savedCfg[periph.key] then
                for i, m in ipairs(matches) do
                    if m.name == savedCfg[periph.key] then defaultIdx = i; break end
                end
            end
            local choice = tonumber(prompt("Which " .. periph.label .. " to use?", defaultIdx))
            if choice and matches[choice] then
                result[periph.key] = matches[choice].name
                printOk(periph.label .. ": " .. matches[choice].name)
            else
                result[periph.key] = matches[1].name
                printWarn("Invalid choice, using: " .. matches[1].name)
            end

        else
            if periph.optional then
                printWarn(periph.label .. " not found (optional, skipping).")
                result[periph.key] = nil
            else
                printErr(periph.label .. " not found! (required)")
                printErr("Tried types: " .. table.concat(periph.versions, ", "))
                return nil
            end
        end
    end

    return result
end

--  Machine type selection 

local function selectMachineType(savedId)
    if savedId then
        for _, mt in ipairs(MACHINE_TYPES) do
            if mt.id == savedId then
                local ans = prompt("Saved machine type: " .. mt.label .. " — use this? [Y/n]", "y")
                if ans:lower() ~= "n" then return mt end
                break
            end
        end
    end

    term.setTextColor(colours.cyan)
    print("\nSelect machine type:")
    term.setTextColor(colours.white)
    for i, mt in ipairs(MACHINE_TYPES) do
        print("  [" .. i .. "] " .. mt.label)
    end
    local n = tonumber(prompt("Choice"))
    if not n or not MACHINE_TYPES[n] then
        printErr("Invalid choice.")
        return nil
    end
    return MACHINE_TYPES[n]
end

--  Startup shim 

local function writeStartup(startupFile)
    local f = io.open("startup.lua", "w")
    if not f then printErr("Could not write startup.lua!"); return false end
    f:write('shell.run("bootstrap_bank.lua", "--update")\n')
    f:write('shell.run("' .. startupFile .. '")\n')
    f:close()
    printOk("startup.lua written.")
    return true
end

--  UPDATE MODE 
-- Called automatically by startup.lua on every boot.
-- Silently re-downloads all files, then exits so startup continues.

local function runUpdate()
    local cfg = loadConfig()
    if not cfg.machineType then return end

    local machineType
    for _, mt in ipairs(MACHINE_TYPES) do
        if mt.id == cfg.machineType then machineType = mt; break end
    end
    if not machineType then return end

    term.setTextColor(colours.yellow)
    print("[Updater] Checking for updates...")
    term.setTextColor(colours.white)

    local failed = downloadAll(machineType.files, false)

    if #failed == 0 then
        term.setTextColor(colours.lime)
        print("[Updater] All files up to date.")
        term.setTextColor(colours.white)
    else
        term.setTextColor(colours.red)
        print("[Updater] " .. #failed .. " file(s) failed to update:")
        term.setTextColor(colours.white)
        for _, f in ipairs(failed) do
            printInfo(f.file .. " (" .. f.err .. ")")
        end
        printWarn("Continuing with existing files.")
    end

    os.sleep(1)
end

--  FULL BOOTSTRAP MODE 

local function runBootstrap()
    local savedCfg = loadConfig()
    local isUpdate = (savedCfg.machineType ~= nil)

    clear()
    header(isUpdate and "update" or "bootstrap")

    if isUpdate then
        printInfo("Existing config found. This will update all files and re-detect peripherals.")
        printInfo("Press Enter to continue or Ctrl+T to abort.")
        io.read()
    end

    local machineType = selectMachineType(savedCfg.machineType)
    if not machineType then return end

    local periphCfg = detectPeripherals(machineType, savedCfg)
    if not periphCfg then
        printErr("Required peripheral(s) missing. Fix hardware and re-run.")
        return
    end

    for k, v in pairs(periphCfg) do savedCfg[k] = v end

    -- open the wireless modem for rednet if detected
    if savedCfg.modemSide then
        rednet.open(savedCfg.modemSide)
        printOk("Wireless modem opened on: " .. savedCfg.modemSide)
    end

    local cfg = machineType.extraSetup(savedCfg, prompt, printOk, printWarn, printInfo)
    if not cfg then
        printErr("Setup incomplete. Fix config and re-run.")
        return
    end

    local failed = downloadAll(machineType.files, false)
    if #failed > 0 then
        printErr("Failed to download " .. #failed .. " file(s):")
        for _, f in ipairs(failed) do printInfo(f.file .. " (" .. f.err .. ")") end
        printErr("Bootstrap incomplete. Fix connection and re-run.")
        return
    end
    printOk("All " .. #machineType.files .. " file(s) downloaded.")

    cfg.machineType = machineType.id
    if not saveConfig(cfg) then
        printErr("Could not save config, halting.")
        return
    end
    printOk("Config saved to " .. CONFIG_FILE)

    if not writeStartup(machineType.startup) then return end

    term.setTextColor(colours.yellow)
    print("\n================================")
    print(isUpdate and "  Update complete!" or "  Bootstrap complete!")
    print("  Computer ID: " .. os.getComputerID())
    print("  Rebooting in 3 seconds...")
    print("================================")
    term.setTextColor(colours.white)
    os.sleep(3)
    os.reboot()
end

--  Entry point 

local args = { ... }
if args[1] == "--update" then
    runUpdate()
else
    runBootstrap()
end