-- blackjack.lua
-- blackjack game engine

local BJ = {}


-- 0.0 = fair, 1.0 = player loses every hand
BJ.rigFactor = 0.7

-- Deck 

local SUITS = {"S","H","D","C"}
local RANKS = {"A","2","3","4","5","6","7","8","9","10","J","Q","K"}

function BJ.newDeck(numDecks)
    numDecks = numDecks or 6
    local deck = {}
    for _ = 1, numDecks do
        for _, suit in ipairs(SUITS) do
            for _, rank in ipairs(RANKS) do
                deck[#deck+1] = {rank=rank, suit=suit}
            end
        end
    end
    return deck
end

function BJ.shuffle(deck)
    for i = #deck, 2, -1 do
        local j = math.random(1, i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    return deck
end

function BJ.deal(deck)
    if BJ.rigFactor > 0 and math.random() < BJ.rigFactor then
        -- Find the worst card (lowest value) in the top 10 and swap it to top
        local searchDepth = math.min(10, #deck)
        local worstIdx, worstVal = #deck, BJ.cardValue(deck[#deck])
        for i = #deck - 1, #deck - searchDepth + 1, -1 do
            local v = BJ.cardValue(deck[i])
            if v < worstVal then
                worstVal = v
                worstIdx = i
            end
        end
        deck[#deck], deck[worstIdx] = deck[worstIdx], deck[#deck]
    end
    return table.remove(deck, #deck)
end
-- Hand Value 

function BJ.cardValue(card)
    local r = card.rank
        if r == "A" then return 11 end
    if r == "J" or r == "Q" or r == "K" then return 10 end
    return tonumber(r)
end

function BJ.handValue(hand)
    local total = 0
    local aces  = 0
    for _, card in ipairs(hand) do
        local v = BJ.cardValue(card)
        total = total + v
        if card.rank == "A" then aces = aces + 1 end
    end
    while total > 21 and aces > 0 do
        total = total - 10
        aces  = aces - 1
    end
    return total
end

function BJ.isSoft(hand)
    local total = 0
    local aces  = 0
    for _, card in ipairs(hand) do
        total = total + BJ.cardValue(card)
        if card.rank == "A" then aces = aces + 1 end
    end
    while total > 21 and aces > 0 do
        total = total - 10
        aces  = aces - 1
    end
    return aces > 0
end

function BJ.isBust(hand)
    return BJ.handValue(hand) > 21
end

function BJ.isBlackjack(hand)
    return #hand == 2 and BJ.handValue(hand) == 21
end

function BJ.cardLabel(card)
    return card.rank .. card.suit
end

function BJ.handLabel(hand)
    local parts = {}
    for _, c in ipairs(hand) do
        parts[#parts+1] = BJ.cardLabel(c)
    end
    return table.concat(parts, " ")
end

-- Dealer Logic 

function BJ.dealerShouldHit(hand)
    local val  = BJ.handValue(hand)
    local soft = BJ.isSoft(hand)
    if val < 17 then return true end
    if val == 17 and soft then return true end
    return false
end

function BJ.runDealer(deck, dealerHand)
    while BJ.dealerShouldHit(dealerHand) do
        dealerHand[#dealerHand+1] = BJ.deal(deck)
    end
    return dealerHand
end

-- Result 

function BJ.resolveHand(playerHand, dealerHand)
    local pVal = BJ.handValue(playerHand)
    local dVal = BJ.handValue(dealerHand)
    local pBJ  = BJ.isBlackjack(playerHand)
    local dBJ  = BJ.isBlackjack(dealerHand)

    if BJ.isBust(playerHand) then
        return "loss", 0
    end

    if pBJ and dBJ then
        return "push", 1   
    end

    if pBJ then
        return "blackjack", 2.5  
    end

    if dBJ then
        return "loss", 0
    end

    if BJ.isBust(dealerHand) then
        return "win", 2
    end

    if pVal > dVal then
        return "win", 2
    elseif pVal == dVal then
        return "push", 1
    else
        return "loss", 0
    end
end

function BJ.calcPayout(bet, multiplier)
    return math.floor(bet * multiplier)
end

--  Split support 

function BJ.canSplit(hand)
    return #hand == 2 and hand[1].rank == hand[2].rank
end

function BJ.canDouble(hand)
    return #hand == 2
end

-- State machine helpers 

function BJ.newGame(deck, bet)
    local state = {
        deck        = deck,
        bet         = bet,
        player      = {},
        dealer      = {},
        splitHands  = nil,   
        activeSplit = nil,   
        phase       = "betting",  
        result      = nil,
        payout      = 0,
        doubled     = false,
    }
    return state
end

function BJ.startDeal(state)
    state.player[1] = BJ.deal(state.deck)
    state.dealer[1] = BJ.deal(state.deck)
    state.player[2] = BJ.deal(state.deck)
    state.dealer[2] = BJ.deal(state.deck)  
    state.phase = "playing"
    return state
end

function BJ.playerHit(state)
    state.player[#state.player+1] = BJ.deal(state.deck)
    if BJ.isBust(state.player) then
        state.phase  = "done"
        state.result = "loss"
        state.payout = 0
    end
    return state
end

function BJ.playerStand(state)
    state.phase = "dealer"
    BJ.runDealer(state.deck, state.dealer)
    local result, mult = BJ.resolveHand(state.player, state.dealer)
    state.result = result
    state.payout = BJ.calcPayout(state.bet, mult)
    state.phase  = "done"
    return state
end

function BJ.playerDouble(state)
    state.bet    = state.bet * 2
    state.doubled = true
    state.player[#state.player+1] = BJ.deal(state.deck)
    if BJ.isBust(state.player) then
        state.result = "loss"
        state.payout = 0
        state.phase  = "done"
        return state
    end
    return BJ.playerStand(state)
end

function BJ.checkNatural(state)
    if BJ.isBlackjack(state.player) then
        local result, mult = BJ.resolveHand(state.player, state.dealer)
        state.result = result
        state.payout = BJ.calcPayout(state.bet, mult)
        state.phase  = "done"
        return true
    end
    return false
end

return BJ