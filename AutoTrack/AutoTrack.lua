-- AutoTrack: hunters only. Switches minimap tracking to the track that matches
-- the creature type of your target.
--
-- Rules this file keeps:
--  * UnitCreatureType can return a secret value. A secret is never compared,
--    indexed or used in arithmetic here; if one shows up we do nothing.
--  * No Blizzard-owned global is written (the slash command only adds its own
--    key to SlashCmdList) and nothing is hooked.
--  * C_Minimap.SetTracking is called untainted, outside combat lockdown. If it
--    does not take effect, or the client reports it blocked or forbidden for
--    this addon, we fall back to a secure button the player keybinds. Its
--    "spell" attribute is only ever changed out of combat.
local ADDON, ns = ...
ns = ns or {}

local issecret = issecretvalue or function() return false end

-- Creature type IDs, as returned second by UnitCreatureType. Locale safe.
local TYPE_BY_ID = {
	[1] = "BEAST", [2] = "DRAGONKIN", [3] = "DEMON", [4] = "ELEMENTAL",
	[5] = "GIANT", [6] = "UNDEAD", [7] = "HUMANOID",
}
-- English names, used only when the client gives no usable ID. Not locale safe.
local TYPE_BY_NAME = {
	Beast = "BEAST", Dragonkin = "DRAGONKIN", Demon = "DEMON", Elemental = "ELEMENTAL",
	Giant = "GIANT", Undead = "UNDEAD", Humanoid = "HUMANOID",
}
-- Hunter tracking spell per type. Matched against GetTrackingInfo(i).spellID,
-- with the localised spell name as a second chance.
local TRACK_SPELL = {
	BEAST = 1494, HUMANOID = 19883, UNDEAD = 19884, DEMON = 19878,
	ELEMENTAL = 19880, GIANT = 19882, DRAGONKIN = 19879,
}
local WORDS = {
	beast = "BEAST", beasts = "BEAST", humanoid = "HUMANOID", humanoids = "HUMANOID",
	undead = "UNDEAD", demon = "DEMON", demons = "DEMON", elemental = "ELEMENTAL",
	elementals = "ELEMENTAL", giant = "GIANT", giants = "GIANT", dragonkin = "DRAGONKIN",
}
local LABEL = {
	BEAST = "beasts", HUMANOID = "humanoids", UNDEAD = "undead", DEMON = "demons",
	ELEMENTAL = "elementals", GIANT = "giants", DRAGONKIN = "dragonkin",
}

local DEFAULTS = { enabled = true, scope = "attackable", default = "none" }
local THROTTLE = 1.0 -- seconds between switches
local CONFIRM_TIMEOUT = 3.0 -- seconds to wait for the client to confirm a switch

local db
local mode = "direct"       -- "direct" or "fallback"
local lastSwitch = -1e9
local retryArmed = false
local pending = nil         -- { idx, key } awaiting confirmation
local pendingCombat = false -- a refresh was skipped because of combat lockdown
local button, frame

local function say(msg) print("AutoTrack: " .. msg) end

-- ----------------------------------------------------------------- target --

-- A plain boolean from a unit query, or nil if it is secret.
local function plainBool(v)
	if issecret(v) then return nil end
	return v and true or false
end

local wantedKey

-- The track key to use for the current target, or nil to do nothing.
function wantedKey()
	if plainBool(UnitExists("target")) ~= true then return nil end
	if plainBool(UnitIsPlayer("target")) ~= false then return nil end -- a player, or secret
	if db.scope ~= "any" and plainBool(UnitCanAttack("player", "target")) ~= true then return nil end
	local name, id = UnitCreatureType("target")
	if issecret(name) or issecret(id) then return nil end
	if type(id) == "number" and TYPE_BY_ID[id] then return TYPE_BY_ID[id] end
	if type(name) == "string" and TYPE_BY_NAME[name] then return TYPE_BY_NAME[name] end
	if name == nil and id == nil then return nil end -- no information at all
	-- a creature type with no hunter track (critter, mechanical, ...)
	if db.default ~= "none" and TRACK_SPELL[db.default] then return db.default end
	return nil
end

-- Index and active flag of the learned tracking entry for a key, else nil.
local function findTrack(key)
	local spellID = TRACK_SPELL[key]
	if not spellID or not (C_Minimap and C_Minimap.GetNumTrackingTypes) then return nil end
	local wantName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(i)
		if type(info) == "table" then
			local sid, nm, act = info.spellID, info.name, info.active
			if not (issecret(sid) or issecret(nm) or issecret(act)) then
				if (sid ~= nil and sid == spellID) or (wantName and nm == wantName) then
					return i, act == true
				end
			end
		end
	end
	return nil
end

-- --------------------------------------------------------------- fallback --

local function ensureButton()
	if button then return button end
	button = CreateFrame("Button", "AutoTrackButton", UIParent, "SecureActionButtonTemplate")
	-- The template only acts on the down or the up half of a press, chosen by
	-- the useOnKeyDown attribute. Pin it to up and register only up, so one
	-- key press is one cast whatever the player's key-down setting is.
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("useOnKeyDown", false)
	button:SetAttribute("type", "spell")
	return button
end

local function setButtonSpell(key)
	if InCombatLockdown() then pendingCombat = true; return end
	local spellID = TRACK_SPELL[key]
	local name = spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	if name then ensureButton():SetAttribute("spell", name) end
end

local refresh

local function enterFallback()
	if mode == "fallback" then return end
	mode = "fallback"
	pending = nil
	say("the game needs a keypress to switch tracking. Bind a key in Options, Keybindings, AutoTrack (Hunter).")
	if not InCombatLockdown() then ensureButton() end
	refresh()
end

-- ---------------------------------------------------------------- refresh --

local function isActive(idx)
	local info = C_Minimap.GetTrackingInfo(idx)
	if type(info) ~= "table" then return false end
	local act = info.active
	return not issecret(act) and act == true
end

-- The client confirms a switch with MINIMAP_UPDATE_TRACKING, after a server
-- round trip. Only a long silence counts as failure.
local function confirm()
	if pending and isActive(pending.idx) then pending = nil end
end

local function expect(idx, key)
	local mine = { idx = idx, key = key }
	pending = mine
	C_Timer.After(CONFIRM_TIMEOUT, function()
		if pending ~= mine then return end -- confirmed, or superseded
		if isActive(idx) then pending = nil; return end
		if wantedKey() ~= key then pending = nil; return end -- target moved on
		enterFallback()
	end)
end

local function armRetry(delay)
	if retryArmed then return end
	retryArmed = true
	C_Timer.After(delay, function() retryArmed = false; refresh() end)
end

function refresh()
	if not db or not db.enabled then return end
	local key = wantedKey()
	if not key then return end
	local idx, active = findTrack(key)
	if not idx then return end -- not learned
	if mode == "fallback" then setButtonSpell(key); return end
	if active then return end
	if InCombatLockdown() then pendingCombat = true; return end
	local wait = lastSwitch + THROTTLE - GetTime()
	if wait > 0 then armRetry(wait); return end
	lastSwitch = GetTime()
	C_Minimap.SetTracking(idx, true)
	expect(idx, key)
end

-- ------------------------------------------------------------------ slash --

local function status()
	say(string.format("%s, mode %s, scope %s, default %s",
		db.enabled and "on" or "off", mode, db.scope, db.default == "none" and "none" or LABEL[db.default]))
end

local function slash(msg)
	local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
	if cmd == "on" or cmd == "off" then
		db.enabled = cmd == "on"
		say(cmd)
		if db.enabled then refresh() end
	elseif cmd == "scope" and (arg == "attackable" or arg == "any") then
		db.scope = arg
		say("scope " .. arg)
	elseif cmd == "default" and (arg == "none" or WORDS[arg]) then
		db.default = arg == "none" and "none" or WORDS[arg]
		say("default " .. (arg == "none" and "none" or LABEL[db.default]))
	elseif cmd == "retry" then
		mode = "direct"
		say("mode direct")
	elseif cmd == "" or cmd == "status" then
		status()
	else
		say("/autotrack on|off|status|scope attackable|any|default <beasts|humanoids|undead|demons|elementals|giants|dragonkin|none>|retry")
	end
end

-- ----------------------------------------------------------------- events --

local function onEvent(self, event, a1)
	if event == "ADDON_LOADED" then
		if a1 ~= ADDON then return end
		self:UnregisterEvent("ADDON_LOADED")
		local _, class = UnitClass("player")
		if issecret(class) or class ~= "HUNTER" then return end -- silent for everyone else
		if type(AutoTrackDB) ~= "table" then AutoTrackDB = {} end
		db = AutoTrackDB
		for k, v in pairs(DEFAULTS) do
			if db[k] == nil then db[k] = v end
		end
		db.version = "0.1.0"
		self:RegisterEvent("PLAYER_TARGET_CHANGED")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterEvent("MINIMAP_UPDATE_TRACKING")
		self:RegisterEvent("ADDON_ACTION_BLOCKED")
		self:RegisterEvent("ADDON_ACTION_FORBIDDEN")
		SLASH_AUTOTRACK1 = "/autotrack"
		SlashCmdList["AUTOTRACK"] = slash
	elseif event == "PLAYER_TARGET_CHANGED" then
		refresh()
	elseif event == "MINIMAP_UPDATE_TRACKING" then
		confirm()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingCombat then pendingCombat = false; refresh() end
	elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		if not issecret(a1) and a1 == ADDON then enterFallback() end
	end
end

-- Binding labels (our own names, not Blizzard's).
BINDING_HEADER_AUTOTRACK = "AutoTrack (Hunter)"
_G["BINDING_NAME_CLICK AutoTrackButton:LeftButton"] = "AutoTrack: track my target's type"

frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", onEvent)

ns.AutoTrack = { TYPE_BY_ID = TYPE_BY_ID, TRACK_SPELL = TRACK_SPELL }
