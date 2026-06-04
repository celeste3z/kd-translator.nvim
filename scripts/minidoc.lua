local minidoc = require('mini.doc')
if _G.MiniDoc == nil then minidoc.setup() end

MiniDoc.generate({ 'lua/kd-translator/init.lua' }, 'doc/kd-translator.txt')
