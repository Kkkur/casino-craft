local PlayerDetector = {}

local IDLE_TIMEOUT = 120

-- Internal state 
local detector       = nil   -- the peripheral
local currentPlayer  = nil   -- username string or nil
local lastActivity   = 0     -- os.clock() of last click

-- Init using the passed name from config
function PlayerDetector.init(detectorName)
    if not detectorName or detectorName == "none" then
        print("[PlayerDetector] Disabled via config.")
        return false
    end

    if peripheral.isPresent(detectorName) then
        detector = peripheral.wrap(detectorName)
    else
        -- Fallback search if the specified network name isn't live right now
        detector = peripheral.find("playerDetector")
    end

    if not detector then
        print("[PlayerDetector] WARNING: Specified peripheral '" .. tostring(detectorName) .. "' not found. Tracking disabled.")
        return false
    end

    print("[PlayerDetector] Ready. Peripheral: " .. peripheral.getName(detector))
    return true
end

-- Current player access 
function PlayerDetector.getCurrentPlayer()
    return currentPlayer
end

function PlayerDetector.clearPlayer()
    currentPlayer = nil
end

function PlayerDetector.isAvailable()
    return detector ~= nil
end

-- Check if player is still nearby 
function PlayerDetector.isNearby(username, range)
    if not detector or not username then return false end
    range = range or 5
    local ok, result = pcall(detector.isPlayerInRange, range, username)
    return ok and result == true
end

-- Get all players currently near the machine
function PlayerDetector.getPlayersNearby(range)
    if not detector then return {} end
    range = range or 5
    local ok, result = pcall(detector.getPlayersInRange, range)
    return (ok and result) or {}
end

-- Gets the single closest player name within range (used by bj_machine's asynchronous listener)
function PlayerDetector.getClosestPlayer(range)
    if not detector then return nil end
    range = range or 5
    
    local ok, players = pcall(detector.getPlayersInRange, range)
    if not ok or not players or #players == 0 then 
        return nil 
    end
    
    -- advancedperipherals returns a list of names. The first index is typically the closest.
    return players[1]
end

-- Listener thread 
function PlayerDetector.listenerThread(shared, onPlayerChange)
    while not (shared and shared.shutdown) do
        local event, username, device = os.pullEvent()

        if event == "playerClick" and type(username) == "string" then
            local old = currentPlayer
            currentPlayer = username
            lastActivity  = os.clock()

            if username ~= old then
                print("[PlayerDetector] Player seated: " .. username)
                if onPlayerChange then
                    pcall(onPlayerChange, username, old)
                end
            end

        elseif event == "timer" or event == "key" or event == "monitor_touch" then
            if currentPlayer
            and not (shared and shared.gameActive)
            and (os.clock() - lastActivity) > IDLE_TIMEOUT then
                local old = currentPlayer
                currentPlayer = nil
                print("[PlayerDetector] Idle timeout — cleared player: " .. old)
                if onPlayerChange then
                    pcall(onPlayerChange, nil, old)
                end
            end
        end
    end
end

return PlayerDetector