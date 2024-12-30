-- Authors: Suuper; some checkpoint and pointer stuffs from MKDasher
-- A Lua script that aims to be helpful for creating tool-assisted speedruns.

-- Script options ---------------------
local collisionScaleFactor = 0.8 / client.getwindowsize()
local showExactMovement = true -- set to true to display movement sine/cosine
local showAnglesAsDegrees = false
local drawAllObjects = false
local increaseCollisionRenderDistance = false
local giveGhostShrooms = false
local seekSettings = {
	alertOnRewindAfterBranch = true, -- BizHawk simply does not support nice seeking behavior, so we can't do it for you.
}
local showBizHawkDumbnessWarning = false
---------------------------------------

-- Pointer internationalization -------
-- This is intended to make the script compatible with most ROM regions and ROM hacks.
-- This is not well-tested. There are some known exceptions, such as Korean version has different locations for checkpoint stuff.
local somePointerWithRegionAgnosticAddress = memory.read_u32_le(0x2000B54)
local valueForUSVersion = 0x0216F320
local ptrOffset = somePointerWithRegionAgnosticAddress - valueForUSVersion
-- Base addresses are valid for the US Version
local ptrRacerDataAddr = 0x0217ACF8 + ptrOffset
local ptrPlayerInputsAddr = 0x02175630 + ptrOffset
local ptrGhostInputsAddr = 0x0217568C + ptrOffset
local ptrItemInfoAddr = 0x0217BC2C + ptrOffset
local ptrRaceTimersAddr = 0x0217AA34 + ptrOffset
local ptrMissionInfoAddr = 0x021A9B70 + ptrOffset
local ptrObjStuff = 0x0217B588 + ptrOffset
local racerCountAddr = 0x0217ACF4 + ptrOffset
local ptrSomethingPlayerAddr = 0x021755FC + ptrOffset
local ptrSomeRaceDataAddr = 0x021759A0 + ptrOffset
local ptrCheckNumAddr = 0x021755FC + ptrOffset
local ptrCheckDataAddr = 0x02175600 + ptrOffset
local ptrScoreCountersAddr = 0x0217ACFC + ptrOffset
local ptrCollisionDataAddr = 0x0217b5f4 + ptrOffset
local ptrCurrentCourse = 0x23cdcd8 + ptrOffset
local ptrCameraAddr = 0x217AA4C + ptrOffset
---------------------------------------
-- These have the same address in E and U versions.
-- Not sure about other versions. K +0x5224 for car at least.
local carHitboxFunc = memory.read_u32_le(0x2158ad4)
local bumperHitboxFunc = memory.read_u32_le(0x209c190)
local clockHandHitboxFunc = memory.read_u32_le(0x2159158)
local pendulumHitboxFunc = memory.read_u32_le(0x21592e8)
local rockyWrenchHitboxFunc = memory.read_u32_le(0x2095fe8)
---------------------------------------

-- BizHawk shenanigans
if script_id == nil then
	script_id = 1
else
	script_id = script_id + 1
end
local my_script_id = script_id
local shouldExit = false
local redrawSeek = nil
local function redraw()
	-- BizHawk won't clear it for us on the next frame, if we don't actually draw anything on the next frame.
	gui.clearGraphics("client")
	gui.clearGraphics("emucore")

	-- If we are not paused, there's no point in redrawing. The next frame will be here soon enough.
	if not client.ispaused() then
		return
	end
	-- BizHawk does not let us re-draw while paused. So the only way to redraw is to rewind and come back to this frame.
	if not tastudio.engaged() then
		return
	end
	local frame = emu.framecount()
	-- tastudio.setplayback(frame - 1)
	-- emu.yield() -- this throws an Exception in BizHawk's code
	-- We ALSO cannot use tastudio.setplayback, at all. Because BizHawk won't trigger Lua while such a seek is happening so (1) we won't have the right data when it's done and (2) we have no way of knowing when it is done.
	--tastudio.setplayback(frame)
	
	-- Can we go back TWO frames, then unpause?
	--tastudio.setplayback(frame - 2)
	-- Yes, we can. BUT, if TAStudio has to rewind then emulate it will do so while the UI is frozen and unresponsive, and Lua scripts will not run during that time!
	local f = frame - 2
	while not tastudio.hasstate(f) do
		f = f - 1
	end
	tastudio.setplayback(f + 1) -- +1 because TAStudio always wants to emulate at least one frame.
	redrawSeek = frame
	client.unpause()
end

-- Some stuff
local function ZeroVector()
	return { x = 0, y = 0, z = 0 }
end
local function NewMyData()
	local n = {}
	n.positionDelta = 0
	n.angleDelta = 0
	n.driftAngleDelta = 0
	n.pos = ZeroVector()
	n.facingAngle = 0
	n.driftAngle = 0
	n.movementDirection = ZeroVector()
	n.movementTarget = ZeroVector()
	return n
end
local function UpdateMag(vector)
	local x = vector.x / 4096
	local y = vector.y / 4096
	local z = vector.z / 4096
	local sxz = x * x + z * z
	vector.mag2 = math.sqrt(sxz)
	vector.mag3 = math.sqrt(sxz + y * y)
end
local myData = NewMyData()
local ghostData = NewMyData()

local raceData = {}
local nearestObjectData = nil

local lastFrame = 0

local form = nil
local watchingGhost = false
local drawWhileUnpaused = true
local courseId = nil

local function clearDataOutsideRace()
	ghostData = NewMyData()
	raceData = {
		coinsBeingCollected = 0,
	}
	nearestObjectData = nil
	form.ghostInputs = nil
	forms.settext(form.ghostInputHackButton, "Copy from player")
	courseId = nil
end

-- General stuffs -------------------------------
function contains(list, x)
	for _, v in ipairs(list) do
		if v == x then return true end
	end
	return false
end

local function time(secs)
	t_sec = math.floor(secs) % 60
	if (t_sec < 10) then t_secaux = "0" else t_secaux = "" end
	t_min = math.floor(secs / 60)
	t_mili = math.floor(secs * 1000) % 1000
	if (t_mili < 10) then t_miliaux = "00" elseif (t_mili < 100) then t_miliaux = "0" else t_miliaux = "" end
	return (t_min .. ":" .. t_secaux .. t_sec .. ":" .. t_miliaux .. t_mili)
end
local function padLeft(str, len)
	-- https://cplusplus.com/reference/cstdio/printf/
	return string.format("%" .. len .. "s", str)
end
local function numToStr(value)
	return string.format("%#.2f", value)
end
local function prettyFloat(value, neg)
	value = math.floor(value * 10000) / 10000
	local ret
	if (not (value == 1 or value == -1)) then
		if (value >= 0) then
			value = " " .. value end
		ret = string.sub(value .. "000000", 0, 6)
	else
		if (value == 1) then
			ret = " 1    "
		else
			ret = "-1    "
		end
	end
	if (not neg) then
		ret = string.sub(ret, 2, 6)
	end
	
	return ret
end
local function format01(value)
	-- Format a value expected to be between 0 and 1 (4096) based on script settings.
	if (not showExactMovement) then
		return prettyFloat(value / 4096, false)
	else
		return value .. ""
	end
end
local function posVecToStr(vector)
	return string.format("%9s, %9s, %8s", vector.x, vector.z, vector.y)
end
local function normalVectorToStr(vector)
	if showExactMovement then
		return string.format("%5s, %5s, %5s", vector.x, vector.z, vector.y)
	else
		return format01(vector.x) .. ", " .. format01(vector.z) .. ", " .. format01(vector.y)
	end
end
local function v4ToStr(vector)
	if showExactMovement then
		return string.format("%5s, %5s, %5s, %5s", vector.x, vector.z, vector.y, vector.w)
	else
		return format01(vector.x) .. ", " .. format01(vector.z) .. ", " .. format01(vector.y) .. ", " .. format01(vector.w)
	end
end
local function bstr(bool)
	if bool == true then
		return "true"
	elseif bool == false then
		return "false"
	else
		return "nab"
	end
end

local function get_u32(data, offset)
	return data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16) | (data[offset + 3] << 24)
end
local function get_s32(data, offset)
	local u = data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16) | (data[offset + 3] << 24)
	return u - ((data[offset + 3] & 0x80) << 25)
end
local function get_u16(data, offset)
	return data[offset] | (data[offset + 1] << 8)
end
local function get_s16(data, offset)
	local u = data[offset] | (data[offset + 1] << 8)
	return u - ((data[offset + 1] & 0x80) << 9)
end

local function read_pos(addr)
	return {
		x = memory.read_s32_le(addr),
		y = memory.read_s32_le(addr + 4),
		z = memory.read_s32_le(addr + 8),
	}
end
local function get_pos(data, offset)
	return {
		x = get_s32(data, offset),
		y = get_s32(data, offset + 4),
		z = get_s32(data, offset + 8),
	}
end
local function read_pos_16(addr)
	local d = memory.read_bytes_as_array(addr, 6)
	return {
		x = get_s16(d, 1),
		y = get_s16(d, 3),
		z = get_s16(d, 5),
	}
end
local function get_pos_16(data, offset)
	return {
		x = get_s16(data, offset),
		y = get_s16(data, offset + 2),
		z = get_s16(data, offset + 4),
	}
end
local function readVec4(addr)
	return {
		x = memory.read_s32_le(addr),
		y = memory.read_s32_le(addr + 4),
		z = memory.read_s32_le(addr + 8),
		w = memory.read_s32_le(addr + 12),
	}
end
local function get_Vec4(data, offset)
	return {
		x = get_s32(data, offset),
		y = get_s32(data, offset + 4),
		z = get_s32(data, offset + 8),
		w = get_s32(data, offset + 12),
	}
end
local function distanceSqBetween(p1, p2)
	local x = p2.x - p1.x
	local y = p2.y - p1.y
	local z = p2.z - p1.z
	return x * x + y * y + z * z
end

local function mul_fx(a, b)
	return a * b // 0x1000
end
local function dotProduct_float(v1, v2)
	-- truncate, fixed point 20.12
	local a = v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
	return a / 0x1000
end
local function dotProduct_t(v1, v2)
	-- truncate, fixed point 20.12
	local a = v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
	return a // 0x1000 -- bitwise shifts are logical
end
local function dotProduct_r(v1, v2)
	-- round, fixed point 20.12
	local a = v1.x * v2.x + v1.y * v2.y + v1.z * v2.z + 0x800
	return a // 0x1000 -- bitwise shifts are logical
end
local function crossProduct(v1, v2)
	return {
		x = (v1.y * v2.z - v1.z * v2.y) / 0x1000,
		y = (v1.z * v2.x - v1.x * v2.z) / 0x1000,
		z = (v1.x * v2.y - v1.y * v2.x) / 0x1000,
	}
end
local function multiplyVector(v, s)
	return {
		x = v.x * s,
		y = v.y * s,
		z = v.z * s,
	}
end
local function addVector(v1, v2)
	return {
		x = v1.x + v2.x,
		y = v1.y + v2.y,
		z = v1.z + v2.z,
	}
end
local function subtractVector(v1, v2)
	return {
		x = v1.x - v2.x,
		y = v1.y - v2.y,
		z = v1.z - v2.z,
	}
end
local function truncateVector(v)
	return {
		x = math.floor(v.x),
		y = math.floor(v.y),
		z = math.floor(v.z),
	}
end

local function vectorEqual(v1, v2)
	if v1.x == v2.x and v1.y == v2.y and v1.z == v2.z then
		return true
	end
end
local function vectorEqual_ignoreSign(v1, v2)
	if v1.x == v2.x and v1.y == v2.y and v1.z == v2.z then
		return true
	end
	v1 = multiplyVector(v1, -1)
	return v1.x == v2.x and v1.y == v2.y and v1.z == v2.z
end
local function copyVector(v)
	return { x = v.x, y = v.y, z = v.z }
end

local function normalizeVector_float(v)
	local m = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) / 0x1000
	return {
		x = v.x / m,
		y = v.y / m,
		z = v.z / m,
	}
end


local axisDirections = {
	x = { x = 0x1000, y = 0, z = 0 },
	y = { x = 0, y = 0x1000, z = 0 },
	z = { x = 0, y = 0, z = 0x1000 },
}
local function getBoxyPolygons(center, directions, sizes, sizes2)
	if sizes2 == nil then sizes2 = sizes end
	local offsets = {
		x1 = multiplyVector(directions.x, sizes.x / 0x1000),
		y1 = multiplyVector(directions.y, sizes.y / 0x1000),
		z1 = multiplyVector(directions.z, sizes.z / 0x1000),
		x2 = multiplyVector(directions.x, sizes2.x / 0x1000),
		y2 = multiplyVector(directions.y, sizes2.y / 0x1000),
		z2 = multiplyVector(directions.z, sizes2.z / 0x1000),
	}
	
	local s = subtractVector
	local a = addVector
	local verts = {
		s(s(s(center, offsets.x2), offsets.y2), offsets.z2),
		a(s(s(center, offsets.x2), offsets.y2), offsets.z1),
		s(a(s(center, offsets.x2), offsets.y1), offsets.z2),
		a(a(s(center, offsets.x2), offsets.y1), offsets.z1),
		s(s(a(center, offsets.x1), offsets.y2), offsets.z2),
		a(s(a(center, offsets.x1), offsets.y2), offsets.z1),
		s(a(a(center, offsets.x1), offsets.y1), offsets.z2),
		a(a(a(center, offsets.x1), offsets.y1), offsets.z1),
	}
	return {
		{ verts[1], verts[5], verts[7], verts[3] },
		{ verts[1], verts[5], verts[6], verts[2] },
		{ verts[1], verts[3], verts[4], verts[2] },
		{ verts[8], verts[4], verts[2], verts[6] },
		{ verts[8], verts[4], verts[3], verts[7] },
		{ verts[8], verts[6], verts[5], verts[7] },
	}
end
local function getCylinderPolygons(center, directions, radius, h1, h2)
	local offsets = {
		x = multiplyVector(directions.x, radius / 0x1000),
		y = multiplyVector(directions.y, h1 / 0x1000),
		d = multiplyVector(directions.y, -h2 / 0x1000),
		z = multiplyVector(directions.z, radius / 0x1000),
	}
	
	local s = subtractVector
	local a = addVector
	local m = multiplyVector
	local norm = normalizeVector_float
	radius = radius / 0x1000
	local around = {
		offsets.x,
		m(norm(a(m(offsets.x, 2), offsets.z)), radius),
		m(norm(a(offsets.x, offsets.z)), radius),
		m(norm(a(offsets.x, m(offsets.z, 2))), radius),
		offsets.z,
		m(norm(a(m(offsets.x, -1), m(offsets.z, 2))), radius),
		m(norm(a(m(offsets.x, -1), offsets.z)), radius),
		m(norm(a(m(offsets.x, -2), offsets.z)), radius),
	}
	local count = #around
	for i = 1, count do
		around[#around + 1] = m(around[i], -1)
	end
	
	local tc = addVector(center, offsets.y)
	local bc = addVector(center, offsets.d)
	local vertsT = {}
	local vertsB = {}
	for i = 1, #around do
		vertsT[i] = a(tc, around[i])
		vertsB[i] = a(bc, around[i])
	end
	
	local polys = {}
	for i = 1, #around - 1 do
		polys[i] = { vertsT[i], vertsT[i + 1], vertsB[i + 1], vertsB[i] }
	end
	polys[#polys + 1] = vertsT
	polys[#polys + 1] = vertsB
	return polys
end
-------------------------------------------------

-- MKDS -----------------------------------------
local triangles = nil
local kclData = nil
local someCourseData = nil
local collisionMap = nil

local function getPlayerData(ptr, previousData)
	local newData = NewMyData()
	if ptr == 0 then
		return newData
	end

	-- Optimization: Do only one (two) BizHawk API call. Yes, this is a little faster.
	-- Off-by-one shenanigans because Lua table indexes are 1-based by default.
	-- Also things not in use are commented out.
	local allData = memory.read_bytes_as_array(ptr + 1, 0x5a8 - 1)
	allData[0] = memory.read_u8(ptr)

	-- Read positions and speed
	newData.pos = get_pos(allData, 0x80)
	newData.posForObjects = get_pos(allData, 0x1B8) -- also used for collision
	newData.preMovementPosForObjects = get_pos(allData, 0x1C4) -- this too is used for collision
	newData.posForItems = get_pos(allData, 0x1D8)
	newData.speed = get_s32(allData, 0x2A8)
	newData.boostAll = allData[0x238]
	newData.boostMt = allData[0x23C]
	newData.verticalVelocity = get_s32(allData, 0x260)
	newData.mtTime = get_s32(allData, 0x30C)
	newData.maxSpeed = get_s32(allData, 0xD0)
	newData.turnLoss = get_s32(allData, 0x2D4)
	newData.offroadSpeed = get_s32(allData, 0xDC)
	newData.wallSpeedMult = get_s32(allData, 0x38C)
	newData.airSpeed = get_s32(allData, 0x3F8)
	newData.effectSpeed = get_s32(allData, 0x394)
	-- Real speed
	local posDelta = math.sqrt((previousData.pos.z - newData.pos.z) ^ 2 + (previousData.pos.x - newData.pos.x) ^ 2)
	newData.posDelta = math.floor(posDelta * 10) / 10
	newData.basePosDelta = get_pos(allData, 0xA4)
	newData.actualPosDelta = subtractVector(newData.pos, previousData.pos)
	newData.collisionPush = subtractVector(newData.actualPosDelta, newData.basePosDelta)
	
	-- angles
	newData.facingAngle = get_s16(allData, 0x236)
	newData.pitch = get_s16(allData, 0x234)
	newData.driftAngle = get_s16(allData, 0x388)
	--newData.wideDrift = get_s16(allData, 0x38A) -- Controls tightness of drift when pressing outside direction, and rate of drift air spin.
	newData.facingDelta = newData.facingAngle - previousData.facingAngle
	newData.driftDelta = newData.driftAngle - previousData.driftAngle
	newData.movementDirection = get_pos(allData, 0x68)
	UpdateMag(newData.movementDirection)
	newData.movementTarget = get_pos(allData, 0x50)
	UpdateMag(newData.movementTarget)
	--newData.targetMovementVectorSigned = get_pos(allData, 0x5c)
	--UpdateMag(newData.targetMovementVectorSigned)
	
	-- surface/collision stuffs
	newData.surfaceNormalVector = get_pos(allData, 0x244)
	UpdateMag(newData.surfaceNormalVector)
	newData.grip = get_s32(allData, 0x240)
	newData.radius = get_s32(allData, 0x1d0)
	--newData.radiusMult = get_s32(allData, 0x4c8)

	-- other
	newData.framesInAir = get_s32(allData, 0x380)
	if allData[0x3DD] == 0 then
		newData.air = "Ground"
	else
		newData.air = "Air"
	end
	newData.spawnPoint = get_s32(allData, 0x3C4)
	newData.movementAdd1fc = get_pos(allData, 0x1fc)
	newData.movementAdd2f0 = get_pos(allData, 0x2f0)
	newData.movementAdd374 = get_pos(allData, 0x374)
	--newData.tb = get_pos(allData, 0x2d8)
	UpdateMag(newData.movementAdd1fc)
	UpdateMag(newData.movementAdd2f0)
	UpdateMag(newData.movementAdd374)

	-- Rank/score
	--local ptrScoreCounters = memory.read_s32_le(ptrScoreCountersAddr)
	--newData.wallHitCount = memory.read_s32_le(ptrScoreCounters + 0x10)
	
	-- ?
	--newData.e0 = get_Vec4(allData, 0xe0)
	newData.f0 = get_Vec4(allData, 0xf0)
	--newData.smsm = get_s32(allData, 0x39c)
	--newData.waterfallPush = get_pos(allData, 0x268)
	--newData.waterfallStrength = get_s32(allData, 274)
	
	return newData
end
local function getCheckpointData(dataObj)
	-- Read pointer values
	local ptrCheckNum = memory.read_s32_le(ptrCheckNumAddr)
	local ptrCheckData = memory.read_s32_le(ptrCheckDataAddr)
	
	if ptrCheckNum == 0 or ptrCheckData == 0 then
		return
	end
	
	-- Read checkpoint values
	dataObj.checkpoint = memory.read_u8(ptrCheckNum + 0x46)
	dataObj.keyCheckpoint = memory.read_s8(ptrCheckNum + 0x48)
	dataObj.checkpointGhost = memory.read_s8(ptrCheckNum + 0xD2)
	dataObj.keyCheckpointGhost = memory.read_s8(ptrCheckNum + 0xD4)
	dataObj.lap = memory.read_s8(ptrCheckNum + 0x38)
	
	-- Lap time
	dataObj.lap_f = memory.read_s32_le(ptrCheckNum + 0x18) * 1.0 / 60 - 0.05
	if (dataObj.lap_f < 0) then dataObj.lap_f = 0 end
end

local function updateGhost(form)
	local ptr = memory.read_s32_le(ptrGhostInputsAddr)
	if ptr == 0 then return end
	memory.write_bytes_as_array(ptr, form.ghostInputs)
	memory.write_s32_le(ptr, 1765) -- max input count for ghost
	-- lap times
	ptr = memory.read_s32_le(ptrSomeRaceDataAddr)
	memory.write_bytes_as_array(ptr + 0x3ec, form.ghostLapTimes)
	
	-- This frame's state won't have it, but any future state will.
	form.firstStateWithGhost = emu.framecount() + 1
end
local function setGhostInputs(form)
	local ptr = memory.read_s32_le(ptrGhostInputsAddr)
	if ptr == 0 then return end
	local currentInputs = memory.read_bytes_as_array(ptr, 0xdce)
	updateGhost(form)
	
	-- Find the first frame where inputs differ.
	local frames = 0
	-- 5, not 4: Lua table is 1-based
	for i = 5, #currentInputs, 2 do
		if form.ghostInputs[i] ~= currentInputs[i] then
			break
		elseif form.ghostInputs[i + 1] ~= currentInputs[i + 1] then
			frames = frames + math.min(form.ghostInputs[i + 1], currentInputs[i + 1])
			break
		else
			frames = frames + currentInputs[i + 1]
		end
	end
	-- Rewind, clear state history
	local targetFrame = frames + form.firstGhostInputFrame
	-- I'm not sure why, but ghosts have been desyncing. So let's just go back a little more.
	targetFrame = targetFrame - 1
	local currentFrame = emu.framecount()
	if currentFrame > targetFrame then
		local inputs = movie.getinput(targetFrame)
		local isOn = inputs["A"]
		tastudio.submitinputchange(targetFrame, "A", not isOn)
		tastudio.applyinputchanges()
		tastudio.submitinputchange(targetFrame, "A", isOn)
		tastudio.applyinputchanges()
	end
end
local function ensureGhostInputs(form)
	-- This function's job is to re-apply the hacked ghost data when the user re-winds far enough back that the hacked ghost isn't in the savestate.

	-- Ensure we're still in the same race
	local firstInputFrame = emu.framecount() - memory.read_s32_le(memory.read_s32_le(ptrRaceTimersAddr) + 4) + 121
	if firstInputFrame ~= form.firstGhostInputFrame then
		return
	end

	-- We don't want to be constantly re-applying ever frame advance.
	-- So, make sure we have either just re-wound or have frame-advanced into the race.
	local frame = emu.framecount()
	if frame < lastFrame or form.firstStateWithGhost > frame then
		updateGhost(form)
	end
end

-- Collision
local isCameraView = false
local function _getNearbyTriangles(pos)
	-- Read map of position -> nearby triangle IDs
	--2ee90?
	local boundary = get_pos(someCourseData, 0x14)
	if pos.x < boundary.x or pos.y < boundary.y or pos.z < boundary.z then
		return {}
	end
	local shift = someCourseData[0x2C]
	local fb = {
		x = (pos.x - boundary.x) >> 12,
		y = (pos.y - boundary.y) >> 12,
		z = (pos.z - boundary.z) >> 12,
	}
	local base = get_u32(someCourseData, 0xC)
	local a = base
	local b = a + 4 * (
		((fb.x >> shift)) |
		((fb.y >> shift) << someCourseData[0x30]) |
		((fb.z >> shift) << someCourseData[0x34])
	)
	if b >= 0x02800000 then
		-- This may happen during course loads: the data we're trying to read isn't initialized yet. ... but we shouldn't ever use this function at that time
		return nil
	end
	b = get_u32(collisionMap, b - base)
	local safety = 0
	while b < 0x80000000 do
		safety = safety + 1
		if safety > 1000 then error("infinite loop: reading nearby triangle map") end
		a = a + b
		shift = shift - 1
		b = a + 4 * (
			(((fb.x >> shift) & 1)) |
			(((fb.y >> shift) & 1) << 1) |
			(((fb.z >> shift) & 1) << 2)
		)
		b = get_u32(collisionMap, b - base)
	end
	a = a + (b - 0x80000000) + 2
	
	-- a now points to first triangle ID
	local nearby = {}
	local index = get_u16(collisionMap, a - base)
	safety = 0
	while index ~= 0 do
		nearby[#nearby + 1] = triangles[index]
		index = get_u16(collisionMap, a + 2 * #nearby - base)
		safety = safety + 1
		if safety > 1000 then
			error("infinite loop: reading nearby triangle list")
		end
	end
	return nearby
end
local _mergeSet = {}
local function merge(l1, l2)
	for i = 1, #l2 do
		local v = l2[i]
		if _mergeSet[v] == nil then
			l1[#l1 + 1] = v
			_mergeSet[v] = true
		end
	end
end
local function getNearbyTriangles(pos)
	if increaseCollisionRenderDistance ~= true then
		return _getNearbyTriangles(pos)
	end

	_mergeSet = {}
	local nearby = {}
	-- How many units should we move at a time?
	-- I got this by testing powers of 2 until one skipped over triangles in rMC1. 256 occasionally did.
	local step = 128 * 0x1000
	local stepCount = 1
	if isCameraView then stepCount = 3 end
	for iX = -stepCount, stepCount do
		for iY = -stepCount, stepCount do
			for iZ = -stepCount, stepCount do
				local p = {
					x = pos.x + iX * step,
					y = pos.y + iY * step,
					z = pos.z + iZ * step,
				}
				merge(nearby, _getNearbyTriangles(p))
			end
		end
	end
	
	return nearby
end
local function updateMinMax(current, new)
	current.min.x = math.min(current.min.x, new.x)
	current.min.y = math.min(current.min.y, new.y)
	current.min.z = math.min(current.min.z, new.z)
	current.max.x = math.max(current.max.x, new.x)
	current.max.y = math.max(current.max.y, new.y)
	current.max.z = math.max(current.max.z, new.z)
end
local function someKindOfTransformation(a, d1, d2, v1, v2)
	-- FUN_01fff434
	local m = (mul_fx(a, d1) - d2) / (mul_fx(a, a) - 0x1000) * 0x1000
	if a == 0x1000 or a == -0x1000 then
		m = 1 -- NDS divide by zero returns 1?
	end
	local n = d1 - mul_fx(m, a)
	
	local out = addVector(
		multiplyVector(v2, m / 0x1000),
		multiplyVector(v1, n / 0x1000)
	)
	UpdateMag(out)
	return out
end
local function getSurfaceDistanceData(toucher, surface)
	local data = {}

	local relativePos = subtractVector(toucher.pos, surface.vertex[1])
	local previousPos = toucher.previousPos and subtractVector(toucher.previousPos, surface.vertex[1])
	local upDistance = dotProduct_t(relativePos, surface.surfaceNormal)
	local inDistance = dotProduct_t(relativePos, surface.inVector)
	local planeDistances = {
		{
			d = dotProduct_t(relativePos, surface.outVector[1]),
			v = surface.outVector[1],
		}, {
			d = dotProduct_t(relativePos, surface.outVector[2]),
			v = surface.outVector[2],
		}, {
			d = inDistance - surface.triangleSize,
			v = surface.outVector[3],
		}
	}
	table.sort(planeDistances, function(a, b) return a.d > b.d end )

	data.isBehind = upDistance < 0
	if previousPos ~= nil and dotProduct_t(previousPos, surface.surfaceNormal) < 0 then
		data.wasBehind = true
		if dotProduct_t(previousPos, surface.outVector[1]) <= 0 and dotProduct_t(previousPos, surface.outVector[2]) <= 0 and dotProduct_t(previousPos, surface.inVector) <= surface.triangleSize then
			data.wasInside = true
		end
	end
	
	data.distanceVector = multiplyVector(surface.surfaceNormal, -upDistance / 0x1000)
	local pDist
	local distanceOffset = nil
	if planeDistances[1].d <= 0 then
		-- fully inside
		pDist = 0
		data.inside = true
		data.nearestPointIsVertex = false
		data.distance = math.max(0, math.abs(upDistance) - toucher.radius)
	else
		data.inside = false
		-- Is the nearest point a vertex?
		local lmdp = dotProduct_t(planeDistances[1].v, planeDistances[2].v)
		data.nearestPointIsVertex = mul_fx(lmdp, planeDistances[1].d) <= planeDistances[2].d
		if data.nearestPointIsVertex then
			-- order matters
			local b = planeDistances[1].v
			local m = planeDistances[2].v
			local t = nil
			if
			  (m == surface.outVector[1] and b == surface.inVector) or
			  (m == surface.outVector[2] and b == surface.outVector[1]) or
			  (m == surface.inVector and b == surface.outVector[2])
			  then
				t = someKindOfTransformation(lmdp, planeDistances[1].d, planeDistances[2].d, b, m)
			else
				t = someKindOfTransformation(lmdp, planeDistances[2].d, planeDistances[1].d, m, b)
			end
			pDist = t.mag3 * 0x1000
			-- maybe a little broken
			if t.mag3 > 0 then
				distanceOffset = t
			end
		else
			pDist = planeDistances[1].d
			distanceOffset = multiplyVector(planeDistances[1].v, planeDistances[1].d / 0x1000)
		end	
		
		data.distance = math.max(0, math.sqrt(pDist * pDist + upDistance * upDistance) - toucher.radius)
	end
	
	if distanceOffset ~= nil then
		data.distanceVector = subtractVector(data.distanceVector, distanceOffset)
	end
	if pDist > toucher.radius then
		data.pushOutBy = -1
	else
		data.pushOutBy = math.sqrt(toucher.radius * toucher.radius - pDist * pDist) - upDistance
	end
	
	data.interacting = true -- NOT the same thing as getting pushed
	if data.pushOutBy < 0 or toucher.radius - upDistance >= 0x1e001 then
		data.interacting = false
	elseif data.isBehind then
		if previousPos == nil then
			data.interacting = false
		elseif data.inside then
			if data.wasBehind == true and data.wasInside ~= true then
				data.interacting = false
			end
		else
			local o = 0
			if planeDistances[1].v == surface.inVector then
				o = surface.triangleSize
			end
			if dotProduct_t(previousPos, planeDistances[1].v) > o then
				data.interacting = false
			end	
		end
	end
	
	if data.wasBehind and previousPos ~= nil and dotProduct_t(previousPos, surface.surfaceNormal) < -0xa000 then
		data.wasFarBehind = true
	end
	
	if data.interacting then
		data.touchSlopedEdge = false
		if not data.inside and not data.nearestPointIsVertex and 0x424 >= planeDistances[1].v.y and planeDistances[1].v.y >= -0x424 then
			data.touchSlopedEdge = true
		end
	
		-- Will it push?
		data.push = true
		if toucher.previousPos ~= nil then
			local posDelta = subtractVector(toucher.pos, toucher.previousPos)
			local outwardMovement = dotProduct_t(posDelta, surface.surfaceNormal)
			-- 820 rule
			if outwardMovement > 819 then
				data.push = false
				data.outwardMovement = outwardMovement
			end
			
			-- Starting behind
			if data.wasBehind and (toucher.flags & 0x3b ~= 0 or data.wasFarBehind) then
				data.push = false
			end
		end
	end
	
	return data
end
local function getTouchDataForSurface(toucher, surface)
	local data = {}
	-- 1) Can we interact with this surface?
	-- Idk what these all represent.
	local st = surface.surfaceType
	if toucher.flags & 0x10 ~= 0 and st & 0xa000 ~= 0 then
		return { canTouch = false }
	end
	local unknown1 = st & 0x2010 == 0
	local unknown2 = toucher.flags & 4 == 0 or st & 0x2000 == 0
	local unknown3 = toucher.flags & 1 == 0 or st & 0x10 == 0
	if not (unknown1 or (unknown2 and unknown3)) then
		return { canTouch = false }
	end
	data.canTouch = true
	-- 2) How far away from the surface are we?
	local dd = getSurfaceDistanceData(toucher, surface)
	data.touching = dd.interacting
	data.pushOutDistance = dd.pushOutBy
	data.distance = dd.distance
	data.behind = dd.isBehind
	local pushVec = multiplyVector(surface.surfaceNormal, data.pushOutDistance)
	data.centerToTriangle = dd.distanceVector
	data.wasBehind = dd.wasBehind
	data.isInside = dd.inside -- wasInside
	-- dd.pushOutBy
	data.push = dd.push
	data.outwardMovement = dd.outwardMovement

	return data
end
local function getCollisionDataForRacer(racerData)
	local nearby = getNearbyTriangles(racerData.posForObjects)
	if #nearby == 0 then
		return {}
	end
	local data = {}
	for i = 1, #nearby do
		data[#data + 1] = {
			triangle = nearby[i],
			touch = getTouchDataForSurface({
				pos = racerData.posForObjects,
				previousPos = racerData.preMovementPosForObjects,
				radius = racerData.radius,
				flags = 1,
			}, nearby[i]),
		} 
	end
	
	-- Comparisons of surfaces, to determine which one controls.
	-- For now, just check which is the slope.
	local maxPushOut = nil
	for i, v in pairs(data) do
		if v.touch.push and not v.triangle.isWall and (maxPushOut == nil or v.touch.pushOutDistance > data[maxPushOut].touch.pushOutDistance) then
			maxPushOut = i
		end
	end
	if maxPushOut ~= nil then
		data[maxPushOut].controlsSlope = true
	end
	
	return data
end

local function getCourseCollisionData()
	local dataPtr = get_u32(someCourseData, 8)
	local endData = get_u32(someCourseData, 12)
	local triangleData = memory.read_bytes_as_array(dataPtr + 1, endData - dataPtr)
	triangleData[0] = memory.read_u8(dataPtr)
	
	triangles = {}
	local triCount = (endData - dataPtr) / 0x10 - 1
	for i = 1, triCount do -- there is no triangle ID 0
		local offs = i * 0x10
		triangles[i] = {
			id = i,
			triangleSize = get_s32(triangleData, offs + 0),
			vertexId = get_s16(triangleData, offs + 4),
			surfaceNormalId = get_s16(triangleData, offs + 6),
			outVector1Id = get_s16(triangleData, offs + 8),
			outVector2Id = get_s16(triangleData, offs + 10),
			inVectorId = get_s16(triangleData, offs + 12),
			surfaceType = get_u16(triangleData, offs + 14),
		}
		triangles[i].collisionType = (triangles[i].surfaceType >> 8) & 0x1f
		triangles[i].unkType = (triangles[i].surfaceType >> 2) & 3
		triangles[i].props = (1 << triangles[i].collisionType) | (1 << (triangles[i].unkType + 0x1a))
		triangles[i].isWall = triangles[i].props & 0x214300 ~= 0
		triangles[i].isFloor = triangles[i].props & 0x1e34ef ~= 0
	end
		
	local vectorsPtr = get_u32(someCourseData, 4)
	local vectorData = memory.read_bytes_as_array(vectorsPtr + 1, dataPtr - vectorsPtr + 0x10)
	vectorData[0] = memory.read_u8(vectorsPtr)
	local vectors = {}
	local vecCount = (dataPtr - vectorsPtr + 0x10) // 6
	for i = 0, vecCount - 1 do
		local offs = i * 6
		vectors[i] = get_pos_16(vectorData, offs)
	end
	
	local vertexesPtr = get_u32(someCourseData, 0)
	local vertexData = memory.read_bytes_as_array(vertexesPtr + 1, vectorsPtr - vertexesPtr) -- guess about length
	vertexData[0] = memory.read_u8(vertexesPtr)
	local vertexes = {}
	local vertCount = (vectorsPtr - vertexesPtr) / 12
	for i = 0, vertCount - 1 do
		local offs = i * 12
		vertexes[i] = get_pos(vertexData, offs)
	end
	
	for i = 1, #triangles do
		local tri = triangles[i]
		tri.surfaceNormal = vectors[tri.surfaceNormalId]
		tri.inVector = vectors[tri.inVectorId]
		tri.vertex = {}
		tri.slope = {}
		tri.vertex[1] = vertexes[tri.vertexId]
		tri.outVector = {}
		tri.outVector[1] = vectors[tri.outVector1Id]
		tri.outVector[2] = vectors[tri.outVector2Id]
		tri.outVector[3] = vectors[tri.inVectorId]
		tri.slope[1] = crossProduct(tri.surfaceNormal, tri.outVector[1])
		tri.slope[2] = crossProduct(tri.surfaceNormal, tri.outVector[2])
		tri.slope[3] = crossProduct(tri.surfaceNormal, tri.outVector[3])
		-- Both slope vectors should be unit vectors, since surfaceNormal and outVectors are.
		-- But one of them is pointed the wrong way
		tri.slope[1] = multiplyVector(tri.slope[1], -1)
		local a = dotProduct_float(vectors[tri.inVectorId], tri.slope[1])
		local b = tri.triangleSize / a
		if a == 0 then
			-- This happens in rKB2.
			b = 0x1000 * 1000
			tri.ignore = true
		end
		local c = multiplyVector(tri.slope[1], b)
		tri.vertex[3] = addVector(tri.vertex[1], c)
		a = dotProduct_float(vectors[tri.inVectorId], tri.slope[2])
		b = tri.triangleSize / a
		if a == 0 then
			-- This happens in rKB2.
			b = 0x1000 * 1000
			tri.ignore = true
		end
		c = multiplyVector(tri.slope[2], b)
		tri.vertex[2] = addVector(tri.vertex[1], c)
	end
	
	local cmPtr = get_u32(someCourseData, 0xC)
	local cmSize = 0x28000 -- ???
	collisionMap = memory.read_bytes_as_array(cmPtr + 1, cmSize - 1)
	collisionMap[0] = memory.read_u8(cmPtr)

end
local function getCourseData()
	someCourseData = memory.read_bytes_as_array(ptrCollisionDataAddr + 1, 0x38 - 1)
	someCourseData[0] = memory.read_u8(ptrCollisionDataAddr)

	getCourseCollisionData()
end

local function inRace()
	-- Check if racer exists.
	if memory.read_s32_le(ptrRacerDataAddr) == 0 then
		clearDataOutsideRace()
		return false
	end
	
	-- Check if race has begun. (This static pointer points to junk on the main menu, which is why we checked racer data first.)
	local timer = memory.read_s32_le(memory.read_s32_le(ptrRaceTimersAddr) + 4)
	if timer == 0 then
		clearDataOutsideRace()
		return false
	end
	local course = memory.read_u8(ptrCurrentCourse)
	if course ~= courseId then
		courseId = course
		getCourseData()
	end
	
	return true
end

-- Objects
-- Objects code is WIP.
local allObjects = {}
local t = { }
if true then -- I just want to collapse this block in my editor.
	t[0x000] = "follows player"
	t[0x00b] = "STOP! signage"; t[0x00d] = "puddle";
	t[0x065] = "item box"; t[0x066] = "post";
	t[0x067] = "wooden crate"; t[0x068] = "coin";
	t[0x06e] = "gate trigger";
	t[0x0cc] = "drawbridge";
	t[201] = "moving item box"; t[202] = "moving block";
	t[203] = "gear"; t[204] = "bridge";
	t[205] = "clock hand"; t[206] = "gear";
	t[207] = "pendulum"; t[208] = "rotating floor";
	t[209] = "rotating bridge"; t[210] = "roulette";
	t[0x12e] = "coconut tree"; t[0x12f] = "pipe";
	t[0x130] = "wumpa-fruit tree";
	t[0x138] = "striped tree";
	t[0x145] = "autumn tree"; t[0x146] = "winter tree";
	t[0x148] = "palm tree";
	t[0x14f] = "pinecone tree"; t[0x150] = "beanstalk";
	t[0x156] = "N64 winter tree";
	t[401] = "goomba"; t[402] = "giant snowball";
	t[403] = "thwomp";
	t[405] = "bus"; t[406] = "chain chomp";
	t[407] = "chain chomp post"; t[408] = "leaping fireball";
	t[409] = "mole"; t[410] = "car";
	t[411] = "cheep cheep"; t[412] = "truck";
	t[413] = "snowman"; t[414] = "coffin";
	t[415] = "bats";
	t[0x1a2] = "bullet bill"; t[0x1a3] = "walking tree";
	t[0x1a4] = "flamethrower"; t[0x1a5] = "stray chain chomp";
	t[0x1ac] = "crab";
	t[0x1a6] = "piranha plant"; t[0x1a7] = "rocky wrench";
	t[0x1a8] = "bumper"; t[0x1a9] = "flipper";
	t[0x1af] = "fireballs"; t[0x1b0] = "pinball";
	t[0x1b1] = "boulder"; t[0x1b2] = "pokey";
	t[0x1f5] = "bully"; t[0x1f6] = "Chief Chilly";
	t[0x1f8] = "King Bomb-omb";
	t[0x1fb] = "Eyerok"; t[0x1fd] = "King Boo";
	t[0x1fe] = "Wiggler";
end
local mapObjTypes = t
local function getBoxyDistances(obj, pos, radius)
	local posDelta = subtractVector(pos, obj.dynPos)
	
	local dir = obj.orientation
	local sizes = obj.sizes
	local orientedPosDelta = {
		x = dotProduct_t(posDelta, dir.x),
		y = dotProduct_t(posDelta, dir.y),
		z = dotProduct_t(posDelta, dir.z),
	}
	local orientedDistanceTo = {
		math.abs(orientedPosDelta.x) - radius - sizes.x,
		math.abs(orientedPosDelta.y) - radius - sizes.y,
		math.abs(orientedPosDelta.z) - radius - sizes.z,
	}
	local outsideTheBox = 0
	for i = 1, 3 do
		if orientedDistanceTo[i] > 0 then
			outsideTheBox = outsideTheBox + orientedDistanceTo[i] * orientedDistanceTo[i]
		end
	end
	local totalDistance = nil
	if outsideTheBox ~= 0 then
		totalDistance = math.sqrt(outsideTheBox)
	else
		totalDistance = math.max(orientedDistanceTo[1], orientedDistanceTo[2], orientedDistanceTo[3])
	end
	return {
		x = orientedDistanceTo[1],
		y = orientedDistanceTo[2],
		z = orientedDistanceTo[3],
		d = totalDistance,
	}
end
local function getCylinderDistances(obj, pos, radius)
	local posDelta = subtractVector(pos, obj.dynPos)
	
	local dir = obj.orientation
	local orientedPosDelta = posDelta
	if obj.hitboxType == "cylinder2" then
		orientedPosDelta = {
			x = dotProduct_t(posDelta, dir.x),
			y = dotProduct_t(posDelta, dir.y),
			z = dotProduct_t(posDelta, dir.z),
		}
	end
	orientedPosDelta = {
		h = math.sqrt(orientedPosDelta.x * orientedPosDelta.x + orientedPosDelta.z * orientedPosDelta.z),
		v = orientedPosDelta.y
	}
	local bHeight = obj.bHeight
	if bHeight == nil then bHeight = obj.height end
	local orientedDistanceTo = {
		math.abs(orientedPosDelta.h) - radius - obj.radius,
		math.max(
			orientedPosDelta.v - radius - obj.height,
			-(orientedPosDelta.v + radius + bHeight)
		),
	}
	local outside = 0
	for i = 1, 2 do
		if orientedDistanceTo[i] > 0 then
			outside = outside + orientedDistanceTo[i] * orientedDistanceTo[i]
		end
	end
	local totalDistance = nil
	if outside ~= 0 then
		totalDistance = math.sqrt(outside)
	else
		totalDistance = math.max(orientedDistanceTo[1], orientedDistanceTo[2])
	end
	return {
		h = math.floor(orientedDistanceTo[1]),
		v = math.floor(orientedDistanceTo[2]),
		d = totalDistance,
	}
end
local function getDetailsForBoxyObject(obj)
	obj.boxy = true
	if obj.hitboxFunc == carHitboxFunc then
		obj.sizes = read_pos(obj.ptr + 0x114)
		obj.backSizes = {
			x = obj.sizes.x,
			y = 0,
			z = memory.read_s32_le(obj.ptr + 0x120),
		}
	elseif obj.hitboxFunc == clockHandHitboxFunc then
		obj.sizes = read_pos(obj.ptr + 0x58)
		obj.backSizes = copyVector(obj.sizes)
		obj.backSizes.z = 0
	elseif obj.hitboxFunc == pendulumHitboxFunc then
		obj.sizes = {
			x = obj.radius,
			y = obj.radius,
			z = memory.read_s32_le(obj.ptr + 0x108),
		}
	elseif obj.hitboxFunc == rockyWrenchHitboxFunc then
		obj.sizes = {
			x = obj.radius,
			y = memory.read_s32_le(obj.ptr + 0xa0),
			z = obj.radius,
		}
	else
		obj.sizes = read_pos(obj.ptr + 0x58)
	end
	obj.dynPos = obj.pos
	obj.polygons = getBoxyPolygons(obj.pos, obj.orientation, obj.sizes, obj.backSizes)
end
local function getDetailsForCylinder2Object(obj, isBumper)
	obj.cylinder2 = true
	obj.dynPos = obj.pos -- It may not be dynamic, but getCylinderDistances expexts this
	
	if isBumper then
		obj.bHeight = 0
		if memory.read_u16_le(obj.ptr + 2) & 0x800 == 0 and memory.read_u32_le(obj.ptr + 0x11c) == 1 then
			obj.radius = mul_fx(obj.radius, memory.read_u32_le(obj.ptr + 0xbc))
		end
	else
		obj.bHeight = obj.height
	end
	
	obj.polygons = getCylinderPolygons(obj.pos, obj.orientation, obj.radius, obj.height, obj.bHeight)
end
local function getDetailsForDynamicBoxyObject(obj)
	obj.sizes = read_pos(obj.ptr + 0x100)
	obj.dynPos = read_pos(obj.ptr + 0xf4)
	obj.backSizes = copyVector(obj.sizes)
	obj.backSizes.z = memory.read_s32_le(obj.ptr + 0x10c)
	obj.polygons = getBoxyPolygons(obj.dynPos, obj.orientation, obj.sizes, obj.backSizes)
end
local function getDetailsForDynamicCylinderObject(obj)
	obj.radius = memory.read_s32_le(obj.ptr + 0x100)
	obj.halfHeight = memory.read_s32_le(obj.ptr + 0x104)
	obj.dynPos = read_pos(obj.ptr + 0xf4)
end
local function getMapObjDetails(obj)	
	local objPtr = obj.ptr
	local typeId = memory.read_u16_le(objPtr)
	obj.typeId = typeId
	obj.type = mapObjTypes[typeId] or "unknown " .. typeId
	obj.boxy = false
	obj.cylinder = false
	
	obj.radius = memory.read_s32_le(objPtr + 0x58)
	obj.height = memory.read_s32_le(objPtr + 0x5C)
	obj.orientation = {
		x = read_pos(obj.ptr + 0x28),
		y = read_pos(obj.ptr + 0x34),
		z = read_pos(obj.ptr + 0x40),
	}

	-- Hitbox
	local hitboxType = ""
	if memory.read_u16_le(objPtr + 2) & 1 == 0 then
		local maybePtr = memory.read_s32_le(objPtr + 0x98)
		local hbType = 0
		if maybePtr > 0 then
			-- The game has no null check, but I don't want to keep seeing the "attempted read outside memory" warning
			hbType = memory.read_s32_le(maybePtr + 8)
		end
		if hbType == 0 or hbType > 5 or hbType < 0 then
			hitboxType = ""
		elseif hbType == 1 then
			hitboxType = "spherical"
		elseif hbType == 2 then
			hitboxType = "cylindrical"
			obj.polygons = getCylinderPolygons(obj.pos, obj.orientation, obj.radius, obj.height, obj.height)
		elseif hbType == 3 then
			hitboxType = "cylinder2" -- I can't find an object in game that directly uses this.
			getDetailsForCylinder2Object(obj, false)
		elseif hbType == 4 then
			hitboxType = "boxy"
			getDetailsForBoxyObject(obj)
		elseif hbType == 5 then
			hitboxType = "custom" -- Object defines its own collision check function
			obj.chb = memory.read_u32_le(objPtr + 0x98)
			obj.hitboxFunc = memory.read_u32_le(obj.chb + 0x18)
			if obj.hitboxFunc == carHitboxFunc then
				hitboxType = "boxy"
				getDetailsForBoxyObject(obj)
			elseif obj.hitboxFunc == bumperHitboxFunc then
				hitboxType = "cylinder2"
				getDetailsForCylinder2Object(obj, true)
			elseif obj.hitboxFunc == clockHandHitboxFunc then
				hitboxType = "boxy"
				getDetailsForBoxyObject(obj)
			elseif obj.hitboxFunc == pendulumHitboxFunc then
				hitboxType = "spherical"
				obj.radius = memory.read_s32_le(obj.ptr + 0x104)
				getDetailsForBoxyObject(obj)
				obj.multiBox = true
			elseif obj.hitboxFunc == rockyWrenchHitboxFunc then
				if memory.read_u8(obj.ptr + 0xb0) == 1 then
					hitboxType = "no hitbox"
				else
					hitboxType = "spherical"
					obj.multiBox = true
					getDetailsForBoxyObject(obj)
				end
			else
				hitboxType = hitboxType .. " " .. string.format("%x", obj.hitboxFunc)
			end
		end
	end
	if hitboxType == "" then hitboxType = "no hitbox" end
	obj.hitboxType = hitboxType
end
local function getItemDetails(obj)
	local ptr = obj.ptr
	obj.radius = memory.read_s32_le(ptr + 0xE0)
	obj.typeId = 0 -- TODO
	obj.type = "item" -- TODO: which kind?
	obj.hitboxType = "item"
end
local function getRacerObjDetails(obj)
	local ptr = obj.ptr
	obj.radius = memory.read_s32_le(ptr + 0x1d0)
	obj.typeId = 0 -- ??
	obj.type = "racer"
	obj.hitboxType = "spherical"
end
local function isCoinAndCollected(objPtr)
	if memory.read_s16_le(objPtr) ~= 0x68 then -- not coin
		return false
	else
		return memory.read_u16_le(objPtr + 2) & 0x01 ~= 0
	end
end
local function isPlayerOrGhost(objPtr)
	local flags7c = memory.read_u8(objPtr + 0x7C)
	return flags7c & 0x05 ~= 0	
end
local function getObjectDetails(obj)
	local flags = obj.flags
	if flags & 0x2000 ~= 0 then
		getMapObjDetails(obj)
	elseif flags & 0x4000 ~= 0 then
		getItemDetails(obj)
	elseif flags & 0x8000 ~= 0 then
		getRacerObjDetails(obj)
	else
		return
	end

	if flags & 0x1000 ~= 0 then
		obj.dynamic = true
		local aCodePtr = memory.read_u8(obj.ptr + 0x134)
		if aCodePtr == 0 then
			obj.dynamicType = "boxy"
			obj.boxy = true
			getDetailsForDynamicBoxyObject(obj)
		elseif aCodePtr == 1 then
			obj.dynamicType = "cylinder"
			getDetailsForDynamicCylinderObject(obj)
		end
		if obj.dynamicType ~= nil then
			if obj.hitboxType == "no hitbox" then
				obj.hitboxType = "dynamic " .. obj.dynamicType
			else
				obj.hitboxType = obj.hitboxType .. " + " .. obj.dynamicType
			end
		end
	else
		obj.dynamic = false
	end
end
local function getAllObjects(racer)
	allObjects = {}
	local playerPos = racer.posForObjects
	
	local ptrObjArray = memory.read_s32_le(ptrObjStuff + 0x10)	
	local maxCount = memory.read_u16_le(ptrObjStuff + 0x08)
	local count = 0
	for id = 0, 255 do
		local current = ptrObjArray + (id * 0x1c)
		local objPtr = memory.read_u32_le(current + 0x18)
		
		local flags = memory.read_u16_le(current + 0x14)
		if objPtr ~= 0 then
			count = count + 1
			-- flag 0x0200: deactivated or something
			if flags & 0x200 == 0 then
				local skip = false
				local obj = {
					id = id,
					pos = read_pos(memory.read_s32_le(current + 0xC)),
					flags = flags,
					ptr = objPtr,
				}
				if flags & 0x2000 ~= 0 then
					if isCoinAndCollected(objPtr) then
						skip = true
					end
				elseif flags & 0x8000 ~= 0 then
					if isPlayerOrGhost(objPtr) then
						skip = true
					end
				elseif flags & 0x5000 == 0 then
					-- 0x4000: item
					-- 0x1000: dynamic object
					skip = true
				end
				if not skip then
					if flags & 0x4000 ~= 0 then
						obj.distanceRaw = distanceSqBetween(racer.posForItems, obj.pos)
					else
						obj.distanceRaw = distanceSqBetween(racer.posForObjects, obj.pos)
					end
					allObjects[#allObjects + 1] = obj
				end
			end
			
			if count == maxCount then
				break
			end
		end
	end
end
local function getNearestTangibleObject(racer)
	local obj = nil
	local distanceToNearest = 1e300
	local positionOfNearest = {}

	for i = 1, #allObjects do
		local o = allObjects[i]
		if o.distanceRaw < distanceToNearest then
			distanceToNearest = o.distanceRaw
			obj = o
		end
	end
	
	if obj == nil then
		return nil
	end
	getObjectDetails(obj)

	if obj.hitboxType == "cylindrical" then
		local relative = subtractVector(racer.posForObjects, obj.pos)
		local distance = relative.x * relative.x + relative.z * relative.z
		distanceToNearest = math.sqrt(distance) - racer.radius - obj.radius
		-- TODO: Check vertical distance?
	elseif obj.hitboxType == "spherical" or obj.hitboxType == "item" then
		local distance = math.sqrt(obj.distanceRaw)
		distanceToNearest = distance - racer.radius - obj.radius
		-- Special object: pendulum
		if obj.hitboxFunc == pendulumHitboxFunc then
			local relative = subtractVector(racer.posForObjects, obj.pos)
			obj.distanceComponents = {
				h = math.floor(distanceToNearest),
				v = dotProduct_t(relative, obj.orientation.z) - racer.radius - obj.sizes.z,
			}
			distanceToNearest = math.max(obj.distanceComponents.h, obj.distanceComponents.v)
		end
	elseif obj.boxy then
		obj.distanceComponents = getBoxyDistances(obj, racer.posForObjects, racer.radius)
		-- TODO: Do all dynamic boxy objects have racer-spherical hitboxes?
		-- Also TODO: Find a nicer way to display this maybe?
		obj.innerDistComps = getBoxyDistances(obj, racer.posForObjects, 0)
		distanceToNearest = obj.distanceComponents.d
	elseif obj.dynamicType == "cylinder" or obj.hitboxType == "cylinder2" then
		obj.distanceComponents = getCylinderDistances(obj, racer.posForObjects, racer.radius)
		distanceToNearest = obj.distanceComponents.d
	else
		distanceToNearest = math.sqrt(obj.distanceRaw)
	end
	
	obj.distance = math.floor(distanceToNearest)
	return obj
end

-- Main info function
local function _mkdsinfo_run_data()
	local frame = emu.framecount()
	
	local ptrPlayerData = memory.read_s32_le(ptrRacerDataAddr)
	myData = getPlayerData(ptrPlayerData, myData)
		
	getCheckpointData(myData)
	local ghostExists = memory.read_s32_le(racerCountAddr) >= 2 and isPlayerOrGhost(ptrPlayerData + 0x5a8)
	if ghostExists then
		ptrPlayerData = 0x5A8 + ptrPlayerData
		ghostData = getPlayerData(ptrPlayerData, ghostData)
		myData.ghost = ghostData
	else
		myData.ghost = nil
	end
	
	local racer = myData
	if watchGhost and ghostExists then
		racer = myData.ghost
	end
	
	kclData = getCollisionDataForRacer(racer)
	getAllObjects(racer)
	nearestObjectData = getNearestTangibleObject(racer)
	
	-- Ghost handling
	if form.ghostInputs ~= nil then
		ensureGhostInputs(form)
	end
	lastFrame = frame
	
	if giveGhostShrooms then
		local itemPtr = memory.read_s32_le(ptrItemInfoAddr)
		itemPtr = itemPtr + 0x210 -- ghost
		memory.write_u8(itemPtr + 0x4c, 5) -- mushroom
		memory.write_u8(itemPtr + 0x54, 3) -- count
	end

	-- Data not tied to a racer
	local ptrRaceTimers = memory.read_s32_le(ptrRaceTimersAddr)
	raceData.framesMod8 = memory.read_s32_le(ptrRaceTimers + 0xC)
	
	local ptrMissionInfo = memory.read_s32_le(ptrMissionInfoAddr)
	raceData.coinsBeingCollected = memory.read_s16_le(ptrMissionInfo + 0x8)
end
---------------------------------------

-- Drawing --------------------------------------
local colView = {}
local iView = {}
local guiScale = client.getwindowsize()

local function drawText(x, y, str, color)
	gui.text(x + iView.x, y + iView.y, str, color)
end

local function p(s, l) return padLeft(s, l or 6) end
local function drawInfo(data)
	gui.use_surface("client")
	
	local lineHeight = 15 -- there's no font size option!?
	local sectionMargin = 8
	local y = 4
	local x = 4
	local function dt(s)
		if s == nil then
			print("drawing nil at y " .. y)
		end
		drawText(x, y, s)
		y = y + lineHeight
	end
	local sectionIsDark = false
	local lastSectionBegin = 0
	local function endSection()
		-- gui.drawThing draws on the emulator surface
		-- our text drawing draws on the client surface
		y = y + sectionMargin / 2 + 1
		if sectionIsDark then
			gui.drawBox(iView.x, lastSectionBegin + iView.y, iView.x + iView.w, y + iView.y, 0xff000000, 0xff000000)
		else
			gui.drawBox(iView.x, lastSectionBegin + iView.y, iView.x + iView.w, y + iView.y, 0x60000000, 0x60000000)
		end
		gui.drawLine(iView.x, y + iView.y, iView.x + iView.w, y + iView.y, "red")
		sectionIsDark = not sectionIsDark
		lastSectionBegin = y + 1
		y = y + sectionMargin / 2 - 1
	end
	
	-- Display speed, boost stuff
	dt("Boost: " .. p(data.boostAll, 2) .. ", MT: " .. p(data.boostMt, 2) .. ", " .. data.mtTime)
	dt("Speed: " .. data.speed .. ", real: " .. data.posDelta)
	dt("Y Sp : " .. data.verticalVelocity.. ", Max Sp: " .. data.maxSpeed)
	local wallClip = data.wallSpeedMult
	local losses = "turnLoss = " .. format01(data.turnLoss)
	if wallClip ~= 4096 then
		losses = losses .. ", wall: " .. format01(data.wallSpeedMult)
	end
	if data.airSpeed ~= 4096 then
		losses = losses .. ", air: " .. format01(data.airSpeed)
	end
	if data.effectSpeed ~= 4096 then
		losses = losses .. ", small: " .. format01(data.effectSpeed)
	end
	dt(losses)
	endSection()

	-- Display position
	dt(data.air .. " (" .. data.framesInAir .. ")")
	dt("X, Z, Y  : " .. posVecToStr(data.pos))
	dt("Delta    : " .. posVecToStr(data.actualPosDelta))
	local bm = addVector(subtractVector(data.pos, data.actualPosDelta), data.basePosDelta)
	local pod = subtractVector(data.posForObjects, bm)
	dt("Collision: " .. posVecToStr(data.collisionPush))
	dt("Hitbox   : " .. posVecToStr(pod))
	endSection()
	-- Display angles
	if showAnglesAsDegrees then
		-- People like this
		local function atd(a)
			local deg = (((a / 0x10000) * 360) + 360) % 360
			return math.floor(deg * 1000) / 1000
		end
		local function ttd(v)
			local radians = math.atan(v.x, v.z)
			local deg = radians * 360 / (2 * math.pi)
			return math.floor(deg * 1000) / 1000
		end
		dt("Facing angle: " .. atd(data.facingAngle))
		dt("Drift angle: " .. atd(data.driftAngle))
		dt("Movement angle: " .. ttd(data.movementDirection) .. " (" .. ttd(data.movementTarget) .. ")")
	else
		-- Suuper likes this
		dt("Angle: " .. p(data.facingAngle) .. " + " .. p(data.driftAngle) .. " = " .. p(data.facingAngle + data.driftAngle))
		dt("Delta: " .. p(data.facingDelta) .. " + " .. p(data.driftDelta) .. " = " .. p(data.facingDelta + data.driftDelta))
		local function tta(v)
			local radians = math.atan(v.x, v.z)
			local dsUnits = math.floor(radians * 0x10000 / (2 * math.pi))
			return prettyFloat(v.mag2) .. ", " .. p(dsUnits)
		end
		dt("Movement: " .. normalVectorToStr(data.movementDirection) .. " (" .. tta(data.movementDirection) .. ")")
		dt("Target  : " .. normalVectorToStr(data.movementTarget) .. " (" .. tta(data.movementTarget) .. ")")
	end
	dt("Pitch: " .. data.pitch)
	endSection()
	-- surface stuff
	local n = data.surfaceNormalVector
	local steepness = n.mag2 / (n.y / 0x1000)
	steepness = numToStr(steepness)
	dt("Surface grip: " .. format01(data.grip) .. ", sp: " .. format01(data.offroadSpeed) .. ",")
	dt("normal: " .. normalVectorToStr(n) .. ", steep: " .. steepness)
	endSection()

	-- Ghost comparison
	if data.ghost then
		local distX = data.pos.x - data.ghost.pos.x
		local distZ = data.pos.z - data.ghost.pos.z
		local dist = math.sqrt(distX * distX + distZ * distZ)
		dt("Distance from ghost (2D): " .. math.floor(dist))
		endSection()
	end
	
	-- Point comparison
	if form.comparisonPoint ~= nil then
		local delta = {
			x = data.pos.x - form.comparisonPoint.x,
			z = data.pos.z - form.comparisonPoint.z
		}
		local dist = math.floor(math.sqrt(delta.x * delta.x + delta.z * delta.z))
		local angleRad = math.atan(delta.x, delta.z)
		dt("Distance travelled: " .. dist)
		dt("Angle: " .. math.floor(angleRad * 0x10000 / (2 * math.pi)))
		endSection()
	end

	-- Nearest object
	if nearestObjectData ~= nil then
		local obj = nearestObjectData
		dt("Distance to nearest object: " .. obj.distance .. " (" .. obj.hitboxType .. ")")
		if obj.distanceComponents ~= nil then
			if obj.innerDistComps ~= nil then
				dt("outer: " .. posVecToStr(obj.distanceComponents))
				dt("inner: " .. posVecToStr(obj.innerDistComps))
			elseif obj.distanceComponents.v == nil then
				dt(posVecToStr(obj.distanceComponents))
			else
				dt(string.format("%9s, %8s", obj.distanceComponents.h, obj.distanceComponents.v))
			end
		end
		dt(obj.id .. ": " .. obj.type)
		endSection()
	end
	
	-- tmep?
	--dt("smsm: " .. data.smsm)
	--dt(data.radius)
	if data.movementAdd1fc.mag3 ~= 0 then
		dt("bounce 1: " .. normalVectorToStr(data.movementAdd1fc))
	end
	if data.movementAdd2f0.mag3 ~= 0 then
		dt("bounce 2: " .. normalVectorToStr(data.movementAdd2f0))
	end
	if data.movementAdd374.mag3 ~= 0 then
		dt("bounce 3: " .. normalVectorToStr(data.movementAdd374))
	end
	dt("fo: " .. v4ToStr(data.f0))
	endSection()

	-- Display checkpoints
	if data.checkpoint ~= nil then
		if (data.spawnPoint > -1) then dt("Spawn Point: " .. data.spawnPoint) end
		dt("Checkpoint number (player) = " .. data.checkpoint .. " (" .. data.keyCheckpoint .. ")")
		endSection()
	end
	
	-- Coins
	if raceData.coinsBeingCollected ~= nil and raceData.coinsBeingCollected > 0 then
		y = y + sectionMargin
		local coinCheckIn = "in " .. (8 - raceData.framesMod8) .. " frames"
		if raceData.framesMod8 == 0 then
			coinCheckIn = "this frame"
		end
		dt("Coin increment " .. coinCheckIn)
	end
	
	--y = 37
	--x = 350
	-- Display lap time
	--if data.lap_f then
	--	dt("Lap: " .. time(data.lap_f))
	--end
end

-- Collision drawing ----------------------------
local scale = 0x1000 * collisionScaleFactor
local drawingCenter = {x = 0, y = 0, z = 0}
local perspectiveId = -5 -- top-down
local cameraRotationVector = {}
local cameraRotationMatrix = {}
local satr = 2 * math.pi / 0x10000
local cameraFW = nil
local cameraFH = nil
local drawingQue = {}
local queHistory = {}
local PIXEL = 1
local CIRCLE = 2
local LINE = 3
local POLYGON = 4
local TEXT = 5
local function addToDrawingQue(priority, kind, data)
	priority = priority or 0
	if drawingQue[priority] == nil then
		drawingQue[priority] = {}
	end
	local que = drawingQue[priority]
	data.kind = kind
	que[#que + 1] = data
end
local function clearDrawingQue()
	drawingQue = {}
	-- Also update drawing region in this function for some reaosn?
	local clientWidth = client.screenwidth()
	local clientHeight = client.screenheight()
	local layout = nds.getscreenlayout()
	local gap = nds.getscreengap()
	local invert = nds.getscreeninvert()
	local gameBaseWidth = nil
	local gameBaseHeight = nil
	if layout == "Natural" then
		-- We do not support rotated screens. Assume vertical.
		layout = "Vertical"
	end
	if layout == "Vertical" then
		gameBaseWidth = 256
		gameBaseHeight = 192 * 2 + gap
	elseif layout == "Horizontal" then
		gameBaseWidth = 256 * 2
		gameBaseHeight = 192
	else
		gameBaseWidth = 256
		gameBaseHeight = 192
	end
	local gameScale = math.min(clientWidth / gameBaseWidth, clientHeight / gameBaseHeight)
	colView = {
		w = 0.5 * 256 * gameScale,
		h = 0.5 * 192 * gameScale,
	}
	colView.x = (clientWidth - gameBaseWidth * gameScale) * 0.5 + colView.w
	colView.y = (clientHeight - gameBaseHeight * gameScale) * 0.5 + colView.h
	iView = {
		x = (clientWidth - (gameBaseWidth * gameScale)) * 0.5,
		y = (clientHeight - (gameBaseHeight * gameScale)) * 0.5,
		w = 256 * gameScale,
		h = 192 * gameScale,
	}
	if layout ~= "Horizontal" then
		-- People who use wide window (black space to the side of game screen) tell me they prefer info to be displayed on the left rather than over the bottom screen.
		iView.x = 0
		iView.y = iView.y + (192 + gap) * gameScale
	else
		iView.x = iView.x + 256 * gameScale
	end
end
clearDrawingQue()
local function atv(v)
	return {x = v[1], y = v[2], z = v[3]}
end
local function setPerspective(surfaceNormal)
	cameraRotationVector = surfaceNormal
	-- We will look in the direction opposite the surface normal.
	local p = multiplyVector(surfaceNormal, -1)
	-- The Z co-ordinate is simply the distance in that direction.
	local mZ = { p.x, p.y, p.z }
	-- The X co-ordinate should be independent of Y. So this vector is orthogonal to 0,1,0 and mZ.
	local mX = nil
	if surfaceNormal.x ~= 0 or surfaceNormal.z ~= 0 then
		mX = crossProduct(atv(mZ), { x = 0, y = 0x1000, z = 0 })
		-- Might not be normalized. Normalize it.
		UpdateMag(mX)
		mX = multiplyVector(mX, 1 / mX.mag3)
	else
		mX = { x = 0x1000, y = 0, z = 0 }
	end
	mX = { mX.x, mX.y, mX.z }
	local mY = crossProduct(atv(mX), atv(mZ))
	mY = { mY.x, mY.y, mY.z }
	cameraRotationMatrix = { mX, mY, mZ }
end
setPerspective({x = 0, y = 0x1000, z = 0})
local function scaleAtDistance(point, s)
	local v = subtractVector(point, drawingCenter)
	local m = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	s = s * (0x1000 / m)
	return s / cameraFW * colView.w
end
local function point3Dto2D(vector)
	local v = subtractVector(vector, drawingCenter)
	local mat = cameraRotationMatrix
	local rotated = {
		x = (v.x * mat[1][1] + v.y * mat[1][2] + v.z * mat[1][3]) / 0x1000,
		y = (v.x * mat[2][1] + v.y * mat[2][2] + v.z * mat[2][3]) / 0x1000,
		z = (v.x * mat[3][1] + v.y * mat[3][2] + v.z * mat[3][3]) / 0x1000,
	}
	if isCameraView then
		-- Perspective
		if rotated.z < 0x1000 then
			return { x = 0xffffff, y = 0xffffff } -- ?
		end
		local scaledByDistance = multiplyVector(rotated, 0x1000 / rotated.z)
		return {
			x = scaledByDistance.x / cameraFW,
			y = -scaledByDistance.y / cameraFH,
		}
	else
		-- Orthographic
		return {
			x = rotated.x / scale / colView.w,
			y = -rotated.y / scale / colView.h,
		}
	end
end
local function line3Dto2D(v1, v2)
	-- Must have a line transformation, because:
	-- Assume you have a triangle where two vertexes are in front of camera, one to the left and one to the right.
	-- The other vertex is far behind the camera, directly behind.
	-- This triangle should appear, in 2D to have four points. The line from v1 to vBehind should diverge from the line from v2 to vBehind.
	v1 = subtractVector(v1, drawingCenter)
	v2 = subtractVector(v2, drawingCenter)
	local mat = cameraRotationMatrix
	v1 = {
		x = (v1.x * mat[1][1] + v1.y * mat[1][2] + v1.z * mat[1][3]) / 0x1000,
		y = (v1.x * mat[2][1] + v1.y * mat[2][2] + v1.z * mat[2][3]) / 0x1000,
		z = (v1.x * mat[3][1] + v1.y * mat[3][2] + v1.z * mat[3][3]) / 0x1000,
	}
	v2 = {
		x = (v2.x * mat[1][1] + v2.y * mat[1][2] + v2.z * mat[1][3]) / 0x1000,
		y = (v2.x * mat[2][1] + v2.y * mat[2][2] + v2.z * mat[2][3]) / 0x1000,
		z = (v2.x * mat[3][1] + v2.y * mat[3][2] + v2.z * mat[3][3]) / 0x1000,
	}
	if isCameraView then
		-- Perspective
		if v1.z < 0x1000 and v2.z < 0x1000 then
			return nil
		end
		local flip = false
		if v1.z < 0x1000 then
			flip = true
			local temp = v1
			v1 = v2
			v2 = temp
		end
		local changed = nil
		if v2.z < 0x1000 then
			local diff = subtractVector(v1, v2)
			local percent = (v1.z - 0x1000) / diff.z
			if percent > 1 then error("invalid math") end
			v2 = subtractVector(v1, multiplyVector(diff, percent))
			if v2.z > 0x1001 or v2.z < 0xfff then
				print(v2)
				error("invalid math")
			end
			changed = 2
			if flip then changed = 1 end
		end
		if flip then
			local temp = v1
			v1 = v2
			v2 = temp
		end
		local s1 = multiplyVector(v1, 0x1000 / v1.z)
		local s2 = multiplyVector(v2, 0x1000 / v2.z)
		local p1 = {
			x = s1.x / cameraFW,
			y = -s1.y / cameraFH,
		}
		local p2 = {
			x = s2.x / cameraFW,
			y = -s2.y / cameraFH,
		}
		
		return { p1, p2, changed }
	else
		-- Orthographic
		return {
			{
				x = v1.x / scale / colView.w,
				y = -v1.y / scale / colView.h,
			},
			{
				x = v2.x / scale / colView.w,
				y = -v2.y / scale / colView.h,
			},
		}
	end
end
local function drawQue()
	-- In camera mode, we need to delay by 2 frames to match the game's 3D renderer
	local oldQue = queHistory[1]
	queHistory[1] = queHistory[2]
	queHistory[2] = drawingQue
	
	local currentQue = drawingQue
	if isCameraView and oldQue ~= nil then
		currentQue = oldQue
	end
	
	-- Order of keys given by pairs is not guaranteed
	local priorities = {}
	for k, _ in pairs(currentQue) do
		priorities[#priorities + 1] = k
	end
	table.sort(priorities)
	
	local cw = colView.w
	local ch = colView.h
	local cx = colView.x
	local cy = colView.y
	for i = 1, #priorities do
		local p = priorities[i]
		local que = currentQue[p]
		for _, v in pairs(que) do
			if v.kind == PIXEL then
				gui.drawPixel(v.x * cw + cx, v.y * ch + cy, v.color)
			elseif v.kind == CIRCLE then
				gui.drawEllipse(v.x * cw + cx - v.radius, v.y * ch + cy - v.radius, v.radius * 2, v.radius * 2, v.fillColor, v.edgeColor)
			elseif v.kind == LINE then
				gui.drawLine(v.x1 * cw + cx, v.y1 * ch + cy, v.x2 * cw + cx, v.y2 * ch + cy, v.color)
			elseif v.kind == POLYGON then
				local p = {}
				for i = 1, #v.points do
					-- BizHawk require that polygon draw method gives integers
					p[i] = {
						math.floor(v.points[i][1] * cw + cx + 0.5),
						math.floor(v.points[i][2] * ch + cy + 0.5),
					}
				end
				gui.drawPolygon(p, 0, 0, v.line, v.fill)
			elseif v.kind == TEXT then
				gui.drawText(v.x * cw + cx, v.y + ch + cy, v.text)
			end
		end
	end
end

local function fixLine(x1, y1, x2, y2)
	-- Avoid drawing over the bottom screen
	if y1 > 1 and y2 > 1 then
		return nil
	elseif y1 > 1 then
		local cut = (y1 - 1) / (y1 - y2)
		y1 = 1
		x1 = x2 + ((x1 - x2) * (1 - cut))
		if y2 < -1 then
			-- very high zooms get weird
			cut = (-1 - y2) / (y1 - y2)
			y2 = -1
			x2 = x1 + ((x2 - x1) * (1 - cut))
		end
	elseif y2 > 1 then
		local cut = (y2 - 1) / (y2 - y1)
		y2 = 1
		x2 = x1 + ((x2 - x1) * (1 - cut))
		if y1 < -1 then
			-- very high zooms get weird
			cut = (-1 - y1) / (y2 - y1)
			y1 = -1
			x1 = x2 + ((x1 - x2) * (1 - cut))
		end
	end
	-- If we cut out the other sides, that would lead to polygons not drawing correctly.
	-- Because if we zoom in, all lines would be fully outside the bounds and so get cut out.
	return { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
end
local function pixel(vector, color, priority)
	local point = point3Dto2D(vector)
	if point.y < 0 or point.y >= maxY then return end
	if point.x < 0 or point.x >= maxX then return end
	addToDrawingQue(priority, PIXEL, {
		x = point.x,
		y = point.y,
		color = color,
	})
end
local function circle(origin, radius, fillColor, priority, edgeColor, rawRadius)
	local point = point3Dto2D(origin)
	if rawRadius ~= true then
		if isCameraView then
			radius = scaleAtDistance(origin, radius)
		else
			radius = radius / scale
			radius = radius - 0.5 -- BizHawk dumb?
		end
	end
	if point.y * colView.h + radius < -colView.h or point.y * colView.h - radius > colView.h then
		return
	end
	if point.x * colView.w + radius < -colView.w or point.x * colView.w - radius > colView.w then
		return
	end
	addToDrawingQue(priority, CIRCLE, {
		x = point.x,
		y = point.y,
		radius = radius,
		fillColor = fillColor,
		edgeColor = edgeColor or fillColor,
	})
end
local function line(vector1, vector2, color, priority)
	local p = line3Dto2D(vector1, vector2)
	if p == nil then
		return
	end
	-- Avoid drawing lines over the bottom screen
	local points = fixLine(p[1].x, p[1].y, p[2].x, p[2].y)
	if points == nil then
		return
	end
	
	addToDrawingQue(priority, LINE, {
		x1 = points.x1, y1 = points.y1,
		x2 = points.x2, y2 = points.y2,
		color = color or "red"
	})
end
local function polygon(verts, lineColor, fillColor, priority)
	local edges = {}
	for i = 1, #verts do
		local e = nil
		if i ~= #verts then
			e = line3Dto2D(verts[i], verts[i + 1])
		else
			e = line3Dto2D(verts[i], verts[1])
		end
		if e ~= nil then
			edges[#edges + 1] = e
		end
	end
	if #edges == 0 then
		return -- Polygon is entirely behind the view area
	end
	
	local points = {}
	for i = 1, #edges do
		points[#points + 1] = edges[i][1]
		if edges[i][3] ~= nil then
			points[#points + 1] = edges[i][2]
		end
	end
	local fp = {}
	for i = 1, #points do
		local nextId = (i % #points) + 1
		local line = fixLine(points[i].x, points[i].y, points[nextId].x, points[nextId].y)
		if line ~= nil then
			if #fp == 0 or line.x1 ~= fp[#fp][1] or line.y1 ~= fp[#fp][2] then
				fp[#fp + 1] = { line.x1, line.y1 }
			end
			if line.x2 ~= fp[1][1] or line.y2 ~= fp[1][2] then
				fp[#fp + 1] = { line.x2, line.y2 }
			end
		end
	end
		
	addToDrawingQue(priority, POLYGON, {
		points = fp,
		line = lineColor,
		fill = fillColor
	})
end
local function triangle(v1, v2, v3, lineColor, fillColor, priority)
	polygon({v1, v2, v3}, lineColor, fillColor, priority)
end
local function text(x, y, t, priority)
	if y < 0 or y >= maxY then return end
	if x < 0 or x >= maxX then return end
	addToDrawingQue(priority, TEXT, {
		x = x, y = y, text = t
	})
end
local function drawVectorDot(v, color, priority)
	if maxX == 256 then
		pixel(v, color, 9)
	else
		-- Make them bigger than just one pixel, so they can be seen easily.
		circle(v, 1.5, color, priority or 9, color, true)
	end
end

local function lineFromVector(base, vector, scale, color, priority)
	local scaledVector = multiplyVector(vector, scale / 0x1000)
	line(base, addVector(base, scaledVector), color, prority)
end

local function _drawObjectCollision(racer, obj)	
	local objColor = 0xff40c0e0
	local fill = objColor
	if obj.multiBox == true or isCameraView then
		fill = 0x5040c0e0
	end
	local skipPolys = false
	if obj.hitboxType == "spherical" or obj.hitboxType == "item" then
		circle(obj.pos, obj.radius, objColor, -4, fill)
		-- White circles to indicate size of hitbox cross-section at the current elevation.
		if not isCameraView then
			local relative = subtractVector(racer.posForObjects, obj.pos)
			local vDist = dotProduct_float(relative, cameraRotationVector)
			local totalRadius = obj.radius + racer.radius
			if totalRadius > vDist then
				local touchHorizDist = math.sqrt(totalRadius * totalRadius - vDist * vDist)
				circle(obj.pos, (obj.radius / totalRadius) * touchHorizDist, 0xffffffff, -1, 0)
				circle(racer.posForObjects, (racer.radius / totalRadius) * touchHorizDist, 0xffffffff, -1, 0)
			end
		end
	elseif obj.hitboxType == "cylindrical" then
		-- A circle is only good for top-down view.
		if vectorEqual(cameraRotationVector, {x=0,y=0x1000,z=0}) then
			skipPolys = true
			circle(obj.pos, obj.radius, objColor, -4, fill)
			-- TODO: White circle if we are above/below?
		end
	end
	if not skipPolys and obj.polygons ~= nil and #obj.polygons ~= 0 then
		local wireframeToo = obj.hitboxType == "boxy"
		if obj.cylinder2 == true or obj.hitboxType == "cylindrical" then
			fill = nil
		end
		for i = 1, #obj.polygons do
			polygon(obj.polygons[i], objColor, fill, -4)
			if wireframeToo then
				polygon(obj.polygons[i], 0xffffffff, 0, -3)
			end
		end
		if obj.hitboxType == "boxy" then
			local racerPolys = getBoxyPolygons(
				racer.posForObjects,
				obj.orientation,
				{ x = racer.radius, y = racer.radius, z = racer.radius }
			)
			for i = 1, #racerPolys do
				polygon(racerPolys[i], 0xffffffff, 0, -2)
			end
		end
	end
end
local function drawObjectCollision(racer)
	if drawAllObjects then
		for i = 1, #allObjects do
			getObjectDetails(allObjects[i])
			_drawObjectCollision(racer, allObjects[i])
		end
	else
		local obj = nearestObjectData
		if obj ~= nil then
			_drawObjectCollision(racer, obj)
		end
	end
end
local function drawKcl(graphical)
	clearDrawingQue()
	local racer = myData
	local other = myData.ghost
	if watchingGhost then
		racer = myData.ghost
		other = myData
	end
	if not form.kclFreezeCamera then
		drawingCenter = racer.posForObjects
	end
	-- Camera view overrides other viewpoint settings
	if isCameraView then
		racer = myData
		other = myData.ghost
		local cameraPtr = memory.read_u32_le(ptrCameraAddr)
		local camPos = read_pos(cameraPtr + 0x24)
		local camOffset = read_pos(cameraPtr + 0x54)
		--drawingCenter = subtractVector(camPos, camOffset)
		drawingCenter = camPos
		--local direction = read_pos(cameraPtr + 0x15c)
		local camTargetPos = read_pos(cameraPtr + 0x18)
		local direction = subtractVector(camPos, camTargetPos)
		direction = normalizeVector_float(direction)
		setPerspective(direction)
		local cameraFoVV = memory.read_u16_le(cameraPtr + 0x60) * satr
		local camAspectRatio = memory.read_s32_le(cameraPtr + 0x6C) / 0x1000
		
		cameraFW = math.tan(cameraFoVV * camAspectRatio) * 0xec0 -- Idk why not 0x1000, but this gives better results. /shrug
		cameraFH = math.tan(cameraFoVV) * 0x1000
	end
	
	local playerColor = 0xff0000ff
	if isCameraView then
		playerColor = 0x500000ff
	end
	if scale > 60 then
		-- Use myData/myData.ghost instead of racer/other: Ghost color should not change when watching ghost.
		circle(myData.posForObjects, myData.radius, playerColor, -3)
		lineFromVector(myData.posForObjects, myData.movementDirection, myData.radius, "white", 5)
		if other ~= nil then
			circle(myData.ghost.posForObjects, myData.ghost.radius, 0x48ff5080, -1)
			lineFromVector(myData.ghost.posForObjects, myData.ghost.movementDirection, myData.ghost.radius, 0xcccccccc, 5)
		end
	end
	if scale <= 1 then
		circle(racer.posForObjects, 1, 0xffffffff, -2)
		circle(racer.posForObjects, 1, 0xffff0000, -2)
	elseif scale < 200 then
		circle(racer.posForObjects, 200, 0xffff0000, -2)
		circle(racer.preMovementPosForObjects, 200, 0xffa04000, -2)
	end
	
	local data = kclData
	local touchList = {}

	-- draw the dots and stuff
	local nearestWall = nil
	local nearestFloor = nil
	for i = 1, #data do
		local d = data[i]
		local tri = d.triangle
		if tri.isActuallyLine or not d.touch.canTouch then
			goto continue
		end
		
		-- fill
		if d.touch.touching then
			if graphical then
				local color = 0x30ff8888
				if d.touch.push then
					if d.controlsSlope then
						color = 0x4088ff88
						lineFromVector(racer.posForObjects, tri.surfaceNormal, racer.radius, 0xff00ff00, 5)
					elseif d.isWall then
						color = 0x20ffff22
					else
						color = 0x50ffffff
					end
				else
					lineFromVector(racer.posForObjects, tri.surfaceNormal, racer.radius, 0xffff0000, 5)
				end
				polygon(tri.vertex, 0, color, -5)
			end
			touchList[#touchList + 1] = d
		end

		-- lines and dots
		if graphical then
			local color, priority = "white", 0
			if tri.isWall then
				if d.touch.touching and d.touch.push then
					color, priority = "yellow", 2
				else
					color, priority = "orange", 1
				end
			end
			if color ~= nil then
				polygon(tri.vertex, color, 0, priority)
			end
			drawVectorDot(tri.vertex[1], "red", 9)
			drawVectorDot(tri.vertex[2], "red", 9)
			drawVectorDot(tri.vertex[3], "red", 9)
		end

		-- surface normal vector, kinda bad visually
		--if graphical and tri.surfaceNormal.y ~= 0 and tri.surfaceNormal.y ~= 4096 then
			--local center = addVector(addVector(tri.vertex[1], tri.vertex[2]), tri.vertex[3])
			--center = multiplyVector(center, 1 / 3)
			--lineFromVector(center, tri.surfaceNormal, racer.radius, color, 4)
		--end
		
		-- find nearest wall/floor
		if tri.isWall and not d.touch.push and (nearestWall == nil or d.touch.distance < data[nearestWall].touch.distance) then
			nearestWall = i
		end
		if tri.isFloor and not d.touch.push and (nearestFloor == nil or d.touch.distance < data[nearestFloor].touch.distance) then
			nearestFloor = i
		end
		
		::continue::
	end
	local y = -19
	if nearestWall ~= nil then
		drawText(2, y, "closest wall: " .. numToStr(data[nearestWall].touch.distance))
		y = y - 18
	end
	if nearestFloor ~= nil then
		drawText(2, y, "closest floor: " .. numToStr(data[nearestFloor].touch.distance))
		y = y - 18
	end
	
	y = y - 3
	for i = 1, #touchList do
		local d = touchList[i]
		local tri = d.triangle
		local stype = ""
		if tri.isWall then stype = stype .. "w" end
		if tri.isFloor then stype = stype .. "f" end
		if stype == "" then stype = "?" end
		local str = tri.id .. ": " .. stype .. ", "
		if d.touch.push == false then
			if d.touch.wasBehind then
				str = str .. "n (behind)"
			else
				str = str .. "n " .. numToStr(d.touch.outwardMovement)
			end
		else
			str = str .. "p " .. numToStr(d.touch.pushOutDistance)
		end
		drawText(2, y, str)
		
		y = y - 18
	end
		
	if graphical then
		gui.use_surface("client")
		drawObjectCollision(racer)
		if not isCameraView then
			gui.drawRectangle(colView.x - colView.w, colView.y - colView.h, colView.w * 2, colView.h * 2, "black", "black")
		end
		drawQue()
	end
end

-- Main drawing function
local function _mkdsinfo_run_draw(inRace)
	-- BizHawk is slow. Let's tell it to not worry about waiting for this.
	if not client.ispaused() and not drawWhileUnpaused then
		if client.isseeking() then
			-- We need special logic here. BizHawk will not set paused = true at end of seek before this script runs!
			emu.yield()
			if not client.ispaused() then
				return
			end
		else
			-- I would just yield, then check if we're still on the same frame and draw then.
			-- However, BizHawk will not display anything we draw after a yield, while not paused.
			return
		end
	end
	
	if inRace then
		local data = myData
		if watchingGhost then data = ghostData end
		
		drawInfo(data)
		drawKcl(form.drawCollision)
	else
		gui.clearGraphics("client")
		gui.clearGraphics("emucore")
		drawText(10, 10, "Not in a race.")
	end
end
-------------------------------------------------

-- Button events --------------------------------
local function useInputsClick()
	if not inRace() then
		print("You aren't in a race.")
		return
	end
	if not tastudio.engaged() then
		return
	end
	
	if form.ghostInputs == nil then
		form.ghostInputs = memory.read_bytes_as_array(memory.read_s32_le(ptrPlayerInputsAddr), 0xdce) -- 0x8ace)
		form.firstGhostInputFrame = emu.framecount() - memory.read_s32_le(memory.read_s32_le(ptrRaceTimersAddr) + 4) + 121
		form.ghostLapTimes = memory.read_bytes_as_array(memory.read_s32_le(ptrSomethingPlayerAddr) + 0x20, 0x4 * 5)
		setGhostInputs(form)
		forms.settext(form.ghostInputHackButton, "input hack active")
	else
		form.ghostInputs = nil
		forms.settext(form.ghostInputHackButton, "Copy from player")
	end
end
local function watchGhostClick()
	if myData.ghost ~= nil then
		watchingGhost = not watchingGhost
	else
		watchingGhost = false
	end
	local s = "player"
	if watchingGhost then s = "ghost" end
	forms.settext(form.watchGhost, s)
	-- update collision data
	getCollisionDataForRacer((watchingGhost and myData.ghost) or myData)
	-- re-draw
	if form.drawCollision then
		-- We need non-text updates, which can't be done without emulating a frame.
		redraw()
	else
		-- Only text updates.
		gui.cleartext()
		_mkdsinfo_run_draw(true)
	end
end
local function setComparisonPointClick()
	if form.comparisonPoint == nil then
		local pos = myData.pos
		if watchingGhost then pos = ghostData.pos end
		form.comparisonPoint = { x = pos.x, z = pos.z }
		forms.settext(form.setComparisonPoint, "Clear comparison point")
	else
		form.comparisonPoint = nil
		forms.settext(form.setComparisonPoint, "Set comparison point")
	end
end
local function loadGhostClick()
	local fileName = forms.openfile(nil,nil,"TAStudio Macros (*.bk2m)|*.bk2m|All Files (*.*)|*.*")
	local inputFile = assert(io.open(fileName, "rb"))
	local inputHeader = inputFile:read("*line")
	-- Parse the header
	local names = {}
	local index = 0
	local nextIndex = string.find(inputHeader, "|", index)
	while nextIndex ~= nil do
		names[#names + 1] = string.sub(inputHeader, index, nextIndex - 1)
		index = nextIndex + 1
		nextIndex = string.find(inputHeader, "|", index)
		if #names > 100 then
			error("unable to parse header")
		end
	end
	nextIndex = string.len(inputHeader)
	names[#names + 1] = string.sub(inputHeader, index, nextIndex - 1)
	-- ignore next 3 lines
	local line = inputFile:read("*line")
	while string.sub(line, 1, 1) ~= "|" do
		line = inputFile:read("*line")
	end
	-- parse inputs
	local inputs = {}
	while line ~= nil and string.sub(line, 1, 1) == "|" do
		-- |  128,   96,    0,    0,.......A...r....|
		-- Assuming all non-button inputs are first.
		local id = 1
		index = 0
		local nextComma = string.find(line, ",", index)
		while nextComma ~= nil do
			id = id + 1
			index = nextComma + 1
			nextComma = string.find(line, ",", index)
			if id > 100 then
				error("unable to parse input")
			end
		end
		-- now buttons
		local buttons = 0
		while id <= #names do
			if string.sub(line, index, index) ~= "." then
				if names[id] == "A" then buttons = buttons | 0x01
				elseif names[id] == "B" then buttons = buttons | 0x02
				elseif names[id] == "R" then buttons = buttons | 0x04
				elseif names[id] == "X" or names[id] == "L" then buttons = buttons | 0x08
				elseif names[id] == "Right" then buttons = buttons | 0x10
				elseif names[id] == "Left" then buttons = buttons | 0x20
				elseif names[id] == "Up" then buttons = buttons | 0x40
				elseif names[id] == "Down" then buttons = buttons | 0x80
				end
			end
			id = id + 1
			index = index + 1
		end
		inputs[#inputs + 1] = buttons
		line = inputFile:read("*line")
	end
	inputFile:close()
	-- turn inputs into MKDS recording format (buttons, count)
	local bytes = { 0, 0, 0, 0 }
	local count = 1
	local lastInput = inputs[1]
	for i = 2, #inputs do
		if inputs[i] ~= lastInput or count == 255 then
			bytes[#bytes + 1] = lastInput
			bytes[#bytes + 1] = count
			lastInput = inputs[i]
			count = 1
			if #bytes == 0xdcc then
				print("Maximum ghost recording length reached.")
				break
			end
		else
			count = count + 1
		end
	end
	while #bytes < 0xdcc do bytes[#bytes + 1] = 0 end
	-- write
	form.ghostInputs = bytes
	form.firstGhostInputFrame = emu.framecount() - memory.read_s32_le(memory.read_s32_le(ptrRaceTimersAddr) + 4) + 121
	form.ghostLapTimes = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
	setGhostInputs(form)
	forms.settext(form.ghostInputHackButton, "input hack active")

end
local function saveCurrentInputsClick()
	-- BizHawk doesn't expose a file open function (Lua can still write to files, we just don't have a nice way to let the user choose a save location.)
	-- So instead, we just tell the user which frames to save.
	local firstInputFrame = emu.framecount() - memory.read_s32_le(memory.read_s32_le(ptrRaceTimersAddr) + 4) + 121
	print("BizHawk doesn't give Lua a save file dialog.")
	print("You can manually save your current inputs as a .bk2m:")
	print("1) Select frames " .. firstInputFrame .. " to " .. emu.framecount() .. " (or however many frames you want to include).")
	print("2) File -> Save Selection to Macro")
end

local function branchLoadHandler()
	if form.firstStateWithGhost ~= 0 then
		form.firstStateWithGhost = 0
	end
	if form.ghostInputs ~= nil then
		local currentFrame = emu.framecount()
		setGhostInputs(form)
		if emu.framecount() ~= currentFrame then
			print("Movie rewind: ghost inputs changed after branch load.")
			print("Stop ghost input hacker to load branch without rewind.")
		end
	end
end

local function drawUnpausedClick()
	drawWhileUnpaused = not drawWhileUnpaused
	if drawWhileUnpaused then
		forms.settext(form.drawUnpausedButton, "Draw while unpaused: ON")
	else
		forms.settext(form.drawUnpausedButton, "Draw while unpaused: OFF")
	end
end

local function kclClick()
	-- BizHawk is very very bad.
	-- It does not allow drawing on any picture boxes if there is more than one Lua window open.
	-- So we will draw over the top screen instead.
	form.drawCollision = not form.drawCollision
	redraw()
end
local function zoomInClick()
	scale = scale * 0.8
	redraw()
end
local function zoomOutClick()
	scale = scale / 0.8
	redraw()
end
local function focuseHereClick()
	form.kclFreezeCamera = not form.kclFreezeCamera
	if form.kclFreezeCamera then
		forms.settext(form.kclFreezeCameraButton, "unfreeze")
	else
		forms.settext(form.kclFreezeCameraButton, "freeze")
		redraw()
	end
end

local function _changePerspective()
	local id = perspectiveId
	if id < 0 then
		local presets = {
			{ "camera", nil },
			{ "top down", { 0, 0x1000, 0 }},
			{ "north-south", { 0, 0, -0x1000 }},
			{ "south-north", { 0, 0, 0x1000 }},
			{ "east-west", { 0x1000, 0, 0 }},
			{ "west-east", { -0x1000, 0, 0 }},
		}
		if id == -6 then
			-- camera
			local cameraPtr = memory.read_u32_le(ptrCameraAddr)
			local direction = read_pos(cameraPtr + 0x15c)
			setPerspective(multiplyVector(direction, -1))
			isCameraView = true
		else
			setPerspective(atv(presets[id + 7][2]))
			isCameraView = false
		end
		forms.settext(form.perspectiveLabel, presets[id + 7][1])
	else
		setPerspective(triangles[id].surfaceNormal)
		isCameraView = false
		forms.settext(form.perspectiveLabel, "triangle " .. id)
	end
	redraw()
end
local function changePerspectiveLeft()
	local id = perspectiveId
	id = id - 1
	if id < -6 then
		id = 9999
	end
	if id >= 0 then
		-- find next nearby triangle ID
		local nextId = 0
		for i = 1, #kclData do
			local ti = kclData[i].triangle.id
			if ti < id and ti > nextId then
				if not vectorEqual(cameraRotationVector, kclData[i].triangle.surfaceNormal) then
					nextId = ti
				end
			end
		end
		if nextId == 0 then
			id = -1
		else
			id = nextId
		end
	end
	perspectiveId = id
	_changePerspective()
end
local function changePerspectiveRight()
	local id = perspectiveId
	id = id + 1
	if id >= 0 then
		-- find next nearby triangle ID
		local nextId = 9999
		for i = 1, #kclData do
			local ti = kclData[i].triangle.id
			if ti >= id and ti < nextId then
				if not vectorEqual(cameraRotationVector, kclData[i].triangle.surfaceNormal) then
					nextId = ti
				end
			end
		end
		if nextId == 9999 then
			id = -6
		else
			id = nextId
		end
	end
	perspectiveId = id
	_changePerspective()
end

local bizHawkEventIds = {}
local function _mkdsinfo_setup()
	if emu.framecount() < 400 then
		-- <400: rough detection of if stuff we need is loaded
		-- Specifically, we find addresses of hitbox functions.
		print("Looks like some data might not be loaded yet. Re-start this Lua script at a later frame.")
		shouldExit = true
	elseif showBizHawkDumbnessWarning then
		print("BizHawk's Lua API is horrible. In order to work around bugs and other limitations, do not stop this script through BizHawk. Instead, close the window it creates and it will stop itself.")
	end
	
	form = {}
	form.firstStateWithGhost = 0
	form.comparisonPoint = nil
	form.handle = forms.newform(305, 153, "MKDS Info Thingy", function()
		if my_script_id == script_id then
			shouldExit = true
			redraw()
		end
	end)
	
	local buttonMargin = 5
	local labelMargin = 2
	local y = 10
	-- I would use a checkbox, but they don't get a change handler.
	local temp = forms.label(form.handle, "Watching: ", 10, y + 4)
	forms.setproperty(temp, "AutoSize", true)
	form.watchGhost = forms.button(
		form.handle, "player", watchGhostClick,
		forms.getproperty(temp, "Right") + labelMargin, y,
		50, 23
	)
	
	form.setComparisonPoint = forms.button(
		form.handle, "Set comparison point", setComparisonPointClick,
		forms.getproperty(form.watchGhost, "Right") + buttonMargin, y,
		100, 23
	)
	
	y = 38
	temp = forms.label(form.handle, "Ghost: ", 10, y + 4)
	forms.setproperty(temp, "AutoSize", true)
	temp = forms.button(
		form.handle, "Copy from player", useInputsClick,
		forms.getproperty(temp, "Right") + buttonMargin, y,
		100, 23
	)
	form.ghostInputHackButton = temp
	
	temp = forms.button(
		form.handle, "Load bk2m", loadGhostClick,
		forms.getproperty(temp, "Right") + labelMargin, y,
		70, 23
	)
	temp = forms.button(
		form.handle, "Save bk2m", saveCurrentInputsClick,
		forms.getproperty(temp, "Right") + labelMargin, y,
		70, 23
	)
	-- I also want a save-to-bk2m at some point. Although BizHawk doesn't expose a file open function (Lua can still write to files, we just don't have a nice way to let the user choose a save location.) so we might instead copy input to the current movie and let the user save as bk2m manually.

	y = y + 28
	form.drawUnpausedButton = forms.button(
		form.handle, "Draw while unpaused: ON", drawUnpausedClick,
		10, y, 150, 23
	)

	-- Collision view
	y = y + 28
	form.kclButton = forms.button(
		form.handle, "View collision", kclClick,
		10, y, 88, 23
	)
	form.zoomInButton = forms.button(
		form.handle, "+", zoomInClick,
		forms.getproperty(form.kclButton, "Right") + labelMargin, y,
		23, 23
	)
	form.zoomOutButton = forms.button(
		form.handle, "-", zoomOutClick,
		forms.getproperty(form.zoomInButton, "Right") + labelMargin, y,
		23, 23
	)
	form.kclFreezeCameraButton = forms.button(
		form.handle, "freeze", focuseHereClick,
		forms.getproperty(form.zoomOutButton, "Right") + labelMargin*2, y,
		70, 23
	)
	
	y = y + 28
	temp = forms.label(form.handle, "Perspective:", 10, y + 4)
	forms.setproperty(temp, "AutoSize", true)
	form.perspectiveLeft = forms.button(
		form.handle, "<", changePerspectiveLeft,
		forms.getproperty(temp, "Right") + labelMargin*2, y,
		18, 23
	)
	form.perspectiveLabel = forms.label(
		form.handle, "top down",
		forms.getproperty(form.perspectiveLeft, "Right") + labelMargin*2, y + 4
	)
	forms.setproperty(form.perspectiveLabel, "AutoSize", true)
	form.perspectiveRight = forms.button(
		form.handle, ">", changePerspectiveRight,
		forms.getproperty(form.perspectiveLabel, "Right") + 22, y,
		18, 23
	)
end
local function _mkdsinfo_close()
	client.SetClientExtraPadding(0, 0, 0, 0)
	forms.destroy(form.handle)
	
	for i = 1, #bizHawkEventIds do
		event.unregisterbyid(bizHawkEventIds[i])
	end
end

-- BizHawk ----------------------------
memory.usememorydomain("ARM9 System Bus")

local function main()
	_mkdsinfo_setup()
	while (not shouldExit) or (redrawSeek ~= nil) do
		if not shouldExit then
			if inRace() then
				_mkdsinfo_run_data()
				_mkdsinfo_run_draw(true)
			else
				_mkdsinfo_run_draw(false)
			end
		end
		
		-- BizHawk shenanigans
		local frame = emu.framecount()
		local stopSeeking = false
		if redrawSeek ~= nil and redrawSeek == frame then
			stopSeeking = true
		elseif client.ispaused() then
			-- User has interrupted the rewind seek.
			stopSeeking = true
		end
		if stopSeeking then
			client.pause()
			redrawSeek = nil
			if not shouldExit then
				emu.frameadvance()
			else
				-- The while loop will exit!
			end
		else
			emu.frameadvance()
		end
	end
	_mkdsinfo_close()
	
	gui.clearGraphics("client")
	gui.clearGraphics("emucore")
	gui.cleartext()
end

gui.clearGraphics("client")
gui.clearGraphics("emucore")
gui.use_surface("emucore")
gui.cleartext()

if tastudio.engaged() then
	bizHawkEventIds[#bizHawkEventIds + 1] = tastudio.onbranchload(branchLoadHandler)
end

main()
