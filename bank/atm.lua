-- atm.lua

local inputBarrel = peripheral.wrap("minecraft:barrel_3")
local storageBarrel = peripheral.wrap("minecraft:barrel_4")
local playerDetector = peripheral.find("player_detector")
local monitor = peripheral.find("monitor")

local PROTOCOL = "bank_protocol"
local HOSTNAME = "bank_server"
local BANK_TIMEOUT = 3

monitor.setTextScale(1)

local W, H = 29, 12
local amount = 1
local presets = {1, 8, 16, 32, 64}
local lastState = {}
local cachedCredits = 0
local feedback = nil
local feedbackTimer = nil

-- MODEM --

peripheral.find("modem", rednet.open)

-- BANK COMMS --

local function bankRequest(msg)
  local serverId = rednet.lookup(PROTOCOL, HOSTNAME)
  if not serverId then
    print("bank offline")
    return nil
  end
  rednet.send(serverId, msg, PROTOCOL)
  local id, reply
  local timeout = os.startTimer(BANK_TIMEOUT)
  repeat
    local event, p1, p2 = os.pullEvent()
    if event == "rednet_message" and p1 == serverId then
      reply = p2
      break
    end
  until event == "timer" and p1 == timeout
  return reply
end

local function refreshCredits(player)
  local reply = bankRequest({action="get", player=player})
  if reply and reply.ok then
    cachedCredits = reply.balance
  end
end

-- FEEDBACK --

local function setFeedback(msg, color)
  feedback = {msg=msg, color=color}
  feedbackTimer = os.startTimer(2)
end

-- COIN LOGIC --

local function getCoinCount(barrel)
  local total = 0
  local items = barrel.list()
  for _, item in pairs(items) do
    if item.name == "createdeco:brass_coin" then
      total = total + item.count
    end
  end
  return total
end

local function moveCoins(fromBarrel, toBarrel, count)
  local moved = 0
  local items = fromBarrel.list()
  for slot, item in pairs(items) do
    if item.name == "createdeco:brass_coin" and moved < count then
      local toMove = math.min(item.count, count - moved)
      moved = moved + fromBarrel.pushItems(peripheral.getName(toBarrel), slot, toMove)
    end
    if moved >= count then break end
  end
  return moved
end

local function getPlayerInRange()
  local players = playerDetector.getPlayersInRange(2)
  if #players == 1 then return players[1] end
  return nil
end

local function getEmptySpace(barrel)
  local used = 0
  local items = barrel.list()
  for _, item in pairs(items) do
    used = used + item.count
  end
  local size = barrel.size()
  return (size * 64) - used
end

local function deposit()
  local player = getPlayerInRange()
  if not player then return end
  local space = getEmptySpace(storageBarrel)
  if space <= 0 then
    setFeedback("Vault is full!", colors.red)
    return
  end
  local toDeposit = math.min(amount, space)
  local moved = moveCoins(inputBarrel, storageBarrel, toDeposit)
  if moved > 0 then
    bankRequest({action="add", player=player, amount=moved})
    refreshCredits(player)
    if moved < amount then
      setFeedback("Partial: +" .. moved .. " coins", colors.orange)
    else
      setFeedback("Deposited " .. moved .. " coins", colors.lime)
    end
  else
    setFeedback("No coins in barrel!", colors.red)
  end
end

local function withdraw()
  local player = getPlayerInRange()
  if not player then return end
  if cachedCredits < amount then
    setFeedback("Insufficient credits!", colors.red)
    return
  end
  local space = getEmptySpace(inputBarrel)
  if space <= 0 then
    setFeedback("Barrel is full!", colors.red)
    return
  end
  local toWithdraw = math.min(amount, space)
  local reply = bankRequest({action="remove", player=player, amount=toWithdraw})
  if reply and reply.ok then
    moveCoins(storageBarrel, inputBarrel, toWithdraw)
    cachedCredits = reply.balance
    if toWithdraw < amount then
      setFeedback("Partial: -" .. toWithdraw .. " coins", colors.orange)
    else
      setFeedback("Withdrew " .. toWithdraw .. " coins", colors.lime)
    end
  else
    setFeedback("Bank error!", colors.red)
  end
end

-- STATE --

local function stateChanged(players, input, storage)
  local playerName = #players == 1 and players[1] or tostring(#players)
  if lastState.playerName ~= playerName    then return true end
  if lastState.credits    ~= cachedCredits then return true end
  if lastState.input      ~= input         then return true end
  if lastState.storage    ~= storage       then return true end
  if lastState.amount     ~= amount        then return true end
  if lastState.feedback   ~= (feedback and feedback.msg) then return true end
  return false
end

local function saveState(players, input, storage)
  lastState.playerName = #players == 1 and players[1] or tostring(#players)
  lastState.credits    = cachedCredits
  lastState.input      = input
  lastState.storage    = storage
  lastState.amount     = amount
  lastState.feedback   = feedback and feedback.msg
end

-- DRAW UTILS --

local buttons = {}

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

local function drawBtn(label, x, y, w, bg)
  monitor.setCursorPos(x, y)
  monitor.setBackgroundColor(bg)
  monitor.setTextColor(colors.white)
  local pad = math.floor((w - #label) / 2)
  monitor.write(string.rep(" ", pad) .. label .. string.rep(" ", w - pad - #label))
  monitor.setBackgroundColor(colors.black)
  buttons[label] = {x1=x, y1=y, x2=x+w-1, y2=y}
end

-- DRAW --

local function drawHeader()
  fill(1, colors.gray)
  centered("\4 COIN TERMINAL \4", 1, colors.white, colors.gray)
end

local function drawPlayer(players)
  fill(2, colors.black)
  fill(3, colors.black)
  if #players == 0 then
    centered("No player nearby", 2, colors.gray)
    centered("Stand within 2 blocks", 3, colors.lightGray)
  elseif #players > 1 then
    centered("Multiple players!", 2, colors.orange)
    centered("One at a time", 3, colors.gray)
  else
    local name = players[1]
    local display = name
    if #display > 12 then display = display:sub(1, 11) .. "~" end
    local bal = tostring(cachedCredits) .. " coins"
    writeAt(2, 2, "\26 " .. display, colors.yellow)
    writeAt(W - #bal, 2, bal, colors.lime)
    fill(3, colors.gray)
    centered("[ balance ]", 3, colors.lightGray, colors.gray)
  end
end

local function drawBarrels(input, storage)
  writeAt(1, 4, string.rep("\140", W), colors.gray)
  fill(5, colors.black)
  local inStr = "BARREL: " .. tostring(input)
  local stStr = "VAULT: " .. tostring(storage)
  writeAt(2, 5, inStr, colors.cyan)
  writeAt(W - #stStr, 5, stStr, colors.blue)
  writeAt(1, 6, string.rep("\140", W), colors.gray)
end

local function drawFeedback()
  fill(8, colors.black)
  if feedback then
    local msg = feedback.msg
    if #msg > W - 2 then msg = msg:sub(1, W - 2) end
    centered(msg, 8, feedback.color)
  end
end

local function drawAmountControls()
  fill(7, colors.black)
  fill(9, colors.black)
  local mid = math.floor(W / 2)
  drawBtn("-", mid - 4, 7, 4, colors.red)
  local amtStr = tostring(amount)
  local amtX = mid - math.floor(#amtStr / 2) + 1
  writeAt(amtX, 7, amtStr, colors.white)
  drawBtn("+", mid + 2, 7, 4, colors.green)
  local btnW = 4
  local totalW = (#presets * btnW) + (#presets - 1)
  local startX = math.floor((W - totalW) / 2) + 1
  local x = startX
  for _, preset in ipairs(presets) do
    local label = tostring(preset)
    local bg = (preset == amount) and colors.purple or colors.gray
    drawBtn(label, x, 9, btnW, bg)
    x = x + btnW + 1
  end
end

local function drawActionButtons()
  writeAt(1, 10, string.rep("\140", W), colors.gray)
  local half = math.floor(W / 2)
  drawBtn("DEPOSIT",  1,        H, half,     colors.green)
  drawBtn("WITHDRAW", half + 1, H, W - half, colors.red)
end

local function redraw(force)
  local players = playerDetector.getPlayersInRange(2)
  local input   = getCoinCount(inputBarrel)
  local storage = getCoinCount(storageBarrel)

  local playerName = #players == 1 and players[1] or nil
  if playerName and playerName ~= lastState.playerName then
    refreshCredits(playerName)
  end

  if not force and not stateChanged(players, input, storage) then return end
  saveState(players, input, storage)

  monitor.clear()
  monitor.setBackgroundColor(colors.black)
  buttons = {}

  drawHeader()
  drawPlayer(players)
  drawBarrels(input, storage)
  drawAmountControls()
  drawFeedback()
  drawActionButtons()
end

-- INPUT --

local function handleTouch(x, y)
  for label, b in pairs(buttons) do
    if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
      if label == "+" then
        amount = amount + 1
      elseif label == "-" then
        amount = math.max(1, amount - 1)
      elseif label == "DEPOSIT" then
        deposit()
      elseif label == "WITHDRAW" then
        withdraw()
      else
        local preset = tonumber(label)
        if preset then amount = preset end
      end
      redraw(true)
      return
    end
  end
end

-- MAIN --

redraw(true)
local timer = os.startTimer(1)

while true do
  local event, p1, p2, p3 = os.pullEvent()
  if event == "monitor_touch" then
    handleTouch(p2, p3)
  elseif event == "timer" and p1 == timer then
    redraw(false)
    timer = os.startTimer(1)
  elseif event == "timer" and p1 == feedbackTimer then
    feedback = nil
    feedbackTimer = nil
    redraw(true)
  end
end
