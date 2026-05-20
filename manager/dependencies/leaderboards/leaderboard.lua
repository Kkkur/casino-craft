-- leaderboard.lua
-- Perplayer blackjack stats. (ONLY BLACKJACK, NEED TO REFACTOR THE FILENAME)

local Leaderboard = {}

local SAVE_FILE      = "manager/leaderboard.json"
local RELAY_PROTOCOL = "CASINO_LEADERBOARD"

local data = {}  -- keyed by username string

-- Persistence 

local function save()
    local f = fs.open(SAVE_FILE, "w")
    if f then
        f.write(textutils.serializeJSON(data))
        f.close()
    end
end

function Leaderboard.load()
    if not fs.exists("manager") then fs.makeDir("manager") end
    if fs.exists(SAVE_FILE) then
        local f = fs.open(SAVE_FILE, "r")
        if f then
            local raw = f.readAll()
            f.close()
            local ok, parsed = pcall(textutils.unserializeJSON, raw)
            if ok and parsed then
                data = parsed
                return true
            end
        end
    end
    data = {}
    return false
end

-- Default entry 

local function defaultEntry(username)
    return {
        username   = username,
        plays      = 0,
        wins       = 0,
        losses     = 0,
        pushes     = 0,
        blackjacks = 0,
        chipsWon   = 0,
        chipsLost  = 0,
        lastSeen   = os.time(),
    }
end

local function getOrCreate(username)
    if not data[username] then
        data[username] = defaultEntry(username)
    end
    return data[username]
end

-- Record a hand 

function Leaderboard.recordHand(username, result, bet, payout)
    if not username or username == "" or username == "Unknown" then return end

    local e = getOrCreate(username)
    e.plays    = e.plays + 1
    e.lastSeen = os.time()

    local net = payout - bet

    if result == "blackjack" then
        e.wins       = e.wins + 1
        e.blackjacks = e.blackjacks + 1
        e.chipsWon   = e.chipsWon + net
    elseif result == "win" then
        e.wins     = e.wins + 1
        e.chipsWon = e.chipsWon + net
    elseif result == "push" then
        e.pushes = e.pushes + 1
    else
        e.losses    = e.losses + 1
        e.chipsLost = e.chipsLost + bet
    end

    save()
end

-- Broadcast to relay display 

function Leaderboard.broadcast(relayId)
    if not relayId then return end
    local top = Leaderboard.getTop(10, "chipsWon")
    for _, e in ipairs(top) do
        e.net     = (e.chipsWon or 0) - (e.chipsLost or 0)
        e.winRate = (e.plays > 0)
            and math.floor((e.wins / e.plays) * 100) or 0
    end
    local totalHands = 0
    local houseEdge  = 0
    for _, e in pairs(data) do
        totalHands = totalHands + (e.plays or 0)
        houseEdge  = houseEdge  + (e.chipsLost or 0) - (e.chipsWon or 0)
    end
    rednet.send(relayId, {
        type       = "leaderboard_update",
        players    = top,
        totalHands = totalHands,
        houseEdge  = houseEdge,
        timestamp  = textutils.formatTime(os.time(), false),
    }, RELAY_PROTOCOL)
end

-- Queries 

function Leaderboard.getPlayer(username)
    return data[username]
end

function Leaderboard.getAll(sortBy)
    sortBy = sortBy or "chipsWon"
    local list = {}
    for _, entry in pairs(data) do
        list[#list+1] = entry
    end
    table.sort(list, function(a, b)
        return (a[sortBy] or 0) > (b[sortBy] or 0)
    end)
    return list
end

function Leaderboard.getTop(n, sortBy)
    local all = Leaderboard.getAll(sortBy)
    local top = {}
    for i = 1, math.min(n, #all) do
        top[i] = all[i]
    end
    return top
end

function Leaderboard.winRate(username)
    local e = data[username]
    if not e or e.plays == 0 then return "0%" end
    return math.floor((e.wins / e.plays) * 100) .. "%"
end

function Leaderboard.resetPlayer(username)
    data[username] = nil
    save()
end

function Leaderboard.resetAll()
    data = {}
    save()
end

return Leaderboard