-- ========================================================================== --
--  Blackjack Engine
--  Core game logic: Deck management, hand values, and state resolution.
-- ========================================================================== --

local BJ = {}

-- -------------------------------------------------------------------------- --
-- Deck & Card Management
-- -------------------------------------------------------------------------- --

local SUITS = {"S", "H", "D", "C"}
local RANKS = {"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"}

function BJ.newDeck(numDecks)
    numDecks = numDecks or 6
    local deck = {}
    for _ = 1, numDecks do
        for _, suit in ipairs(SUITS) do
            for _, rank in ipairs(RANKS) do
                deck[#deck+1] = {rank = rank, suit = suit}
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
    return table.remove(deck, #deck)
end

-- -------------------------------------------------------------------------- --
-- Scoring Logic
-- -------------------------------------------------------------------------- --

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
        total = total + BJ.cardValue(card)
        if card.rank == "A" then aces = aces + 1 end
    end
    while total > 21 and aces > 0 do
        total = total - 10
        aces  = aces - 1
    end
    return total
end

function BJ.isSoft(hand)
    local total, aces = 0, 0
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

function BJ.isBust(hand)      return BJ.handValue(hand) > 21 end
function BJ.isBlackjack(hand) return #hand == 2 and BJ.handValue(hand) == 21 end

-- -------------------------------------------------------------------------- --
-- Dealer & Resolution Logic
-- -------------------------------------------------------------------------- --

function BJ.dealerShouldHit(hand)
    local val = BJ.handValue(hand)
    return val < 17 or (val == 17 and BJ.isSoft(hand))
end

function BJ.runDealer(deck, dealerHand)
    while BJ.dealerShouldHit(dealerHand) do
        dealerHand[#dealerHand + 1] = BJ.deal(deck)
    end
    return dealerHand
end

function BJ.resolveHand(playerHand, dealerHand)
    if BJ.isBust(playerHand) then return "loss", 0 end
    
    local pBJ, dBJ = BJ.isBlackjack(playerHand), BJ.isBlackjack(dealerHand)
    if pBJ and dBJ then return "push", 1 end
    if pBJ        then return "blackjack", 2.5 end
    if dBJ        then return "loss", 0 end
    
    if BJ.isBust(dealerHand) then return "win", 2 end
    
    local pVal, dVal = BJ.handValue(playerHand), BJ.handValue(dealerHand)
    if pVal > dVal then return "win", 2
    elseif pVal < dVal then return "loss", 0
    else return "push", 1 end
end

function BJ.calcPayout(bet, multiplier)
    return math.floor(bet * multiplier)
end

-- -------------------------------------------------------------------------- --
-- Game State Machine
-- -------------------------------------------------------------------------- --

function BJ.newGame(deck, bet)
    return {
        deck    = deck,
        bet     = bet,
        player  = {},
        dealer  = {},
        phase   = "betting",
        result  = nil,
        payout  = 0
    }
end

function BJ.startDeal(state)
    state.player[1] = BJ.deal(state.deck)
    state.dealer[1] = BJ.deal(state.deck)
    state.player[2] = BJ.deal(state.deck)
    state.dealer[2] = BJ.deal(state.deck)
    state.phase = "playing"
end

function BJ.playerHit(state)
    state.player[#state.player + 1] = BJ.deal(state.deck)
    if BJ.isBust(state.player) then
        state.phase  = "done"
        state.result = "loss"
        state.payout = 0
    end
end

function BJ.playerStand(state)
    BJ.runDealer(state.deck, state.dealer)
    local result, mult = BJ.resolveHand(state.player, state.dealer)
    state.result = result
    state.payout = BJ.calcPayout(state.bet, mult)
    state.phase  = "done"
end

function BJ.playerDouble(state)
    state.bet = state.bet * 2
    state.player[#state.player + 1] = BJ.deal(state.deck)
    if BJ.isBust(state.player) then
        state.result = "loss"
        state.payout = 0
        state.phase  = "done"
    else
        BJ.playerStand(state)
    end
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

function BJ.canSplit(hand)  return #hand == 2 and hand[1].rank == hand[2].rank end
function BJ.canDouble(hand) return #hand == 2 end

return BJ