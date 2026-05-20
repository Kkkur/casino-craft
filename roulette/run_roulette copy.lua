local ROULETTE    = require("roulette")
local ROULETTE_UI = require("roulette_ui")

local mon = peripheral.find("monitor")
if not mon then error("Attach a monitor first!") end

ROULETTE_UI.init(mon)
local gameState = ROULETTE.newGame(1000, "CasinoGuest")
local strip = ROULETTE_UI.getWheelStrip()

-- Keep track of where the wheel is currently resting (starts at 0, index 1)
local currentWheelIndex = 1

while true do
    ROULETTE_UI.draw(gameState)

    if gameState.phase == "spinning" then
        -- Find where the target winning number sits on the wheel array
        local targetIdx = 1
        for idx, val in ipairs(strip) do
            if val == gameState.winningNumber then 
                targetIdx = idx 
                break 
            end
        end

        -- Calculate total steps: 2 full revolutions (74 steps) + distance to target number
        local fullRotationsSteps = #strip * 2
        local distanceToTarget = (targetIdx - currentWheelIndex) % #strip
        local totalSteps = fullRotationsSteps + distanceToTarget

        -- Spin the wheel continuously
        for step = 1, totalSteps do
            gameState.spinTick = step
            
            -- Move the index pointer forward along the track
            currentWheelIndex = (currentWheelIndex % #strip) + 1
            
            -- Display the actual roulette number at this current index position
            gameState.activeSpinNumber = strip[currentWheelIndex]
            
            ROULETTE_UI.draw(gameState)

            -- Cinematic Brake Physics: Smooth deceleration during the final 15 slots
            local stepsRemaining = totalSteps - step
            if stepsRemaining <= 15 then
                local brakeFactor = 16 - stepsRemaining
                sleep(0.04 + (brakeFactor * 0.03)) -- Increasingly longer delays
            else
                sleep(0.04) -- Fast, continuous cruising speed
            end
        end

        -- Make absolutely sure the wheel index matches our target mathematically
        currentWheelIndex = targetIdx
        gameState.activeSpinNumber = gameState.winningNumber
        
        -- Distribute chips & render winning states
        ROULETTE.resolveGame(gameState)
        ROULETTE_UI.draw(gameState)
    else
        -- Standard Event Touch Monitoring
        local event, side, x, y = os.pullEvent()
        if event == "monitor_touch" then
            local action = ROULETTE_UI.hitTest(x, y)
            if action then
                if gameState.phase == "results" then
                    ROULETTE.resetTable(gameState)
                elseif action:sub(1, 4) == "bet:" then
                    ROULETTE.handleBetClick(gameState, action:sub(5))
                elseif action == "clear" then
                    ROULETTE.clearBets(gameState)
                elseif action == "spin" then
                    ROULETTE.startSpin(gameState)
                end
            end
        end
    end
end