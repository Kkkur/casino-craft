-- bank/bootstrap.lua
-- Single bootstrap for all bank machines.
-- On first boot: pick machine type, detect peripherals, download files, save config, write startup.
-- On subsequent boots: re-runs setup to refresh files and update config.

local CONFIG_FILE = "bank_config.json"
local BASE_URL    = "https://raw.githubusercontent.com/Kkkur/casino-craft/refs/heads/dev/dziksonn/"

-- ── machine type definitions ──────────────────────────────────────────────────
-- Each type declares exactly what files it needs, what peripherals to detect,
-- what extra config to ask for, and what file to launch on startup.

local MACHINE_TYPES = {
    {
        id      = "server",
        label   = "Bank Server",
        files   = {
            "bank/server.lua",
            "lib/bank.lua",
        },
        startup = "bank/server.lua",
        peripherals = {
            {
                label    = "Baltop monitor",
                versions = { "monitor" },
                key      = "monitorSide",
                optional = true,
            },
        },
        extraSetup = function(cfg, prompt, printOk, printWarn)
            -- Network
            term.setTextColor(colours.cyan)
            print("\nNetwork / rednet:")
            term.setTextColor(colours.white)
            cfg.protocol    = prompt("Rednet protocol name", cfg.protocol    or "bank_protocol")
            cfg.hostname    = prompt("Rednet hostname",      cfg.hostname    or "bank_server")
            cfg.bankTimeout = tonumber(prompt("Request timeout (s)", cfg.bankTimeout or 3))

            -- Persistence
            term.setTextColor(colours.cyan)
            print("\nPersistence:")
            term.setTextColor(colours.white)
            cfg.saveFile = prompt("Balance save file", cfg.saveFile or "balances.json")

            -- Baltop refresh (only relevant if monitor was found)
            if cfg.monitorSide then
                cfg.baltopRefresh = tonumber(prompt("Baltop refresh interval (s)", cfg.baltopRefresh or 5))
            end

            return cfg
        end,
    },
    {
        id      = "atm",
        label   = "ATM Terminal",
        files   = {
            "bank/atm.lua",
            "lib/bank.lua",
        },
        startup = "bank/atm.lua",
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
        extraSetup = function(cfg, prompt, printOk, printWarn)
            -- Bank connection
            term.setTextColor(colours.cyan)
            print("\nBank connection:")
            term.setTextColor(colours.white)
            cfg.protocol    = prompt("Rednet protocol name", cfg.protocol    or "bank_protocol")
            cfg.hostname    = prompt("Rednet hostname",      cfg.hostname    or "bank_server")
            cfg.bankTimeout = tonumber(prompt("Request timeout (s)", cfg.bankTimeout or 3))

            -- Monitor scale
            cfg.monitorScale = tonumber(prompt("Monitor text scale (0.5-2)", cfg.monitorScale or 1))
            cfg.playerRange  = tonumber(prompt("Player detection range (blocks)", cfg.playerRange or 2))

            -- Barrels
            term.setTextColor(colours.cyan)
            print("\nBarrel configuration (wired network):")
            term.setTextColor(colours.white)

            local allNames = {}
            for _, n in ipairs(peripheral.getNames()) do allNames[n] = true end

            local savedInputNum = cfg.inputBarrel and tonumber(cfg.inputBarrel:match("(%d+)$"))
            local inputNum = tonumber(prompt("Input barrel number (player deposits, e.g. 3)", savedInputNum))
            if not inputNum then printWarn("Invalid number, skipping input barrel.") return nil end
            cfg.inputBarrel = "minecraft:barrel_" .. inputNum
            if allNames[cfg.inputBarrel] then printOk("Input barrel: " .. cfg.inputBarrel)
            else printWarn(cfg.inputBarrel .. " not visible on network right now.") end

            local savedStorageNum = cfg.storageBarrel and tonumber(cfg.storageBarrel:match("(%d+)$"))
            local storageNum = tonumber(prompt("Storage barrel number (vault, e.g. 4)", savedStorageNum))
            if not storageNum then printWarn("Invalid number, skipping storage barrel.") return nil end
            cfg.storageBarrel = "minecraft:barrel_" .. storageNum
            if allNames[cfg.storageBarrel] then printOk("Storage barrel: " .. cfg.storageBarrel)
            else printWarn(cfg.storageBarrel .. " not visible on network right now.") end

            cfg.coinItem = prompt("Coin item ID", cfg.coinItem or "createdeco:brass_coin")

            return cfg
        end,
    },
    {
        id      = "baltop",
        label   = "Baltop Display",
        files   = {
            "bank/server.lua",
            "lib/bank.lua",
        },
        startup = "bank/server.lua",
        peripherals = {
            {
                label    = "Baltop monitor",
                versions = { "monitor" },
                key      = "monitorSide",
                optional = false,
            },
        },
        extraSetup = function(cfg, prompt, printOk, printWarn)
            term.setTextColor(colours.cyan)
            print("\nBank connection:")
            term.setTextColor(colours.white)
            cfg.protocol      = prompt("Rednet protocol name",       cfg.protocol      or "bank_protocol")
            cfg.hostname      = prompt("Rednet hostname",            cfg.hostname      or "bank_server")
            cfg.bankTimeout   = tonumber(prompt("Request timeout (s)", cfg.bankTimeout or 3))
            cfg.baltopRefresh = tonumber(prompt("Refresh interval (s)", cfg.baltopRefresh or 5))
            return cfg
        end,
    },
}

-- ── UI helpers ────────────────────────────────────────────────────────────────

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
    term.setTextColor(colours.lime);   print("[OK]  " .. msg); term.setTextColor(colours.white)
end

local function printErr(msg)
    term.setTextColor(colours.red);    print("[ERR] " .. msg); term.setTextColor(colours.white)
end

local function printWarn(msg)
    term.setTextColor(colours.yellow); print("[!!!] " .. msg); term.setTextColor(colours.white)
end

local function printInfo(msg)
    term.setTextColor(colours.lightGrey); print("      " .. msg); term.setTextColor(colours.white)
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
    if input == "" then return default end
    return input
end

-- ── persistence ───────────────────────────────────────────────────────────────

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then return {} end
    local f = io.open(CONFIG_FILE, "r")
    if not f then return {} end
    local raw = f:read("*a"); f:close()
    local ok, data = pcall(textutils.unserialiseJSON, raw)
    return (ok and type(data) == "table") and data or {}
end

local function saveConfig(cfg)
    local f = io.open(CONFIG_FILE, "w")
    if not f then printErr("Could not write " .. CONFIG_FILE); return false end
    f:write(textutils.serialiseJSON(cfg)); f:close()
    return true
end

-- ── modem ─────────────────────────────────────────────────────────────────────

local function openModem()
    for _, side in ipairs({"top","bottom","left","right","front","back"}) do
        if peripheral.getType(side) == "modem" then
            local m = peripheral.wrap(side)
            if m and m.isWireless and m.isWireless() then
                rednet.open(side)
                printInfo("Modem opened on: " .. side)
                return true
            end
        end
    end
    printErr("No wireless modem found!")
    return false
end

-- ── machine type selection ────────────────────────────────────────────────────

local function selectMachineType(savedId)
    if savedId then
        for _, mt in ipairs(MACHINE_TYPES) do
            if mt.id == savedId then
                local ans = prompt("Saved machine type: " .. mt.label .. " — use this? [Y/n]", "y")
                if ans:lower() == "y" or ans == "" then return mt end
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

-- ── peripheral detection ──────────────────────────────────────────────────────

local function findAllMatching(versions)
    local found = {}
    local vset  = {}
    for _, v in ipairs(versions) do vset[v] = true end
    for _, name in ipairs(peripheral.getNames()) do
        if vset[peripheral.getType(name)] then
            found[#found+1] = { name = name, typeName = peripheral.getType(name) }
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
            -- Use saved side if still valid
            if savedCfg[periph.key] then
                for _, m in ipairs(matches) do
                    if m.name == savedCfg[periph.key] then
                        result[periph.key] = m.name
                        printOk(periph.label .. " (saved): " .. m.name)
                        goto continue
                    end
                end
            end
            -- Let user pick
            print("Multiple " .. periph.label .. " found:")
            for i, m in ipairs(matches) do print("  [" .. i .. "] " .. m.name) end
            local choice = tonumber(prompt("Choose " .. periph.label))
            if choice and matches[choice] then
                result[periph.key] = matches[choice].name
                printOk(periph.label .. ": " .. matches[choice].name)
            elseif periph.optional then
                printWarn(periph.label .. ": invalid choice, skipping (optional).")
            else
                printErr(periph.label .. ": invalid choice (required).")
                return nil
            end
            ::continue::

        else
            if periph.optional then
                printWarn(periph.label .. " not found (optional — skipping).")
                result[periph.key] = nil
            else
                printErr(periph.label .. " not found (required).")
                return nil
            end
        end
    end

    return result
end

-- ── download ──────────────────────────────────────────────────────────────────

local function downloadFile(remotePath, localPath)
    io.write("  " .. remotePath .. "... ")
    local url = BASE_URL .. remotePath .. "?t=" .. os.epoch("utc")
    local res = http.get(url, nil, true)
    if not res then print("FAILED"); return false end
    local content = res.readAll(); res.close()
    local dir = localPath:match("^(.*)/[^/]+$")
    if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local f = io.open(localPath, "w")
    if not f then print("WRITE ERROR"); return false end
    f:write(content); f:close()
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
        if not downloadFile(path, path) then failed[#failed+1] = path end
    end
    return failed
end

-- ── startup shim ──────────────────────────────────────────────────────────────

local function writeStartup(startupFile)
    local f = io.open("startup.lua", "w")
    if not f then printErr("Could not write startup.lua!"); return false end
    f:write('shell.run("' .. startupFile .. '")\n')
    f:close()
    printOk("startup.lua → " .. startupFile)
    return true
end

-- ── main ──────────────────────────────────────────────────────────────────────

local savedCfg = loadConfig()
local isUpdate = (savedCfg.machineType ~= nil)

if fs.exists(CONFIG_FILE) then fs.delete(CONFIG_FILE) end

clear()
header(isUpdate)

if isUpdate then
    printInfo("Existing config found. Re-running will update all files.")
    printInfo("Press Enter to continue or Ctrl+T to abort.")
    io.read()
end

-- Step 1: Machine type
local machineType = selectMachineType(savedCfg.machineType)
if not machineType then return end

-- Step 2: Open modem
if not openModem() then return end

-- Step 3: Detect peripherals
local periphCfg = detectPeripherals(machineType, savedCfg)
if not periphCfg then
    printErr("Required peripheral(s) missing. Fix hardware and re-run.")
    return
end

-- Merge peripheral results into savedCfg so extraSetup can see them
for k, v in pairs(periphCfg) do savedCfg[k] = v end

-- Step 4: Machine-specific questions
local cfg = machineType.extraSetup(savedCfg, prompt, printOk, printWarn)
if not cfg then
    printErr("Setup failed. Fix config and re-run.")
    return
end

-- Step 5: Download files
local failed = downloadAll(machineType.files)
if #failed > 0 then
    printErr("Failed to download:")
    for _, fname in ipairs(failed) do printInfo(fname) end
    printErr("Bootstrap incomplete. Fix connection and try again.")
    return
end
printOk("All " .. #machineType.files .. " file(s) downloaded.")

-- Step 6: Save config
cfg.machineType = machineType.id
if not saveConfig(cfg) then
    printErr("Could not save config, halting.")
    return
end
printOk("Config saved to " .. CONFIG_FILE)

-- Step 7: Write startup shim
writeStartup(machineType.startup)

-- Done
term.setTextColor(colours.yellow)
print("\n================================")
print(isUpdate and "  Update complete!" or "  Bootstrap complete!")
print("  Rebooting in 3 seconds...")
print("================================")
term.setTextColor(colours.white)
os.sleep(3)
os.reboot()