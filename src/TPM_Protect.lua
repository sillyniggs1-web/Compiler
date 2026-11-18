script_name("Hexed TPM")
script_author("Hexed Studio")
script_version("4.0-TPM-ReSA")
script_description("always active  |  cmd: /members (sync, auto)  /members clear  /tpms (scan)  /tpml (list)  /tpmd (debug)")

if not pcall(require, "lib.moonloader") then pcall(require, "moonloader") end
local bitex  = require('bitex')
local sampev = require 'samp.events'

local PROTECT        = true
local AUTO_REFRESH   = true
local EVENT_RGBA     = true
local IGNORE_WHITE   = true
local ACTIVE_ON_START = true

local SW, SH  = getScreenResolution()
local TD_X    = SW * 0.5
local TD_Y    = SH * 0.02
local TD_SIZE = 1.3
local TD_SECONDS = 4.0

local IS_AL = AL_VERSION ~= nil
local DPI = AL_DPI_SCALE or MONET_DPI_SCALE or 1
local function isMonetLoader() return MONET_VERSION ~= nil and not IS_AL end
local realMyId = nil

local color_nicks = {
    [4261215253] = 368966908,  [4294967168] = 368966908,  [4294967040] = 368966908,
    [1717460481] = 23486046,   [4286480000] = 2164227710, [2570282624] = 2157523814,
    [2573611904] = 2157536819, [4284887936] = 2164221491, [9643929]    = 2566951719,
    [3484370560] = 2161094470, [4286578816] = 2164228096, [139422719]  = 2150852249,
    [2516714112] = 2157314562, [5177216]    = 2147503871, [4849536]    = 2147503871,
    [3126074752] = 2159694877, [3439263872] = 2160918272, [3183328640] = 2159918525,
    [3422604441] = 2580283596, [1718026137] = 2573625087, [4294967295] = 2580667164,
    [3520797849] = 2580667164, [2826467456] = 2158524536, [16769689]   = 2566979554
}

local TPM = {}
TPM.active = ACTIVE_ON_START
TPM.evt = {}
TPM.evtCount = 0
TPM.mode = 'poll'
TPM.myId, TPM.myRaw, TPM.myKey = -1, nil, nil
TPM.source = 'none'
TPM.nextTick = 0
TPM.nextPublish = 0
TPM.showUntil = 0
TPM.req = nil
TPM.roster = {}
TPM.capLines = {}
TPM.silent = false
TPM.AUTO_SYNC = 60
TPM.nextAuto = 0
TPM.ROSTER_FILE = getWorkingDirectory() .. "/HexedTPM_Members.txt"
TPM.captureUntil = 0
TPM.capturing = false
TPM.MEMBERS_CMD = '/gang online'
TPM.CAPTURE_SECONDS = 4.0

local function isPlayerListed(id)
	return sampIsPlayerConnected(id) == true
end

local function getMyPoolId()
	local ok, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
	if ok and type(id) == 'number' and id >= 0 and id <= sampGetMaxPlayerId() then return id end
	return nil
end

local function tpmNick(id)
	local ok, n = pcall(sampGetPlayerNickname, id)
	if ok and type(n) == 'string' then return n end
	return ''
end

local function tpmPollRaw(id)
	local ok, raw = pcall(sampGetPlayerColor, id)
	return ok and tonumber(raw) or nil
end

local function tpmPollKey(raw)
	local color = raw
	if isMonetLoader() and color_nicks[color] then color = color_nicks[color] end
	return bitex.bextract(color, 16, 8) * 65536 + bitex.bextract(color, 8, 8) * 256 + bitex.bextract(color, 0, 8)
end

local function tpmIsDefaultWhite(raw)
	raw = tonumber(raw)
	if raw == nil then return false end
	raw = raw % 4294967296
	return raw == 0xFFFFFFFF or math.floor(raw / 256) == 0xFFFFFF or raw % 16777216 == 0xFFFFFF
end

local function tpmEvtRGB(v)
	v = v % 4294967296
	if EVENT_RGBA then
		return math.floor(v / 16777216) % 256, math.floor(v / 65536) % 256, math.floor(v / 256) % 256
	end
	return math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256
end

function TPM.store(playerId, color)
	playerId, color = tonumber(playerId), tonumber(color)
	if playerId == nil or color == nil then return end
	TPM.evt[playerId] = color % 4294967296
	TPM.evtCount = TPM.evtCount + 1
	TPM.nextTick = 0
	TPM.nextPublish = math.min(TPM.nextPublish, os.clock() + 0.25)
end

function TPM.onInit(playerId)
	TPM.evt = {}
	TPM.evtCount = 0
	TPM.mode = 'poll'
	TPM.myKey, TPM.myRaw = nil, nil
	TPM.nextTick = 0
	TPM.capturing = false
	TPM.nextAuto = os.clock() + 10
end

function TPM.tick(force)
	local now = os.clock()
	if not force and now < TPM.nextTick then return end
	TPM.nextTick = now + 0.5
	if not force and not AUTO_REFRESH and TPM.myKey ~= nil then return end

	local pool = getMyPoolId()
	local evId = tonumber(realMyId) or pool
	TPM.myId = pool or evId or -1

	if evId ~= nil and TPM.evt[evId] ~= nil then
		TPM.mode = 'evt'
		TPM.myRaw = TPM.evt[evId]
		TPM.myKey = TPM.myRaw
		TPM.source = tonumber(realMyId) and 'server events' or 'server events (server ID unknown)'
		return
	end

	TPM.mode = 'poll'
	TPM.myKey, TPM.myRaw = nil, nil
	if pool == nil then TPM.source = 'no player slot'; return end

	local myNick = tpmNick(pool)
	local cands = { pool }
	local rid = tonumber(realMyId)
	if rid ~= nil and rid ~= pool then
		local nick = tpmNick(rid)
		if nick == '' or nick == myNick then cands[#cands + 1] = rid end
	end
	local fallbackRaw = nil
	for _, id in ipairs(cands) do
		local raw = tpmPollRaw(id)
		if raw ~= nil and raw % 4294967296 ~= 0 then
			if not tpmIsDefaultWhite(raw) then
				TPM.myRaw, TPM.myKey, TPM.source = raw, tpmPollKey(raw), 'polling'
				return
			end
			fallbackRaw = fallbackRaw or raw
		end
	end
	if fallbackRaw then
		TPM.myRaw, TPM.myKey, TPM.source = fallbackRaw, tpmPollKey(fallbackRaw), 'polling (default white)'
	else
		TPM.source = 'waiting for color'
	end
end

function TPM.keyOf(id)
	if TPM.mode == 'evt' then return TPM.evt[id] end
	if not sampIsPlayerConnected(id) then return nil end
	local raw = tpmPollRaw(id)
	if raw == nil or raw % 4294967296 == 0 then return nil end
	return tpmPollKey(raw)
end

function TPM.isMember(id)
	if next(TPM.roster) == nil or not sampIsPlayerConnected(id) then return false end
	local nick = tpmNick(id)
	return nick ~= '' and TPM.roster[TPM.norm(nick)] == true
end

function TPM.isTeam(id)
	if id == nil then return false end
	if id == TPM.myId or id == tonumber(realMyId) then return false end
	if TPM.isMember(id) then return true end
	if TPM.myKey == nil then return false end
	if IGNORE_WHITE and tpmIsDefaultWhite(TPM.myRaw) then return false end
	local k = TPM.keyOf(id)
	return k ~= nil and k == TPM.myKey
end

TPM.debug = false
TPM.cnt = { dmg = 0, bullet = 0, blocked = 0, rawBullet = 0, rawRpc = 0 }
TPM.dbgAt = {}
function TPM.dbg(key, text)
	if not TPM.debug then return end
	local now = os.clock()
	if (TPM.dbgAt[key] or 0) > now then return end
	TPM.dbgAt[key] = now + 0.4
	sampAddChatMessage('{ffaa00}[TPM dbg] ' .. text, -1)
end
function TPM.describe(id)
	id = tonumber(id)
	if id == nil then return 'id=nil' end
	local nick = sampIsPlayerConnected(id) and tpmNick(id) or '?'
	local ok, team = pcall(TPM.isTeam, id)
	local ok2, member = pcall(TPM.isMember, id)
	return string.format('id=%d nick=%s team=%s roster=%s', id, nick, tostring(ok and team), tostring(ok2 and member))
end
function TPM.blocks(id)
	if not PROTECT then return false end
	local ok, member = pcall(TPM.isTeam, tonumber(id))
	return ok and member == true
end

local TPM_LINK_FILE = getWorkingDirectory() .. "/HexedTPM_Link.txt"

function TPM.unpublish()
	pcall(os.remove, TPM_LINK_FILE)
end

function TPM.publish(force)
	local now = os.clock()
	if not force and now < TPM.nextPublish then return end
	TPM.nextPublish = now + 1.0

	local ids = {}
	do
		local rid = tonumber(realMyId)
		for id = 0, sampGetMaxPlayerId() do
			if id ~= TPM.myId and id ~= rid and isPlayerListed(id) then
				local ok, member = pcall(TPM.isTeam, id)
				if ok and member then ids[#ids + 1] = id end
			end
		end
	end
	local text = string.format('HEXEDTPM1\nt %d\nprotect %d\nme %d\nteam %s\n',
		os.time(), PROTECT and 1 or 0, TPM.myId, table.concat(ids, ','))
	pcall(function()
		local f = io.open(TPM_LINK_FILE, 'w')
		if f then f:write(text) f:close() end
	end)
end

local function tpmHex()
	if TPM.myKey == nil then return 'unknown' end
	local r, g, b
	if TPM.mode == 'evt' then r, g, b = tpmEvtRGB(TPM.myKey)
	else r, g, b = bitex.bextract(TPM.myKey, 16, 8), bitex.bextract(TPM.myKey, 8, 8), bitex.bextract(TPM.myKey, 0, 8) end
	return string.format('#%02X%02X%02X', r, g, b)
end

function TPM.chatScan()
	TPM.tick(true)
	local note = (IGNORE_WHITE and tpmIsDefaultWhite(TPM.myRaw)) and ' (white = no team)' or ''
	sampAddChatMessage(string.format('{44ff88}[TPM] You: ID %s (slot %s), color %s%s | source: %s | color messages: %d | gang roster: %d | hooks: damage %d, bullet %d, rawBullet %d, rawRpc %d, blocked %d',
		tostring(realMyId or TPM.myId), tostring(TPM.myId), tpmHex(), note, TPM.source, TPM.evtCount, TPM.rosterCount(), TPM.cnt.dmg, TPM.cnt.bullet, TPM.cnt.rawBullet, TPM.cnt.rawRpc, TPM.cnt.blocked), -1)
end

function TPM.chatList()
	TPM.chatScan()
	local n = 0
	for id = 0, sampGetMaxPlayerId() do
		if id ~= TPM.myId and isPlayerListed(id) and TPM.isTeam(id) then
			n = n + 1
			sampAddChatMessage(string.format('{aaaaaa}  [%d] %s', id, tpmNick(id)), -1)
		end
	end
	sampAddChatMessage('{44ff88}[TPM] ' .. n .. ' on your team.', -1)
end

local function tpmStripColors(text)
	return (tostring(text):gsub('{%x%x%x%x%x%x}', ''):gsub('{%x%x%x%x%x%x%x%x}', ''))
end

local function tpmNorm(s)
	s = tostring(s):gsub('_', ' '):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', ''):gsub('%.+$', '')
	return s:lower()
end

local function tpmParseGangLine(text)
	return tpmStripColors(text):match('^%s*%(%d+%)%s+(.-)%s*|')
end

local function tpmResolveGang(bodies, myNick, onlineNorms)
	local myNorm = tpmNorm(myNick)
	local names, unmatched = {}, 0
	for _, body in ipairs(bodies) do
		local words = {}
		for w in tpmNorm(body):gmatch('%S+') do words[#words + 1] = w end
		local hit = nil
		for i = 1, #words do
			local tail = table.concat(words, ' ', i)
			if onlineNorms[tail] then hit = tail; break end
		end
		if hit then
			if hit ~= myNorm then names[hit] = true end
		else
			unmatched = unmatched + 1
		end
	end
	return names, unmatched
end

local function tpmMergeRoster(roster, listed, onlineNorms)
	for name in pairs(listed) do roster[name] = true end
	for name in pairs(roster) do
		if onlineNorms[name] and not listed[name] then roster[name] = nil end
	end
end

TPM.norm = tpmNorm

function TPM.saveRoster()
	pcall(function()
		local f = io.open(TPM.ROSTER_FILE, 'w')
		if not f then return end
		for name in pairs(TPM.roster) do f:write(name .. '\n') end
		f:close()
	end)
end

function TPM.loadRoster()
	pcall(function()
		local f = io.open(TPM.ROSTER_FILE, 'r')
		if not f then return end
		for line in f:lines() do
			line = line:gsub('\r', '')
			if line ~= '' and not line:match('^tag ') then TPM.roster[line] = true end
		end
		f:close()
	end)
end

function TPM.rosterCount()
	local n = 0
	for _ in pairs(TPM.roster) do n = n + 1 end
	return n
end

function TPM.startMembers(silent)
	TPM.capLines = {}
	TPM.capturing = true
	TPM.silent = silent and true or false
	TPM.captureUntil = os.clock() + TPM.CAPTURE_SECONDS
	if not TPM.silent then sampAddChatMessage('{44ff88}[TPM] Syncing gang members...', -1) end
	sampSendChat(TPM.MEMBERS_CMD)
end

function TPM.captureLine(text)
	local body = tpmParseGangLine(text)
	if body and body ~= '' then
		TPM.capLines[#TPM.capLines + 1] = body
		return true
	end
	return tpmStripColors(text):match('^%s*Gangs? Online') ~= nil
end

function TPM.finishMembers()
	TPM.capturing = false
	local silent = TPM.silent
	local lines = TPM.capLines or {}
	if #lines == 0 then
		if not silent then sampAddChatMessage('{ff5544}[TPM] No "' .. TPM.MEMBERS_CMD .. '" reply received. Try /members again.', -1)  end
		return
	end
	local pool = getMyPoolId()
	local myNick = pool and tpmNick(pool) or ''
	local online = {}
	for id = 0, sampGetMaxPlayerId() do
		if isPlayerListed(id) then
			local nick = tpmNick(id)
			if nick ~= '' then online[tpmNorm(nick)] = true end
		end
	end
	local listed, unmatched = tpmResolveGang(lines, myNick, online)
	tpmMergeRoster(TPM.roster, listed, online)
	TPM.roster[tpmNorm(myNick)] = nil
	TPM.saveRoster()
	TPM.nextPublish = 0
	pcall(TPM.publish, true)
	if silent then return end
	local shown = 0
	for id = 0, sampGetMaxPlayerId() do
		if id ~= TPM.myId and isPlayerListed(id) and TPM.isMember(id) then
			shown = shown + 1
			sampAddChatMessage(string.format('{aaaaaa}  [%d] %s', id, tpmNick(id)), -1)
		end
	end
	sampAddChatMessage(string.format('{44ff88}[TPM] Gang: %d online now, %d remembered.%s Auto sync: %s',
		shown, TPM.rosterCount(), unmatched > 0 and (' (' .. unmatched .. ' line(s) not matched to a player)') or '',
		TPM.AUTO_SYNC > 0 and (TPM.AUTO_SYNC .. 's') or 'off'), -1)
end

function TPM.clearRoster()
	TPM.roster = {}
	TPM.saveRoster()
	TPM.nextPublish = 0
	pcall(TPM.publish, true)
	sampAddChatMessage('{ff5544}[TPM] Gang roster cleared.', -1)
end

local imgui = nil
local tagFont = nil
if IS_AL and renderCreateFont and renderFontDrawText then
	addEventHandler('onD3DPresent', function()
		if os.clock() >= TPM.showUntil then return end
		if not tagFont then
			local ok, f = pcall(renderCreateFont, 'Arial', 15 * DPI, 5)
			if ok then tagFont = f else TPM.showUntil = 0 return end
		end
		local text = 'TPM: ON'
		local len = renderGetFontDrawTextLength(tagFont, text)
		renderFontDrawText(tagFont, text, TD_X - len / 2, TD_Y, 0xFF3CE664)
	end)
else
	local okImgui, lib = pcall(require, 'mimgui')
	if okImgui and lib then
		imgui = lib
		pcall(function()
			imgui.OnFrame(function() return os.clock() < TPM.showUntil end, function()
				local wf = imgui.WindowFlags
				imgui.SetNextWindowPos(imgui.ImVec2(TD_X, TD_Y), imgui.Cond.Always, imgui.ImVec2(0.5, 0))
				imgui.Begin('##hexedtpmtag', nil, wf.NoTitleBar + wf.NoResize + wf.NoScrollbar + wf.NoBackground + wf.NoInputs + wf.AlwaysAutoResize)
				imgui.SetWindowFontScale(TD_SIZE * DPI)
				imgui.TextColored(imgui.ImVec4(0.24, 0.9, 0.39, 1), 'TPM: ON')
				imgui.End()
			end)
		end)
	end
end

function sampev.onInitGame(playerId)
	realMyId = playerId
	TPM.onInit(playerId)
end

function sampev.onSetPlayerColor(playerId, color)
	TPM.store(playerId, color)
end

function sampev.onPlayerStreamIn(playerId, team, model, position, rotation, color, fightingStyle)
	if tonumber(color) and tonumber(color) % 4294967296 ~= 0 then TPM.store(playerId, color) end
end

function sampev.onPlayerQuit(playerId, reason)
	playerId = tonumber(playerId)
	if playerId then TPM.evt[playerId] = nil end
end

function sampev.onServerMessage(color, text)
	if TPM.capturing and os.clock() < TPM.captureUntil then
		local ok, isGangLine = pcall(TPM.captureLine, text)
		if ok and isGangLine and TPM.silent then return false end
	end
end

function sampev.onSendGiveDamage(playerId, damage, weapon, bodypart)
	TPM.cnt.dmg = TPM.cnt.dmg + 1
	local blocked = TPM.blocks(playerId)
	TPM.dbg('dmg', 'GiveDamage ' .. TPM.describe(playerId) .. ' blocked=' .. tostring(blocked))
	if blocked then
		TPM.cnt.blocked = TPM.cnt.blocked + 1
		return false
	end
end

function sampev.onSendBulletData(data)
	if type(data) ~= 'table' then return end
	TPM.cnt.bullet = TPM.cnt.bullet + 1
	if tonumber(data.targetType) == 1 then
		local blocked = TPM.blocks(data.targetId)
		TPM.dbg('bullet', 'Bullet type=1 ' .. TPM.describe(data.targetId) .. ' blocked=' .. tostring(blocked))
		if blocked then
			TPM.cnt.blocked = TPM.cnt.blocked + 1
			return false
		end
	else
		TPM.dbg('bullet0', 'Bullet type=' .. tostring(data.targetType) .. ' target=' .. tostring(data.targetId))
	end
end

local function rawOk()
	return raknetBitStreamGetReadOffset and raknetBitStreamSetReadOffset and raknetBitStreamReadInt8 and raknetBitStreamReadInt16 and raknetBitStreamReadBool
end

function TPM.rawBullet(bs)
	if not rawOk() then return true end
	local off = raknetBitStreamGetReadOffset(bs)
	local first = raknetBitStreamReadInt8(bs)
	if first ~= 206 then raknetBitStreamSetReadOffset(bs, off) end
	local ttype = (first == 206) and raknetBitStreamReadInt8(bs) or first
	local tid = raknetBitStreamReadInt16(bs)
	raknetBitStreamSetReadOffset(bs, off)
	TPM.cnt.rawBullet = TPM.cnt.rawBullet + 1
	if tonumber(ttype) == 1 then
		local blocked = TPM.blocks(tid)
		TPM.dbg('rawbullet', 'RawBullet ' .. TPM.describe(tid) .. ' blocked=' .. tostring(blocked))
		if blocked then
			TPM.cnt.blocked = TPM.cnt.blocked + 1
			return false
		end
	end
	return true
end

function TPM.rawDamage(bs)
	if not rawOk() then return true end
	local off = raknetBitStreamGetReadOffset(bs)
	local take = raknetBitStreamReadBool(bs)
	local tid = raknetBitStreamReadInt16(bs)
	raknetBitStreamSetReadOffset(bs, off)
	TPM.cnt.rawRpc = TPM.cnt.rawRpc + 1
	if not take then
		local blocked = TPM.blocks(tid)
		TPM.dbg('rawrpc', 'RawDamage ' .. TPM.describe(tid) .. ' blocked=' .. tostring(blocked))
		if blocked then
			TPM.cnt.blocked = TPM.cnt.blocked + 1
			return false
		end
	end
	return true
end

addEventHandler('onSendPacket', function(id, bs)
	if id == 206 then
		local ok, pass = pcall(TPM.rawBullet, bs)
		if ok and pass == false then return false end
	end
end)

addEventHandler('onSendRpc', function(id, bs)
	if id == 115 then
		local ok, pass = pcall(TPM.rawDamage, bs)
		if ok and pass == false then return false end
	end
end)

function onScriptTerminate(scr, quitGame)
	local mine = scr == thisScript()
	if not mine then
		local ok, same = pcall(function() return scr.id == thisScript().id end)
		mine = ok and same
	end
	if mine then TPM.unpublish() end
end

function main()
	if not isSampLoaded() or not isSampfuncsLoaded() then return end
	while not isSampAvailable() do wait(0) end

	sampAddChatMessage('{ff0000}[INFO] {ffffff}Hexed TPM ' .. thisScript().version .. ' - always ON  |  /members gang sync (also automatic), /tpms scan, /tpml list', -1)
	sampRegisterChatCommand('members', function(arg)
		if tostring(arg or ''):lower():find('clear') then TPM.req = 'clear' else TPM.req = 'members' end
	end)
	sampRegisterChatCommand('tpmd', function() TPM.req = 'debug' end)
	sampRegisterChatCommand('tpms', function() TPM.req = 'scan' end)
	sampRegisterChatCommand('tpml', function() TPM.req = 'list' end)

	TPM.loadRoster()
	TPM.nextAuto = os.clock() + 10
	TPM.showUntil = os.clock() + TD_SECONDS
	TPM.nextTick, TPM.nextPublish = 0, 0
	pcall(TPM.tick, true)
	pcall(TPM.publish, true)

	while true do
		wait(100)
		local req = TPM.req
		if req then
			TPM.req = nil
			if req == 'members' then pcall(TPM.startMembers, false)
			elseif req == 'clear' then pcall(TPM.clearRoster)
			elseif req == 'debug' then
				TPM.debug = not TPM.debug
				sampAddChatMessage(TPM.debug and '{ffaa00}[TPM] Debug ON - shoot a teammate and read the lines' or '{ffaa00}[TPM] Debug OFF', -1)
			elseif req == 'scan' then pcall(TPM.chatScan)
			elseif req == 'list' then pcall(TPM.chatList) end
		end
		if TPM.capturing and os.clock() >= TPM.captureUntil then pcall(TPM.finishMembers) end
		if TPM.AUTO_SYNC > 0 and not TPM.capturing and os.clock() >= TPM.nextAuto and getMyPoolId() then
			local busy = false
			if sampIsChatInputActive then pcall(function() busy = busy or sampIsChatInputActive() end) end
			if sampIsDialogActive then pcall(function() busy = busy or sampIsDialogActive() end) end
			if not busy then
				TPM.nextAuto = os.clock() + TPM.AUTO_SYNC
				pcall(TPM.startMembers, true)
			end
		end
		pcall(TPM.tick)
		pcall(TPM.publish)
		if imgui and not IS_AL then pcall(function() imgui.Process = os.clock() < TPM.showUntil end) end
	end
end
