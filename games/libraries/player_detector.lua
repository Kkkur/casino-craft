-- player_detector.lua

local PlayerDetector = {}

local IDLE_TIMEOUT = 120

-- Internal state 

local detector       = nil   -- the peripheral
local currentPlayer  = nil   -- username string or nil
local lastActivity   = 0     -- os.clock() of last click

--  Init 

function PlayerDetector.init()
    detector = peripheral.find("playerDetector") or peripheral.find("player_detector")
    if not detector then
        print("[PlayerDetector] WARNING: No player detector found. Names will be 'Unknown'.")
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

-- Optional, check if player is still nearby 
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