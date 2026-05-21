-- bank/atm/init.lua

local logger = dofile("libraries/logger/logger.lua")
logger.init("atm", "bank/atm/logs")

local ui   = dofile("bank/atm/ui.lua")
local bank = dofile("libraries/bank/BankLib.lua")

local CONFIG_FILE = "bank_config.json"

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then
        logger.error("Missing " .. CONFIG_FILE .. ", run bootstrap first")
        error("atm: missing " .. CONFIG_FILE .. ", run bootstrap first")
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
}

local feedbackTimer = nil

local function setFeedback(msg, color)
    state.feedback = { msg = msg, color = color }
    feedbackTimer  = os.startTimer(2)
end

local function getPlayer()
    local players = playerDetector.getPlayersInRange(playerRange)
    if #players == 1 then return players[1] end
    return nil
end

local function countCoins(container)
    local total = 0
    local items = container.list()
    for _, item in pairs(items) do
        if item.name == coinItem then
            total = total + item.count
        end
    end
    return total
end

local function freeSpace(container)
    local used = 0
    local items = container.list()
    for _, item in pairs(items) do
        used = used + item.count
    end
    return (container.size() * 64) - used
end

local function moveCoins(from, toName, count)
    local moved = 0
    local items = from.list()
    for slot, item in pairs(items) do
        if item.name == coinItem and moved < count then
            local toMove = math.min(item.count, count - moved)
            moved = moved + from.pushItems(toName, slot, toMove)
        end
        if moved >= count then break end
    end
    return moved
end

local function refreshState()
    state.barrelCount = countCoins(inputBarrel)
    state.vaultCount  = countCoins(vault)
    local player      = getPlayer()
    if player and player ~= state.playerName then
        state.credits  = bank.getBalance(player) or 0
        state.playerName = player
    elseif player then
        state.playerName = player
    else
        state.playerName = nil
        state.credits    = 0
    end
end

local function deposit()
    local player = getPlayer()
    if not player then return end
    local space = freeSpace(vault)
    if space <= 0 then
        logger.warn("Deposit refused: vault full")
        setFeedback("Vault is full!", colours.red)
        return
    end
    local toDeposit = math.min(state.amount, space)
    local moved     = moveCoins(inputBarrel, vaultName, toDeposit)
    if moved == 0 then
        logger.warn("Deposit: no coins found in barrel for " .. player)
        setFeedback("No coins in barrel!", colours.red)
        return
    end
    local newBal = bank.add(player, moved)
    if newBal then state.credits = newBal end
    if moved < state.amount then
        logger.warn("Partial deposit: " .. player .. " +" .. moved .. " (wanted " .. state.amount .. ")")
        setFeedback("Partial: +" .. moved .. " coins", colours.orange)
    else
        logger.info("Deposit: " .. player .. " +" .. moved .. " → balance=" .. tostring(newBal))
        setFeedback("Deposited " .. moved .. " coins", colours.lime)
    end
    refreshState()
end

local function withdraw()
    local player = getPlayer()
    if not player then return end
    if state.credits < state.amount then
        logger.warn("Withdraw refused: insufficient credits for " .. player)
        setFeedback("Insufficient credits!", colours.red)
        return
    end
    local space = freeSpace(inputBarrel)
    if space <= 0 then
        logger.warn("Withdraw refused: barrel full for " .. player)
        setFeedback("Barrel is full!", colours.red)
        return
    end
    local toWithdraw = math.min(state.amount, space)
    local newBal, err = bank.remove(player, toWithdraw)
    if not newBal then
        logger.error("Withdraw FAILED for " .. player .. ": " .. tostring(err))
        setFeedback(err == "insufficient" and "Insufficient credits!" or "Bank error!", colours.red)
        return
    end
    moveCoins(vault, inputBarrelName, toWithdraw)
    state.credits = newBal
    if toWithdraw < state.amount then
        logger.warn("Partial withdraw: " .. player .. " -" .. toWithdraw .. " (wanted " .. state.amount .. ")")
        setFeedback("Partial: -" .. toWithdraw .. " coins", colours.orange)
    else
        logger.info("Withdraw: " .. player .. " -" .. toWithdraw .. " → balance=" .. tostring(newBal))
        setFeedback("Withdrew " .. toWithdraw .. " coins", colours.lime)
    end
    refreshState()
end

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

logger.info("ATM ready. vault=" .. vaultName .. " barrel=" .. inputBarrelName)
refreshState()
ui.redraw(state)

local pollTimer = os.startTimer(1)

while true do
    local ev, p1, p2, p3 = os.pullEvent()

    if ev == "monitor_touch" then
        local label = ui.hitTest(p2, p3)
        if label then
            handleButton(label)
            ui.redraw(state)
        end

    elseif ev == "timer" and p1 == pollTimer then
        refreshState()
        ui.redraw(state)
        pollTimer = os.startTimer(1)

    elseif ev == "timer" and p1 == feedbackTimer then
        state.feedback = nil
        feedbackTimer  = nil
        ui.redraw(state)
    end
end