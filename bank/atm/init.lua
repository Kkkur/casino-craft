-- bank/atm/init.lua

local logger = dofile("libraries/logger/logger.lua")
logger.init("atm", "bank/atm/logs")

local ui   = dofile("bank/atm/ui.lua")
local bank = dofile("libraries/bank/BankLib.lua")
bank.setLogger(logger)

local CONFIG_FILE = "bank_config.json"

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then
        logger.error("Missing " .. CONFIG_FILE .. ", run bootstrap first")
        error("atm: missing " .. CONFIG_FILE)
    end
    local f = fs.open(CONFIG_FILE, "r")
    if not f then error("atm: cannot open " .. CONFIG_FILE) end
    local data = textutils.unserialiseJSON(f.readAll())
    f.close()
    if not data then error("atm: corrupt " .. CONFIG_FILE) end
    return data
end

local cfg = loadConfig()

local monitorPeripheral  = cfg.monitorSide    or error("atm: missing monitorSide in config")
local playerDetectorName = cfg.playerDetector or error("atm: missing playerDetector in config")
local inputBarrelName    = cfg.inputBarrel     or error("atm: missing inputBarrel in config")
local vaultName          = cfg.vaultPeripheral or error("atm: missing vaultPeripheral in config")
local coinItem           = cfg.coinItem        or "createdeco:brass_coin"
local playerRange        = cfg.playerRange     or 2
local monitorScale       = cfg.monitorScale    or 1

local playerDetector = peripheral.wrap(playerDetectorName)
local inputBarrel    = peripheral.wrap(inputBarrelName)
local vault          = peripheral.wrap(vaultName)

if not playerDetector then error("atm: cannot wrap player detector: " .. playerDetectorName) end
if not inputBarrel    then error("atm: cannot wrap input barrel: "    .. inputBarrelName)    end
if not vault          then error("atm: cannot wrap vault: "           .. vaultName)          end

ui.init(monitorPeripheral, monitorScale)

local PRESETS = {1, 8, 16, 32, 64}

local state = {
    playerName  = nil,
    credits     = 0,
    barrelCount = 0,
    vaultCount  = 0,
    amount      = 1,
    presets     = PRESETS,
    feedback    = nil,
    connecting  = true,   -- shown during bank.connect()
}

local feedbackTimer = nil

local function setFeedback(msg, color)
    state.feedback = { msg = msg, color = color }
    feedbackTimer  = os.startTimer(3)
    ui.redraw(state)
end

local function getPlayer()
    local players = playerDetector.getPlayersInRange(playerRange)
    if #players == 1 then return players[1] end
    return nil
end

local function countCoins(container)
    local total = 0
    for _, item in pairs(container.list()) do
        if item.name == coinItem then total = total + item.count end
    end
    return total
end

local function freeSpace(container)
    local used = 0
    for _, item in pairs(container.list()) do used = used + item.count end
    return (container.size() * 64) - used
end

local function moveCoins(from, toName, count)
    local moved = 0
    for slot, item in pairs(from.list()) do
        if item.name == coinItem and moved < count then
            local toMove = math.min(item.count, count - moved)
            moved = moved + from.pushItems(toName, slot, toMove)
        end
        if moved >= count then break end
    end
    return moved
end

-- connect to bank on startup 

local function connectBank()
    state.connecting = true
    ui.redraw(state)
    local ok, err = bank.connect()
    state.connecting = false
    if not ok then
        logger.error("ATM cannot reach bank server: " .. tostring(err))
        setFeedback("Bank offline! Retry in 10s", colours.red)
        return false
    end
    logger.info("ATM connected to bank server.")
    return true
end

--  refresh 

local function refreshCoinCounts()
    state.barrelCount = countCoins(inputBarrel)
    state.vaultCount  = countCoins(vault)
end

-- deposit 
local function deposit()
    local player = getPlayer()
    if not player then return end

    local space = freeSpace(vault)
    if space <= 0 then
        logger.warn("Deposit refused: vault full")
        setFeedback("Vault is full!", colours.red)
        return
    end

    local toDeposit = math.min(state.amount, space, countCoins(inputBarrel))
    if toDeposit == 0 then
        setFeedback("No coins in barrel!", colours.red)
        return
    end

    -- step 1: move coins physically first so the vault actually holds them
    local moved = moveCoins(inputBarrel, vaultName, toDeposit)
    if moved == 0 then
        logger.warn("Deposit: no coins moved for " .. player)
        setFeedback("No coins in barrel!", colours.red)
        return
    end

    -- step 2: ping → ledger add → await confirmation
    local newBal, err = bank.add(player, moved)
    if not newBal then
        -- ledger failed: reverse the physical move
        logger.error("Deposit ledger FAILED for " .. player .. ": " .. tostring(err)
            .. " — reversing " .. moved .. " coins")
        local reversed = moveCoins(vault, inputBarrelName, moved)
        if reversed < moved then
            logger.error("PARTIAL REVERSAL: only " .. reversed .. "/" .. moved .. " coins returned!")
        end
        setFeedback("Bank error! Please retry.", colours.red)
        return
    end

    -- step 3: confirmed
    state.credits = newBal
    if moved < state.amount then
        logger.warn("Partial deposit: " .. player .. " +" .. moved .. " (wanted " .. state.amount .. ")")
        setFeedback("Partial: +" .. moved .. " coins", colours.orange)
    else
        logger.info("Deposit: " .. player .. " +" .. moved .. " → balance=" .. newBal)
        setFeedback("Deposited " .. moved .. " coins!", colours.lime)
    end
    refreshCoinCounts()
end

--  withdraw 
--
-- Safe order:
--   1. ping → bank.remove()   (ledger deducted + confirmed)
--   2. Move coins vault → barrel  (physical, only if ledger ok)
--   3. If physical move fails, refund ledger via bank.add()
--
local function withdraw()
    local player = getPlayer()
    if not player then return end

    if state.credits < state.amount then
        setFeedback("Insufficient credits!", colours.red)
        return
    end
    local space = freeSpace(inputBarrel)
    if space <= 0 then
        setFeedback("Barrel is full!", colours.red)
        return
    end

    local toWithdraw = math.min(state.amount, space)

    -- step 1: ledger deduction first, confirmed by server
    local newBal, err = bank.remove(player, toWithdraw)
    if not newBal then
        logger.warn("Withdraw ledger FAILED for " .. player .. ": " .. tostring(err))
        if err == "insufficient" then
            setFeedback("Insufficient credits!", colours.red)
        elseif err == "server_unreachable" or err == "no_confirmation" then
            setFeedback("Bank offline! Please retry.", colours.red)
        else
            setFeedback("Bank error! Please retry.", colours.red)
        end
        return
    end

    -- step 2: physically dispense coins
    local moved = moveCoins(vault, inputBarrelName, toWithdraw)
    if moved < toWithdraw then
        -- vault didnt have enough physical coins; refund the difference
        local missing = toWithdraw - moved
        logger.error("Withdraw: vault short by " .. missing .. " coins for " .. player .. " — refunding")
        local refunded, refErr = bank.add(player, missing)
        if refunded then
            newBal = refunded
            logger.info("Refund ok: " .. player .. " +" .. missing)
        else
            logger.error("REFUND FAILED for " .. player .. ": " .. tostring(refErr))
        end
        setFeedback("Vault short! Got " .. moved .. " coins.", colours.orange)
        state.credits = newBal
        refreshCoinCounts()
        return
    end

    -- step 3: all good
    state.credits = newBal
    logger.info("Withdraw: " .. player .. " -" .. toWithdraw .. " → balance=" .. newBal)
    setFeedback("Withdrew " .. toWithdraw .. " coins!", colours.lime)
    refreshCoinCounts()
end

-- session reset (called when a player leaves) 

local function resetSession()
    state.playerName = nil
    state.credits    = 0
    state.amount     = 1
    state.feedback   = nil
    if feedbackTimer then
        -- let the stale timer fire harmlessly; it checks feedbackTimer == p1
        feedbackTimer = nil
    end
    logger.info("ATM: player left, session reset")
    ui.redraw(state)
end

--  player entered range 

local function onPlayerEntered(playerName)
    if playerName == state.playerName then return end
    logger.info("ATM: player entered – " .. playerName)
    local bal, err = bank.getBalance(playerName)
    if bal then
        state.credits    = bal
        state.playerName = playerName
    else
        logger.warn("Could not fetch balance for " .. playerName .. ": " .. tostring(err))
        state.credits    = 0
        state.playerName = playerName
        setFeedback("Bank error, try again", colours.red)
    end
    ui.redraw(state)
end

-- button handler 

local function handleButton(label)
    if label == "+" then
        state.amount = state.amount + 1
    elseif label == "-" then
        state.amount = math.max(1, state.amount - 1)
    elseif label == "DEPOSIT" then
        deposit()
    elseif label == "WITHDRAW" then
        withdraw()
    else
        local preset = tonumber(label)
        if preset then state.amount = preset end
    end
end

--  startup 

logger.info("ATM starting. vault=" .. vaultName .. " barrel=" .. inputBarrelName)

-- connect (retries every 10s if offline)
local bankOnline = false
while not bankOnline do
    bankOnline = connectBank()
    if not bankOnline then
        os.sleep(10)
    end
end

refreshCoinCounts()
ui.redraw(state)

local pollTimer = os.startTimer(1)

-- main event loop 

while true do
    local ev, p1, p2, p3 = os.pullEvent()

    if ev == "monitor_touch" then
        local label = ui.hitTest(p2, p3)
        if label then
            handleButton(label)
            ui.redraw(state)
        end

    -- player detector events 
    elseif ev == "playerLeft" or ev == "playerChangedDimension" then
        -- p1 = player name (fired by the Player Detector peripheral)
        if p1 == state.playerName then
            resetSession()
        end

    elseif ev == "playerEntered" then
        -- p1 = player name
        onPlayerEntered(p1)

    -- poll timer (secondary safety-net + coin count refresh) 
    elseif ev == "timer" and p1 == pollTimer then
        -- Refresh coin counts every tick; also catches any missed detector events
        state.barrelCount = countCoins(inputBarrel)
        state.vaultCount  = countCoins(vault)

        local detected = getPlayer()
        if detected and detected ~= state.playerName then
            -- missed a playerEntered event — recover gracefully
            onPlayerEntered(detected)
        elseif not detected and state.playerName then
            -- missed a playerLeft event — recover gracefully
            resetSession()
        else
            ui.redraw(state)
        end
        pollTimer = os.startTimer(1)

    elseif ev == "timer" and p1 == feedbackTimer then
        state.feedback = nil
        feedbackTimer  = nil
        ui.redraw(state)
    end
end