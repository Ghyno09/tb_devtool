fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'the basics - devtool'
author 'The Basics'
description 'The Basics - Dev Tool: point-and-copy prop coordinates, and a freecam zone builder'
version '1.1.0'

dependencies {
  'ox_lib',
}

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
}

client_scripts {
  'client/ray.lua',
  'client/render.lua',
  'client/freecam.lua',
  'client/zone.lua',
  'client/main.lua',
  'client/zonemode.lua',
}

server_scripts {
  'server/main.lua',
}

files {
  'web/index.html',
  'web/style.css',
  'web/app.js',
}

ui_page 'web/index.html'
