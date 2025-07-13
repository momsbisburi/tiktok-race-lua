-- TikTok Race FiveM Mod - Client Side (FIXED)
-- Port of the original GTA V Script Hook mod with proper UI positioning and name rendering

local TikTokRace = {}

-- Constants
local GAME_STATES = {
    IDLE = 0,
    SETUP = 1,
    SETUP_DONE = 2,
    QUEUE = 3,
    READY = 4,
    COUNTDOWN = 5,
    RACE = 6,
    WIN = 7,
    WINNERS = 8,
    CLEAN = 9
}

-- Main variables
local gameState = GAME_STATES.IDLE
local raceMenu = false
local queueList = false
local winnersList = false
local holdF = false
local debugLock = false
local isDebug = false
local pedsEnabled = true
local aiMode = false
local isRacing = false
local racingCam = false
local countdown = false
local countdownTime = 11
local countdownStart = 0

-- Player management
local maxPlayers = 100
local playerNumber = 0
local players = {}
local playerNames = {}
local playerPositions = {}
local playerSpeeds = {}
local vehicles = {}
local peds = {}

-- Camera and positioning
local raceCamera = nil
local cameraPosition = vector3(1768.0, 3266.0, 60.0)
local cameraLookAt = vector3(1621.0, 3228.0, 40.41968)
local racePoint = vector3(0.0, 0.0, 0.0)
local currentCamera = 0

-- Race positioning
local playersX = 0.0
local playersY = 0.0
local playersRowNumber = 1
local playersRowCount = 0

-- Winners
local place = 0
local place1 = ""
local place2 = ""
local place3 = ""

-- WebSocket connection (will be handled server-side)
local websocketConnected = false

-- Sound management
local soundPlayId = 0
local soundPlayIdS = 1

-- Version
local version = "v0.6 FiveM"

-- Screen resolution helpers
local screenW, screenH = GetActiveScreenResolution()

-- UI Helper Functions
function GetUIPosition(x, y, anchorX, anchorY)
    -- Convert relative positions to screen coordinates
    -- anchorX: 0 = left, 0.5 = center, 1 = right
    -- anchorY: 0 = top, 0.5 = center, 1 = bottom
    anchorX = anchorX or 0
    anchorY = anchorY or 0
    
    local finalX = anchorX + (x / screenW)
    local finalY = anchorY + (y / screenH)
    
    return finalX, finalY
end

function DrawText2D(text, x, y, scale, color, font, centered, shadow, outline)
    font = font or 4
    centered = centered or false
    shadow = shadow or false
    outline = outline or false
    
    SetTextFont(font)
    SetTextProportional(false)
    SetTextScale(scale, scale)
    SetTextColour(color[1], color[2], color[3], color[4] or 255)
    
    if centered then
        SetTextCentre(true)
    end
    
    if shadow then
        SetTextDropShadow(0, 0, 0, 0, 255)
    end
    
    if outline then
        SetTextOutline()
    end
    
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
    
    -- Reset text properties
    SetTextCentre(false)
end

function DrawRaceMenuItem(text, x, y, color, scale, shadow, qlist, alignCenter, cent)
    local finalX, finalY
    scale = scale or 0.4
    shadow = shadow or false
    
    if cent then
        -- Centered positioning
        finalX = x
        finalY = y
    elseif qlist then
        -- Queue list positioning (left side)
        finalX = 0.05 + (x * 0.001)
        finalY = 0.25 + (y * 0.025)
    else
        -- Right side menu positioning
        finalX = 0.75
        finalY = 0.25 + (y * 0.025)
    end
    
    DrawText2D(text, finalX, finalY, scale, color, 4, alignCenter, shadow, false)
end

function DrawBackground(x, y, width, height, color)
    color = color or {0, 0, 0, 150}
    DrawRect(x, y, width, height, color[1], color[2], color[3], color[4])
end

-- Key mappings
RegisterKeyMapping('tiktok_toggle_menu', 'Toggle TikTok Race Menu', 'keyboard', 'U')
RegisterKeyMapping('tiktok_action', 'TikTok Race Action', 'keyboard', 'H')
RegisterKeyMapping('tiktok_queue', 'Toggle Queue/Winners List', 'keyboard', 'J')
RegisterKeyMapping('tiktok_camera_left', 'Previous Camera', 'keyboard', 'LEFT')
RegisterKeyMapping('tiktok_camera_right', 'Next Camera', 'keyboard', 'RIGHT')
RegisterKeyMapping('tiktok_search_player', 'Search Player', 'keyboard', 'L')

-- Initialize
CreateThread(function()
    while true do
        Wait(0)
        onTick()
    end
end)

function onTick()
    -- Set weather and time
    SetWeatherTypeNow("CLEAR")
    NetworkOverrideClockTime(12, 0, 0)
    
    -- Get waypoint if in setup mode
    if gameState == GAME_STATES.SETUP_DONE then
        local waypoint = GetFirstBlipInfoId(8) -- Waypoint blip
        if DoesBlipExist(waypoint) then
            local coord = GetBlipCoords(waypoint)
            racePoint = vector3(coord.x, coord.y, coord.z)
        end
    end
    
    -- Draw main title
    DrawText2D("Muzzy Tiktok Race " .. version, 0.01, 0.01, 0.4, {0, 162, 255, 255}, 4, false, true, true)
    
    -- Main game loop functions
    deletePopulation()
    debugInfo()
    drawRaceMenu()
    renderNames()
    handleRacingCam()
    handleCountdown()
    checkRaceFinish()
end

-- Key handlers
RegisterCommand('tiktok_toggle_menu', function()
    if not holdF then
        holdF = true
        raceMenu = not raceMenu
        SetTimeout(200, function() holdF = false end)
    end
end)

RegisterCommand('tiktok_action', function()
    if not holdF and raceMenu and not queueList then
        holdF = true
        buttonControlH()
        SetTimeout(200, function() holdF = false end)
    end
end)

RegisterCommand('tiktok_queue', function()
    if not holdF then
        holdF = true
        if gameState == GAME_STATES.QUEUE then
            queueList = not queueList
        elseif gameState == GAME_STATES.WINNERS then
            winnersList = not winnersList
        end
        SetTimeout(200, function() holdF = false end)
    end
end)

RegisterCommand('tiktok_camera_left', function()
    if not holdF and gameState == GAME_STATES.RACE then
        holdF = true
        if currentCamera <= 0 then
            if vehicles[playerNumber] then
                TaskWarpPedIntoVehicle(PlayerPedId(), vehicles[playerNumber], 0) -- passenger seat
            end
            currentCamera = playerNumber - 1
        else
            if vehicles[currentCamera] then
                TaskWarpPedIntoVehicle(PlayerPedId(), vehicles[currentCamera], 0)
            end
            currentCamera = currentCamera - 1
        end
        SetTimeout(200, function() holdF = false end)
    end
end)

RegisterCommand('tiktok_camera_right', function()
    if not holdF and gameState == GAME_STATES.RACE then
        holdF = true
        if currentCamera >= playerNumber - 1 then
            if vehicles[1] then
                TaskWarpPedIntoVehicle(PlayerPedId(), vehicles[1], 0)
            end
            currentCamera = 0
        else
            if vehicles[currentCamera + 2] then
                TaskWarpPedIntoVehicle(PlayerPedId(), vehicles[currentCamera + 2], 0)
            end
            currentCamera = currentCamera + 1
        end
        SetTimeout(200, function() holdF = false end)
    end
end)

RegisterCommand('tiktok_search_player', function()
    if gameState == GAME_STATES.RACE then
        DisplayOnscreenKeyboard(1, "FMMC_KEY_TIP8", "", "", "", "", "", 64)
        while UpdateOnscreenKeyboard() == 0 do
            Wait(0)
        end
        if GetOnscreenKeyboardResult() then
            local searchName = GetOnscreenKeyboardResult()
            local playerId = getNameId(searchName)
            if playerId ~= -1 and vehicles[playerId] then
                TaskWarpPedIntoVehicle(PlayerPedId(), vehicles[playerId], 0)
                currentCamera = playerId
            end
        end
    end
end)

function drawRaceMenu()
    if raceMenu then
        -- Main menu background (right side)
        DrawBackground(0.75, 0.35, 0.23, 0.3, {0, 0, 0, 180})
        
        if gameState == GAME_STATES.IDLE then
            DrawRaceMenuItem("TikTok Race Menu", 0, 0, {255, 165, 0, 255}, 0.7, true, false, false, false)
            DrawRaceMenuItem("[H] - Setup race!", 0, 2, {255, 255, 255, 255}, 0.5, false, false, false, false)
            
        elseif gameState == GAME_STATES.SETUP_DONE then
            DrawRaceMenuItem("TikTok Race Menu", 0, 0, {255, 165, 0, 255}, 0.7, true, false, false, false)
            if racePoint.x == 0.0 and racePoint.y == 0.0 then
                DrawRaceMenuItem("PLEASE SET WAYPOINT!", 0, 2, {64, 224, 208, 255}, 0.6, true, false, false, false)
            end
            DrawRaceMenuItem("[H] - Open Queue!", 0, 4, {255, 255, 255, 255}, 0.5, false, false, false, false)
            
        elseif gameState == GAME_STATES.QUEUE then
            if queueList then
                drawQueueList()
            else
                DrawRaceMenuItem("TikTok Race Menu", 0, 0, {255, 165, 0, 255}, 0.7, true, false, false, false)
                DrawRaceMenuItem("[H] - End Queue!", 0, 2, {255, 255, 255, 255}, 0.5, false, false, false, false)
                DrawRaceMenuItem("[J] - Open Queue List!", 0, 4, {255, 255, 255, 255}, 0.5, false, false, false, false)
            end
            
        elseif gameState == GAME_STATES.READY then
            DrawRaceMenuItem("TikTok Race Menu", 0, 0, {255, 165, 0, 255}, 0.7, true, false, false, false)
            DrawRaceMenuItem("[H] - Start countdown!", 0, 2, {255, 255, 255, 255}, 0.5, false, false, false, false)
            
        elseif gameState == GAME_STATES.RACE then
            DrawRaceMenuItem("TikTok Race Menu", 0, 0, {255, 165, 0, 255}, 0.7, true, false, false, false)
            DrawRaceMenuItem("Change camera (" .. (currentCamera + 1) .. "):", 0, 2, {255, 255, 255, 255}, 0.5, false, false, false, false)
            DrawRaceMenuItem("[<] - Previous player!", 0, 3, {255, 255, 255, 255}, 0.4, false, false, false, false)
            DrawRaceMenuItem("[>] - Next player!", 0, 4, {255, 255, 255, 255}, 0.4, false, false, false, false)
            DrawRaceMenuItem("[L] - Search player!", 0, 5, {255, 255, 255, 255}, 0.4, false, false, false, false)
            
            -- Draw leaderboard on the left
            drawLeaderboard()
            
        elseif gameState == GAME_STATES.WINNERS then
            if winnersList then
                drawWinnersList()
            else
                DrawRaceMenuItem("TikTok Race Menu", 0, 0, {255, 165, 0, 255}, 0.7, true, false, false, false)
                DrawRaceMenuItem("[H] - Setup Race!", 0, 2, {255, 255, 255, 255}, 0.5, false, false, false, false)
                DrawRaceMenuItem("[J] - Open Winners List!", 0, 4, {255, 255, 255, 255}, 0.5, false, false, false, false)
            end
        end
    else
        -- Minimized menu (top right corner)
        DrawBackground(0.75, 0.02, 0.23, 0.05, {0, 0, 0, 180})
        DrawText2D("[U] - Show Race Menu!", 0.765, 0.03, 0.4, {255, 255, 255, 255}, 4, false, true, false)
        
        if gameState == GAME_STATES.RACE then
            drawLeaderboard()
        end
    end
end

function drawQueueList()
    -- Large background for queue list (center screen)
    DrawBackground(0.5, 0.5, 0.85, 0.7, {0, 0, 0, 200})
    
    -- Close button (top)
    DrawText2D("[J] - Close Queue List!", 0.5, 0.15, 0.5, {255, 255, 255, 255}, 4, true, true, true)
    
    -- Header
    local headerText = "Joined: " .. playerNumber .. "/" .. maxPlayers .. " | Write !join in chat to enter the race"
    DrawText2D(headerText, 0.5, 0.22, 0.6, {255, 255, 255, 255}, 4, true, true, true)
    DrawText2D("_________________________________________", 0.5, 0.25, 0.6, {255, 255, 255, 255}, 4, true, false, false)
    DrawText2D("Players List", 0.5, 0.3, 0.7, {0, 162, 255, 255}, 4, true, true, false)
    
    -- Draw player list in columns (3 columns, 20 rows each)
    local startX = 0.2
    local startY = 0.38
    local columnWidth = 0.25
    local rowHeight = 0.02
    local maxRowsPerColumn = 20
    
    for i = 1, playerNumber do
        if playerNames[i] and playerNames[i] ~= "" then
            local name = playerNames[i]
            if string.len(name) > 18 then
                name = string.sub(name, 1, 18) .. "..."
            end
            
            local column = math.floor((i - 1) / maxRowsPerColumn)
            local row = (i - 1) % maxRowsPerColumn
            
            local x = startX + (column * columnWidth)
            local y = startY + (row * rowHeight)
            
            if column < 3 then -- Only show first 3 columns (60 players max visible)
                DrawText2D(i .. ". " .. name, x, y, 0.4, {255, 255, 255, 255}, 4, false, false, false)
            end
        end
    end
    
    -- Show overflow message if more than 60 players
    if playerNumber > 60 then
        DrawText2D("... and " .. (playerNumber - 60) .. " more players", 0.5, 0.82, 0.4, {255, 255, 0, 255}, 4, true, false, false)
    end
end

function drawLeaderboard()
    -- Leaderboard background (left side)
    DrawBackground(0.02, 0.35, 0.25, 0.35, {0, 0, 0, 180})
    
    -- Header
    DrawText2D("Leaderboard", 0.03, 0.18, 0.6, {0, 255, 255, 255}, 4, false, true, true)
    DrawText2D("_____________", 0.03, 0.21, 0.5, {255, 255, 255, 255}, 4, false, false, false)
    
    -- Sort players by distance to finish (like the C# code)
    local sortedPlayers = {}
    for i = 1, playerNumber do
        if playerPositions[i] and DoesEntityExist(players[i]) and not IsEntityDead(players[i]) then
            local parts = {}
            for part in string.gmatch(playerPositions[i], "[^|]+") do
                table.insert(parts, part)
            end
            if #parts >= 2 then
                local distance = tonumber(parts[1]) or 9999
                table.insert(sortedPlayers, {
                    distance = distance,
                    name = parts[2],
                    index = i
                })
            end
        end
    end
    
    -- Sort by distance (closest to finish first)
    table.sort(sortedPlayers, function(a, b) return a.distance < b.distance end)
    
    -- Draw top 10 (like the C# code limit)
    local maxDisplay = math.min(10, #sortedPlayers)
    for i = 1, maxDisplay do
        local player = sortedPlayers[i]
        local name = player.name
        
        -- Extract name like C# code does
        if string.find(name, "%(") then
            name = string.match(name, "(.-)%s*%(") or name
        end
        
        -- Limit name length
        if string.len(name) > 15 then
            name = string.sub(name, 1, 15) .. "..."
        end
        
        local y = 0.25 + (i * 0.025)
        local displayText = i .. ". " .. name .. " (" .. math.floor(player.distance) .. "m)"
        
        -- Different colors for top 3
        local color = {255, 255, 255, 255} -- White for others
        if i == 1 then
            color = {255, 215, 0, 255} -- Gold for 1st
        elseif i == 2 then
            color = {192, 192, 192, 255} -- Silver for 2nd
        elseif i == 3 then
            color = {205, 127, 50, 255} -- Bronze for 3rd
        end
        
        DrawText2D(displayText, 0.03, y, 0.4, color, 4, false, false, false)
    end
end

function drawWinnersList()
    -- Winners list background (center screen)
    DrawBackground(0.5, 0.5, 0.5, 0.6, {0, 0, 0, 200})
    
    -- Close button
    DrawText2D("[J] - Close Winners List!", 0.5, 0.22, 0.5, {255, 255, 255, 255}, 4, true, true, true)
    
    -- Header
    DrawText2D("Race Results", 0.5, 0.3, 0.8, {255, 255, 255, 255}, 4, true, true, true)
    DrawText2D("__________________", 0.5, 0.35, 0.6, {255, 255, 255, 255}, 4, true, false, false)
    
    -- Extract names like C# code
    local function extractName(fullName)
        if string.find(fullName, "%(") then
            return string.match(fullName, "(.-)%s*%(") or fullName
        end
        return fullName
    end
    
    -- Winners
    if place1 ~= "" then
        DrawText2D("🥇 1st: " .. extractName(place1), 0.5, 0.45, 0.7, {255, 215, 0, 255}, 4, true, true, true)
    end
    
    if place2 ~= "" then
        DrawText2D("🥈 2nd: " .. extractName(place2), 0.5, 0.52, 0.6, {192, 192, 192, 255}, 4, true, true, true)
    end
    
    if place3 ~= "" and playerNumber >= 3 then
        DrawText2D("🥉 3rd: " .. extractName(place3), 0.5, 0.59, 0.5, {205, 127, 50, 255}, 4, true, true, true)
    end
    
    -- Next race info
    DrawText2D("Next race starting soon...", 0.5, 0.7, 0.4, {0, 255, 255, 255}, 4, true, false, false)
end

function handleCountdown()
    if countdown then
        local timeLeft = (countdownStart + (countdownTime * 1000) - GetGameTimer()) / 1000
        local seconds = math.ceil(timeLeft)
        
        if timeLeft <= 0 then
            -- COUNTDOWN FINISHED - START RACE
            print("^2[TikTok Race]^7 Countdown finished! Starting race...")
            
            DisplayRadar(true)
            countdown = false
            isRacing = true
            racingCam = true
            
            -- CRITICAL: Set game state to RACE (6)
            gameState = GAME_STATES.RACE
            TriggerServerEvent('tiktok_race:setGameState', gameState)
            
            SetEntityInvincible(PlayerPedId(), false)
            FreezeEntityPosition(PlayerPedId(), false)
            
            -- Start the cars driving (but don't use AI mode)
            startDrivingWithoutAI()
            
        elseif seconds < 1 then
            if soundPlayId ~= soundPlayIdS then
                PlaySoundFrontend(-1, "Beep_Green", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
                soundPlayId = soundPlayIdS
            end
            DrawText2D("GO!!!", 0.5, 0.5, 2.0, {0, 255, 0, 255}, 4, true, true, true)
        elseif seconds <= 3 then
            if soundPlayId ~= soundPlayIdS then
                PlaySoundFrontend(-1, "3_2_1", "HUD_MINI_GAME_SOUNDSET", true)
                soundPlayId = soundPlayIdS
            end
            DrawText2D(tostring(seconds), 0.5, 0.5, 2.0, {255, 0, 0, 255}, 4, true, true, true)
        else
            if soundPlayId ~= soundPlayIdS then
                PlaySoundFrontend(-1, "3_2_1", "HUD_MINI_GAME_SOUNDSET", true)
                soundPlayId = soundPlayIdS
            end
            DrawText2D(tostring(seconds), 0.5, 0.5, 2.0, {255, 255, 255, 255}, 4, true, true, true)
        end
        
        soundPlayIdS = seconds
    end
end

function deletePopulation()
    if pedsEnabled then
        -- Clear area of unwanted peds and vehicles
        ClearAreaOfPeds(1722.0, 3239.0, 40.7287, 500.0, 1)
        ClearAreaOfVehicles(1722.0, 3239.0, 40.7287, 500.0, false, false, false, false, false)
    end
end

function debugInfo()
    if not websocketConnected then
        DrawText2D("🔴 Not connected to TikTok events", 0.5, 0.95, 0.4, {255, 100, 100, 255}, 4, true, true, true)
    else
        DrawText2D("🟢 Connected to TikTok events", 0.5, 0.95, 0.4, {100, 255, 100, 255}, 4, true, true, true)
    end
    
    if isDebug then
        local line = 0
        local startY = 0.7
        
        DrawText2D("=== DEBUG INFO ===", 0.02, startY + (line * 0.025), 0.4, {255, 165, 0, 255}, 4, false, true, false)
        line = line + 1
        
        DrawText2D("Game State: " .. gameState, 0.02, startY + (line * 0.025), 0.35, {255, 255, 255, 255}, 4, false, false, false)
        line = line + 1
        
        DrawText2D("Players: " .. playerNumber .. "/" .. maxPlayers, 0.02, startY + (line * 0.025), 0.35, {255, 255, 255, 255}, 4, false, false, false)
        line = line + 1
        
        local connectText = websocketConnected and "Connected" or "Disconnected"
        local connectColor = websocketConnected and {0, 255, 0, 255} or {255, 0, 0, 255}
        DrawText2D("WebSocket: " .. connectText, 0.02, startY + (line * 0.025), 0.35, connectColor, 4, false, false, false)
        line = line + 1
        
        DrawText2D("Peds Enabled: " .. tostring(pedsEnabled), 0.02, startY + (line * 0.025), 0.35, {255, 255, 255, 255}, 4, false, false, false)
        line = line + 1
        
        DrawText2D("AI Mode: " .. tostring(aiMode), 0.02, startY + (line * 0.025), 0.35, {255, 255, 255, 255}, 4, false, false, false)
    end
end

function buttonControlH()
    if gameState == GAME_STATES.IDLE then
        -- Setup race
        RemoveBlip(GetFirstBlipInfoId(8)) -- Remove waypoint
        SetEntityInvincible(PlayerPedId(), true)
        FreezeEntityPosition(PlayerPedId(), true)
        DisplayRadar(false)
        
        -- Teleport to race location
        SetEntityCoords(PlayerPedId(), 1717.06, 3287.031, 41.16869, false, false, false, true)
        
        -- Create camera
        if raceCamera then
            DestroyCam(raceCamera, false)
        end
        raceCamera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
        SetCamCoord(raceCamera, cameraPosition.x, cameraPosition.y, cameraPosition.z)
        PointCamAtCoord(raceCamera, cameraLookAt.x, cameraLookAt.y, cameraLookAt.z)
        SetCamActive(raceCamera, true)
        RenderScriptCams(true, false, 0, true, true)
        
        -- Reset ALL variables completely
        playerNumber = 0
        place = 0
        place1 = ""
        place2 = ""
        place3 = ""
        playerNames = {}
        players = {}
        vehicles = {}
        playerSpeeds = {}
        playerPositions = {}
        
        -- CRITICAL: Reset spawn positioning to match C# initial values
        playersX = 0.0
        playersY = 0.0
        playersRowNumber = 1
        playersRowCount = 0
        
        gameState = GAME_STATES.SETUP_DONE
        TriggerServerEvent('tiktok_race:setGameState', gameState)
        
    elseif gameState == GAME_STATES.SETUP_DONE then
        if racePoint.x == 0.0 and racePoint.y == 0.0 then
            print("^1[TikTok Race]^7 Please set a waypoint first!")
            return
        end
        
        -- Reset spawn positioning again when opening queue (like C# ButtonControlH case 2)
        playersRowCount = 0
        playersRowNumber = 1
        playersX = 0.0
        playersY = 0.0
        queueList = true
        
        print("^2[TikTok Race]^7 ✅ Queue opened! Spawn vars reset - X: " .. playersX .. ", Y: " .. playersY .. ", Row: " .. playersRowNumber)
        
        gameState = GAME_STATES.QUEUE
        TriggerServerEvent('tiktok_race:setGameState', gameState)
        
    elseif gameState == GAME_STATES.QUEUE then
        if playerNumber < 2 then
            print("^1[TikTok Race]^7 Need at least 2 players to start!")
            return
        end
        
        gameState = GAME_STATES.READY
        TriggerServerEvent('tiktok_race:setGameState', gameState)
        
    elseif gameState == GAME_STATES.READY then
        -- Start countdown
        countdown = true
        countdownStart = GetGameTimer()
        gameState = GAME_STATES.COUNTDOWN
        TriggerServerEvent('tiktok_race:setGameState', gameState)
        
    elseif gameState == GAME_STATES.WINNERS then
        -- Reset for new race - FULL RESET like case 0
        SetEntityInvincible(PlayerPedId(), true)
        FreezeEntityPosition(PlayerPedId(), true)
        DisplayRadar(false)
        SetEntityCoords(PlayerPedId(), 1717.06, 3287.031, 41.16869, false, false, false, true)
        
        if raceCamera then
            SetCamActive(raceCamera, true)
            RenderScriptCams(true, false, 0, true, true)
        end
        
        -- Kill all existing racers first
        killAllRacers()
        
        -- Reset ALL variables completely (like C# case 8)
        playerNumber = 0
        place = 0
        place1 = ""
        place2 = ""
        place3 = ""
        playerNames = {}
        players = {}
        vehicles = {}
        playerSpeeds = {}
        playerPositions = {}
        
        -- Reset spawn positioning
        playersX = 0.0
        playersY = 0.0
        playersRowNumber = 1
        playersRowCount = 0
        
        -- Reset UI states
        winnersList = false
        queueList = false
        raceMenu = true
        
        gameState = GAME_STATES.SETUP_DONE
        TriggerServerEvent('tiktok_race:setGameState', gameState)
    end
end

function createPlayer(name, carModel)
    if playerNumber >= maxPlayers or gameState ~= GAME_STATES.QUEUE then
        print("^1[TikTok Race]^7 Cannot create player - wrong state or full")
        return false
    end
    
    carModel = carModel or GetHashKey("hermes") -- Default car
    if type(carModel) == "string" then
        carModel = GetHashKey(carModel)
    end
    
    -- Increment playerNumber FIRST (before any calculations)
    playerNumber = playerNumber + 1
    local currentPlayerIndex = playerNumber
    
    print("^3[TikTok Race]^7 Creating player " .. currentPlayerIndex .. ": " .. name)
    print("^3[TikTok Race]^7 Using spawn vars - X: " .. playersX .. ", Y: " .. playersY .. ", Row: " .. playersRowNumber)
    
    -- Calculate spawn position using C# logic: Vector3(1722f, 3239f, 40.7287f) + Vector3(Players_X, Players_Y, 0f)
    local spawnPos = vector3(1722.0 + playersX, 3239.0 + playersY, 40.7287)
    
    print("^3[TikTok Race]^7 Spawning at: " .. spawnPos.x .. ", " .. spawnPos.y .. ", " .. spawnPos.z)
    
    -- Clear area more aggressively to prevent overlapping
    ClearAreaOfVehicles(spawnPos.x, spawnPos.y, spawnPos.z, 12.0, false, false, false, false, false)
    ClearAreaOfPeds(spawnPos.x, spawnPos.y, spawnPos.z, 12.0, 1)
    ClearAreaOfObjects(spawnPos.x, spawnPos.y, spawnPos.z, 12.0, 0)
    
    -- Wait a moment for area to clear
    Wait(100)
    
    -- Request and wait for vehicle model
    RequestModel(carModel)
    local timeout = 0
    while not HasModelLoaded(carModel) and timeout < 5000 do
        Wait(10)
        timeout = timeout + 10
    end
    
    if not HasModelLoaded(carModel) then
        print("^1[TikTok Race]^7 Failed to load vehicle model for " .. name)
        playerNumber = playerNumber - 1 -- Revert player count
        return false
    end
    
    -- Create vehicle with better parameters
    local vehicle = CreateVehicle(carModel, spawnPos.x, spawnPos.y, spawnPos.z, 286.7277, true, false)
    
    -- Wait for vehicle to fully spawn
    timeout = 0
    while not DoesEntityExist(vehicle) and timeout < 3000 do
        Wait(10)
        timeout = timeout + 10
    end
    
    if not DoesEntityExist(vehicle) then
        print("^1[TikTok Race]^7 Failed to create vehicle for " .. name)
        playerNumber = playerNumber - 1 -- Revert player count
        SetModelAsNoLongerNeeded(carModel)
        return false
    end
    
    -- Ensure vehicle is properly placed
    SetEntityCoords(vehicle, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false, true)
    SetEntityHeading(vehicle, 286.7277)
    PlaceObjectOnGroundProperly(vehicle)
    
    -- Set vehicle properties immediately
    SetEntityInvincible(vehicle, true)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleDoorsLocked(vehicle, 2) -- Lock doors to prevent NPCs from entering
    SetEntityAsMissionEntity(vehicle, true, true) -- Make it a mission entity
    
    -- Request and wait for ped model
    local pedModel = GetHashKey("a_m_m_skater_01")
    RequestModel(pedModel)
    timeout = 0
    while not HasModelLoaded(pedModel) and timeout < 5000 do
        Wait(10)
        timeout = timeout + 10
    end
    
    if not HasModelLoaded(pedModel) then
        print("^1[TikTok Race]^7 Failed to load ped model for " .. name)
        DeleteEntity(vehicle)
        playerNumber = playerNumber - 1 -- Revert player count
        SetModelAsNoLongerNeeded(carModel)
        return false
    end
    
    -- Create ped near the vehicle (not inside it yet)
    local pedSpawnPos = vector3(spawnPos.x + 2.0, spawnPos.y, spawnPos.z)
    local ped = CreatePed(4, pedModel, pedSpawnPos.x, pedSpawnPos.y, pedSpawnPos.z, 0.0, true, false)
    
    -- Wait for ped to fully spawn
    timeout = 0
    while not DoesEntityExist(ped) and timeout < 3000 do
        Wait(10)
        timeout = timeout + 10
    end
    
    if not DoesEntityExist(ped) then
        print("^1[TikTok Race]^7 Failed to create ped for " .. name)
        DeleteEntity(vehicle)
        playerNumber = playerNumber - 1 -- Revert player count
        SetModelAsNoLongerNeeded(carModel)
        SetModelAsNoLongerNeeded(pedModel)
        return false
    end
    
    -- Set ped properties
    SetEntityInvincible(ped, true)
    SetPedCanBeDraggedOut(ped, false)
    SetPedCanBeKnockedOffVehicle(ped, 1)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    
    -- Store references using the current player index
    players[currentPlayerIndex] = ped
    vehicles[currentPlayerIndex] = vehicle
    playerNames[currentPlayerIndex] = name
    playerSpeeds[currentPlayerIndex] = 0
    
    -- Wait a moment before putting ped in vehicle
    Wait(200)
    
    -- Put ped into vehicle (driver seat) with task warp for reliability
    TaskWarpPedIntoVehicle(ped, vehicle, -1)
    
    -- Wait to ensure ped is in vehicle
    timeout = 0
    while not IsPedInVehicle(ped, vehicle, false) and timeout < 3000 do
        Wait(10)
        timeout = timeout + 10
        -- Retry if needed
        if timeout % 500 == 0 then
            TaskWarpPedIntoVehicle(ped, vehicle, -1)
        end
    end
    
    -- Add blip to vehicle
    local blip = AddBlipForEntity(vehicle)
    SetBlipSprite(blip, 56)
    SetBlipColour(blip, 3)
    SetBlipScale(blip, 0.8)
    
    -- Update spawn position for NEXT player (using C# logic - AFTER storing current player)
    if playersRowNumber >= 7 then
        playersRowCount = playersRowCount + 1
        playersY = -4.4 * playersRowCount
        playersX = playersX - 10.0
        playersRowNumber = 0
    else
        playersY = playersY + 5.0
        playersX = playersX - 1.0
    end
    playersRowNumber = playersRowNumber + 1
    
    print("^2[TikTok Race]^7 ✅ Successfully created player " .. currentPlayerIndex .. ": " .. name)
    print("^2[TikTok Race]^7 Vehicle: " .. (DoesEntityExist(vehicle) and "EXISTS" or "MISSING"))
    print("^2[TikTok Race]^7 Ped: " .. (DoesEntityExist(ped) and "EXISTS" or "MISSING"))
    print("^2[TikTok Race]^7 Ped in vehicle: " .. (IsPedInVehicle(ped, vehicle, false) and "YES" or "NO"))
    print("^3[TikTok Race]^7 Next spawn will be at X: " .. playersX .. ", Y: " .. playersY)
    
    -- Clean up models
    SetModelAsNoLongerNeeded(carModel)
    SetModelAsNoLongerNeeded(pedModel)
    
    return true
end

function killAllRacers()
    for i = 1, playerNumber do
        if DoesEntityExist(players[i]) then
            DeleteEntity(players[i])
        end
        if DoesEntityExist(vehicles[i]) then
            DeleteEntity(vehicles[i])
        end
    end
    
    players = {}
    vehicles = {}
    playerNames = {}
    playerSpeeds = {}
    playerPositions = {}
end

function startDrivingWithoutAI()
    print("^2[TikTok Race]^7 Cars ready - waiting for viewer boosts to move!")
    
    for i = 1, playerNumber do
        if DoesEntityExist(players[i]) and DoesEntityExist(vehicles[i]) then
            local ped = players[i]
            local vehicle = vehicles[i]
            
            print("^3[TikTok Race]^7 Preparing racer " .. i .. ": " .. (playerNames[i] or "Unknown"))
            
            -- Set very slow initial speed - cars won't move much without boosts
            playerSpeeds[i] = 5.0 -- Very slow start
            
            -- Make sure vehicle is ready but won't auto-drive
            SetVehicleEngineOn(vehicle, true, true, false)
            SetEntityInvincible(vehicle, false)
            
            -- Give a tiny initial push so they don't just sit there
            TaskVehicleDriveToCoord(ped, vehicle, racePoint.x, racePoint.y, racePoint.z, 
                playerSpeeds[i], 0, GetEntityModel(vehicle), 786603, 5.0, -1.0)
            
            print("^2[TikTok Race]^7 Racer " .. i .. " ready at slow speed " .. playerSpeeds[i])
        end
    end
    
    print("^2[TikTok Race]^7 🎮 Cars need viewer interactions to speed up!")
end

-- REPLACE the original startDriving function
function startDriving()
    -- This is called by the old AI system - redirect to our new function
    startDrivingWithoutAI()
end

function renderNames()
    if gameState == GAME_STATES.RACE then
        for i = 1, playerNumber do
            if DoesEntityExist(players[i]) and DoesEntityExist(vehicles[i]) then
                local ped = players[i]
                local vehicle = vehicles[i]
                local pedPos = GetEntityCoords(ped)
                local distance = #(pedPos - racePoint)
                
                -- Update player position for leaderboard
                playerPositions[i] = math.floor(distance) .. "|" .. playerNames[i]
                
                -- Check if player finished
                if distance < 50.0 and not IsEntityDead(ped) then
                    if place == 0 then
                        place1 = playerNames[i]
                        SetEntityHealth(ped, 0)
                        TriggerServerEvent('tiktok_race:playerWin', i, 1)
                    elseif place == 1 then
                        place2 = playerNames[i]
                        SetEntityHealth(ped, 0)
                        if playerNumber == 2 then
                            isRacing = false
                            gameState = GAME_STATES.WIN
                        end
                        TriggerServerEvent('tiktok_race:playerWin', i, 2)
                    elseif place >= 2 then
                        place3 = playerNames[i]
                        isRacing = false
                        SetEntityHealth(ped, 0)
                        gameState = GAME_STATES.WIN
                        TriggerServerEvent('tiktok_race:playerWin', i, 3)
                    end
                    place = place + 1
                end
                
                -- FIXED: Proper name rendering like C# code
                local playerPos = GetEntityCoords(PlayerPedId())
                local distanceToPlayer = #(pedPos - playerPos)
                
                -- Only render names for nearby cars and if they're on screen
                if distanceToPlayer < 100.0 and IsEntityOnScreen(ped) then
                    -- Get world position above the vehicle
                    local namePos = vector3(pedPos.x, pedPos.y, pedPos.z + 2.0)
                    
                    -- Convert world coordinates to screen coordinates
                    local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(namePos.x, namePos.y, namePos.z)
                    
                    if onScreen then
                        -- Extract the display name like the C# code does
                        local displayName = playerNames[i]
                        
                        -- Extract name outside parentheses like C# ExtractOutsideName function
                        if string.find(displayName, "%(") then
                            displayName = string.match(displayName, "(.-)%s*%(") or displayName
                            displayName = string.gsub(displayName, "%s+$", "") -- trim trailing spaces
                        end
                        
                        -- Limit name length for better visibility
                        if string.len(displayName) > 12 then
                            displayName = string.sub(displayName, 1, 12) .. "..."
                        end
                        
                        -- Draw the name with proper styling like C# code
                        DrawText2D(displayName, screenX, screenY, 0.5, {255, 255, 255, 255}, 4, true, true, true)
                        
                        -- Optional: Draw distance for debugging
                        if isDebug then
                            local distanceText = math.floor(distance) .. "m"
                            DrawText2D(distanceText, screenX, screenY + 0.03, 0.3, {255, 255, 0, 200}, 4, true, false, false)
                        end
                    end
                end
            end
        end
    end
end

function handleRacingCam()
    if racingCam then
        DisableControlAction(0, 75, true) -- Disable exit vehicle
        
        if not IsPedInAnyVehicle(PlayerPedId(), false) and vehicles[1] then
            TaskWarpPedIntoVehicle(PlayerPedId(), vehicles[1], 0)
            RenderScriptCams(false, false, 0, true, true)
        end
    end
end

function checkRaceFinish()
    if gameState == GAME_STATES.WIN then
        SetEntityInvincible(PlayerPedId(), true)
        FreezeEntityPosition(PlayerPedId(), true)
        DisplayRadar(false)
        SetEntityCoords(PlayerPedId(), 1717.06, 3287.031, 41.16869, false, false, false, true)
        
        if raceCamera then
            SetCamActive(raceCamera, true)
            RenderScriptCams(true, false, 0, true, true)
        end
        
        isRacing = false
        racingCam = false
        killAllRacers()
        gameState = GAME_STATES.WINNERS
        winnersList = true
        raceMenu = true
    end
end

function boostPlayer(playerId, speed)
    if not players[playerId] or not DoesEntityExist(players[playerId]) then
        print("^1[TikTok Race]^7 Cannot boost - Player " .. playerId .. " doesn't exist")
        return
    end
    
    local ped = players[playerId]
    local vehicle = vehicles[playerId]
    
    if not DoesEntityExist(vehicle) then
        print("^1[TikTok Race]^7 Cannot boost - Vehicle " .. playerId .. " doesn't exist")
        return
    end
    
    -- Update speed - significant boost
    local oldSpeed = playerSpeeds[playerId] or 5
    playerSpeeds[playerId] = math.min(oldSpeed + speed, 80) -- Cap at 80
    local newSpeed = playerSpeeds[playerId]
    
    print("^2[TikTok Race]^7 🚀 BOOSTING player " .. playerId .. " (" .. (playerNames[playerId] or "Unknown") .. ") from " .. oldSpeed .. " to " .. newSpeed)
    
    -- Clear current task and start new one with higher speed
    ClearPedTasks(ped)
    Wait(50)
    
    -- Start driving with new speed
    TaskVehicleDriveToCoord(ped, vehicle, racePoint.x, racePoint.y, racePoint.z, 
        newSpeed, 0, GetEntityModel(vehicle), 786603, 15.0, -1.0)
        
    -- Visual feedback - give immediate speed boost
    SetVehicleForwardSpeed(vehicle, newSpeed * 0.3)
    
    -- Show boost notification on screen
    local playerName = playerNames[playerId] or "Unknown"
    if string.find(playerName, "%(") then
        playerName = string.match(playerName, "(.-)%s*%(") or playerName
    end
    
    -- Display boost message
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName("🚀 " .. playerName .. " got +" .. speed .. " speed boost!")
    EndTextCommandDisplayHelp(0, false, true, 3000)
end

function getNameId(searchName)
    searchName = string.lower(searchName)
    for i = 1, playerNumber do
        if playerNames[i] and string.find(string.lower(playerNames[i]), searchName) and currentCamera ~= i - 1 then
            return i
        end
    end
    return -1
end

-- Server events for TikTok integration
RegisterNetEvent('tiktok_race:playerJoin')
AddEventHandler('tiktok_race:playerJoin', function(playerName, carModel)
    print("^3[TikTok Race]^7 Server requesting player join: " .. playerName .. " with car: " .. (carModel or "default"))
    
    if gameState == GAME_STATES.QUEUE then
        -- Add a small delay to prevent race conditions
        CreateThread(function()
            Wait(100) -- Small delay for stability
            local success = createPlayer(playerName, carModel)
            if success then
                print("^2[TikTok Race]^7 ✅ Player join successful: " .. playerName)
            else
                print("^1[TikTok Race]^7 ❌ Player join failed: " .. playerName)
            end
        end)
    else
        print("^1[TikTok Race]^7 Cannot join - not in queue state (current: " .. gameState .. ")")
    end
end)

RegisterNetEvent('tiktok_race:boostPlayer')
AddEventHandler('tiktok_race:boostPlayer', function(playerId, boostAmount)
    if gameState == GAME_STATES.RACE and not aiMode then
        print("^3[TikTok Race]^7 Server requesting boost for player " .. playerId .. " amount: " .. boostAmount)
        boostPlayer(playerId, boostAmount)
    else
        print("^1[TikTok Race]^7 Cannot boost - wrong state or AI mode enabled")
    end
end)

RegisterNetEvent('tiktok_race:websocketStatus')
AddEventHandler('tiktok_race:websocketStatus', function(connected)
    websocketConnected = connected
    local statusText = connected and "connected" or "disconnected"
    print("^3[TikTok Race]^7 WebSocket status: " .. statusText)
end)

RegisterNetEvent('tiktok_race:updatePlayerCount')
AddEventHandler('tiktok_race:updatePlayerCount', function(count, names)
    -- Update local player tracking from server
    print("^3[TikTok Race]^7 Server sync - Player count: " .. count)
    if names then
        for i, name in ipairs(names) do
            if name and name ~= "" then
                playerNames[i] = name
                print("^3[TikTok Race]^7 Synced player " .. i .. ": " .. name)
            end
        end
    end
end)

RegisterNetEvent('tiktok_race:syncGameState')
AddEventHandler('tiktok_race:syncGameState', function(newState)
    print("^3[TikTok Race]^7 Game state synced from server: " .. newState)
    gameState = newState
end)

RegisterNetEvent('tiktok_race:resetRace')
AddEventHandler('tiktok_race:resetRace', function()
    print("^2[TikTok Race]^7 Server reset command received")
    
    -- Kill all racers first
    killAllRacers()
    
    -- Reset to initial state
    gameState = GAME_STATES.IDLE
    playerNumber = 0
    place = 0
    place1 = ""
    place2 = ""
    place3 = ""
    
    -- Reset spawn positioning
    playersX = 0.0
    playersY = 0.0
    playersRowNumber = 1
    playersRowCount = 0
    
    -- Reset UI states
    raceMenu = false
    queueList = false
    winnersList = false
    countdown = false
    isRacing = false
    racingCam = false
    
    -- Reset player state
    SetEntityInvincible(PlayerPedId(), false)
    FreezeEntityPosition(PlayerPedId(), false)
    DisplayRadar(true)
    
    if raceCamera then
        DestroyCam(raceCamera, false)
        RenderScriptCams(false, false, 0, true, true)
        raceCamera = nil
    end
    
    print("^2[TikTok Race]^7 ✅ Full race reset complete!")
end)

RegisterNetEvent('tiktok_race:resetToQueue')
AddEventHandler('tiktok_race:resetToQueue', function()
    print("^2[TikTok Race]^7 Server queue reset command received")
    
    -- Kill existing racers
    killAllRacers()
    
    -- Reset to queue state
    gameState = GAME_STATES.QUEUE
    playerNumber = 0
    place = 0
    place1 = ""
    place2 = ""
    place3 = ""
    
    -- Reset spawn positioning
    playersX = 0.0
    playersY = 0.0
    playersRowNumber = 1
    playersRowCount = 0
    
    queueList = true
    winnersList = false
    
    print("^2[TikTok Race]^7 ✅ Reset to queue state complete!")
end)

RegisterNetEvent('tiktok_race:forceRaceState')
AddEventHandler('tiktok_race:forceRaceState', function()
    print("^2[TikTok Race]^7 Server force race command received")
    
    gameState = GAME_STATES.RACE
    isRacing = true
    racingCam = true
    countdown = false
    queueList = false
    
    -- Start driving if players exist
    if playerNumber > 0 then
        startDrivingWithoutAI()
    end
    
    print("^2[TikTok Race]^7 ✅ Race state forced with " .. playerNumber .. " players!")
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        if raceCamera then
            DestroyCam(raceCamera, false)
            RenderScriptCams(false, false, 0, true, true)
        end
        
        killAllRacers()
        
        -- Reset player state
        SetEntityInvincible(PlayerPedId(), false)
        FreezeEntityPosition(PlayerPedId(), false)
        DisplayRadar(true)
    end
end)

-- Debug commands (only for development)
if GetConvar('tiktok_race_debug', 'false') == 'true' then
    RegisterCommand('ttr_debug', function()
        isDebug = not isDebug
        print("^3[TikTok Race]^7 Debug mode: " .. tostring(isDebug))
    end)
    
    RegisterCommand('ttr_start_driving', function()
        if gameState == GAME_STATES.RACE then
            startDriving()
        else
            print("^1[TikTok Race]^7 Not in race state (current: " .. gameState .. ")")
        end
    end)
    
    RegisterCommand('ttr_test_boost_local', function(source, args)
        local playerId = tonumber(args[1]) or 1
        local boost = tonumber(args[2]) or 10
        
        if gameState == GAME_STATES.RACE then
            boostPlayer(playerId, boost)
        else
            print("^1[TikTok Race]^7 Not in race state (current: " .. gameState .. ")")
        end
    end)
    
    RegisterCommand('ttr_test_join_local', function(source, args)
        local name = args[1] or "TestPlayer"
        local car = args[2] or "hermes"
        
        if gameState == GAME_STATES.QUEUE then
            createPlayer(name, car)
        else
            print("^1[TikTok Race]^7 Not in queue state (current: " .. gameState .. ")")
        end
    end)
end