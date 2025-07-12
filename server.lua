-- TikTok Race FiveM Mod - Server Side
-- Handles TikTok WebSocket integration and player management

local TikTokRaceServer = {}

-- WebSocket connection variables
local websocket = nil
local websocketConnected = false
local eventQueue = {}
local playerUsernames = {}
local playerRealNames = {}
local playerUniqueIds = {}
local playerCount = -1

-- Game state tracking
local gameState = 0 -- 0=IDLE, 3=QUEUE, 6=RACE
local aiMode = false

-- Configuration
local config = {
    websocketUrl = "ws://localhost:21213",
    maxPlayers = 100,
    defaultCar = "hermes",
    giftCars = {
        ["rose"] = "vigilante",
        ["gift1"] = "adder",
        ["gift2"] = "zentorno"
    }
}




-- Event handlers for TikFinity events
local eventHandlers = {
    ["like"] = function(data)
        print("^3[TikTok Race]^7 Received like event from: " .. (data.nickname or "Unknown") .. " (Like count: " .. (data.likeCount or 0) .. ")")
        
        if gameState == 3 and handleUser(data.uniqueId, data.nickname, data.userId) then
            -- Player joins race on like during queue
            TriggerClientEvent('tiktok_race:playerJoin', -1, data.nickname, config.defaultCar)
            print("^2[TikTok Race]^7 " .. data.nickname .. " joined via LIKE!")
        elseif gameState == 6 and not aiMode then
            -- Boost player during race
            local playerId = getUserId(data.uniqueId)
            if playerId ~= -1 then
                local boostAmount = math.max(data.likeCount or 1, 1) * 2 -- Scale with like count
                TriggerClientEvent('tiktok_race:boostPlayer', -1, playerId, boostAmount)
                print("^2[TikTok Race]^7 Boosted " .. data.nickname .. " by " .. boostAmount .. " for liking!")
            end
        end
    end,
    
    ["chat"] = function(data)
        print("^3[TikTok Race]^7 Chat from " .. (data.nickname or "Unknown") .. ": " .. (data.comment or ""))
        
        if data.comment and string.lower(data.comment):find("!join") then
            if gameState == 3 and handleUser(data.uniqueId, data.nickname, data.userId) then
                -- Player joins race with !join command
                TriggerClientEvent('tiktok_race:playerJoin', -1, data.nickname, config.defaultCar)
                print("^2[TikTok Race]^7 " .. data.nickname .. " joined via !join command!")
            end
        end
    end,
    
    ["gift"] = function(data)
        local giftName = data.giftName or data.originalName or "Unknown Gift"
        local repeatCount = data.repeatCount or 1
        local diamondCount = data.diamondCount or 1
        
        print("^3[TikTok Race]^7 Gift received from: " .. (data.nickname or "Unknown") .. " - " .. giftName .. " x" .. repeatCount .. " (Diamonds: " .. diamondCount .. ")")
        
        -- Determine car based on gift value/name
        local carModel = config.defaultCar
        if diamondCount >= 100 or string.lower(giftName):find("rocket") then
            carModel = "vigilante" -- Super expensive gift = super car
        elseif diamondCount >= 50 or string.lower(giftName):find("sports") then
            carModel = "zentorno" -- Expensive gift = sports car
        elseif diamondCount >= 10 or string.lower(giftName):find("rose") then
            carModel = "adder" -- Medium gift = luxury car
        else
            carModel = "buffalo" -- Small gift = better than default
        end
        
        if gameState == 3 and handleUser(data.uniqueId, data.nickname, data.userId) then
            -- VIP entry with special car based on gift value
            TriggerClientEvent('tiktok_race:playerJoin', -1, data.nickname, carModel)
            print("^2[TikTok Race]^7 " .. data.nickname .. " joined as VIP with " .. carModel .. " for sending " .. giftName .. "!")
        elseif gameState == 6 and not aiMode then
            -- Big boost for gifts based on diamond value and repeat count
            local playerId = getUserId(data.uniqueId)
            if playerId ~= -1 then
                local boostAmount = (diamondCount * repeatCount) + 10 -- Scale boost with gift value
                TriggerClientEvent('tiktok_race:boostPlayer', -1, playerId, boostAmount)
                print("^2[TikTok Race]^7 Boosted " .. data.nickname .. " by " .. boostAmount .. " for " .. giftName .. "!")
            end
        end
    end
}

-- Initialize WebSocket connection to TikFinity
function initializeWebSocket()
    print("^3[TikTok Race]^7 Initializing TikFinity WebSocket connection...")
    
    -- TikFinity WebSocket connection (you'll need to implement actual WebSocket client)
    -- For now, we'll set up the event handlers for when TikFinity sends events
    websocketConnected = true
    TriggerClientEvent('tiktok_race:websocketStatus', -1, websocketConnected)
    
    print("^2[TikTok Race]^7 Ready to receive TikFinity events!")
    print("^3[TikTok Race]^7 Make sure TikFinity is running and connected to: ws://localhost:21213")
    
    -- Notify all clients about connection status
    CreateThread(function()
        while true do
            Wait(5000) -- Update every 5 seconds
            TriggerClientEvent('tiktok_race:websocketStatus', -1, true)
        end
    end)
end

-- TikFinity Event Handler - Call this function when you receive WebSocket data from TikFinity
function handleTikFinityEvent(eventData)
    -- Handle both string and table inputs
    local parsedData = eventData
    if type(eventData) == "string" then
        parsedData = json.decode(eventData)
    end
    
    print("^3[TikTok Race]^7 Received TikFinity event: " .. (parsedData.event or "unknown"))
    
    local eventType = parsedData.event
    local data = parsedData.data
    
    if eventType and data and eventHandlers[eventType] then
        eventHandlers[eventType](data)
    else
        print("^1[TikTok Race]^7 Unknown or malformed TikFinity event: " .. tostring(eventType))
    end
end

-- Alternative function name for backwards compatibility
function processTikTokEvent(eventData)
    return handleTikFinityEvent(eventData)
end

-- Export these functions so TikFinity/other resources can call them
exports('handleTikFinityEvent', handleTikFinityEvent)
exports('processTikTokEvent', processTikTokEvent)

-- HTTP endpoint for receiving TikFinity events
if GetConvar('tiktok_race_http', 'false') == 'true' then
    -- Enable HTTP endpoint
    SetHttpHandler(function(request, response)
        local path = request.path
        local method = request.method
        
        if path == '/tiktok-race/event' and method == 'POST' then
            local success, eventData = pcall(json.decode, request.body)
            if success and eventData then
                handleTikFinityEvent(eventData)
                response.writeHead(200, {['Content-Type'] = 'application/json'})
                response.send(json.encode({status = 'success'}))
            else
                response.writeHead(400, {['Content-Type'] = 'application/json'})
                response.send(json.encode({error = 'Invalid JSON'}))
            end
        else
            response.writeHead(404)
            response.send('Not Found')
        end
    end)
    
    print("^2[TikTok Race]^7 HTTP endpoint enabled: /tiktok-race/event")
end

-- Handle TikFinity user registration with proper data structure
function handleUser(uniqueId, nickname, userId)
    if gameState ~= 3 then
        print("^1[TikTok Race]^7 Cannot join - race not in queue state (current state: " .. gameState .. ")")
        return false
    end
    
    -- Check if user already exists by uniqueId (TikTok username)
    for i = 1, playerCount do
        if playerUniqueIds[i] == uniqueId then
            print("^1[TikTok Race]^7 User already in race: " .. nickname .. " (@" .. uniqueId .. ")")
            return false
        end
    end
    
    -- Add new user
    playerCount = playerCount + 1
    playerUsernames[playerCount] = userId -- TikTok user ID
    playerRealNames[playerCount] = nickname -- Display name
    playerUniqueIds[playerCount] = uniqueId -- TikTok username (@handle)
    
    print("^2[TikTok Race]^7 Added player: " .. nickname .. " (@" .. uniqueId .. ") [ID: " .. playerCount .. "]")
    
    -- Sync player count to all clients
    TriggerClientEvent('tiktok_race:updatePlayerCount', -1, playerCount, playerRealNames)
    
    return true
end

-- Get user ID by unique identifier (TikTok username)
function getUserId(uniqueId)
    for i = 1, playerCount do
        if playerUniqueIds[i] == uniqueId then
            return i
        end
    end
    return -1
end

-- Simulate receiving TikTok events (replace with actual WebSocket implementation)
function simulateTikTokEvent(eventType, data)
    if eventHandlers[eventType] then
        eventHandlers[eventType](data)
    else
        print("^1[TikTok Race]^7 Unknown event type: " .. eventType)
    end
end

-- Track game state changes from client
RegisterNetEvent('tiktok_race:setGameState')
AddEventHandler('tiktok_race:setGameState', function(newState)
    local source = source
    gameState = newState
    print("^3[TikTok Race]^7 Game state changed to: " .. newState .. " by player " .. source)
    
    if newState == 3 then
        -- Queue started - reset player tracking
        playerCount = 0
        playerUsernames = {}
        playerRealNames = {}
        playerUniqueIds = {}
        print("^2[TikTok Race]^7 Queue opened - ready for players!")
    elseif newState == 6 then
        print("^2[TikTok Race]^7 Race started with " .. playerCount .. " players!")
    end
end)

-- Auto-sync game state when client requests it
RegisterNetEvent('tiktok_race:requestGameState')
AddEventHandler('tiktok_race:requestGameState', function()
    local source = source
    TriggerClientEvent('tiktok_race:syncGameState', source, gameState)
end)

RegisterNetEvent('tiktok_race:setAiMode')
AddEventHandler('tiktok_race:setAiMode', function(enabled)
    aiMode = enabled
    print("^3[TikTok Race]^7 AI Mode: " .. (enabled and "Enabled" or "Disabled"))
end)

RegisterNetEvent('tiktok_race:playerWin')
AddEventHandler('tiktok_race:playerWin', function(playerId, position)
    if playerRealNames[playerId] then
        print("^2[TikTok Race]^7 " .. playerRealNames[playerId] .. " finished in position " .. position)
        
        -- Here you could send the win data to an external API
        -- sendWinToAPI(playerRealNames[playerId], playerUsernames[playerId], position)
    end
end)

-- Admin commands for testing with TikFinity format
RegisterCommand('ttr_test_like', function(source, args)
    if source == 0 then -- Console only
        local nickname = args[1] or "TestUser"
        local uniqueId = args[2] or ("test_" .. nickname:lower())
        handleTikFinityEvent({
            event = "like",
            data = {
                likeCount = tonumber(args[3]) or 1,
                totalLikeCount = 1000,
                userId = "test_" ..uniqueId,
                uniqueId = uniqueId,
                nickname = nickname,
                profilePictureUrl = "https://example.com/avatar.jpg"
            }
        })
    end
end, true)

RegisterCommand('ttr_test_join', function(source, args)
    if source == 0 then -- Console only
        local nickname = args[1] or "TestUser"
        local uniqueId = args[2] or ("test_" .. nickname:lower())
        handleTikFinityEvent({
            event = "chat",
            data = {
                comment = "!join",
                userId = "test_" .. uniqueId,
                uniqueId = uniqueId,
                nickname = nickname,
                profilePictureUrl = "https://example.com/avatar.jpg"
            }
        })
    end
end, true)

RegisterCommand('ttr_test_gift', function(source, args)
    if source == 0 then -- Console only
        local nickname = args[1] or "TestUser"
        local giftName = args[2] or "Rose"
        local diamondCount = tonumber(args[3]) or 1
        local uniqueId = args[4] or ("test_" .. nickname:lower())
        
        handleTikFinityEvent({
            event = "gift",
            data = {
                giftId = 5655,
                repeatCount = 1,
                userId = "test_" .. uniqueId,
                uniqueId = uniqueId,
                nickname = nickname,
                giftName = giftName,
                originalName = giftName,
                diamondCount = diamondCount,
                giftType = 1,
                profilePictureUrl = "https://example.com/avatar.jpg"
            }
        })
    end
end, true)

-- Legacy commands for backwards compatibility
RegisterCommand('ttr_simulate_like', function(source, args)
    ExecuteCommand('ttr_test_like ' .. (args[1] or 'TestUser'))
end, true)

RegisterCommand('ttr_simulate_join', function(source, args)
    ExecuteCommand('ttr_test_join ' .. (args[1] or 'TestUser'))
end, true)

RegisterCommand('ttr_simulate_gift', function(source, args)
    ExecuteCommand('ttr_test_gift ' .. (args[1] or 'TestUser') .. ' ' .. (args[2] or 'Rose') .. ' ' .. (args[3] or '1'))
end, true)

RegisterCommand('ttr_status', function(source)
    if source == 0 then -- Console only
        print("^3[TikTok Race]^7 Status:")
        print("  Game State: " .. gameState)
        print("  Player Count: " .. playerCount)
        print("  WebSocket: " .. (websocketConnected and "Connected" or "Disconnected"))
        print("  AI Mode: " .. (aiMode and "Enabled" or "Disabled"))
        
        if playerCount > 0 then
            print("  Players:")
            for i = 1, playerCount do
                print("    " .. i .. ". " .. (playerRealNames[i] or "Unknown"))
            end
        end
    end
end, true)

-- Send win data to external API (placeholder)
function sendWinToAPI(nickname, username, position)
    -- This would send the winner data to your TikTok integration API
    print("^2[TikTok Race]^7 Sending win data: " .. nickname .. " - Position " .. position)
    
    --[[
    Example implementation:
    PerformHttpRequest('https://your-api.com/race/win', function(errorCode, resultData, resultHeaders)
        if errorCode == 200 then
            print("^2[TikTok Race]^7 Win data sent successfully!")
        else
            print("^1[TikTok Race]^7 Failed to send win data: " .. errorCode)
        end
    end, 'POST', json.encode({
        nickname = nickname,
        username = username,
        position = position,
        timestamp = os.time()
    }), {['Content-Type'] = 'application/json'})
    --]]
end

-- Auto-execute commands from bridge file
CreateThread(function()
    local commandFile = 'fivem_commands.txt'
    
    while true do
        Wait(500) -- Check every 500ms
        
        -- Check if command file exists
        local file = io.open(commandFile, 'r')
        if file then
            local content = file:read('*all')
            file:close()
            
            if content and content ~= '' then
                -- Split commands by newlines
                for command in content:gmatch('[^\r\n]+') do
                    if command and command ~= '' then
                        print("^3[TikTok Race]^7 Auto-executing: " .. command)
                        ExecuteCommand(command)
                    end
                end
                
                -- Clear the file after processing
                local clearFile = io.open(commandFile, 'w')
                if clearFile then
                    clearFile:write('')
                    clearFile:close()
                end
            end
        end
    end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        print("^3[TikTok Race]^7 Resource stopping - cleaning up...")
        websocketConnected = false
        TriggerClientEvent('tiktok_race:websocketStatus', -1, websocketConnected)
    end
end)

-- Initialize on resource start
CreateThread(function()
    Wait(1000) -- Wait for resource to fully load
    initializeWebSocket()
end)