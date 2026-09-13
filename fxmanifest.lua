fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'jgrp-garage'
author 'jgrp'
description 'Parking-lot garages: config-driven lots with bounds and spot arrays, radial-menu parking, per-vehicle spot memory'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/lots.lua'
}

client_scripts {
    'client/main.lua',
    'client/dev.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

-- qb-radialmenu is checked at runtime rather than declared, so a missing radial
-- degrades to the /park command instead of stopping the resource from starting.
dependencies {
    'ox_lib',
    'oxmysql',
    'qb-core'
}
