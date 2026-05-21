-- bootstrap/bootstrap_bank.lua

local CONFIG_FILE = "bank_config.json"
local BASE_URL    = "https://raw.githubusercontent.com/Kkkur/casino-craft/refs/heads/dev/dziksonn/"

local MACHINE_TYPES = {
    {
        id      = "server",
        label   = "Bank Server",
        files   = {
            "libraries/logger/logger.lua",
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
        },
        extraSetup = function(cfg, prompt, printOk, printWarn, printInfo)
            term.setTextColor(colours.cyan)
            print("\nVault:")
            term.setTextColor(colours.white)

            local allNames = {}
            for _, n in ipairs(peripheral.getNames()) do allNames[n] = true end

            printInfo("Available peripherals on network:")
            for _, n in ipairs(peripheral.getNames()) do
                printInfo("  " .. n .. " (" .. (peripheral.getType(n) or "?") .. ")")
            end

            local savedVault = cfg.vaultPeripheral
            local vaultName  = prompt("Vault peripheral name (e.g. create:item_vault_0)", savedVault)
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

            cfg.coinItem = prompt("Coin item ID", cfg.coinItem or "createdeco:brass_coin")

            term.setTextColor(colours.cyan)
            print("\nSecurity:")
            term.setTextColor(colours.white)
            printInfo("The shared token must be the same on all machines.")
            printInfo("Leave blank to disable token authentication.")
            local token = prompt("Shared secret token", cfg.token or "")
            cfg.token = (token and token ~= "") and token or nil
            if cfg.token then
                printOk("Token set.")
            else
                printWarn("No token set. All machines will be accepted if whitelisted.")
            end

            printInfo("Whitelist is managed via the CLI on the server computer after startup.")
            printInfo("Use: whitelist add <id>  /  whitelist list  /  whitelist remove <id>")
            printInfo("To find a machine's ID, run: print(os.getComputerID()) on that machine.")

            -- allow seeding initial IDs during bootstrap
            term.setTextColor(colours.cyan)
            print("\nInitial whitelist:")
            term.setTextColor(colours.white)
            printInfo("Enter comma-separated computer IDs to whitelist now, or leave blank.")
            local idsRaw = prompt("Computer IDs (e.g. 12,45)", "")
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
                cfg.monitorScale = tonumber(prompt("Monitor text scale (0.5-1)", cfg.monitorScale or 0.5))
            end

            return cfg
        end,
    },
    {
        id      = "atm",
        label   = "ATM Terminal",
        files   = {
            "libraries/logger/logger.lua",
            "bank/atm/init.lua",
            "bank/atm/ui.lua",
            "libraries/bank/BankLib.lua",
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
        },
        extraSetup = function(cfg, prompt, printOk, printWarn, printInfo)
            term.setTextColor(colours.cyan)
            print("\nBank connection:")
            term.setTextColor(colours.white)
            cfg.protocol    = prompt("Rednet protocol name", cfg.protocol    or "bank_protocol")
            cfg.hostname    = prompt("Rednet hostname",      cfg.hostname    or "bank_server")
            cfg.bankTimeout = tonumber(prompt("Request timeout (s)", cfg.bankTimeout or 3))

            term.setTextColor(colours.cyan)
            print("\nSecurity:")
            term.setTextColor(colours.white)
            printInfo("Must match the token set on the server.")
            local token = prompt("Shared secret token", cfg.token or "")
            cfg.token = (token and token ~= "") and token or nil
            if cfg.token then printOk("Token set.") else printWarn("No token set.") end

            term.setTextColor(colours.cyan)
            print("\nPeripherals:")
            term.setTextColor(colours.white)

            local allNames = {}
            for _, n in ipairs(peripheral.getNames()) do allNames[n] = true end

            printInfo("Available peripherals on network:")
            for _, n in ipairs(peripheral.getNames()) do
                printInfo("  " .. n .. " (" .. (peripheral.getType(n) or "?") .. ")")
            end

            local savedVault = cfg.vaultPeripheral
            local vaultName  = prompt("Vault peripheral name (e.g. create:item_vault_0)", savedVault)
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

            local savedBarrel = cfg.inputBarrel
            local barrelName  = prompt("Input barrel peripheral name (player deposits coins here)", savedBarrel)
            if not barrelName or barrelName == "" then
                printWarn("No input barrel name entered.")
                return nil
            end
            if allNames[barrelName] then
                printOk("Input barrel found: " .. barrelName)
            else
                printWarn(barrelName .. " not visible on network right now. Saved anyway.")
            end
            cfg.inputBarrel = barrelName

            cfg.coinItem     = prompt("Coin item ID",                    cfg.coinItem     or "createdeco:brass_coin")
            cfg.monitorScale = tonumber(prompt("Monitor text scale (0.5-2)", cfg.monitorScale or 1))
            cfg.playerRange  = tonumber(prompt("Player detection range (blocks)", cfg.playerRange or 2))

            return cfg
        end,
    },
    {
        id      = "baltop",
        label   = "Baltop Display",
        files   = {
            "libraries/logger/logger.lua",
            "bank/baltop/init.lua",
            "libraries/bank/BankLib.lua",
        },
        startup = "bank/baltop/init.lua",
        peripherals = {
            {
                label    = "Baltop monitor",
                versions = { "monitor" },
                key      = "monitorSide",
                optional = false,
            },
        },
        extraSetup = function(cfg, prompt, printOk, printWarn, printInfo)
            term.setTextColor(colours.cyan)
            print("\nBank connection:")
            term.setTextColor(colours.white)
            cfg.protocol      = prompt("Rednet protocol name", cfg.protocol      or "bank_protocol")
            cfg.hostname      = prompt("Rednet hostname",      cfg.hostname      or "bank_server")
            cfg.bankTimeout   = tonumber(prompt("Request timeout (s)", cfg.bankTimeout   or 3))
            cfg.baltopRefresh = tonumber(prompt("Refresh interval (s)", cfg.baltopRefresh or 5))

            term.setTextColor(colours.cyan)
            print("\nSecurity:")
            term.setTextColor(colours.white)
            printInfo("Must match the token set on the server.")
            local token = prompt("Shared secret token", cfg.token or "")
            cfg.token = (token and token ~= "") and token or nil
            if cfg.token then printOk("Token set.") else printWarn("No token set.") end

            return cfg
        end,
    },
}

local function clear()
    term.setBackgroundColor(colours.black)
    term.clear()
    term.setCursorPos(1, 1)
end

local function header(isUpdate)
    term.setTextColor(colours.yellow)
    print("================================")
    print(isUpdate and "    BANK MACHINE UPDATER" or "    BANK MACHINE BOOTSTRAP")
    print("================================")
    term.setTextColor(colours.white)
end

local function printOk(msg)
    term.setTextColor(colours.lime)
    print("[OK]  " .. msg)
    term.setTextColor(colours.white)
end

local function printErr(msg)
    term.setTextColor(colours.red)
    print("[ERR] " .. msg)
    term.setTextColor(colours.white)
end

local function printWarn(msg)
    term.setTextColor(colours.yellow)
    print("[!!!] " .. msg)
    term.setTextColor(colours.white)
end

local function printInfo(msg)
    term.setTextColor(colours.lightGrey)
    print("      " .. msg)
    term.setTextColor(colours.white)
end

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
    if not f then
        printErr("Could not write " .. CONFIG_FILE)
        return false
    end
    f:write(textutils.serialiseJSON(cfg))
    f:close()
    return true
end

local function openModem()
    for _, side in ipairs({ "top", "bottom", "left", "right", "front", "back" }) do
        if peripheral.getType(side) == "modem" then
            local m = peripheral.wrap(side)
            if m and m.isWireless and m.isWireless() then
                rednet.open(side)
                printInfo("Wireless modem opened on: " .. side)
                return true
            end
        end
    end
    printErr("No wireless modem found!")
    return false
end

local function selectMachineType(savedId)
    if savedId then
        for _, mt in ipairs(MACHINE_TYPES) do
            if mt.id == savedId then
                local ans = prompt("Saved machine type: " .. mt.label .. ". Use this?", "y")
                if ans:lower() == "y" then return mt end
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

local function findAllMatching(versions)
    local found = {}
    local vset  = {}
    for _, v in ipairs(versions) do vset[v] = true end
    for _, name in ipairs(peripheral.getNames()) do
        if vset[peripheral.getType(name)] then
            found[#found + 1] = { name = name, typeName = peripheral.getType(name) }
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
        local matches = findAllMatching(periph.versions)

        if #matches == 1 then
            result[periph.key] = matches[1].name
            printOk(periph.label .. ": " .. matches[1].name)

        elseif #matches > 1 then
            if savedCfg[periph.key] then
                for _, m in ipairs(matches) do
                    if m.name == savedCfg[periph.key] then
                        result[periph.key] = m.name
                        printOk(periph.label .. " (saved): " .. m.name)
                        goto continue
                    end
                end
            end
            print("Multiple " .. periph.label .. " found:")
            for i, m in ipairs(matches) do
                print("  [" .. i .. "] " .. m.name)
            end
            local choice = tonumber(prompt("Choose " .. periph.label))
            if choice and matches[choice] then
                result[periph.key] = matches[choice].name
                printOk(periph.label .. ": " .. matches[choice].name)
            elseif periph.optional then
                printWarn(periph.label .. ": skipping (optional).")
            else
                printErr(periph.label .. ": invalid choice (required).")
                return nil
            end
            ::continue::

        else
            if periph.optional then
                printWarn(periph.label .. " not found (optional, skipping).")
                result[periph.key] = nil
            else
                printErr(periph.label .. " not found (required).")
                return nil
            end
        end
    end

    return result
end

local function downloadFile(remotePath, localPath)
    io.write("  " .. remotePath .. "... ")
    local url = BASE_URL .. remotePath .. "?t=" .. os.epoch("utc")
    local res = http.get(url, nil, true)
    if not res then
        print("FAILED")
        return false
    end
    local content = res.readAll()
    res.close()
    local dir = localPath:match("^(.*)/[^/]+$")
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local f = io.open(localPath, "w")
    if not f then
        print("WRITE ERROR")
        return false
    end
    f:write(content)
    f:close()
    term.setTextColor(colours.lime)
    print("OK (" .. #content .. " bytes)")
    term.setTextColor(colours.white)
    return true
end

local function downloadAll(files)
    term.setTextColor(colours.cyan)
    print("\nDownloading " .. #files .. " file(s) from GitHub:")
    term.setTextColor(colours.white)
    local failed = {}
    for _, path in ipairs(files) do
        if not downloadFile(path, path) then
            failed[#failed + 1] = path
        end
    end
    return failed
end

local function writeStartup(startupFile)
    local f = io.open("startup.lua", "w")
    if not f then
        printErr("Could not write startup.lua!")
        return false
    end
    f:write('shell.run("' .. startupFile .. '")\n')
    f:close()
    printOk("startup.lua written, will run: " .. startupFile)
    return true
end

-- main

local savedCfg = loadConfig()
local isUpdate = (savedCfg.machineType ~= nil)

clear()
header(isUpdate)

if isUpdate then
    printInfo("Existing config found for machine type: " .. tostring(savedCfg.machineType))
    printInfo("Re-running will re-download all files and update config.")
    printInfo("Press Enter to continue or Ctrl+T to abort.")
    io.read()
end

local machineType = selectMachineType(savedCfg.machineType)
if not machineType then return end

if not openModem() then return end

-- ── server ID (first question for all non-server machines) ───────────────────

if machineType.id ~= "server" then
    term.setTextColor(colours.cyan)
    print("\nBank Server:")
    term.setTextColor(colours.white)
    printInfo("This computer's ID: " .. os.getComputerID())
    printInfo("Enter the computer ID of the bank server.")
    printInfo("You can find it by running: id   in the server CLI.")
    local serverID = tonumber(prompt("Bank server computer ID", savedCfg.serverID))
    if not serverID then
        printErr("Server ID is required. Fix and re-run.")
        return
    end
    savedCfg.serverID = serverID
    printOk("Server ID set to: " .. serverID)
end

local periphCfg = detectPeripherals(machineType, savedCfg)
if not periphCfg then
    printErr("Required peripheral(s) missing. Fix hardware and re-run.")
    return
end

for k, v in pairs(periphCfg) do savedCfg[k] = v end

local cfg = machineType.extraSetup(savedCfg, prompt, printOk, printWarn, printInfo)
if not cfg then
    printErr("Setup incomplete. Fix config and re-run.")
    return
end

term.setTextColor(colours.cyan)
print("\nDownloading files...")
term.setTextColor(colours.white)

local failed = downloadAll(machineType.files)
if #failed > 0 then
    printErr("Failed to download " .. #failed .. " file(s):")
    for _, fname in ipairs(failed) do printInfo(fname) end
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