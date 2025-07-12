fx_version 'cerulean'
game 'gta5'

name 'TikTok Race'
description 'Interactive TikTok Racing Mod for FiveM - Viewers can join races and boost players through TikTok interactions'
author 'Muzzy (Ported to FiveM)'
version '0.6.0'

-- Client scripts
client_scripts {
    'client.lua'
}

-- Server scripts
server_scripts {
    'server.lua'
}

-- Configuration files
files {
    'config.json'
}

-- Dependencies (if any WebSocket libraries are available)
dependencies {
    -- Add WebSocket dependency here when available
}

-- Export functions for other resources
exports {
    'getCurrentGameState',
    'getPlayerCount',
    'isRaceActive'
}

server_exports {
    'simulateTikTokEvent',
    'handleTikTokLike',
    'handleTikTokGift',
    'handleTikTokChat'
}