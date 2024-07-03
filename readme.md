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

### How to Install Dependencies for `screenshot.lua` (32-bit, in DeSmuME environment)

1. Ensure you have the 32-bit version of `lua51.dll` in a directory added to PATH.
2. Obtain the `.lua` scripts for the `socket` and `mime` libraries [here](https://luarocks.org/modules/luasocket/luasocket/2.0.2-1). Download the file at the link titled [`win32-x86`](https://luarocks.org/manifests/luasocket/luasocket-2.0.2-1.win32-x86.rock). This file is an archive - use e.g. 7-zip to extract the contents, producing two directories: `lib` and `lua`.
3. The above contains 64-bit DLLs, but we want 32-bit DLLs, so go [here](https://github.com/pkulchenko/ZeroBraneStudio/blob/master/bin/clibs/socket/core.dll) (socket) and [here](https://github.com/pkulchenko/ZeroBraneStudio/blob/master/bin/clibs/mime/core.dll) (mime) to download the 32-bit versions of `core.dll` for `socket` and `mime` respectively. **Replace** the current versions of `core.dll` in the `lib` directories with these new 32-bit versions.
4. Obtain the `gd` library [here](https://downloads.onworks.net/softwaredownload.php?link=https%3A%2F%2Fdownloads.onworks.net%2Fdownloadapp%2FSOFTWARE%2Flua-gd-2.0.33r2-win32.zip%3Fservice%3Dservice01&filename=lua-gd-2.0.33r2-win32.zip). Extract all the `.dll` files: `free.type6.dll`, `gd.dll`, `jpeg62.dll`, `libgd2.dll`, `libiconv2.dll`, `libpng13.dll` into the same directory as the Lua engine DLL `lua51.dll`.
5. Re-organise the files of the other two directories (in Step 2, 3) to produce the following structure:
```
    .
    ├── socket/
        ├── socket/
            ├── core.dll
        ├── ftp.lua
        ├── http.lua
        ├── ltn12.lua
        ├── mime.lua
        ├── smtp.lua
        ├── socket.lua
        ├── tp.lua
        ├── url.lua
    ├── mime/
        ├── mime/
            ├── core.dll
    ├── freetype6.dll
    ├── gd.dll
    ├── jpeg62.dll
    ├── libgd2.dll
    ├── libiconv2.dll
    ├── libpng13.dll
    ├── lua51.dll
```
6. Inside `/socket/socket.lua`, on line 42, change `try = newtry()` to `try = socket.newtry()`.
7. In your own Lua script that you are using this for, import the modules.
    ```lua
    local gd_path = script_dir .. "path/to/gd.dll"
    local socket_path = script_dir .. "path/to/socket"
    local mime_path = script_dir .. "path/to/mime"

    package.path = socket_path .. "/?.lua;" .. mime_path .. "/?.lua;"
    package.cpath = socket_path .. "/?.dll;" .. mime_path .. "/?.dll;" .. gd_path

    local gd = require("gd")
    local socket = require("socket")
    local mime = require("mime")
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
