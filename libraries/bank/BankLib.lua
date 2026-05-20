-- libraries/bank/BankLib.lua

local bank = {}

local PROTOCOL    = "bank_protocol"
local HOSTNAME    = "bank_server"
local BANK_TIMEOUT = 3

peripheral.find("modem", rednet.open)


local function request(msg)
  local serverId = rednet.lookup(PROTOCOL, HOSTNAME)
  if not serverId then return nil end
  rednet.send(serverId, msg, PROTOCOL)
  local timeout = os.startTimer(BANK_TIMEOUT)
  while true do
    local ev, p1, p2 = os.pullEvent()
    if ev == "rednet_message" and p1 == serverId then return p2 end
    if ev == "timer"          and p1 == timeout  then return nil end
  end
end


--- Returns the current balance for `player`, or nil on error.
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
  if not reply        then return nil, "error"        end
  if not reply.ok     then return nil, "insufficient" end
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