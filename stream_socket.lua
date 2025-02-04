--[[
How to run:

1. Run the Python program `main.py` first, which starts the server.
2. Load and run this Lua script `stream_socket.lua` in DeSmuME.
3. Observe the live stream of the game screen and control the game using the Python script.
4. Press the 'q' key at any time while on the DeSmuME window to stop the streaming.

Info and docs:

Mario Kart DS Player information:
https://tasvideos.org/GameResources/DS/MarioKartDS#TricksAndGameMechanics

Mario Kart DS Modding Community Discord Server:
https://discord.com/invite/CAktUYP

DeSmuME Lua Script Source
https://github.com/TASEmulators/desmume/blob/master/desmume/src/lua-engine.cpp
]]


local script_dir = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]
local gd_path = script_dir .. "lua_libs/gd"
local socket_path = script_dir .. "lua_libs/socket"
local mime_path = script_dir .. "lua_libs/mime"

-- import gd library
package.cpath = gd_path .. "/gd.dll;"
local gd = require('gd')

-- import luasocket library
package.path = script_dir .. "lua_libs/luasocket/?.lua;"
package.cpath = socket_path .. "/core.dll;" .. mime_path .. "/core.dll;"
local socket = require('socket')

--print(gd.VERSION)
--print(socket._VERSION)

local file = io.open('stream_log.log', 'a')
io.stdout = file

local host, port = "127.0.0.1", 12345
local client = assert(socket.connect(host, port))
client:settimeout(0.5)  -- set 500 ms timeout for non-blocking mode
print("Connected to the server: " .. host .. ":" .. port)

OR, XOR, AND = 1, 3, 4

local ptrRacerDataAddr = 0x0217ACF8  -- pointer to the player data structure

function bitoper(a, b, oper)
    -- performs a bitwise operation
    -- source: https://stackoverflow.com/a/32389020/8747480
    local r, m, s = 0, 2^31
    repeat
        s, a, b = a + b + m, a % m, b % m
        r, m = r + m * oper % (s - a - b), m / 2
    until m < 1
    return r
end

function sendScreenshot()
    local screen = gui.gdscreenshot("top")  -- options: "both" (default), "top", "bottom"
    local img = gd.createFromGdStr(screen)
    local pngData = img:pngStr()
    local dataLength = string.format("%09d", #pngData)
    client:send(dataLength)
    client:send(pngData)
end

function receiveButtons()
    local data, err = client:receive(1)  -- 1 byte from the Python script
    if data then
        local buttons = string.byte(data)
        -- decode the buttons
        -- A: 128, Left: 64, Right: 32, Unused: 16, 8, 4, 2, 1
        local A_press = bitoper(buttons, 128, AND) ~= 0
        local left_press = bitoper(buttons, 64, AND) ~= 0
        local right_press = bitoper(buttons, 32, AND) ~= 0
        -- only actively set left and right to pressed if they are  received
        -- this allows manual override while driving
        local buttons_table = {}
        if left_press then
            buttons_table = {A = A_press, left = left_press}
        elseif right_press then
            buttons_table = {A = A_press, right = right_press}
        else
            buttons_table = {A = A_press}
        end
        joypad.set(1, buttons_table)
        -- other useful functions for allowing manual override:
        -- joypad.get(), joypad.read(), joypad.peek(), joypad.set()
        -- can also request which buttons are 'only pressed' (down) or 'only released' (up)
    else
        -- socket is closed
        print("Error receiving button input data:", err, "at", socket.gettime())
        print("Disconnecting from server and pausing the game.")
        client:close()
        emu.pause()
    end
end

local function read_dword_table_le(data, offset)
    -- read four bytes from the data table in little-endian order
    return 256^0 * data[offset] + 256^1 * data[offset + 1] + 256^2 * data[offset + 2] + 256^3 * data[offset + 3]
end

function sendData()
    -- extract useful data from the game memory
    -- this will be used in the RL agent's reward model
    local ptrPlayerData = memory.readdwordsigned(ptrRacerDataAddr)
    local allData = memory.readbyterange(ptrPlayerData + 1, 0x5A8 - 1)
    local speed = read_dword_table_le(allData, 0x2A8)
    local maxSpeed = read_dword_table_le(allData, 0xD0)
    local offroadSpeed = read_dword_table_le(allData, 0xDC)
    print(speed, maxSpeed, offroadSpeed)
end

-- main event loop
while not input.get().Q do  -- press key 'q' while on DeSmuME window to stop streaming
    sendScreenshot()
    sendData()
    receiveButtons()
    emu.frameadvance()
end

print("Quitting and disconnecting from the server.")
client:close()
file:close()