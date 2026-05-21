-- libraries/bank/BankLib.lua
--
-- SECURITY CONTRACT:
--   No machine may communicate with the bank server except through this library.
--   Every mutating transaction follows: ping → request → await confirmation.
--   If any step fails, the function returns nil + error string. Callers MUST
--   check the return value and must NOT move physical coins unless this lib
--   returns ok=true.

local bank = {}

-- ── config ────────────────────────────────────────────────────────────────────

local PROTOCOL   = "bank_protocol"
local HOSTNAME   = "bank_server_1"   -- must match rednet.lua HOSTNAME
local PING_TIMEOUT  = 3   -- seconds to wait for ping reply
local TX_TIMEOUT    = 5   -- seconds to wait for transaction confirmation

local _token      = nil
local _protocol   = PROTOCOL
local _hostname   = HOSTNAME
local _serverID   = nil   -- explicit computer ID from config, preferred over lookup
local _pingTimeout  = PING_TIMEOUT
local _txTimeout    = TX_TIMEOUT
local _computerID = os.getComputerID()
local _log        = nil   -- optional logger injected via bank.setLogger()
local _ready      = false -- true after bank.connect() succeeds

-- ── internal helpers ──────────────────────────────────────────────────────────

local function log(level, msg)
    if _log and _log[level] then _log[level]("[BankLib] " .. msg)
    elseif level == "error" or level == "warn" then
        print("[BankLib:" .. level .. "] " .. msg)
    end
end

local function loadConfig()
    if not fs.exists("bank_config.json") then return end
    local f = fs.open("bank_config.json", "r")
    if not f then return end
    local data = textutils.unserialiseJSON(f.readAll())
    f.close()
    if not data then return end
    if data.token       then _token       = data.token               end
    if data.protocol    then _protocol    = data.protocol            end
    if data.hostname    then _hostname    = data.hostname            end
    if data.serverID    then _serverID    = data.serverID            end
    if data.bankTimeout then _pingTimeout = data.bankTimeout
                             _txTimeout  = data.bankTimeout + 2      end
end

-- djb2 checksum over action+amount+timestamp – tamper sanity check
local function checksum(action, amount, ts)
    local s = tostring(action) .. tostring(amount or "") .. tostring(ts)
    local h = 5381
    for i = 1, #s do
        h = ((h * 33) + string.byte(s, i)) % 2147483648
    end
    return h
end

-- resolve server ID: prefer explicit serverID from config, fall back to lookup
local function resolveServer()
    peripheral.find("modem", rednet.open)
    if _serverID then return _serverID end
    local id = rednet.lookup(_protocol, _hostname)
    if not id then
        log("warn", "Cannot resolve server '" .. _hostname .. "' on '" .. _protocol .. "'")
    end
    return id
end

-- raw send + timed receive. Returns reply table or nil.
local function sendAndWait(serverId, msg, timeout)
    local ts = os.epoch("utc")
    msg.computerID = _computerID
    msg.token      = _token
    msg.ts         = ts
    msg.checksum   = checksum(msg.action, msg.amount, ts)

    rednet.send(serverId, msg, _protocol)

    local timer = os.startTimer(timeout)
    while true do
        local ev, p1, p2 = os.pullEvent()
        if ev == "rednet_message" and p1 == serverId then
            os.cancelTimer(timer)
            return p2
        end
        if ev == "timer" and p1 == timer then
            return nil
        end
    end
end

-- ── public API ─────────────────────────────────────────────────────────────────

-- Inject a logger (same interface as libraries/logger/logger.lua)
function bank.setLogger(logger)
    _log = logger
end

-- Must be called once before any transaction.
-- Opens the modem, loads config, and pings the server.
-- Returns true, serverId   on success
-- Returns nil, "error msg" on failure
function bank.connect()
    loadConfig()
    peripheral.find("modem", rednet.open)

    local serverId = rednet.lookup(_protocol, _hostname)
    if not serverId then
        log("error", "connect: server not found")
        return nil, "server_not_found"
    end

    -- ping
    local reply = sendAndWait(serverId, { action = "ping" }, _pingTimeout)
    if not reply then
        log("error", "connect: ping timed out")
        return nil, "ping_timeout"
    end
    if not reply.ok then
        log("error", "connect: ping rejected – " .. tostring(reply.err))
        return nil, reply.err or "ping_rejected"
    end

    _ready = true
    log("info", "connect: server online, ID=" .. serverId)
    return true, serverId
end

-- Lightweight liveness check (non-blocking ping). Does NOT set _ready.
-- Returns true if server replies, false otherwise.
function bank.ping()
    local serverId = resolveServer()
    if not serverId then return false end
    local reply = sendAndWait(serverId, { action = "ping" }, _pingTimeout)
    return reply ~= nil and reply.ok == true
end

-- ── transaction helpers (internal) ───────────────────────────────────────────

-- Full ping → tx → confirm cycle.
-- Returns reply on confirmed ok, or nil + err string on any failure.
local function transaction(msg)
    if not _ready then
        log("warn", "transaction called before bank.connect()")
        -- attempt auto-connect
        local ok, e = bank.connect()
        if not ok then return nil, e end
    end

    local serverId = resolveServer()
    if not serverId then return nil, "server_not_found" end

    -- step 1: ping
    local pingReply = sendAndWait(serverId, { action = "ping" }, _pingTimeout)
    if not pingReply or not pingReply.ok then
        log("warn", "transaction: ping failed before " .. tostring(msg.action))
        return nil, "server_unreachable"
    end

    -- step 2: send transaction, await confirmation
    local reply = sendAndWait(serverId, msg, _txTimeout)
    if reply == nil then
        log("error", "transaction: no confirmation for " .. tostring(msg.action)
            .. " player=" .. tostring(msg.player))
        return nil, "no_confirmation"
    end

    -- step 3: check server confirmed ok
    if not reply.ok then
        log("warn", "transaction: server rejected " .. tostring(msg.action)
            .. " err=" .. tostring(reply.err))
        return nil, reply.err or "rejected"
    end

    log("info", "transaction ok: " .. tostring(msg.action)
        .. " player=" .. tostring(msg.player)
        .. " amount=" .. tostring(msg.amount))
    return reply
end

-- ── public transaction API ────────────────────────────────────────────────────

-- Returns balance (number) or nil, errString
function bank.getBalance(player)
    local serverId = resolveServer()
    if not serverId then return nil, "server_not_found" end
    -- reads are lightweight: single request, no ping gate needed
    local reply = sendAndWait(serverId, { action = "get", player = player }, _txTimeout)
    if not reply        then return nil, "timeout"              end
    if not reply.ok     then return nil, reply.err or "error"   end
    return reply.balance
end

-- Adds coins to player's ledger. Physical coins must already be in the vault.
-- Returns newBalance (number) or nil, errString
function bank.add(player, amount)
    local reply, err = transaction({ action = "add", player = player, amount = amount })
    if not reply then return nil, err end
    return reply.balance
end

-- Removes coins from player's ledger. Caller must move physical coins ONLY after this returns ok.
-- Returns newBalance (number) or nil, errString
function bank.remove(player, amount)
    local reply, err = transaction({ action = "remove", player = player, amount = amount })
    if not reply then return nil, err end
    return reply.balance
end

-- Sets a player's balance directly (admin use).
-- Returns newBalance or nil, errString
function bank.set(player, amount)
    local reply, err = transaction({ action = "set", player = player, amount = amount })
    if not reply then return nil, err end
    return reply.balance
end

-- Returns list of {player, balance} or empty table, errString
function bank.top(limit)
    local serverId = resolveServer()
    if not serverId then return {}, "server_not_found" end
    local reply = sendAndWait(serverId, { action = "top", limit = limit or 10 }, _txTimeout)
    if not reply    then return {}, "timeout"            end
    if not reply.ok then return {}, reply.err or "error" end
    return reply.top
end

return bank