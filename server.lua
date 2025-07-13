-- TikTok Race FiveM Mod - Fixed Server Side with proper car spawning

local TikTokRaceServer = {}

-- Game state tracking
local gameState = 0 -- 0=IDLE, 3=QUEUE, 6=RACE
local aiMode = false

-- Player tracking - FIXED: Use both systems for compatibility
local registeredPlayers = {} -- New system: {uniqueId = {nickname = "name", playerId = 1}}
local nextPlayerId = 1

-- Legacy player tracking (REQUIRED for client compatibility)
local playerUsernames = {}
local playerRealNames = {}
local playerUniqueIds = {}
local playerCount = 0

-- Configuration
local config = {
    maxPlayers = 100,
    
    -- ORIGINAL CARS FROM C# CODE
    defaultCar = "vigero",        -- C#: WSC.DefaultCar = VehicleHash.Vigero
    paidCar = "adder",           -- C#: WSC.Paid = VehicleHash.Adder  
    vvipCar = "adder",           -- C#: WSC.VVIPCar = VehicleHash.Adder
    
    -- Car mappings from original config.json
    giftCar = "vigilante",       -- For high-value gifts
    vipCar = "zentorno",         -- For VIP level
    roseCar = "adder",           -- For rose gifts
    diamondCar = "entityxf",     -- For diamond gifts
    rocketCar = "vigilante",     -- For rocket/special gifts
    
    boost = {
        like = 1,
        gift = 1, 
        share = 0,
        follow = 20
    }
}

-- Performance optimization
local TriggerClientEvent = TriggerClientEvent
local print = print
local math_max = math.max
local string_lower = string.lower

-- FIXED: Handle user registration for BOTH systems
function handleUser(uniqueId, nickname, userId)
    print("^3[TTR]^7 HandleUser: " .. (nickname or "nil") .. " (@" .. (uniqueId or "nil") .. ") State:" .. gameState)
    
    if gameState ~= 3 then
        print("^1[TTR]^7 Cannot join - not in queue state (current: " .. gameState .. ")")
        return false
    end
    
    if playerCount >= config.maxPlayers then
        print("^1[TTR]^7 Cannot join - race full (" .. playerCount .. "/" .. config.maxPlayers .. ")")
        return false
    end
    
    -- Check if user already exists by uniqueId
    for i = 1, playerCount do
        if playerUniqueIds[i] == uniqueId then
            print("^1[TTR]^7 User already in race: " .. nickname .. " (@" .. uniqueId .. ")")
            return false
        end
    end
    
    -- FIXED: Increment playerCount FIRST, then use it as index
    playerCount = playerCount + 1
    local playerId = playerCount
    
    -- Add to BOTH tracking systems using the same ID
    playerUsernames[playerId] = userId or uniqueId
    playerRealNames[playerId] = nickname
    playerUniqueIds[playerId] = uniqueId
    
    registeredPlayers[uniqueId] = {
        nickname = nickname,
        playerId = playerId  -- Use same ID as legacy system
    }
    
    print("^2[TTR]^7 ✅ Added player: " .. nickname .. " (@" .. uniqueId .. ") [ID: " .. playerId .. "]")
    
    -- Sync to clients with the correct count
    TriggerClientEvent('tiktok_race:updatePlayerCount', -1, playerCount, playerRealNames)
    
    return true
end

-- FIXED: Get user ID for boosts
function getUserId(uniqueId)
    if registeredPlayers[uniqueId] then
        return registeredPlayers[uniqueId].playerId
    end
    
    -- Fallback: search legacy arrays
    for i = 1, playerCount do
        if playerUniqueIds[i] == uniqueId then
            return i
        end
    end
    
    return -1
end

-- Event handlers - FIXED to use proper user management
local eventHandlers = {
    ["like"] = function(data)
        local nickname = data.nickname or "Unknown"
        local uniqueId = data.uniqueId or data.userId or nickname
        local likeCount = data.likeCount or 1
        
        print("^3[TTR]^7 ❤️ " .. nickname .. " (" .. likeCount .. ") State:" .. gameState)
        
        if gameState == 3 then
            -- QUEUE: Join using ORIGINAL DefaultCar (Vigero)
            if handleUser(uniqueId, nickname, data.userId) then
                TriggerClientEvent('tiktok_race:playerJoin', -1, uniqueId, config.defaultCar) -- "vigero" like C#
                print("^2[TTR]^7 ✅ " .. nickname .. " joined via LIKE with " .. config.defaultCar .. "!")
            end
            
        elseif gameState == 6 then
            -- RACE: Boost
            local playerId = getUserId(uniqueId)
            if playerId ~= -1 then
                local boostAmount = likeCount * 3
                TriggerClientEvent('tiktok_race:boostPlayer', -1, playerId, boostAmount)
                print("^2[TTR]^7 🚀 " .. nickname .. " (Player #" .. playerId .. ") +" .. boostAmount)
            else
                print("^1[TTR]^7 " .. nickname .. " not in race - cannot boost")
            end
        end
    end,
    
   ["chat"] = function(data)
    local nickname = data.nickname or "Unknown"
    local uniqueId = data.uniqueId or data.userId or nickname
    local comment = data.comment or ""
    
    print("^3[TTR]^7 💬 " .. nickname .. ": " .. comment)
    
    if string_lower(comment):find("!join") and gameState == 3 then
        if handleUser(uniqueId, nickname, data.userId) then
            TriggerClientEvent('tiktok_race:playerJoin', -1, uniqueId, config.defaultCar) -- "vigero" like C#
            print("^2[TTR]^7 ✅ " .. nickname .. " joined via !join with " .. config.defaultCar .. "!")
        end
    end
end,
    
   ["gift"] = function(data)
                local nickname = data.nickname or "Unknown"
                local uniqueId = data.uniqueId or data.userId or nickname
                local giftName = data.giftName or "Gift"
                local diamondCount = data.diamondCount or 1
                local repeatCount = data.repeatCount or 1
                
                -- Calculate total gift value
                local totalValue = diamondCount * repeatCount
                
                print("^3[TTR]^7 🎁 " .. nickname .. " sent " .. giftName .. " x" .. repeatCount .. " (" .. totalValue .. " total diamonds)")
                
                -- ORIGINAL C# CAR SELECTION LOGIC - FIXED
                local carModel = config.defaultCar -- "vigero" fallback
                local carTier = "Default"
                
                -- Check for specific gift IDs like C# code
                local giftId = data.giftId or 0
                
                if giftId == 8913 then -- Specific gift mentioned in C# 
                    carModel = config.vvipCar -- "adder"
                    carTier = "VVIP SPECIAL"
                elseif giftId == 5827 or giftId == 5879 then -- Other special gifts from C#
                    carModel = config.rocketCar -- "vigilante" 
                    carTier = "ROCKET SPECIAL"
                elseif totalValue >= 1000 then
                    carModel = config.giftCar -- "vigilante" 
                    carTier = "ULTRA VIP"
                elseif totalValue >= 500 then
                    carModel = config.vvipCar -- "adder"
                    carTier = "SUPER VIP"
                elseif totalValue >= 100 then
                    carModel = config.vipCar -- "zentorno"
                    carTier = "HIGH VIP"
                elseif totalValue >= 50 then
                    carModel = config.diamondCar -- "entityxf"
                    carTier = "MID VIP"
                elseif totalValue >= 10 then
                    carModel = config.roseCar -- "adder" 
                    carTier = "VIP"
                else
                    carModel = config.paidCar -- "adder" for any gift (like C# Paid car)
                    carTier = "GIFT VIP"
                end
                
                if gameState == 3 then
                    -- QUEUE STATE: VIP join with original car selection
                    if handleUser(uniqueId, nickname, data.userId) then
                        TriggerClientEvent('tiktok_race:playerJoin', -1, uniqueId, carModel)
                        print("^2[TTR]^7 ✅ " .. nickname .. " joined as " .. carTier .. " with " .. carModel .. "!")
                        
                        -- Announce VIP join
                        TriggerClientEvent('chat:addMessage', -1, {
                            color = {255, 215, 0},
                            multiline = false,
                            args = {"[VIP ENTRY]", uniqueId .. " joined as " .. carTier .. " with " .. carModel .. "!"}
                        })
                    else
                        print("^1[TTR]^7 " .. nickname .. " couldn't join (duplicate or full)")
                    end
                    
                elseif gameState == 6 then
                    -- RACE STATE: Same boost logic 
                    local playerId = getUserId(uniqueId)
                    if playerId ~= -1 then
                        -- BOOST CALCULATION
                        local baseBoost = 0
                        local boostAmount = totalValue
                        
                       
                        
                        TriggerClientEvent('tiktok_race:boostPlayer', -1, playerId, boostAmount)
                        print("^2[TTR]^7 🚀 " .. nickname .. " (Player #" .. playerId .. ") BOOSTED +" .. boostAmount .. " for " .. giftName .. "!")
                        
                        -- Announce boost
                        local boostText = ""
                        if boostAmount >= 75 then
                            boostText = "MEGA BOOST"
                        elseif boostAmount >= 50 then
                            boostText = "SUPER BOOST"
                        elseif boostAmount >= 25 then
                            boostText = "BIG BOOST"
                        else
                            boostText = "BOOST"
                        end
                        
                        TriggerClientEvent('chat:addMessage', -1, {
                            color = {255, 69, 0},
                            multiline = false,
                            args = {"[" .. boostText .. "]", uniqueId .. " got +" .. boostAmount .. " speed from " .. giftName .. "!"}
                        })
                    else
                        print("^1[TTR]^7 " .. nickname .. " not in race - cannot boost")
                    end
                    
                else
                    print("^1[TTR]^7 Gift from " .. nickname .. " received but wrong game state: " .. gameState)
                end
            end,
    ["share"] = function(data)
        local nickname = data.nickname or "Unknown"
        local uniqueId = data.uniqueId or data.userId or nickname
        
        if gameState == 6 then
            local playerId = getUserId(uniqueId)
            if playerId ~= -1 then
                TriggerClientEvent('tiktok_race:boostPlayer', -1, playerId, 25)
                print("^2[TTR]^7 📤 " .. nickname .. " (Player #" .. playerId .. ") +25 share")
            end
        end
    end,
    
    ["follow"] = function(data)
        local nickname = data.nickname or "Unknown"
        local uniqueId = data.uniqueId or data.userId or nickname
        
        if gameState == 6 then
            local playerId = getUserId(uniqueId)
            if playerId ~= -1 then
                TriggerClientEvent('tiktok_race:boostPlayer', -1, playerId, 30)
                print("^2[TTR]^7 👥 " .. nickname .. " (Player #" .. playerId .. ") +30 follow")
            end
        end
    end
}

-- Helper functions
function getTableLength(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

function getGameStateText(state)
    if state == 0 then return "IDLE"
    elseif state == 3 then return "QUEUE"
    elseif state == 5 then return "COUNTDOWN"
    elseif state == 6 then return "RACE"
    else return "STATE_" .. state
    end
end

-- Bridge command handlers
RegisterCommand('ttr_test_like', function(source, args)
    if source == 0 then
        eventHandlers["like"]({
            nickname = args[1] or "TestUser",
            uniqueId = args[2] or ("test_" .. (args[1] or "testuser"):lower()),
            userId = args[2] or ("test_" .. (args[1] or "testuser"):lower()),
            likeCount = tonumber(args[3]) or 1
        })
    end
end, true)

RegisterCommand('ttr_test_join', function(source, args)
    if source == 0 then
        eventHandlers["chat"]({
            nickname = args[1] or "TestUser",
            uniqueId = args[2] or ("test_" .. (args[1] or "testuser"):lower()),
            userId = args[2] or ("test_" .. (args[1] or "testuser"):lower()),
            comment = "!join"
        })
    end
end, true)

RegisterCommand('ttr_test_gift', function(source, args)
    if source == 0 then
        eventHandlers["gift"]({
            nickname = args[1] or "TestUser",
            uniqueId = args[4] or ("test_" .. (args[1] or "testuser"):lower()),
            userId = args[4] or ("test_" .. (args[1] or "testuser"):lower()),
            giftName = args[2] or "Rose",
            diamondCount = tonumber(args[3]) or 1
        })
    end
end, true)

RegisterCommand('ttr_test_gift_tier', function(source, args)
    if source == 0 then
        local tier = args[1] or "1"
        local nickname = args[2] or "GiftTester"
        local uniqueId = "gift_test_" .. nickname:lower()
        
        -- Predefined gift tiers for testing
        local giftTiers = {
            ["1"] = {giftName = "Rose", diamonds = 1, desc = "ENTRY VIP - Sultan"},
            ["2"] = {giftName = "Heart", diamonds = 25, desc = "VIP - Buffalo"}, 
            ["3"] = {giftName = "Sports Car", diamonds = 75, desc = "MID VIP - EntityXF"},
            ["4"] = {giftName = "Diamond Ring", diamonds = 150, desc = "HIGH VIP - Zentorno"},
            ["5"] = {giftName = "Luxury Yacht", diamonds = 750, desc = "SUPER VIP - Adder"},
            ["6"] = {giftName = "Private Jet", diamonds = 1500, desc = "ULTRA VIP - Vigilante"}
        }
        
        local giftData = giftTiers[tier]
        if not giftData then
            print("^1[TTR]^7 Invalid tier! Use 1-6:")
            for k, v in pairs(giftTiers) do
                print("  " .. k .. ": " .. v.giftName .. " (" .. v.diamonds .. " diamonds) - " .. v.desc)
            end
            return
        end
        
        print("^3[TTR]^7 🧪 Testing Tier " .. tier .. ": " .. giftData.desc)
        
        eventHandlers["gift"]({
            nickname = nickname,
            uniqueId = uniqueId,
            userId = uniqueId,
            giftName = giftData.giftName,
            diamondCount = giftData.diamonds,
            repeatCount = 1
        })
    end
end, true)

RegisterCommand('ttr_gift_tiers', function(source)
    if source == 0 then
        print("^3[TTR]^7 ═══ GIFT TIERS ═══")
        print("^2[VIP CARS (Queue State):]")
        print("  1-9 diamonds:    ENTRY VIP - Sultan")
        print("  10-49 diamonds:  VIP - Buffalo") 
        print("  50-99 diamonds:  MID VIP - EntityXF")
        print("  100-499 diamonds: HIGH VIP - Zentorno")
        print("  500-999 diamonds: SUPER VIP - Adder")
        print("  1000+ diamonds:   ULTRA VIP - Vigilante")
        print("")
        print("^2[SPEED BOOSTS (Race State):]")
        print("  1-9 diamonds:    +15 speed")
        print("  10-49 diamonds:  +25 speed")
        print("  50-99 diamonds:  +35 speed") 
        print("  100-499 diamonds: +50 speed")
        print("  500-999 diamonds: +75 speed")
        print("  1000+ diamonds:   +100 speed")
        print("")
        print("^3[Test Commands:]")
        print("  ttr_test_gift_tier [1-6] [name] - Test specific tier")
        print("  ttr_test_gift [name] [giftname] [diamonds] [id] - Custom test")
    end
end, true)

RegisterCommand('ttr_status_detailed', function(source)
    if source == 0 then
        print("^3[TTR]^7 ═══ DETAILED STATUS ═══")
        print("  State: " .. gameState .. " (" .. getGameStateText(gameState) .. ")")
        print("  Players: " .. playerCount)
        print("")
        
        if playerCount > 0 then
            print("^2[Current Players:]")
            for i = 1, playerCount do
                local name = playerRealNames[i] or "Unknown"
                local id = playerUniqueIds[i] or "unknown"
                print("    " .. i .. ": " .. name .. " (@" .. id .. ")")
            end
        end
        
        print("")
        if gameState == 6 then
            print("^2[TTR]^7 🏁 RACE ACTIVE - Send gifts for boosts!")
            print("^3[TTR]^7 💎 Higher diamond value = bigger boost!")
        elseif gameState == 3 then
            print("^2[TTR]^7 🚪 QUEUE OPEN - Send gifts for VIP cars!")
            print("^3[TTR]^7 🏎️ Higher diamond value = better car!")
        end
        
        print("^3[TTR]^7 Type 'ttr_gift_tiers' to see all tiers")
    end
end, true)

RegisterCommand('ttr_test_scenario', function(source, args)
    if source == 0 then
        local scenario = args[1] or "help"
        
        if scenario == "queue_fill" then
            print("^3[TTR]^7 🧪 Testing queue with different gift tiers...")
            Wait(100)
            ExecuteCommand('ttr_reset_queue')
            Wait(500)
            ExecuteCommand('ttr_test_gift_tier 1 "Budget_Player"')
            Wait(200) 
            ExecuteCommand('ttr_test_gift_tier 3 "Mid_Spender"')
            Wait(200)
            ExecuteCommand('ttr_test_gift_tier 6 "Big_Spender"')
            print("^2[TTR]^7 ✅ Queue filled with different VIP tiers!")
            
        elseif scenario == "race_boosts" then
            print("^3[TTR]^7 🧪 Testing race boosts...")
            ExecuteCommand('ttr_force_race')
            Wait(500)
            ExecuteCommand('ttr_test_gift_tier 2 "Budget_Player"')
            Wait(200)
            ExecuteCommand('ttr_test_gift_tier 4 "Mid_Spender"') 
            Wait(200)
            ExecuteCommand('ttr_test_gift_tier 6 "Big_Spender"')
            print("^2[TTR]^7 ✅ Different boost tiers tested!")
            
        else
            print("^3[TTR]^7 ═══ TEST SCENARIOS ═══")
            print("  ttr_test_scenario queue_fill  - Fill queue with VIP tiers")
            print("  ttr_test_scenario race_boosts - Test different boost levels")
            print("  ttr_gift_tiers                - Show all gift tiers")
            print("  ttr_test_gift_tier [1-6] [name] - Test specific tier")
        end
    end
end, true)

RegisterCommand('ttr_simulate_gifts', function(source, args)
    if source == 0 then
        local scenario = args[1] or "help"
        
        if scenario == "small_spender" then
            print("^3[TTR]^7 🧪 Simulating small spender...")
            ExecuteCommand('ttr_test_gift_manual "SmallSpender" "Rose" 1 3 "small123"')        -- 3 roses = 3 diamonds
            
        elseif scenario == "medium_spender" then  
            print("^3[TTR]^7 🧪 Simulating medium spender...")
            ExecuteCommand('ttr_test_gift_manual "MediumSpender" "Heart" 5 10 "medium123"')    -- 10 hearts = 50 diamonds
            
        elseif scenario == "big_spender" then
            print("^3[TTR]^7 🧪 Simulating big spender...")
            ExecuteCommand('ttr_test_gift_manual "BigSpender" "SportsCar" 25 8 "big123"')      -- 8 sports cars = 200 diamonds
            
        elseif scenario == "whale" then
            print("^3[TTR]^7 🧪 Simulating whale...")
            ExecuteCommand('ttr_test_gift_manual "Whale" "PrivateJet" 500 3 "whale123"')       -- 3 private jets = 1500 diamonds
            
        elseif scenario == "gift_combo" then
            print("^3[TTR]^7 🧪 Simulating gift combo from same user...")
            Wait(100)
            ExecuteCommand('ttr_test_gift_manual "ComboUser" "Rose" 1 5 "combo123"')           -- 5 diamonds
            Wait(500)
            ExecuteCommand('ttr_test_gift_manual "ComboUser" "Heart" 10 2 "combo123"')         -- +20 diamonds  
            Wait(500) 
            ExecuteCommand('ttr_test_gift_manual "ComboUser" "Diamond" 50 1 "combo123"')       -- +50 diamonds
            print("^2[TTR]^7 ✅ Combo complete! Same user sent multiple gifts")
            
        else
            print("^3[TTR]^7 ═══ GIFT SCENARIOS ═══")
            print("  ttr_simulate_gifts small_spender   - 3 diamonds (Entry VIP)")
            print("  ttr_simulate_gifts medium_spender  - 50 diamonds (Mid VIP)")
            print("  ttr_simulate_gifts big_spender     - 200 diamonds (High VIP)")
            print("  ttr_simulate_gifts whale           - 1500 diamonds (Ultra VIP)")
            print("  ttr_simulate_gifts gift_combo      - Multiple gifts from same user")
            print("")
            print("^3[Manual Commands:]")
            print("  ttr_test_gift_manual [name] [gift] [diamonds] [repeat] [id]")
            print("  ttr_test_gift_enhanced [name] [gift] [diamonds] [repeat] [id]")
        end
    end
end, true)

RegisterCommand('ttr_test_gift_manual', function(source, args)
    if source == 0 then
        local nickname = args[1] or "TestUser"
        local giftName = args[2] or "Rose"
        local diamondCount = tonumber(args[3]) or 1
        local repeatCount = tonumber(args[4]) or 1  -- NEW: Support repeat count
        local uniqueId = args[5] or ("test_" .. nickname:lower())
        
        print("^3[TTR]^7 🧪 Manual Gift Test: " .. giftName .. " x" .. repeatCount .. " (" .. (diamondCount * repeatCount) .. " total)")
        
        eventHandlers["gift"]({
            nickname = nickname,
            uniqueId = uniqueId,
            userId = uniqueId,
            giftName = giftName,
            diamondCount = diamondCount,
            repeatCount = repeatCount
        })
    end
end, true)

RegisterCommand('ttr_test_gift_enhanced', function(source, args)
    if source == 0 then
        local nickname = args[1] or "TestUser"
        local giftName = args[2] or "Rose"
        local diamondCount = tonumber(args[3]) or 1
        local repeatCount = tonumber(args[4]) or 1
        local uniqueId = args[5] or ("test_" .. nickname:lower())
        
        -- Calculate total value
        local totalValue = diamondCount * repeatCount
        
        print("^3[TTR]^7 🎁 Enhanced Gift: " .. nickname .. " sent " .. giftName .. " x" .. repeatCount .. " (" .. totalValue .. " total diamonds)")
        
        -- Process using the enhanced gift handler
        eventHandlers["gift"]({
            nickname = nickname,
            uniqueId = uniqueId,
            userId = uniqueId,
            giftName = giftName,
            diamondCount = diamondCount,
            repeatCount = repeatCount
        })
    end
end, true)
RegisterCommand('ttr_test_boost', function(source, args)
    if source == 0 then
        local eventType = args[3] or "share"
        eventHandlers[eventType]({
            nickname = args[1] or "TestUser",
            uniqueId = args[2] or ("test_" .. (args[1] or "testuser"):lower()),
            userId = args[2] or ("test_" .. (args[1] or "testuser"):lower())
        })
    end
end, true)

-- Control commands
RegisterCommand('ttr_reset', function(source)
    if source == 0 then
        gameState = 0
        registeredPlayers = {}
        nextPlayerId = 1
        -- RESET LEGACY ARRAYS TOO
        playerCount = 0
        playerUsernames = {}
        playerRealNames = {}
        playerUniqueIds = {}
        
        TriggerClientEvent('tiktok_race:resetRace', -1)
        print("^2[TTR]^7 ✅ Full reset!")
    end
end, true)

RegisterCommand('ttr_reset_queue', function(source)
    if source == 0 then
        gameState = 3
        registeredPlayers = {}
        nextPlayerId = 1
        -- RESET LEGACY ARRAYS TOO
        playerCount = 0
        playerUsernames = {}
        playerRealNames = {}
        playerUniqueIds = {}
        
        TriggerClientEvent('tiktok_race:resetToQueue', -1)
        print("^2[TTR]^7 ✅ Queue reset!")
    end
end, true)

RegisterCommand('ttr_force_race', function(source)
    if source == 0 then
        gameState = 6
        TriggerClientEvent('tiktok_race:forceRaceState', -1)
        print("^2[TTR]^7 🏁 RACE FORCED!")
    end
end, true)

RegisterCommand('ttr_status', function(source)
    if source == 0 then
        print("^3[TTR]^7 ═══ STATUS ═══")
        print("  State: " .. gameState .. " (" .. getGameStateText(gameState) .. ")")
        print("  Players: " .. playerCount .. " (Legacy) | " .. getTableLength(registeredPlayers) .. " (New)")
        
        -- Show legacy player list (what client uses)
        for i = 1, math.min(playerCount, 5) do
            print("    " .. i .. ": " .. (playerRealNames[i] or "Unknown") .. " (@" .. (playerUniqueIds[i] or "unknown") .. ")")
        end
        
        if playerCount > 5 then
            print("    ... and " .. (playerCount - 5) .. " more")
        end
        
        if gameState == 6 then
            print("^2[TTR]^7 🏁 RACE ACTIVE")
        elseif gameState == 3 then
            print("^2[TTR]^7 🚪 QUEUE OPEN")
        end
    end
end, true)

-- Game state management
RegisterNetEvent('tiktok_race:setGameState')
AddEventHandler('tiktok_race:setGameState', function(newState)
    gameState = newState
    print("^3[TTR]^7 State changed: " .. gameState .. " (" .. getGameStateText(gameState) .. ")")
    
    if newState == 3 then
        -- QUEUE: Reset BOTH player systems completely
        print("^3[TTR]^7 🔄 Resetting all player data...")
        
        -- Reset new system
        registeredPlayers = {}
        nextPlayerId = 1
        
        -- Reset legacy system
        playerCount = 0
        playerUsernames = {}
        playerRealNames = {}
        playerUniqueIds = {}
        
        print("^2[TTR]^7 ✅ Queue opened - ready for players!")
        
    elseif newState == 5 then
        print("^3[TTR]^7 ⏰ Countdown started - no more joins!")
        
    elseif newState == 6 then
        print("^2[TTR]^7 🏁 RACE STARTED!")
        print("^2[TTR]^7 Players in race: " .. playerCount)
        
        -- Show all players
        for i = 1, playerCount do
            if playerRealNames[i] then
                print("   " .. i .. ": " .. playerRealNames[i] .. " (@" .. (playerUniqueIds[i] or "unknown") .. ")")
            end
        end
        
        if playerCount == 0 then
            print("^1[TTR]^7 ⚠️ WARNING: Race started with 0 players!")
        end
    end
end)

-- Required event handlers for client compatibility
RegisterNetEvent('tiktok_race:requestGameState')
AddEventHandler('tiktok_race:requestGameState', function()
    TriggerClientEvent('tiktok_race:syncGameState', source, gameState)
end)

RegisterNetEvent('tiktok_race:playerWin')
AddEventHandler('tiktok_race:playerWin', function(playerId, position)
    if playerRealNames[playerId] then
        print("^2[TTR]^7 " .. playerRealNames[playerId] .. " finished position " .. position)
    end
end)

-- Legacy exports for compatibility
exports('handleTikFinityEvent', function(eventData)
    if eventData and eventData.event and eventData.data then
        if eventHandlers[eventData.event] then
            eventHandlers[eventData.event](eventData.data)
        end
    end
end)

-- Initialization
CreateThread(function()
    Wait(2000)
    
    print("^2[TTR]^7 ══════════════════════")
    print("^2[TTR]^7 🚀 TIKTOK RACE READY!")
    print("^2[TTR]^7 ══════════════════════")
    print("^3[TTR]^7 📁 File-based event system")
    print("^3[TTR]^7 🚫 NO RCON TIMEOUTS!")
    print("^3[TTR]^7 ⚡ Ultra-fast processing")
    print("^3[TTR]^7")
    print("^3[TTR]^7 🎮 File Commands:")
    print("^3[TTR]^7   ttr_file_status  - Processor status")
    print("^3[TTR]^7   ttr_file_test    - Test file access")
    print("^3[TTR]^7   ttr_file_info    - Show file paths")
    print("^3[TTR]^7   ttr_force_process - Force process file")
    print("^3[TTR]^7")
    print("^3[TTR]^7 🎮 Game Commands:")
    print("^3[TTR]^7   ttr_status       - Game status")
    print("^3[TTR]^7   ttr_reset_queue  - Reset to queue")
    print("^2[TTR]^7 ══════════════════════")
    
    -- Initialize file processor
    local success = initializeFileProcessor()
    if not success then
        print("^1[TTR]^7 ⚠️ File processor failed to initialize")
        print("^3[TTR]^7 💡 Run 'ttr_file_info' for setup instructions")
    end
end)

RegisterCommand('ttr_help', function(source)
    if source == 0 then
        print("^3[TTR]^7 ═══ COMMANDS ═══")
        print("  ttr_reset_queue    - Open queue")
        print("  ttr_force_race     - Start race")
        print("  ttr_reset          - Full reset")
        print("  ttr_status         - Show status")
        print("  ttr_test_like [name] [id] [count]")
        print("  ttr_test_join [name] [id]")
        print("  ttr_test_gift [name] [gift] [diamonds] [id]")
    end
end, true)

local fileEventProcessor = {
    -- OPTION 1: Inside FiveM Resource (Recommended)
    -- Make sure the 'events' folder exists in your tiktok-race resource
    eventFile = GetResourcePath(GetCurrentResourceName()) .. "/events/events_queue.json",
    processedFile = GetResourcePath(GetCurrentResourceName()) .. "/events/events_processed.json",
    statsFile = GetResourcePath(GetCurrentResourceName()) .. "/events/bridge_stats.json",
    
    -- OPTION 2: Shared Directory (Alternative)
    -- Uncomment these and comment out Option 1 if you prefer a shared folder
    -- Windows:
    -- eventFile = "C:/TikTokRaceEvents/events_queue.json",
    -- processedFile = "C:/TikTokRaceEvents/events_processed.json",
    -- statsFile = "C:/TikTokRaceEvents/bridge_stats.json",
    
    -- Linux/Mac:
    -- eventFile = "/tmp/tiktok-race-events/events_queue.json",
    -- processedFile = "/tmp/tiktok-race-events/events_processed.json",
    -- statsFile = "/tmp/tiktok-race-events/bridge_stats.json",
    
    -- Internal variables
    lastProcessedTime = 0,
    processedEventIds = {},
    isProcessing = false,
    stats = {
        eventsProcessed = 0,
        duplicatesSkipped = 0,
        errorsEncountered = 0,
        lastProcessTime = 0,
        fileNotFound = 0,
        fileReadErrors = 0
    }
}



-- Initialize file processor with path validation
function initializeFileProcessor()
    print("^3[TTR]^7 📁 Initializing file-based event processor...")
    print("^3[TTR]^7    Events: " .. fileEventProcessor.eventFile)
    print("^3[TTR]^7    Processed: " .. fileEventProcessor.processedFile)
    print("^3[TTR]^7    Stats: " .. fileEventProcessor.statsFile)
    
    -- Test file access
    local testSuccess = testFileAccess()
    if not testSuccess then
        print("^1[TTR]^7 ❌ File access test failed!")
        print("^1[TTR]^7 💡 Check if the events folder exists and has proper permissions")
        return false
    end
    
    -- Create processing thread
    CreateThread(function()
        while true do
            if not fileEventProcessor.isProcessing then
                processEventFile()
            end
            Wait(100) -- Check every 100ms
        end
    end)
    
    -- Stats thread
    CreateThread(function()
        while true do
            Wait(30000) -- Every 30 seconds
            printFileProcessorStats()
        end
    end)
    
    print("^2[TTR]^7 ✅ File processor ready!")
    return true
end

-- Test file access
function testFileAccess()
    -- Try to read the event file (it's ok if it doesn't exist)
    local file = io.open(fileEventProcessor.eventFile, "r")
    if file then
        file:close()
        print("^2[TTR]^7 ✅ Event file accessible")
        return true
    else
        -- File doesn't exist, try to create directory structure
        print("^3[TTR]^7 ⚠️ Event file not found, this is normal on first run")
        return true -- This is ok for first run
    end
end

-- Print file processor statistics
function printFileProcessorStats()
    local stats = fileEventProcessor.stats
    print("^3[TTR]^7 📊 File Processor Stats:")
    print("  Processed: " .. stats.eventsProcessed)
    print("  Duplicates: " .. stats.duplicatesSkipped) 
    print("  Errors: " .. stats.errorsEncountered)
    print("  File Not Found: " .. stats.fileNotFound)
    print("  Read Errors: " .. stats.fileReadErrors)
end

-- Process events from file
function processEventFile()
    fileEventProcessor.isProcessing = true
    
    -- Try to read the events file
    local file = io.open(fileEventProcessor.eventFile, "r")
    if not file then
        fileEventProcessor.stats.fileNotFound = fileEventProcessor.stats.fileNotFound + 1
        fileEventProcessor.isProcessing = false
        return
    end
    
    local content = file:read("*all")
    file:close()
    
    if not content or content == "" then
        fileEventProcessor.isProcessing = false
        return
    end
    
    -- Parse JSON
    local success, data = pcall(json.decode, content)
    if not success or not data or not data.events then
        fileEventProcessor.stats.fileReadErrors = fileEventProcessor.stats.fileReadErrors + 1
        fileEventProcessor.isProcessing = false
        return
    end
    
    local events = data.events
    local processedCount = 0
    local skippedCount = 0
    
    -- Process each event
    for _, event in ipairs(events) do
        if event.id and event.timestamp and event.command and event.command ~= "" then
            -- Check if already processed
            if not fileEventProcessor.processedEventIds[event.id] then
                -- Process the event
                local success = processFileEvent(event)
                if success then
                    fileEventProcessor.processedEventIds[event.id] = true
                    processedCount = processedCount + 1
                    fileEventProcessor.stats.eventsProcessed = fileEventProcessor.stats.eventsProcessed + 1
                else
                    fileEventProcessor.stats.errorsEncountered = fileEventProcessor.stats.errorsEncountered + 1
                end
            else
                skippedCount = skippedCount + 1
                fileEventProcessor.stats.duplicatesSkipped = fileEventProcessor.stats.duplicatesSkipped + 1
            end
        end
    end
    
    if processedCount > 0 then
        print("^2[TTR]^7 📝 Processed " .. processedCount .. " new events (skipped " .. skippedCount .. " duplicates)")
        fileEventProcessor.stats.lastProcessTime = GetGameTimer()
    end
    
    fileEventProcessor.isProcessing = false
end

-- Process individual event from file
function processFileEvent(event)
    if not event.command or event.command == "" then
        return false
    end
    
    -- Parse the command and execute directly
    local parts = {}
    for part in event.command:gmatch("[^%s]+") do
        -- Remove quotes
        local cleanPart = part:gsub('"', '')
        table.insert(parts, cleanPart)
    end
    
    if #parts == 0 then
        return false
    end
    
    local command = parts[1]
    local args = {}
    for i = 2, #parts do
        table.insert(args, parts[i])
    end
    
    -- Execute the appropriate command
    if command == "ttr_test_like" then
        if #args >= 3 then
            eventHandlers["like"]({
                nickname = args[1],
                uniqueId = args[2],
                userId = args[2],
                likeCount = tonumber(args[3]) or 1
            })
            return true
        end
        
    elseif command == "ttr_test_join" then
        if #args >= 2 then
            eventHandlers["chat"]({
                nickname = args[1],
                uniqueId = args[2],
                userId = args[2],
                comment = "!join"
            })
            return true
        end
        
    elseif command == "ttr_test_gift_enhanced" then
        if #args >= 5 then
            eventHandlers["gift"]({
                nickname = args[1],
                uniqueId = args[5],
                userId = args[5],
                giftName = args[2],
                diamondCount = tonumber(args[3]) or 1,
                repeatCount = tonumber(args[4]) or 1
            })
            return true
        end
        
    elseif command == "ttr_test_boost" then
        if #args >= 3 then
            local eventType = args[3] -- share or follow
            if eventHandlers[eventType] then
                eventHandlers[eventType]({
                    nickname = args[1],
                    uniqueId = args[2],
                    userId = args[2]
                })
                return true
            end
        end
    end
    
    return false
end

-- File processor commands
RegisterCommand('ttr_file_status', function(source)
    if source == 0 then
        local stats = fileEventProcessor.stats
        print("^3[TTR]^7 ═══ FILE PROCESSOR STATUS ═══")
        print("  Event File: " .. fileEventProcessor.eventFile)
        print("  Processed File: " .. fileEventProcessor.processedFile)
        print("  Stats File: " .. fileEventProcessor.statsFile)
        print("  Events Processed: " .. stats.eventsProcessed)
        print("  Duplicates Skipped: " .. stats.duplicatesSkipped)
        print("  Errors: " .. stats.errorsEncountered)
        print("  File Not Found: " .. stats.fileNotFound)
        print("  Read Errors: " .. stats.fileReadErrors)
        print("  Processing: " .. (fileEventProcessor.isProcessing and "YES" or "NO"))
        print("  Cached IDs: " .. getTableLength(fileEventProcessor.processedEventIds))
        print("  Last Process: " .. (stats.lastProcessTime > 0 and ((GetGameTimer() - stats.lastProcessTime) / 1000) .. "s ago" or "Never"))
    end
end, true)

RegisterCommand('ttr_file_test', function(source)
    if source == 0 then
        print("^3[TTR]^7 🧪 Testing file access...")
        local success = testFileAccess()
        if success then
            print("^2[TTR]^7 ✅ File access test passed")
        else
            print("^1[TTR]^7 ❌ File access test failed")
            print("^3[TTR]^7 💡 Make sure the events folder exists:")
            print("^3[TTR]^7    mkdir " .. GetResourcePath(GetCurrentResourceName()) .. "/events")
        end
    end
end, true)

RegisterCommand('ttr_clear_cache', function(source)
    if source == 0 then
        local count = getTableLength(fileEventProcessor.processedEventIds)
        fileEventProcessor.processedEventIds = {}
        print("^2[TTR]^7 ✅ Cleared " .. count .. " processed event IDs from cache")
    end
end, true)

RegisterCommand('ttr_force_process', function(source)
    if source == 0 then
        print("^3[TTR]^7 🔄 Force processing event file...")
        CreateThread(function()
            processEventFile()
        end)
    end
end, true)

RegisterCommand('ttr_file_info', function(source)
    if source == 0 then
        print("^3[TTR]^7 ═══ FILE CONFIGURATION ═══")
        print("  Resource Path: " .. GetResourcePath(GetCurrentResourceName()))
        print("  Event File: " .. fileEventProcessor.eventFile)
        print("  Processed File: " .. fileEventProcessor.processedFile)
        print("  Stats File: " .. fileEventProcessor.statsFile)
        print("")
        print("^3[TTR]^7 📂 To setup files manually:")
        print("  1. Create folder: mkdir " .. GetResourcePath(GetCurrentResourceName()) .. "/events")
        print("  2. Bridge will create JSON files automatically")
        print("  3. Run: ttr_file_test")
    end
end, true)