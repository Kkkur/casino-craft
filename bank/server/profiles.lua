-- bank/server/profiles.lua

local profiles = {}

local PROFILES_DIR = "bank/server/profiles"

local function normalize(player)
    return player:lower()
end

local function path(player)
    return PROFILES_DIR .. "/" .. player .. ".json"
end

local function ensureDir()
    if not fs.exists(PROFILES_DIR) then
        fs.makeDir(PROFILES_DIR)
    end
end

local function load(player)
    local p = path(player)
    if not fs.exists(p) then return nil end
    local f = fs.open(p, "r")
    if not f then return nil end
    local data = textutils.unserialiseJSON(f.readAll())
    f.close()
    return data
end

local function save(player, data)
    ensureDir()
    local f = fs.open(path(player), "w")
    if not f then return false end
    f.write(textutils.serialiseJSON(data))
    f.close()
    return true
end

-- returns profile, creating it if it does not exist
function profiles.get(player)
    player = normalize(player)
    local data = load(player)
    if data then return data end
    local fresh = { player = player, balance = 0, createdAt = os.epoch("utc") }
    save(player, fresh)
    return fresh
end

function profiles.getBalance(player)
    player = normalize(player)
    local p = profiles.get(player)
    return p.balance
end

function profiles.setBalance(player, amount)
    player = normalize(player)
    local p = profiles.get(player)
    p.balance = amount
    return save(player, p)
end

function profiles.add(player, amount)
    player = normalize(player)
    local p = profiles.get(player)
    p.balance = p.balance + amount
    if save(player, p) then return p.balance end
    return nil
end

-- returns new balance, or nil + "insufficient"
function profiles.remove(player, amount)
    player = normalize(player)
    local p = profiles.get(player)
    if p.balance < amount then return nil, "insufficient" end
    p.balance = p.balance - amount
    if save(player, p) then return p.balance end
    return nil, "error"
end

-- delete a player profile entirely
function profiles.delete(player)
    player = normalize(player)
    local p = path(player)
    if not fs.exists(p) then return false, "not_found" end
    fs.delete(p)
    return true
end

-- wipe all profiles
function profiles.flush()
    ensureDir()
    local list = fs.list(PROFILES_DIR)
    local count = 0
    for _, fname in ipairs(list) do
        if fname:match("%.json$") then
            fs.delete(PROFILES_DIR .. "/" .. fname)
            count = count + 1
        end
    end
    return count
end

-- list all player names, normalized to lowercase
function profiles.list()
    ensureDir()
    local list = fs.list(PROFILES_DIR)
    local seen = {}
    local names = {}
    for _, fname in ipairs(list) do
        if fname:match("%.json$") then
            local name = normalize(fname:gsub("%.json$", ""))
            if not seen[name] then
                seen[name] = true
                table.insert(names, name)
            end
        end
    end
    table.sort(names)
    return names
end

-- returns sum of all player balances
function profiles.sumAll()
    ensureDir()
    local total = 0
    local list  = fs.list(PROFILES_DIR)
    for _, fname in ipairs(list) do
        if fname:match("%.json$") then
            local player = fname:gsub("%.json$", "")
            total = total + profiles.getBalance(player)
        end
    end
    return total
end

-- returns list of { player, balance } sorted by balance descending
function profiles.top(limit)
    ensureDir()
    limit = limit or 10
    local list = fs.list(PROFILES_DIR)
    local entries = {}
    for _, fname in ipairs(list) do
        if fname:match("%.json$") then
            local player = fname:gsub("%.json$", "")
            local bal    = profiles.getBalance(player)
            table.insert(entries, { player = player, balance = bal })
        end
    end
    table.sort(entries, function(a, b) return a.balance > b.balance end)
    local result = {}
    for i = 1, math.min(limit, #entries) do
        result[i] = entries[i]
    end
    return result
end

return profiles