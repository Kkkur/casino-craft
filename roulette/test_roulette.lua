-- test_roulette.lua
-- A complete testing runner harness for roulette_ui.lua

local ui = require("roulette_ui")

-- 1. Find and wrap your 5x3 monitor wall 
-- Change "top" to whichever side or network name your monitor uses (e.g., "monitor_0")
local monitorSide = "top" 
local mon = peripheral.wrap(monitorSide)

if not mon then
    error("Could not find a monitor on side: " .. monitorSide .. ". Please edit test_roulette.lua and fix the monitorSide variable!")
end

-- 2. Initialize the UI engine layout
ui.init(mon)

-- 3. Set up a mock virtual player state profile
local gameState = {
    phase = "betting",          -- States: "betting", "spinning", "results"
    playerName = "TesterSteve",
    queueChips = 50,            -- Virtual chip count balance
    bets = {},                  -- Tracks active chips dropped onto table layout grid
    activeSpinNumber = 0,       -- Tracks the current frame position during roll
    winningNumber = nil,
    payout = 0
}

-- Initial display paint run
ui.draw(gameState)
print("Roulette UI Test initialized successfully! Touch your monitor wall to test.")

-- 4. Main execution runtime listener event loop
while true do
    local event, side, x, y = os.pullEvent()
    
    if event == "monitor_touch" then
        -- Run the hit test vector lookup against monitor pixel coordinates
        local action = ui.hitTest(x, y)
        
        if gameState.phase == "betting" then
            if action then
                -- Check if clicked button was an entry on the betting table
                if action:sub(1, 4) == "bet:" then
                    local betTarget = action:sub(5)
                    
                    -- Toggle chip presence on value state inside array map profile
                    if gameState.bets[betTarget] then
                        gameState.bets[betTarget] = nil
                        print("Removed bet from: " .. betTarget)
                    else
                        gameState.bets[betTarget] = true
                        print("Placed bet on: " .. betTarget)
                    end
                    
                -- Handle action firing execution trigger from the SPIN button 
                elseif action == "spin" then
                    gameState.phase = "spinning"
                    print("Wheel spin triggered! Rolling...")
                    
                    -- Pure mechanical slot wheel rotation strip loop emulation simulation
                    -- We step randomly through 25 frames to show the vertical tape wheel rolling live
                    for frame = 1, 25 do
                        gameState.activeSpinNumber = math.random(0, 36)
                        ui.draw(gameState)
                        os.sleep(0.08) -- Controls wheel visual velocity speed frame-rate pacing
                    end
                    
                    -- 5. Lock resolution payout mathematics calculations 
                    gameState.winningNumber = math.random(0, 36)
                    gameState.phase = "results"
                    
                    -- Simple test payout engine checks
                    gameState.payout = 0
                    local winStr = tostring(gameState.winningNumber)
                    
                    -- Straight up single numbers evaluation check match
                    if gameState.bets["num_" .. winStr] or (gameState.winningNumber == 0 and gameState.bets["0"]) then
                        gameState.payout = gameState.payout + 35
                    end
                    
                    -- Quick helper evaluation to test outside grouping payouts
                    local isRed = (winStr == "1" or winStr == "3" or winStr == "5" or winStr == "7" or winStr == "9" or winStr == "12" or winStr == "14" or winStr == "16" or winStr == "18" or winStr == "19" or winStr == "21" or winStr == "23" or winStr == "25" or winStr == "27" or winStr == "30" or winStr == "32" or winStr == "34" or winStr == "36")
                    
                    if gameState.bets["red"] and isRed and gameState.winningNumber ~= 0 then
                        gameState.payout = gameState.payout + 2
                    end
                    if gameState.bets["black"] and (not isRed) and gameState.winningNumber ~= 0 then
                        gameState.payout = gameState.payout + 2
                    end
                    
                    print("Ball landed on: " .. gameState.winningNumber .. " | Payout: " .. gameState.payout)
                    
                -- Handle layout flush clear action request
                elseif action == "clear" then
                    gameState.bets = {}
                    print("Betting layout cleared.")
                end
                
                -- Force refresh frame repaint draw sequence update execution
                ui.draw(gameState)
            end
            
        elseif gameState.phase == "results" then
            -- If screen is displaying historical results payout winner banner frame, 
            -- tapping anywhere clear resets the canvas for the next operational round.
            gameState.phase = "betting"
            gameState.winningNumber = nil
            gameState.payout = 0
            ui.draw(gameState)
            print("Table reset. Awaiting new bets.")
        end
    end
end