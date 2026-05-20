-- Roulette game core engine logic matching blackjack.lua style

local ROULETTE = {}

local function checkBetWin(betKey, winningNum)
    if winningNum == 0 then
        return betKey == "0"
    end

    if betKey:sub(1, 4) == "num_" then
        return tonumber(betKey:sub(5)) == winningNum
    end

    -- FIXED: Adjusted Red/Black evaluation to match your Parity Rule (Odd = Red, Even = Black)
    local isRed = (winningNum % 2 ~= 0)

    if betKey == "doz1"  then return winningNum >= 1  and winningNum <= 12 end
    if betKey == "doz2"  then return winningNum >= 13 and winningNum <= 24 end
    if betKey == "doz3"  then return winningNum >= 25 and winningNum <= 36 end
    if betKey == "low"   then return winningNum >= 1  and winningNum <= 18 end
    if betKey == "high"  then return winningNum >= 19 and winningNum <= 36 end
    if betKey == "odd"   then return winningNum % 2 ~= 0 end
    if betKey == "even"  then return winningNum % 2 == 0 end
    if betKey == "red"   then return isRed end
    if betKey == "black" then return not isRed end

    return false
end

local function getPayoutMultiplier(betKey)
    if betKey == "0" or betKey:sub(1, 4) == "num_" then
        return 35
    elseif betKey == "doz1" or betKey == "doz2" or betKey == "doz3" then
        return 2
    else
        return 1
    end
end

function ROULETTE.newGame(queueChips, playerName)
    return {
        playerName         = playerName or "Guest",
        queueChips         = queueChips or 100,
        bets               = {}, 
        phase              = "betting", 
        winningNumber      = nil,
        activeSpinNumber   = nil, 
        spinTick           = 0,   
        payout             = 0,
    }
end

function ROULETTE.handleBetClick(state, betKey)
    if state.phase ~= "betting" then return state end
    
    local current = state.bets[betKey]
    local nextVal

    -- 1. Determine the absolute next logical step in the betting cycle
    if not current then       nextVal = 1
    elseif current == 1 then  nextVal = 2
    elseif current == 2 then  nextVal = 4
    elseif current == 4 then  nextVal = 10
    else                      nextVal = nil end

    -- Use direct values now instead of passing through an adapter function
    local oldCost = current or 0
    local newCost = nextVal or 0

    -- 2. Calculate their "Total Available Wealth" for this specific slot
    local totalAvailableWealth = state.queueChips + oldCost

    -- 3. If they want to upgrade but can't afford the total cost, 
    --    skip the upgrade and completely clear/refund the bet.
    if newCost > totalAvailableWealth then
        nextVal = nil
        newCost = 0
    end

    -- 4. Apply the change and deduct accurately from the queue
    state.bets[betKey] = nextVal
    state.queueChips = totalAvailableWealth - newCost

    return state
end

function ROULETTE.clearBets(state)
    if state.phase ~= "betting" then return state end
    for betKey, val in pairs(state.bets) do
        state.queueChips = state.queueChips + (val or 0)
    end
    state.bets = {}
    return state
end

function ROULETTE.startSpin(state)
    if state.phase ~= "betting" then return state end
    state.winningNumber = math.random(0, 36)
    state.activeSpinNumber = 0
    state.spinTick = 0
    state.phase = "spinning"
    state.payout = 0
    return state
end

function ROULETTE.resolveGame(state)
    local totalPayout = 0
    local winningNum = state.winningNumber

    for betKey, betVal in pairs(state.bets) do
        local chipCount = betVal or 0
        if chipCount > 0 and checkBetWin(betKey, winningNum) then
            local multiplier = getPayoutMultiplier(betKey)
            totalPayout = totalPayout + chipCount + (chipCount * multiplier)
        end
    end

    state.payout = totalPayout
    state.queueChips = state.queueChips + totalPayout
    state.phase = "results"
    return state
end

function ROULETTE.resetTable(state)
    state.bets = {}
    state.phase = "betting"
    state.winningNumber = nil
    state.activeSpinNumber = nil
    state.spinTick = 0
    state.payout = 0
    return state
end

return ROULETTE