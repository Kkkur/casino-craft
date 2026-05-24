-- slots.lua

local playerDetector = peripheral.find("player_detector")
local monitor        = peripheral.find("monitor")

local bank = require("lib.bank")

monitor.setTextScale(0.5)

-- layout
local W, H = monitor.getSize()
-- left panel: reels + controls
local REEL_W   = 3   -- chars per reel cell
local REEL_GAP = 1
local PANEL_W  = (REEL_W * 3) + (REEL_GAP * 2) + 4  -- ~15
local PAY_X    = PANEL_W + 3  -- paytable starts here

local SYMBOLS = {
  { em = "*", label = "RARE", weight = 1,  mult = 50 },
  { em = "$", label = "STAR", weight = 2,  mult = 20 },
  { em = "@", label = "GEM",  weight = 3,  mult = 15 },
  { em = "&", label = "FLOR", weight = 5,  mult = 10 },
  { em = "%", label = "BAG",  weight = 7,  mult = 5  },
  { em = "#", label = "MELO", weight = 10, mult = 3  },
  { em = "~", label = "GRPE", weight = 12, mult = 2  },
  { em = "o", label = "ORNG", weight = 14, mult = 2  },
}

local POOL = {}
for _, s in ipairs(SYMBOLS) do
  for _ = 1, s.weight do POOL[#POOL+1] = s end
end
local function pick() return POOL[math.random(#POOL)] end

local cachedCredits = 0
local bet           = 1
local lastWin       = 0
local totalWon      = 0
local feedback      = nil
local feedbackTimer = nil
local spinning      = false
local reelResult    = { SYMBOLS[7], SYMBOLS[7], SYMBOLS[7] }

local presets = {1, 5, 10, 25, 50}
local buttons = {}

local function refreshCredits(player)
  local bal = bank.getBalance(player)
  if bal then cachedCredits = bal end
end

local function getPlayerInRange()
  local players = playerDetector.getPlayersInRange(2)
  if #players == 1 then return players[1] end
  return nil
end

-- feedback 

local function setFeedback(msg, color)
  feedback      = { msg = msg, color = color }
  feedbackTimer = os.startTimer(2.5)
end

-- draw utils 

local function reg(label, x1, y1, x2, y2)
  buttons[label] = { x1=x1, y1=y1, x2=x2, y2=y2 }
end

local function fill(x, y, w, bg)
  monitor.setCursorPos(x, y)
  monitor.setBackgroundColor(bg)
  monitor.write(string.rep(" ", w))
  monitor.setBackgroundColor(colors.black)
end

local function writeAt(x, y, text, fg, bg)
  monitor.setCursorPos(x, y)
  monitor.setBackgroundColor(bg or colors.black)
  monitor.setTextColor(fg)
  monitor.write(text)
  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
end

local function drawBtn(label, x, y, w, bg, fg)
  fg = fg or colors.white
  fill(x, y, w, bg)
  local pad = math.floor((w - #label) / 2)
  monitor.setCursorPos(x + pad, y)
  monitor.setBackgroundColor(bg)
  monitor.setTextColor(fg)
  monitor.write(label)
  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
  reg(label, x, y, x + w - 1, y)
end

-- header 

local function drawHeader()
  fill(1, 1, W, colors.gray)
  local title = "\4 SLOTS \4"
  local tx = math.floor((PANEL_W - #title) / 2) + 1
  writeAt(tx, 1, title, colors.yellow, colors.gray)
end

-- credits bar 

local function drawCredits(player)
  fill(1, 2, PANEL_W, colors.black)
  fill(1, 3, PANEL_W, colors.black)
  if not player then
    writeAt(2, 2, "No player nearby", colors.gray)
    writeAt(2, 3, "Stand within 2 blocks", colors.lightGray)
    return
  end
  local name = player
  if #name > 10 then name = name:sub(1,9) .. "~" end
  writeAt(2, 2, "\26 " .. name, colors.yellow)
  local balStr = tostring(cachedCredits) .. "c"
  writeAt(PANEL_W - #balStr, 2, balStr, colors.lime)
  local winStr = "W:" .. tostring(lastWin)
  local totStr = "T:" .. tostring(totalWon)
  writeAt(2, 3, winStr, colors.cyan)
  writeAt(PANEL_W - #totStr, 3, totStr, colors.green)
end

-- reels 
-- rows 5-9: reel display (5 rows, centre row = payline at row 7)

local REEL_TOP  = 5
local REEL_ROWS = 5
local REEL_BOT  = REEL_TOP + REEL_ROWS - 1  -- 9

local REEL_XS = { 2, 7, 12 }  -- left edge of each reel column

local function drawReelBorder()
  fill(1, 4, PANEL_W, colors.gray)  -- separator above
  for row = REEL_TOP, REEL_BOT do
    fill(1, row, PANEL_W, colors.black)
  end
  fill(1, REEL_BOT + 1, PANEL_W, colors.gray)  -- separator below
end

local function drawReels(results, spinning_mask)
  spinning_mask = spinning_mask or {}
  for ri, rx in ipairs(REEL_XS) do
    for row = REEL_TOP, REEL_BOT do
      local onPayline = (row == 7)
      local bg = onPayline and colors.gray or colors.black
      fill(rx, row, REEL_W, bg)
      local sym
      if spinning_mask[ri] then
        sym = POOL[math.random(#POOL)].em
      else
        sym = results[ri].em
      end
      local fg = onPayline and colors.yellow or colors.lightGray
      monitor.setCursorPos(rx + 1, row)
      monitor.setBackgroundColor(bg)
      monitor.setTextColor(fg)
      monitor.write(sym)
      monitor.setBackgroundColor(colors.black)
      monitor.setTextColor(colors.white)
    end
  end
end

-- feedback / message 

local function drawFeedback()
  fill(1, 11, PANEL_W, colors.black)
  if feedback then
    local msg = feedback.msg
    if #msg > PANEL_W - 2 then msg = msg:sub(1, PANEL_W - 2) end
    local x = math.floor((PANEL_W - #msg) / 2) + 1
    writeAt(x, 11, msg, feedback.color)
  end
end

-- bet controls 

local function drawBetControls()
  fill(1, 12, PANEL_W, colors.black)
  fill(1, 13, PANEL_W, colors.black)

  -- [-] amount [+]
  local mid = math.floor(PANEL_W / 2)
  drawBtn("-", mid - 4, 12, 3, colors.red)
  local amtStr = tostring(bet)
  writeAt(mid - math.floor(#amtStr / 2) + 1, 12, amtStr, colors.white)
  drawBtn("+", mid + 2, 12, 3, colors.green)

  -- presets
  local btnW = 3
  local total = #presets * btnW + (#presets - 1)
  local sx = math.floor((PANEL_W - total) / 2) + 1
  local x = sx
  for _, v in ipairs(presets) do
    local label = tostring(v)
    local bg = (v == bet) and colors.purple or colors.gray
    drawBtn(label, x, 13, btnW, bg)
    x = x + btnW + 1
  end
end

-- spin button 

local function drawSpinButton(enabled)
  local bg = enabled and colors.green or colors.gray
  drawBtn("SPIN", 1, H, PANEL_W, bg, colors.white)
end

-- paytable 

local PAY_ROWS = {
  { syms = "***", label = "RARE x3", mult = "x50 JACKPOT", col = colors.yellow },
  { syms = "$$$", label = "STAR x3", mult = "x20",         col = colors.lime   },
  { syms = "@@@", label = "GEM  x3", mult = "x15",         col = colors.cyan   },
  { syms = "&&&", label = "FLOR x3", mult = "x10",         col = colors.green  },
  { syms = "%%%", label = "BAG  x3", mult = "x5",          col = colors.orange },
  { syms = "###", label = "MELO x3", mult = "x3",          col = colors.white  },
  { syms = "~~~", label = "GRPE x3", mult = "x2",          col = colors.lightGray },
  { syms = "ooo", label = "ORNG x3", mult = "x2",          col = colors.lightGray },
  { syms = "??-", label = "Any pair", mult = "x1 push",    col = colors.gray   },
}

local function drawPaytable()
  local px = PAY_X
  local pw = W - px

  -- header
  fill(px, 1, pw, colors.gray)
  local hdr = "PAYTABLE"
  writeAt(px + math.floor((pw - #hdr) / 2), 1, hdr, colors.yellow, colors.gray)

  for i, row in ipairs(PAY_ROWS) do
    local y = i + 1
    if y > H then break end
    fill(px, y, pw, colors.black)
    writeAt(px + 1, y, row.syms, row.col)
    writeAt(px + 5, y, row.label, colors.lightGray)
    local mx = px + pw - #row.mult - 1
    writeAt(mx, y, row.mult, row.col)
  end
end

-- full redraw 

local function redraw(player)
  monitor.clear()
  monitor.setBackgroundColor(colors.black)
  buttons = {}

  drawHeader()
  drawCredits(player)
  drawReelBorder()
  drawReels(reelResult, nil)
  drawFeedback()
  drawBetControls()
  drawSpinButton(player ~= nil and not spinning)
  drawPaytable()
end

-- spin logic 

local function doSpin(player)
  if spinning then return end
  if cachedCredits < bet then
    setFeedback("Insufficient credits!", colors.red)
    redraw(player)
    return
  end

  spinning = true
  lastWin = 0

  -- deduct immediately
  local newBal, err = bank.remove(player, bet, "game")
  if not newBal then
    spinning = false
    setFeedback(err == "insufficient" and "Insufficient credits!" or "Bank error!", colors.red)
    redraw(player)
    return
  end
  cachedCredits = newBal

  -- animate reels
  local results = { pick(), pick(), pick() }
  local stopDelay = { 0.8, 1.2, 1.6 }

  drawSpinButton(false)

  for frame = 1, 20 do
    local mask = {}
    if frame <= 10 then mask = {true, true, true}
    elseif frame <= 14 then mask = {false, true, true}
    elseif frame <= 18 then mask = {false, false, true}
    end
    drawReels(results, mask)
    os.sleep(0.07)
  end

  reelResult = results

  -- evaluate
  local a, b, c = results[1], results[2], results[3]
  local win = 0
  if a.label == b.label and b.label == c.label then
    win = bet * a.mult
    if a.mult >= 50 then
      setFeedback("JACKPOT! +" .. win .. " credits", colors.yellow)
    else
      setFeedback("WIN! " .. a.em .. a.em .. a.em .. " +" .. win, colors.lime)
    end
  elseif a.label == b.label or b.label == c.label or a.label == c.label then
    win = bet
    setFeedback("Pair! Push. +" .. win, colors.cyan)
  else
    setFeedback("No match. -" .. bet, colors.red)
  end

  if win > 0 then
    local newBal = bank.add(player, win, "game")
    cachedCredits = newBal or (cachedCredits + win)
    lastWin  = win
    totalWon = totalWon + win
  end

  spinning = false
  redraw(player)
end

-- input 

local function handleTouch(x, y, player)
  for label, b in pairs(buttons) do
    if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
      if label == "+" then
        bet = bet + 1
      elseif label == "-" then
        bet = math.max(1, bet - 1)
      elseif label == "SPIN" then
        if player then doSpin(player) end
        return
      else
        local v = tonumber(label)
        if v then bet = v end
      end
      redraw(player)
      return
    end
  end
end

-- main loop 

local lastPlayer = nil
local pollTimer  = os.startTimer(1)

do
  local p = getPlayerInRange()
  if p then refreshCredits(p) end
  lastPlayer = p
  redraw(lastPlayer)
end

while true do
  local ev, p1, p2, p3 = os.pullEvent()

  if ev == "monitor_touch" then
    local player = getPlayerInRange()
    handleTouch(p2, p3, player)

  elseif ev == "timer" and p1 == pollTimer then
    local player = getPlayerInRange()
    if player ~= lastPlayer then
      totalWon  = 0
      lastWin   = 0
      feedback  = nil
      if player then refreshCredits(player) end
      lastPlayer = player
      redraw(lastPlayer)
    elseif player then
      refreshCredits(player)
      redraw(player)
    else
      redraw(nil)
    end
    pollTimer = os.startTimer(1)

  elseif ev == "timer" and p1 == feedbackTimer then
    feedback      = nil
    feedbackTimer = nil
    redraw(lastPlayer)
  end
end