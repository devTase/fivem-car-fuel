fx_version 'cerulean'
game 'gta5'

author 'kori91'
description 'Script to show amount of fuel of the current car'
version '1.0.0'

lua54 'yes'

client_script 'client/client.lua'
server_scripts {
    'server/db_setup.lua',
    'server/server.lua',
    '@oxmysql/lib/MySQL.lua'
}

shared_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@es_extended/imports.lua'
} 
