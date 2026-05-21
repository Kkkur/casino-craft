-- bank/server/init.lua

local logger        = dofile("/libraries/logger/logger.lua")
logger.init("server", "bank/server/logs")

local vault         = dofile("/bank/server/vault.lua")
local ledger        = dofile("/bank/server/ledger.lua")
local profiles      = dofile("/bank/server/profiles.lua")
local rednetHandler = dofile("/bank/server/rednet.lua")
local monitorMod    = dofile("/bank/server/monitor.lua")
local cliMod        = dofile("/bank/server/cli.lua")

-- ── load config ───────────────────────────────────────────────────────────────

local CONFIG_FILE = "bank_config.json"

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then
        logger.error("Missing " .. CONFIG_FILE .. ", run bootstrap first")
        error("missing config")
    end
    local f = fs.open(CONFIG_FILE, "r")
    if not f then logger.error("Cannot open " .. CONFIG_FILE) error("cannot open config") end
    local data = textutils.unserialiseJSON(f.readAll())
    f.close()
    if not data then logger.error("Corrupt " .. CONFIG_FILE) error("corrupt config") end
    return data
end

local cfg = loadConfig()

-- ── validate required config fields ──────────────────────────────────────────

local function needCfg(key)
    if not cfg[key] then
        logger.error("Missing config key '" .. key .. "'")
        error("missing config key: " .. key)
    end
    return cfg[key]
end

local vaultPeripheral   = needCfg("vaultPeripheral")
local monitorPeripheral = cfg.monitorSide
local token             = cfg.token
local whitelist         = cfg.whitelist or {}
local coinItem          = cfg.coinItem or "createdeco:brass_coin"

-- ── init subsystems ───────────────────────────────────────────────────────────

logger.info("Initialising vault: " .. vaultPeripheral)
vault.init(vaultPeripheral, logger)

logger.info("Initialising security...")
monitorMod.setRednet(rednetHandler)
rednetHandler.init(token, whitelist, logger)

logger.info("Startup reconciliation...")
local sum            = profiles.sumAll()
local ok, exp, act   = vault.reconcile(sum, coinItem)
if not ok then
    ledger.recordReconcile(exp, act)
    logger.warn("Reconciliation MISMATCH on startup! expected=" .. exp .. " actual=" .. act)
else
    logger.info("Vault OK. Coins=" .. act)
end

ledger.record("SERVER", "startup", nil, nil, nil)
logger.info("Initialising CLI...")
cliMod.init(rednetHandler, vault, profiles, ledger, logger)

logger.info("Ready.")

-- ── parallel runners ──────────────────────────────────────────────────────────

local function runMonitor()
    if not monitorPeripheral then
        logger.warn("No monitor in config, skipping monitor.")
        while true do os.sleep(9999) end
    end
    monitorMod.init(monitorPeripheral, logger)
    monitorMod.run()
end

local function runRednet()
    rednetHandler.run()
end

local function runCLI()
    cliMod.run()
    -- if the user types 'exit', CLI closes but server keeps running
    while true do os.sleep(9999) end
end

parallel.waitForAll(runRednet, runMonitor, runCLI)