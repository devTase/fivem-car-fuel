fx_version 'cerulean'
games { 'gta5' }
use_experimental_fxv2_oal 'yes'

name 'fivem-car-fuel'
author 'devTASE'
description 'Advanced vehicle fuel management system with optimization and caching'
version '2.0.0'
repository 'https://github.com/ctw02217/fivem-car-fuel'

lua54 'yes'

-- Resource metadata
provides {
    'car_fuel_system',
    'vehicle_fuel_management'
}

-- Dependency declarations
dependencies {
    'es_extended',
    'oxmysql'
}

-- Manifest version ensures compatibility with newer FiveM versions
fxdk_manifest_version '1'

-- Scripts
client_scripts {
    'client/client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua'
}

shared_scripts {
    '@es_extended/imports.lua'
}

-- Proper versioning
version_requires_oxmysql '2.0.0'
version_requires_es_extended '1.8.5'

-- Convar defaults
server_only 'no'
