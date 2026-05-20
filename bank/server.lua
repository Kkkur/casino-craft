-- server.lua

local PROTOCOL = "bank_protocol"
local HOSTNAME = "bank_server"
local SAVE_FILE = "balances.json"
local balances = {}

-- PERSISTENCE --

local function saveBalances()
  local f = fs.open(SAVE_FILE, "w")
  f.write(textutils.serialiseJSON(balances))
  f.close()
end

local function loadBalances()
  if not fs.exists(SAVE_FILE) then return end
  local f = fs.open(SAVE_FILE, "r")
  local data = textutils.unserialiseJSON(f.readAll())
  f.close()
  if data then balances = data end
end

-- BANK LOGIC --

local function getBalance(player)
  return balances[player] or 0
end

local function addBalance(player, amount)
  balances[player] = getBalance(player) + amount
  saveBalances()
  return balances[player]
end

local function removeBalance(player, amount)
  local bal = getBalance(player)
  if bal < amount then return false, bal end
  balances[player] = bal - amount
  saveBalances()
  return true, balances[player]
end

local function setBalance(player, amount)
  balances[player] = amount
  saveBalances()
end

local function getTop(limit)
  local list = {}
  for name, bal in pairs(balances) do
    table.insert(list, {name=name, balance=bal})
  end
  table.sort(list, function(a, b) return a.balance > b.balance end)
  local result = {}
  for i = 1, math.min(limit, #list) do
    result[i] = list[i]
  end
  return result
end

-- REDNET SERVER --

local function runBankServer()
  print("[bank] Listening for requests...")
  while true do
    local senderId, msg = rednet.receive(PROTOCOL)
    if type(msg) == "table" then
      local action = msg.action
      local reply = {ok=false, err="unknown action"}

      if action == "get" and msg.player then
        reply = {ok=true, balance=getBalance(msg.player)}

      elseif action == "add" and msg.player and msg.amount then
        local bal = addBalance(msg.player, msg.amount)
        reply = {ok=true, balance=bal}

      elseif action == "remove" and msg.player and msg.amount then
        local ok, bal = removeBalance(msg.player, msg.amount)
        if ok then
          reply = {ok=true, balance=bal}
        else
          reply = {ok=false, err="insufficient", balance=bal}
        end

      elseif action == "set" and msg.player and msg.amount then
        setBalance(msg.player, msg.amount)
        reply = {ok=true, balance=msg.amount}

      elseif action == "top" then
        reply = {ok=true, top=getTop(msg.limit or 10)}
      end

      rednet.send(senderId, reply, PROTOCOL)
    end
  end
end

-- BALTOP MONITOR --

local function runBaltopMonitor()
  local monitor = peripheral.find("monitor")
  if not monitor then
    print("[baltop] No monitor found, skipping.")
    while true do sleep(9999) end
  end

  monitor.setTextScale(1)
  local W, H = monitor.getSize()

  local function fill(y, bg)
    monitor.setCursorPos(1, y)
    monitor.setBackgroundColor(bg)
    monitor.write(string.rep(" ", W))
    monitor.setBackgroundColor(colors.black)
  end

  local function writeAt(x, y, text, fg, bg)
    monitor.setCursorPos(x, y)
    monitor.setBackgroundColor(bg or colors.black)
    monitor.setTextColor(fg)
    monitor.write(text)
    monitor.setBackgroundColor(colors.black)
  end

  local function centered(text, y, fg, bg)
    local x = math.floor((W - #text) / 2) + 1
    writeAt(x, y, text, fg, bg or colors.black)
  end

  local medals = {"\1", "\2", "\3"}
  local medalColors = {colors.yellow, colors.lightGray, colors.orange}

  while true do
    local top = getTop(H - 1)
    monitor.clear()
    monitor.setBackgroundColor(colors.black)
    fill(1, colors.gray)
    centered("\4 BALTOP \4", 1, colors.white, colors.gray)

    if #top == 0 then
      centered("No balances yet", 3, colors.gray)
    else
      for i, entry in ipairs(top) do
        local row = i + 1
        if row > H then break end
        local rank = i <= 3 and medals[i] or tostring(i) .. "."
        local fg = i <= 3 and medalColors[i] or colors.white
        local name = entry.name
        if #name > W - 8 then name = name:sub(1, W - 9) .. "~" end
        local bal = tostring(entry.balance)
        writeAt(2, row, rank, fg)
        writeAt(5, row, name, fg)
        writeAt(W - #bal, row, bal, colors.lime)
      end
    end

    sleep(5)
  end
end

-- ADMIN CONSOLE --

local function runAdminConsole()
  print("[admin] Commands: bal <p> | set <p> <n> | add <p> <n> | remove <p> <n> | top | list")
  while true do
    io.write("> ")
    local input = io.read()
    if not input then break end
    local parts = {}
    for word in input:gmatch("%S+") do table.insert(parts, word) end
    local cmd = parts[1]

    if cmd == "bal" and parts[2] then
      print(parts[2] .. ": " .. getBalance(parts[2]) .. " coins")

    elseif cmd == "set" and parts[2] and parts[3] then
      local amt = tonumber(parts[3])
      if amt then
        setBalance(parts[2], amt)
        print("Set " .. parts[2] .. " to " .. amt)
      else
        print("Invalid amount")
      end

    elseif cmd == "add" and parts[2] and parts[3] then
      local amt = tonumber(parts[3])
      if amt then
        print(parts[2] .. " now has " .. addBalance(parts[2], amt))
      else
        print("Invalid amount")
      end

    elseif cmd == "remove" and parts[2] and parts[3] then
      local amt = tonumber(parts[3])
      if amt then
        local ok, bal = removeBalance(parts[2], amt)
        if ok then
          print(parts[2] .. " now has " .. bal)
        else
          print("Insufficient. Has: " .. bal)
        end
      else
        print("Invalid amount")
      end

    elseif cmd == "top" then
      for i, entry in ipairs(getTop(10)) do
        print(i .. ". " .. entry.name .. " - " .. entry.balance)
      end

    elseif cmd == "list" then
      for name, bal in pairs(balances) do
        print(name .. ": " .. bal)
      end

    else
      print("Unknown command")
    end
  end
end

-- MAIN --

loadBalances()
peripheral.find("modem", rednet.open)
rednet.host(PROTOCOL, HOSTNAME)
print("[bank] Online as '" .. HOSTNAME .. "' on protocol '" .. PROTOCOL .. "'")
print("[bank] Computer ID: " .. os.getComputerID())

parallel.waitForAll(
  runBankServer,
  runBaltopMonitor,
  runAdminConsole
)
