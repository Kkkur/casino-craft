-- bank/server/ledger.lua

local ledger = {}

local LOG_FILE = "bank/server/ledger.log"

local function timestamp()
    return os.epoch("utc")
end

local function append(line)
    local f = fs.open(LOG_FILE, "a")
    if not f then return end
    f.writeLine(line)
    f.close()
end

-- format: timestamp | player | action | amount | balance_before | balance_after
function ledger.record(player, action, amount, balBefore, balAfter)
    local line = table.concat({
        tostring(timestamp()),
        tostring(player),
        tostring(action),
        tostring(amount    or ""),
        tostring(balBefore or ""),
        tostring(balAfter  or ""),
    }, " | ")
    append(line)
end

function ledger.recordSecurity(event, detail)
    local line = table.concat({
        tostring(timestamp()),
        "SECURITY",
        tostring(event),
        tostring(detail or ""),
    }, " | ")
    append(line)
end

function ledger.recordReconcile(expected, actual)
    local line = table.concat({
        tostring(timestamp()),
        "RECONCILE",
        "expected=" .. tostring(expected),
        "actual="   .. tostring(actual),
        "delta="    .. tostring(actual - expected),
    }, " | ")
    append(line)
end

-- returns last `limit` lines as a list of strings, newest first
function ledger.tail(limit)
    limit = limit or 20
    if not fs.exists(LOG_FILE) then return {} end
    local f = fs.open(LOG_FILE, "r")
    if not f then return {} end
    local lines = {}
    local line = f.readLine()
    while line do
        table.insert(lines, line)
        line = f.readLine()
    end
    f.close()
    local result = {}
    local start = math.max(1, #lines - limit + 1)
    for i = #lines, start, -1 do
        table.insert(result, lines[i])
    end
    return result
end

return ledger