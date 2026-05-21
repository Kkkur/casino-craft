-- libraries/bank/BankLib.lua

local bank = {}

local PROTOCOL     = "bank_protocol"
local HOSTNAME     = "bank_server"
local TIMEOUT      = 3

-- loaded from bank_config.json at require time
local _token    = nil
local _computerID = os.getComputerID()

local function loadToken()
    if _token then return end
    if not fs.exists("bank_config.json") then return end
    local f = fs.open("bank_config.json", "r")
    if not f then return end
    local data = textutils.unserialiseJSON(f.readAll())
    f.close()
    if data and data.token then _token = data.token end
end

peripheral.find("modem", rednet.open)
loadToken()

-- simple djb2 checksum over action+amount+timestamp for basic tamper
-- not cryptographic, just a sanity check against accidental corruption
local function checksum(action, amount, ts)
    local s = tostring(action) .. tostring(amount or "") .. tostring(ts)
    local h = 5381
    for i = 1, #s do
        h = ((h * 33) + string.byte(s, i)) % 2147483648
    end
    return h
end

local function request(msg)
    local serverId = rednet.lookup(PROTOCOL, HOSTNAME)
    if not serverId then return nil end

    local ts = os.epoch("utc")
    msg.computerID = _computerID
    msg.token      = _token
    msg.ts         = ts
    msg.checksum   = checksum(msg.action, msg.amount, ts)

    rednet.send(serverId, msg, PROTOCOL)

    local timeout = os.startTimer(TIMEOUT)
    while true do
        local ev, p1, p2 = os.pullEvent()
        if ev == "rednet_message" and p1 == serverId then return p2 end
        if ev == "timer"          and p1 == timeout  then return nil end
    end
end

function bank.getBalance(player)
    local reply = request({ action = "get", player = player })
    if reply and reply.ok then return reply.balance end
    return nil
end

function bank.add(player, amount)
    local reply = request({ action = "add", player = player, amount = amount })
    if reply and reply.ok then return reply.balance end
    return nil
end

function bank.remove(player, amount)
    local reply = request({ action = "remove", player = player, amount = amount })
    if not reply    then return nil, "error"        end
    if not reply.ok then return nil, reply.err or "insufficient" end
    return reply.balance
end

function bank.set(player, amount)
    local reply = request({ action = "set", player = player, amount = amount })
    if reply and reply.ok then return reply.balance end
    return nil
end

function bank.top(limit)
    local reply = request({ action = "top", limit = limit or 10 })
    if reply and reply.ok then return reply.top end
    return {}
end

return bank