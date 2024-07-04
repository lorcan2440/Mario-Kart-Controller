local script_dir = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]
local gd_path = script_dir .. "lua_libs/gd"
package.cpath = gd_path .. "/gd.dll;"

local gd = require('gd')

print(gd.VERSION)