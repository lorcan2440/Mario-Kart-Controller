# Mario Kart DS Control System

This project explores the techniques of control theory and related concepts to develop a control system for the game Mario Kart DS. The game is played automatically in the DeSmuME emulator, with automation provided by a Lua script. The main loop of the program is:

- Lua script in DeSmuME captures a screenshot of the current game frame
- Lua script sends the screenshot to a Python script via a TCP IPv4 socket
- Python script uses computer vision (OpenCV) to extract the game state from the screenshot
- Python script uses a control algorithm to determine the desired control input (button presses)
- Python script sends the button press commands back to the Lua script
- Lua script presses the required buttons in the emulator, progressing the game state

### Requirements

- Windows 11
- DeSmuME (x86), set up to use 32-bit Lua 5.1
- Lua libraries: [lua-gd](https://github.com/ittner/lua-gd), [LuaSocket](https://github.com/lunarmodules/luasocket)
- Python libraries: [OpenCV](https://pypi.org/project/opencv-python/), [NumPy](https://numpy.org/)
- Mario Kart DS ROM

### How to Run

1. Open DeSmuME with Mario Kart DS.
2. In python, run `receive_data.py` to set up a server.
3. In the Lua scripting window of DeSmuME, load `screenshot.lua`.
4. Start a race in Mario Kart.
5. You will see game in OpenCV playing itself.

### How to Install Lua Dependencies (for `stream_socket.lua`, 32-bit, in DeSmuME environment)

1. Ensure you have the 32-bit version of `lua51.dll` in a directory added to PATH.
2. Obtain the pre-built 32-bit Lua 5.1 LuaSocket libraries (`socket` and `mime`) from [this source](https://www.unrealsoftware.de/files_show.php?file=16117). Download and extract to the script directory.
3. Obtain the pre-built `gd` library [here](https://downloads.onworks.net/softwaredownload.php?link=https%3A%2F%2Fdownloads.onworks.net%2Fdownloadapp%2FSOFTWARE%2Flua-gd-2.0.33r2-win32.zip%3Fservice%3Dservice01&filename=lua-gd-2.0.33r2-win32.zip). Extract all the `.dll` files: `free.type6.dll`, `gd.dll`, `jpeg62.dll`, `libgd2.dll`, `libiconv2.dll`, `libpng13.dll`.
4. The required directory structure is shown in the `lua_libs` folder inside this repo. Copy the extracted files to the appropriate directories. It has the following structure:
```
    lua_libs/
    ├── gd/
    │   ├── free.type6.dll
    │   ├── gd.dll
    │   ├── jpeg62.dll
    │   ├── libgd2.dll
    │   ├── libiconv2.dll
    │   └── libpng13.dll
    ├── socket/
    │   └── core.dll
    ├── mime/
    │   └── core.dll
    └── lua/
        ├── socket/
        │   ├── ftp.lua
        │   ├── http.lua
        │   ├── smtp.lua
        │   ├── tp.lua
        │   └── url.lua
        ├── headers.lua
        ├── ltn12.lua
        ├── mbox.lua
        ├── mime.lua
        └── socket.lua
```
5. In your own Lua scripts, import the modules from those directories as follows:
    ```lua
    local script_dir = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]  -- directory of this file
    local gd_path = script_dir .. "lua_libs/gd"
    local socket_path = script_dir .. "lua_libs/socket"
    local mime_path = script_dir .. "lua_libs/mime"

    -- import gd library
    package.cpath = gd_path .. "/gd.dll;"
    local gd = require('gd')

    -- import luasocket library
    package.path = script_dir .. "lua_libs/lua/?.lua;"
    package.cpath = socket_path .. "/core.dll;" .. mime_path .. "/core.dll;"
    local socket = require('socket')
    ```

### To do list

- [x] Find out how to take screenshots in Lua
- [x] Use sockets to stream the screen image data to Python's OpenCV library
- [ ] Try to optimise the streaming rate: use UDP sockets instead of TCP, send grayscale images only, etc
- [ ] Use morphological operations to produce sharper images of the track
- [ ] Allow the player to manually steer while the script automatically holds A
- [ ] Write the OpenCV and socket Python program in C++ for faster processing - may not actually improve performance that much but will be good for learning

Ideas for control algorithm:
- Set a specified path and design a PID controller to follow it (line following)
- Or MPC with discrete inputs [reference](https://ieeexplore.ieee.org/document/1346886)
- Use MATLAB to design optimal controllers ($H_2$ or $H_{\infty}$)
- Deep reinforcement learning using OpenAI gym
- - RL with human feedback - allow manual steering override as feedback signal. Look at how Wayve did this for autonomous driving.
