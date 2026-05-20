-- ========================================================================== --
--  Roulette Core Engine
--  Calculates payouts, manages bet cycles, and updates game state.
-- ========================================================================== --

local ROULETTE = {}

-- -------------------------------------------------------------------------- --
-- Internal Helpers
-- -------------------------------------------------------------------------- --

local function checkBetWin(betKey, winningNum)
    if winningNum == 0 then return betKey == "0" end

    if betKey:sub(1, 4) == "num_" then
        return tonumber(betKey:sub(5)) == winningNum
    end

    -- Outside bets
    if betKey == "doz1"  then return winningNum >= 1  and winningNum <= 12 end
    if betKey == "doz2"  then return winningNum >= 13 and winningNum <= 24 end
    if betKey == "doz3"  then return winningNum >= 25 and winningNum <= 36 end
    if betKey == "low"   then return winningNum >= 1  and winningNum <= 18 end
    if betKey == "high"  then return winningNum >= 19 and winningNum <= 36 end
    if betKey == "odd"   then return winningNum % 2 ~= 0 end
    if betKey == "even"  then return winningNum % 2 == 0 end
    if betKey == "red"   then return (winningNum % 2 ~= 0) end
    if betKey == "black" then return (winningNum % 2 == 0) end

    return false
end

local function getPayoutMultiplier(betKey)
    if betKey == "0" or betKey:sub(1, 4) == "num_" then return 35 end
    if betKey:sub(1, 3) == "doz" then return 2 end
    return 1 -- Even money bets (1:1)
end

-- -------------------------------------------------------------------------- --
-- Public API
-- -------------------------------------------------------------------------- --

function ROULETTE.newGame(queueChips, playerName)
    return {
        playerName       = playerName or "Guest",
        queueChips       = queueChips or 100,
        bets             = {}, 
        phase            = "betting", 
        winningNumber    = nil,
        activeSpinNumber = nil, 
        spinTick         = 0,   
        lastPayout       = 0,
    }
end

function ROULETTE.handleBetClick(state, betKey, betAmount)
    if state.phase ~= "betting" then return end
    
    -- Cycle: 1 -> 2 -> 4 -> 10 -> 0
    local cycle = {1, 2, 4, 10}
    local current = state.bets[betKey] or 0
    local nextVal = 0
    
    for i, v in ipairs(cycle) do
        if v == current then
            nextVal = cycle[i + 1] or 0
            break
        end
    end
    if current == 0 then nextVal = cycle[1] end

    local costDiff = nextVal - current
    if costDiff <= state.queueChips then
        state.queueChips = state.queueChips - costDiff
        state.bets[betKey] = (nextVal > 0) and nextVal or nil
    end
end

function ROULETTE.clearBets(state)
    if state.phase ~= "betting" then return end
    for _, val in pairs(state.bets) do
        state.queueChips = state.queueChips + (val or 0)
    end
    state.bets = {}
end

function ROULETTE.getTotalBets(state)
    local total = 0
    for _, v in pairs(state.bets) do total = total + (v or 0) end
    return total
end

function ROULETTE.startSpin(state)
    if state.phase ~= "betting" then return end
    state.winningNumber = math.random(0, 36)
    state.phase         = "spinning"
    state.lastPayout    = 0
end

function ROULETTE.resolveGame(state)
    local totalPayout = 0
    for key, val in pairs(state.bets) do
        if checkBetWin(key, state.winningNumber) then
            totalPayout = totalPayout + (val * (getPayoutMultiplier(key) + 1))
        end
    end

    state.lastPayout = totalPayout
    state.queueChips = state.queueChips + totalPayout
    state.phase      = "results"
end

function ROULETTE.resetTable(state)
    state.bets            = {}
    state.phase           = "betting"
    state.winningNumber   = nil
    state.activeSpinNumber = nil
    state.spinTick        = 0
    state.lastPayout      = 0
end

return ROULETTE