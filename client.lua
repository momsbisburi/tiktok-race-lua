-- TikTok Race FiveM Mod - Client Side
-- Port of the original GTA V Script Hook mod

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
    DrawText2D("Muzzy Tiktok Race " .. version, 0.0, 0.1, 0.3, {255, 0, 0, 255})
    
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

function DrawText2D(text, x, y, scale, color)
    SetTextFont(4)
    SetTextProportional(0)
    SetTextScale(scale, scale)
    SetTextColour(color[1], color[2], color[3], color[4])
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

function DrawRaceMenuItem(text, x, y, color, scale, shadow, qlist, alignCenter, cent)
    local finalX, finalY
    
    if cent then
        finalX = x
        finalY = y
    elseif qlist then
        finalX = x
        finalY = 0.3 + y + 0.05 -- Adjust positioning for queue list
    else
        finalX = 0.8 -- Right side of screen
        finalY = 0.3 + y + 0.05
    end
    
    SetTextFont(4)
    SetTextProportional(0)
    SetTextScale(scale, scale)
    SetTextColour(color[1], color[2], color[3], color[4])
    if shadow then
        SetTextDropShadow()
    end
    if alignCenter then
        SetTextCentre(true)
    end
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(finalX, finalY)
end

function drawRaceMenu()
    local menuIndex = 0
    
    if raceMenu then
        -- Draw background
        DrawRect(0.85, 0.4, 0.25, 0.3, 0, 0, 0, 150)
        
        if gameState == GAME_STATES.IDLE then
            DrawRaceMenuItem("TikTok Race Menu", 0.85, 0.0, {255, 165, 0, 255}, 0.7, false, false, true, false)
            DrawRaceMenuItem("[H] - Setup race!", 0.85, 0.05, {255, 255, 255, 255}, 0.4, false, false, true, false)
            
        elseif gameState == GAME_STATES.SETUP_DONE then
            DrawRaceMenuItem("TikTok Race Menu", 0.85, 0.0, {255, 165, 0, 255}, 0.7, false, false, true, false)
            if racePoint.x == 0.0 and racePoint.y == 0.0 then
                DrawRaceMenuItem("PLEASE SET WAYPOINT!", 0.85, 0.05, {64, 224, 208, 255}, 0.5, false, false, true, false)
            end
            DrawRaceMenuItem("[H] - Open Queue!", 0.85, 0.1, {255, 255, 255, 255}, 0.4, false, false, true, false)
            
        elseif gameState == GAME_STATES.QUEUE then
            if queueList then
                drawQueueList()
            else
                DrawRaceMenuItem("TikTok Race Menu", 0.85, 0.0, {255, 165, 0, 255}, 0.7, false, false, true, false)
                DrawRaceMenuItem("[H] - End Queue!", 0.85, 0.05, {255, 255, 255, 255}, 0.4, false, false, true, false)
                DrawRaceMenuItem("[J] - Open Queue List!", 0.85, 0.15, {255, 255, 255, 255}, 0.4, false, false, true, false)
            end
            
        elseif gameState == GAME_STATES.READY then
            DrawRaceMenuItem("TikTok Race Menu", 0.85, 0.0, {255, 165, 0, 255}, 0.7, false, false, true, false)
            DrawRaceMenuItem("[H] - Start countdown!", 0.85, 0.05, {255, 255, 255, 255}, 0.4, false, false, true, false)
            
        elseif gameState == GAME_STATES.RACE then
            DrawRaceMenuItem("TikTok Race Menu", 0.85, 0.0, {255, 165, 0, 255}, 0.7, false, false, true, false)
            DrawRaceMenuItem("Change camera (" .. (currentCamera + 1) .. "):", 0.85, 0.05, {255, 255, 255, 255}, 0.4, false, false, true, false)
            DrawRaceMenuItem("[<] - Previous player!", 0.85, 0.1, {255, 255, 255, 255}, 0.4, false, false, true, false)
            DrawRaceMenuItem("[>] - Next player!", 0.85, 0.15, {255, 255, 255, 255}, 0.4, false, false, true, false)
            DrawRaceMenuItem("[L] - Search player!", 0.85, 0.2, {255, 255, 255, 255}, 0.4, false, false, true, false)
            
            -- Draw leaderboard
            drawLeaderboard()
            
        elseif gameState == GAME_STATES.WINNERS then
            if winnersList then
                drawWinnersList()
            else
                DrawRaceMenuItem("TikTok Race Menu", 0.85, 0.0, {255, 165, 0, 255}, 0.7, false, false, true, false)
                DrawRaceMenuItem("[H] - Setup Race!", 0.85, 0.05, {255, 255, 255, 255}, 0.4, false, false, true, false)
                DrawRaceMenuItem("[J] - Open Winners List!", 0.85, 0.15, {255, 255, 255, 255}, 0.4, false, false, true, false)
            end
        end
    else
        -- Show minimized menu
        DrawRect(0.85, 0.35, 0.25, 0.08, 0, 0, 0, 150)
        DrawRaceMenuItem("[U] - Show Race Menu!", 0.85, 0.0, {255, 255, 255, 255}, 0.4, true, false, true, false)
        
        if gameState == GAME_STATES.RACE then
            drawLeaderboard()
        end
    end
end

function drawQueueList()
    -- Draw large background for queue list
    DrawRect(0.5, 0.5, 0.9, 0.6, 0, 0, 0, 150)
    
    DrawRaceMenuItem("[J] - Close Queue List!", 0.5, -0.2, {255, 255, 255, 255}, 0.4, true, false, true, true)
    DrawRaceMenuItem("Joined: " .. playerNumber .. "/" .. maxPlayers .. " | Write !join in chat to enter the race", 0.5, -0.1, {255, 255, 255, 255}, 0.8, true, true, true, true)
    DrawRaceMenuItem("___________________________", 0.5, -0.05, {255, 255, 255, 255}, 0.8, true, true, true, true)
    DrawRaceMenuItem("Players List", 0.5, 0.0, {0, 0, 255, 255}, 0.7, true, true, true, true)
    
    -- Draw player list in columns
    local column = 0
    local row = 0
    for i = 1, playerNumber do
        if playerNames[i] and playerNames[i] ~= "" then
            local name = playerNames[i]
            if string.len(name) > 13 then
                name = string.sub(name, 1, 13)
            end
            
            local x = 0.3 + (column * 0.2)
            local y = 0.1 + (row * 0.025)
            
            DrawRaceMenuItem(i .. ". " .. name, x, y, {255, 255, 255, 255}, 0.4, true, true, false, true)
            
            row = row + 1
            if row >= 19 then
                row = 0
                column = column + 1
            end
        end
    end
end

function drawLeaderboard()
    -- Draw leaderboard background
    DrawRect(0.15, 0.4, 0.25, 0.3, 0, 0, 0, 150)
    DrawRaceMenuItem("Leaderboard", 0.15, -0.1, {0, 255, 255, 255}, 0.7, false, false, true, true)
    
    -- Sort players by distance to finish
    local sortedPlayers = {}
    for i = 1, playerNumber do
        if playerPositions[i] then
            table.insert(sortedPlayers, playerPositions[i])
        end
    end
    table.sort(sortedPlayers)
    
    -- Draw top 10
    for i = 1, math.min(10, #sortedPlayers) do
        local parts = {}
        for part in string.gmatch(sortedPlayers[i], "[^|]+") do
            table.insert(parts, part)
        end
        if #parts >= 2 then
            local y = -0.05 + (i * 0.025)
            DrawRaceMenuItem(i .. ". " .. parts[2], 0.05, y, {255, 255, 255, 255}, 0.5, false, false, false, true)
        end
    end
end

function drawWinnersList()
    -- Draw winners list background
    DrawRect(0.5, 0.5, 0.4, 0.45, 0, 0, 0, 150)
    
    DrawRaceMenuItem("[J] - Close Winners List!", 0.5, -0.15, {255, 255, 255, 255}, 0.4, true, false, true, true)
    DrawRaceMenuItem("Leaderboard", 0.5, -0.1, {255, 255, 255, 255}, 0.8, true, true, true, true)
    DrawRaceMenuItem("____________", 0.5, -0.05, {255, 255, 255, 255}, 0.8, true, true, true, true)
    
    DrawRaceMenuItem("1st " .. place1, 0.5, 0.0, {255, 255, 255, 255}, 0.9, true, true, true, true)
    DrawRaceMenuItem("2nd " .. place2, 0.5, 0.06, {255, 255, 255, 255}, 0.6, true, true, true, true)
    if playerNumber >= 3 then
        DrawRaceMenuItem("3rd " .. place3, 0.5, 0.12, {255, 255, 255, 255}, 0.4, true, true, true, true)
    end
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
            startDriving()
            
        elseif seconds < 1 then
            if soundPlayId ~= soundPlayIdS then
                PlaySoundFrontend(-1, "Beep_Green", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
                soundPlayId = soundPlayIdS
            end
            DrawRaceMenuItem("GO!!!", 0.5, 0.5, {0, 255, 0, 255}, 1.5, true, false, true, true)
        elseif seconds <= 3 then
            if soundPlayId ~= soundPlayIdS then
                PlaySoundFrontend(-1, "3_2_1", "HUD_MINI_GAME_SOUNDSET", true)
                soundPlayId = soundPlayIdS
            end
            DrawRaceMenuItem(tostring(seconds), 0.5, 0.5, {255, 0, 0, 255}, 1.5, true, false, true, true)
        else
            if soundPlayId ~= soundPlayIdS then
                PlaySoundFrontend(-1, "3_2_1", "HUD_MINI_GAME_SOUNDSET", true)
                soundPlayId = soundPlayIdS
            end
            DrawRaceMenuItem(tostring(seconds), 0.5, 0.5, {255, 255, 255, 255}, 1.5, true, false, true, true)
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
    local line = 10
    
    if not websocketConnected then
        DrawText2D("Not connected...", 0.0, 0.0, 0.3, {255, 0, 0, 255})
    end
    
    if isDebug then
        DrawText2D("Debug info: ", 0.0, line * 0.02, 0.3, {255, 165, 0, 255})
        line = line + 1
        
        if websocketConnected then
            DrawText2D("Connected", 0.0, line * 0.02, 0.3, {0, 255, 0, 255})
        else
            DrawText2D("Not connected", 0.0, line * 0.02, 0.3, {255, 0, 0, 255})
        end
        line = line + 1
        
        DrawText2D("Disable peds: " .. tostring(pedsEnabled), 0.0, line * 0.02, 0.3, pedsEnabled and {0, 255, 0, 255} or {255, 0, 0, 255})
        line = line + 1
        
        DrawText2D("Enable AI: " .. tostring(aiMode), 0.0, line * 0.02, 0.3, aiMode and {255, 0, 0, 255} or {0, 255, 0, 255})
    end
end

local isSpawning = false

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
        
        -- Reset variables
        playerNumber = 0
        place = 0
        playerNames = {}
        
        gameState = GAME_STATES.SETUP_DONE
        TriggerServerEvent('tiktok_race:setGameState', gameState)
        
    elseif gameState == GAME_STATES.SETUP_DONE then
        if racePoint.x == 0.0 and racePoint.y == 0.0 then
            return
        end
        
        -- Reset spawn positioning
        playersRowCount = 0
        playersRowNumber = 1
        playersX = 0.0
        playersY = 0.0
        queueList = true
        
        gameState = GAME_STATES.QUEUE
        TriggerServerEvent('tiktok_race:setGameState', gameState)
        
    elseif gameState == GAME_STATES.QUEUE then
        if playerNumber < 2 then
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
        -- Reset for new race
        SetEntityInvincible(PlayerPedId(), true)
        FreezeEntityPosition(PlayerPedId(), true)
        DisplayRadar(false)
        SetEntityCoords(PlayerPedId(), 1717.06, 3287.031, 41.16869, false, false, false, true)
        
        if raceCamera then
            SetCamActive(raceCamera, true)
            RenderScriptCams(true, false, 0, true, true)
        end
        
        playerNumber = 0
        place = 0
        playerNames = {}
        
        gameState = GAME_STATES.SETUP_DONE
        TriggerServerEvent('tiktok_race:setGameState', gameState)
    elseif gameState == GAME_STATES.SETUP_DONE then
            if racePoint.x == 0.0 and racePoint.y == 0.0 then
                return
            end
            
            -- FIXED: Reset spawn positioning exactly like C# does
            -- C# code:
            -- this.Players_r_nr = 0;
            -- this.Players_r_n = 1;
            -- this.Players_X = 0f;
            -- this.Players_Y = 0f;
            playersRowCount = 0      -- Players_r_nr
            playersRowNumber = 1     -- Players_r_n  
            playersX = 0.0          -- Players_X
            playersY = 0.0          -- Players_Y
            
            queueList = true
            
            gameState = GAME_STATES.QUEUE
            TriggerServerEvent('tiktok_race:setGameState', gameState)
    end
end

function createPlayer(name, carModel)
    -- Prevent multiple simultaneous spawns
    if isSpawning then
        print("^3[TikTok Race]^7 Spawn in progress, queuing: " .. name)
        -- Wait a bit and try again
        SetTimeout(200, function()
            createPlayer(name, carModel)
        end)
        return
    end
    
    if playerNumber >= maxPlayers or gameState ~= GAME_STATES.QUEUE then
        print("^1[TikTok Race]^7 Cannot create player - wrong state or full")
        return
    end
    
    -- Lock spawning
    isSpawning = true
    
    carModel = carModel or GetHashKey("hermes") -- Default car
    if type(carModel) == "string" then
        carModel = GetHashKey(carModel)
    end
    
    print("^3[TikTok Race]^7 Creating player " .. (playerNumber + 1) .. ": " .. name)
    
    -- CALCULATE spawn position BEFORE any async operations
    local currentSpawnX = playersX
    local currentSpawnY = playersY
    local spawnPos = vector3(1722.0 + currentSpawnX, 3239.0 + currentSpawnY, 40.7287)
    
    print("^3[TikTok Race]^7 Spawn position: " .. spawnPos.x .. ", " .. spawnPos.y .. " (X=" .. currentSpawnX .. ", Y=" .. currentSpawnY .. ")")
    
    -- UPDATE spawn position variables IMMEDIATELY for next player
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
    
    print("^3[TikTok Race]^7 Next spawn prepared: X=" .. playersX .. ", Y=" .. playersY .. ", Row=" .. playersRowNumber)
    
    -- Clear area to prevent overlapping
    ClearAreaOfVehicles(spawnPos.x, spawnPos.y, spawnPos.z, 10.0, false, false, false, false, false)
    ClearAreaOfPeds(spawnPos.x, spawnPos.y, spawnPos.z, 10.0, 1)
    
    -- Create vehicle
    RequestModel(carModel)
    while not HasModelLoaded(carModel) do
        Wait(1)
    end
    
    local vehicle = CreateVehicle(carModel, spawnPos.x, spawnPos.y, spawnPos.z, 286.7277, true, false)
    
    if not DoesEntityExist(vehicle) then
        print("^1[TikTok Race]^7 Failed to create vehicle for " .. name)
        isSpawning = false -- Unlock spawning
        return
    end
    
    -- Create ped
    local pedModel = GetHashKey("a_m_m_skater_01")
    RequestModel(pedModel)
    while not HasModelLoaded(pedModel) do
        Wait(1)
    end
    
    local ped = CreatePed(4, pedModel, 1732.0, 3204.0, 43.0, 0.0, true, false)
    
    if not DoesEntityExist(ped) then
        print("^1[TikTok Race]^7 Failed to create ped for " .. name)
        DeleteEntity(vehicle)
        isSpawning = false -- Unlock spawning
        return
    end
    
    -- Add blip to vehicle
    local blip = AddBlipForEntity(vehicle)
    SetBlipSprite(blip, 56)
    SetBlipColour(blip, 3)
    
    -- Set vehicle properties
    SetVehicleAsNoLongerNeeded(vehicle)
    SetEntityInvincible(vehicle, true)
    SetVehicleEngineOn(vehicle, true, true, false)
    
    -- Set ped properties
    SetEntityInvincible(ped, true)
    SetPedCanBeDraggedOut(ped, false)
    SetPedCanBeKnockedOffVehicle(ped, 1)
    SetPedCanBeShotInVehicle(ped, false)
    SetPedStayInVehicleWhenJacked(ped, true)
    ClearPedTasks(ped)
    TaskStandStill(ped, -1)
    SetPedKeepTask(ped, true)
    
    -- Store in arrays - INCREMENT playerNumber FIRST
    playerNumber = playerNumber + 1
    players[playerNumber] = ped
    vehicles[playerNumber] = vehicle
    playerNames[playerNumber] = name
    playerSpeeds[playerNumber] = 0
    
    -- Put ped into vehicle
    SetPedIntoVehicle(ped, vehicle, -1)
    
    print("^2[TikTok Race]^7 ✅ Created player " .. playerNumber .. ": " .. name .. " at position " .. spawnPos.x .. ", " .. spawnPos.y)
    
    SetModelAsNoLongerNeeded(carModel)
    SetModelAsNoLongerNeeded(pedModel)
    
    -- Small delay before unlocking to ensure everything is settled
    SetTimeout(150, function()
        isSpawning = false -- Unlock spawning
        print("^3[TikTok Race]^7 Spawn completed for " .. name .. ", ready for next player")
    end)
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


-- REPLACE the original startDriving function
function startDriving()
    print("^2[TikTok Race]^7 Starting race with " .. playerNumber .. " players")
    
    for i = 1, playerNumber do
        if DoesEntityExist(players[i]) and DoesEntityExist(vehicles[i]) then
            local ped = players[i]
            local vehicle = vehicles[i]
            
            print("^3[TikTok Race]^7 Setting up AI for player " .. i .. ": " .. (playerNames[i] or "Unknown"))
            
            -- FOR TESTING: Give cars a default speed so they move immediately
            playerSpeeds[i] = 15  -- Default testing speed (change to 0 for production)
            
            -- Configure AI driving abilities
            SetDriverAbility(ped, 1.0)  -- Max driving skill
            SetDriverAggressiveness(ped, 0.4)  -- Moderate aggression
            
            -- Make sure vehicle is ready
            SetVehicleEngineOn(vehicle, true, true, false)
            SetVehicleOnGroundProperly(vehicle)
            
            -- Start AI driving at testing speed
            TaskVehicleDriveToCoord(ped, vehicle, 
                racePoint.x, racePoint.y, racePoint.z,  -- Destination
                playerSpeeds[i],  -- Testing speed (15)
                0,    -- No special flags
                GetEntityModel(vehicle),
                262144 + 4 + 8,  -- NORMAL + AVOID_TRAFFIC + AVOID_VEHICLES
                15.0,  -- Target radius
                -1.0   -- Straight line distance
            )
            
            print("^2[TikTok Race]^7 Player " .. i .. " starting with testing speed: " .. playerSpeeds[i])
        end
    end
    
    print("^2[TikTok Race]^7 🏁 All cars driving at testing speed! Boosts will make them faster!")
end

function renderNames()
    if gameState == GAME_STATES.RACE then
        for i = 1, playerNumber do
            if DoesEntityExist(players[i]) and DoesEntityExist(vehicles[i]) then
                local ped = players[i]
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
                
                -- Draw name above player if nearby
                local playerPos = GetEntityCoords(PlayerPedId())
                if #(pedPos - playerPos) < 50.0 and IsEntityOnScreen(ped) then
                    local screenX, screenY = GetScreenCoordFromWorldCoord(pedPos.x, pedPos.y, pedPos.z + 1.0)
                    if screenX and screenY then
                        SetTextFont(4)
                        SetTextProportional(0)
                        SetTextScale(0.5, 0.5)
                        SetTextColour(255, 255, 255, 255)
                        SetTextDropShadow()
                        SetTextCentre(true)
                        SetTextEntry("STRING")
                        AddTextComponentString(playerNames[i])
                        DrawText(screenX, screenY)
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

function boostPlayer(playerId, speed, nitro)
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
    
    -- PERMANENT SPEED INCREASE - speed never decreases!
    local oldSpeed = playerSpeeds[playerId] or 0
    playerSpeeds[playerId] = math.min(oldSpeed + speed, 80) -- Add to permanent speed, cap at 80
    local newSpeed = playerSpeeds[playerId]
    
    print("^2[TikTok Race]^7 🚀 PERMANENT SPEED BOOST player " .. playerId .. " (" .. (playerNames[playerId] or "Unknown") .. ") from " .. oldSpeed .. " to " .. newSpeed .. " (PERMANENT)")
    
    -- Update AI driving with new PERMANENT speed
    -- This becomes the car's new cruising speed until the race ends
    TaskVehicleDriveToCoord(ped, vehicle,
        racePoint.x, racePoint.y, racePoint.z,
        newSpeed,  -- New permanent driving speed
        0,         -- No special flags
        GetEntityModel(vehicle),
        262144 + 4 + 8,  -- NORMAL + AVOID_TRAFFIC + AVOID_VEHICLES
        15.0,      -- Target radius
        -1.0       -- Straight line distance
    )
    
    -- Update AI behavior based on permanent speed
    if newSpeed > 40 then
        SetDriverAggressiveness(ped, 0.9)  -- Very aggressive for fast cars
        print("^3[TikTok Race]^7 Player " .. playerId .. " now drives aggressively (high speed)")
    elseif newSpeed > 20 then
        SetDriverAggressiveness(ped, 0.6)  -- Medium aggression
        print("^3[TikTok Race]^7 Player " .. playerId .. " now drives moderately (medium speed)")
    elseif newSpeed > 5 then
        SetDriverAggressiveness(ped, 0.3)  -- Careful driving for slow cars
        print("^3[TikTok Race]^7 Player " .. playerId .. " now drives carefully (low speed)")
    else
        SetDriverAggressiveness(ped, 0.1)  -- Very careful for very slow cars
        print("^3[TikTok Race]^7 Player " .. playerId .. " crawling forward (very low speed)")
    end
    
    -- ONLY apply nitro force for actual nitro gifts
    if nitro then
        print("^2[TikTok Race]^7 💨 NITRO EXPLOSION for player " .. playerId .. "!")
        
        -- Apply explosive nitro force (temporary visual effect)
        local forwardVector = GetEntityForwardVector(vehicle)
        local nitroForce = speed * 4.0  -- Strong explosive push
        
        ApplyForceToEntity(vehicle, 1, 
            forwardVector.x * nitroForce, 
            forwardVector.y * nitroForce, 
            0.0,  -- No vertical force
            0.0, 0.0, 0.0,  -- No rotation
            0,    -- Bone index
            false, true, true, false, true
        )
        
        -- Temporary speed burst for visual effect
        SetVehicleForwardSpeed(vehicle, newSpeed * 1.2)
    else
        -- Normal boost - just permanent speed increase, no forces
        print("^2[TikTok Race]^7 ⚡ Normal speed increase (permanent)")
    end
    
    -- Show current status
    if newSpeed == 0 then
        print("^1[TikTok Race]^7 Player " .. playerId .. " is still stationary")
    else
        print("^2[TikTok Race]^7 Player " .. playerId .. " now permanently drives at speed " .. newSpeed)
    end
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
    if gameState == GAME_STATES.QUEUE then
        createPlayer(playerName, carModel)
    end
end)

RegisterNetEvent('tiktok_race:boostPlayer')
AddEventHandler('tiktok_race:boostPlayer', function(playerId, boostAmount)
    if gameState == GAME_STATES.RACE and not aiMode then
        boostPlayer(playerId, boostAmount)
    end
end)

RegisterNetEvent('tiktok_race:websocketStatus')
AddEventHandler('tiktok_race:websocketStatus', function(connected)
    websocketConnected = connected
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
end

