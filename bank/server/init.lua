-- bank/server/init.lua

local vault         = require("bank/server/vault")
local ledger        = require("bank/server/ledger")
local profiles      = require("bank/server/profiles")
local rednetHandler = require("bank/server/rednet")
local monitorMod    = require("bank/server/monitor")

-- load config 

local CONFIG_FILE = "bank_config.json"

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then
        error("bank server: missing " .. CONFIG_FILE .. ", run bootstrap first")
    end
    local f = fs.open(CONFIG_FILE, "r")
    if not f then error("bank server: cannot open " .. CONFIG_FILE) end
    local data = textutils.unserialiseJSON(f.readAll())
    f.close()
    if not data then error("bank server: corrupt " .. CONFIG_FILE) end
    return data
end

local cfg = loadConfig()

-- validate required config fields 

local function needCfg(key)
    if not cfg[key] then
        error("bank server: missing config key '" .. key .. "'")
    end
    return cfg[key]
end

local vaultPeripheral   = needCfg("vaultPeripheral")
local monitorPeripheral = cfg.monitorSide
local token             = cfg.token
local whitelist         = cfg.whitelist or {}
local coinItem          = cfg.coinItem or "createdeco:brass_coin"

-- init subsystems 

print("[server] Initialising vault...")
vault.init(vaultPeripheral)

print("[server] Initialising security...")
rednetHandler.init(token, whitelist)

print("[server] Startup reconciliation...")
local sum            = profiles.sumAll()
local ok, exp, act   = vault.reconcile(sum, coinItem)
if not ok then
    ledger.recordReconcile(exp, act)
    print("[server] WARNING: reconciliation mismatch on startup! expected=" .. exp .. " actual=" .. act)
else
    print("[server] Vault OK. Coins=" .. act)
end

ledger.record("SERVER", "startup", nil, nil, nil)
print("[server] Ready.")

-- parallel runners 

local function runMonitor()
    if not monitorPeripheral then
        print("[monitor] No monitor in config, skipping.")
        while true do os.sleep(9999) end
    end
    monitorMod.init(monitorPeripheral)
    monitorMod.run()
end

local function runRednet()
    rednetHandler.run()
end

parallel.waitForAll(runRednet, runMonitor)