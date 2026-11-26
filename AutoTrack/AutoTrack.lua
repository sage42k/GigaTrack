-- AutoTrack. A reminder icon plus a one press button. Nothing switches by itself.
--
-- The icon shows the Track spell your target needs, until that track is active. The secure button
-- AutoTrackButton casts it when you press your macro or keybind. HunterHelperAutoTrackButton is a legacy alias with identical behaviour.
--
-- Rules this file keeps:
--  * C_Minimap.SetTracking is never called.
--  * Unit queries can return secret values. A secret is only passed to issecretvalue, never
--    compared or indexed. A secret means "unknown", and then nothing is shown.
--  * The button's attributes change only out of combat. In combat the button is marked dirty and
--    is brought up to date on PLAYER_REGEN_ENABLED. The icon is plain display and always updates.
--  * No Blizzard global is written, nothing is hooked.
--  * Every handler runs inside xpcall. Errors go to a 20 entry ring in the SavedVariables and are
--    shown by /autotrack report. Nothing is printed for them.
--  * The 0.5s re-check creates no tables or closures of its own. (GetTrackingInfo returns a
--    table, which belongs to the client.)
--
-- APIs, checked against the forever branch of Gethe/wow-ui-source (Blizzard_APIDocumentationGenerated
-- and Blizzard_FrameXML/SecureTemplates.lua): C_Minimap.GetNumTrackingTypes and GetTrackingInfo
-- (returns name, texture, active, type, subType, spellID), C_Spell.GetSpellTexture, UnitCreatureType
-- (name, id), UnitIsDeadOrGhost, UnitIsPlayer, UnitExists, events UNIT_FLAGS,
-- UNIT_TARGETABLE_CHANGED and MINIMAP_UPDATE_TRACKING, C_AddOns.IsAddOnLoaded, animation Alpha with
-- SetLooping("BOUNCE"), EnableMouseMotion. The secure "spell" action accepts a spell ID
-- (tonumber, then CastSpellByID).
local addonName = ...

local BUTTON_NAME = "AutoTrackButton"
local LEGACY_BUTTON_NAME = "HunterHelperAutoTrackButton" -- the macro first handed out; keep it working
local TICK = 0.5
local TEST_SECONDS = 5
local LOG_SIZE = 20
local FALLBACK_ICON = "Interface\\Icons\\Ability_Tracking"
local TOOLTIP = "Not tracking your target. Press your AutoTrack macro."
local PREFIX = "AutoTrack: "

-- Binding labels are our own globals, set for every class so the key bindings screen reads well.
_G["BINDING_HEADER_AUTOTRACK"] = "AutoTrack"
_G["BINDING_NAME_CLICK " .. BUTTON_NAME .. ":LeftButton"] = "Track my target's type"

local _, class = UnitClass("player")
if class ~= "HUNTER" then return end

local issecret = issecretvalue or function() return false end

local HUMANOID = 19883
-- UnitCreatureType second return: 1 Beast, 2 Dragonkin, 3 Demon, 4 Elemental, 5 Giant, 6 Undead, 7 Humanoid
local TRACK_BY_TYPE = {
	[1] = 1494, [2] = 19879, [3] = 19878, [4] = 19880, [5] = 19882, [6] = 19884, [7] = HUMANOID,
}

local DEFAULTS = { enabled = true, locked = true, scale = 1, point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }

local db
local driver, icon, tex, border, label, pulseGroup
local buttons = {} -- AutoTrackButton and its legacy alias, always kept identical
local iconShown, iconSpell, pulsing = false, nil, false
local appliedSpell = false -- what the button holds; false means never applied
local dirty = false
local testUntil
local acc = 0
local curEvent, curArg1

-- ------------------------------------------------------------------- log --

local pending = {} -- errors from before the SavedVariables exist
local STAMP = 10   -- entries read "HH:MM:SS message", the message starts at 10
local function logError(err)
	local msg = tostring(err)
	local entry = (date and date("%H:%M:%S") or "--:--:--") .. " " .. msg
	if not db then
		if #pending < LOG_SIZE then pending[#pending + 1] = entry end
		return err
	end
	local newest = db.log[db.logPos]
	if newest and newest:sub(STAMP) == msg then return err end -- same error again, keep one
	db.logPos = db.logPos % LOG_SIZE + 1
	db.log[db.logPos] = entry
	return err
end

local function guard(fn)
	return xpcall(fn, logError)
end

local function say(msg) print(PREFIX .. msg) end

-- ----------------------------------------------------------- tracking state --

local idxCache = {}

-- learned (bool), active (bool). A secret reading counts as not learned: show nothing.
local function trackState(spell)
	if not (C_Minimap and C_Minimap.GetTrackingInfo and C_Minimap.GetNumTrackingTypes) then return false, false end
	local i = idxCache[spell]
	if i then
		local info = C_Minimap.GetTrackingInfo(i)
		if type(info) == "table" then
			local sid, act = info.spellID, info.active
			if issecret(sid) or issecret(act) then return false, false end
			if sid == spell then return true, act == true end
		end
		idxCache[spell] = nil
	end
	for n = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(n)
		if type(info) == "table" then
			local sid, act = info.spellID, info.active
			if issecret(sid) or issecret(act) then return false, false end
			if sid == spell then
				idxCache[spell] = n
				return true, act == true
			end
		end
	end
	return false, false
end

-- The needed track spell and whether it is already active. nil means nothing is needed.
local function needed()
	local exists = UnitExists("target")
	if issecret(exists) or not exists then return nil end
	local dead = UnitIsDeadOrGhost("target")
	if issecret(dead) or dead then return nil end
	local isPlayer = UnitIsPlayer("target")
	if issecret(isPlayer) then return nil end
	local spell
	if isPlayer then
		spell = HUMANOID
	else
		local _, id = UnitCreatureType("target")
		if issecret(id) or type(id) ~= "number" then return nil end
		spell = TRACK_BY_TYPE[id]
	end
	if not spell then return nil end
	local learned, active = trackState(spell)
	if not learned then return nil end
	return spell, active
end

-- ------------------------------------------------------------------ button --

local function applyButton(spell)
	for _, b in ipairs(buttons) do
		b:SetAttribute("type", "spell")
		b:SetAttribute("spell", spell) -- nil clears it, and then the button does nothing
	end
	appliedSpell = spell or false
	dirty = false
end

local function syncButton(spell)
	local want = spell or false
	if want == appliedSpell then dirty = false; return end
	if InCombatLockdown() then dirty = true; return end
	applyButton(spell)
end

-- -------------------------------------------------------------------- icon --

local function reducedMotion()
	local ok, v = pcall(GetCVarBool, "reduceMotion")
	return ok and v and true or false
end

local function setPulse(on)
	if on and reducedMotion() then on = false end
	if on and not pulsing then
		pulseGroup:Play(); pulsing = true
	elseif not on and pulsing then
		pulseGroup:Stop(); icon:SetAlpha(1); pulsing = false
	end
end

local function showIcon(spell, pulse)
	if iconSpell ~= spell then
		iconSpell = spell
		tex:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell)) or FALLBACK_ICON)
	end
	if not iconShown then icon:Show(); iconShown = true end
	setPulse(pulse)
end

local function hideIcon()
	setPulse(false)
	if iconShown then icon:Hide(); iconShown = false end
end

local function applyLock()
	local unlocked = not db.locked
	border:SetShown(unlocked)
	label:SetShown(unlocked)
	icon:EnableMouse(unlocked)
	icon:EnableMouseMotion(true) -- hover for the tooltip without catching clicks
	icon:SetMovable(unlocked)
end

local function applyPlacement()
	icon:SetScale(db.scale)
	icon:ClearAllPoints()
	icon:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
end

-- ----------------------------------------------------------------- refresh --

local function refresh()
	if testUntil and GetTime() >= testUntil then testUntil = nil end
	local spell, active = needed()
	if db.enabled and spell and not active then
		showIcon(spell, true)
	elseif testUntil or not db.locked then
		showIcon(spell or HUMANOID, false) -- placement aid, steady
	else
		hideIcon()
	end
	-- Never leave a spell on the button when it is already the active track:
	-- recasting an active Track spell may toggle it off on some clients.
	syncButton((spell and not active) and spell or nil)
end

-- ---------------------------------------------------------------- handlers --

local handlers = {}
local function onChange() refresh() end
handlers.PLAYER_TARGET_CHANGED = onChange
handlers.UNIT_FLAGS = onChange
handlers.UNIT_TARGETABLE_CHANGED = onChange
handlers.PLAYER_REGEN_ENABLED = onChange
handlers.MINIMAP_UPDATE_TRACKING = function() idxCache = {}; refresh() end
handlers.SPELLS_CHANGED = handlers.MINIMAP_UPDATE_TRACKING
handlers.PLAYER_ENTERING_WORLD = handlers.MINIMAP_UPDATE_TRACKING

local function dispatch()
	local h = handlers[curEvent]
	if h then h(curArg1) end
end

local function tick() refresh() end

-- ------------------------------------------------------------------- slash --

local function help()
	say("/autotrack on | off  reminder icon")
	say("/autotrack unlock | lock  move the icon")
	say("/autotrack scale 0.5-2")
	say("/autotrack test  show the icon for " .. TEST_SECONDS .. " seconds")
	say("/autotrack report  recent errors")
	say("/autotrack reset  reset position and the error log")
	say("Macro: /click " .. BUTTON_NAME)
end

local function resetLog()
	db.log, db.logPos = {}, 0
end

local function slash(msg)
	local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "on" or cmd == "off" then
		db.enabled = (cmd == "on")
		say("reminder " .. cmd)
	elseif cmd == "unlock" then
		db.locked = false; applyLock(); say("unlocked, drag the icon, then /autotrack lock")
	elseif cmd == "lock" then
		db.locked = true; applyLock(); say("locked")
	elseif cmd == "scale" then
		local s = tonumber(arg)
		if not s or s < 0.5 or s > 2 then say("scale takes a number from 0.5 to 2"); return end
		db.scale = s; applyPlacement(); say("scale " .. s)
	elseif cmd == "test" then
		testUntil = GetTime() + TEST_SECONDS
		say("showing the icon for " .. TEST_SECONDS .. " seconds")
	elseif cmd == "report" then
		local n = 0
		for k = 1, LOG_SIZE do
			local e = db.log[(db.logPos + k - 1) % LOG_SIZE + 1]
			if e then n = n + 1; say(e) end
		end
		if n == 0 then say("no errors recorded") end
	elseif cmd == "reset" then
		db.point, db.relPoint, db.x, db.y = DEFAULTS.point, DEFAULTS.relPoint, DEFAULTS.x, DEFAULTS.y
		resetLog(); applyPlacement(); say("position and log reset")
	else
		help(); return
	end
	refresh()
end

-- -------------------------------------------------------------------- setup --

local function build()
	icon = CreateFrame("Frame", "AutoTrackIcon", UIParent)
	icon:SetSize(48, 48)
	icon:SetFrameStrata("HIGH")
	icon:SetClampedToScreen(true)
	icon:RegisterForDrag("LeftButton")
	border = icon:CreateTexture(nil, "BACKGROUND")
	border:SetColorTexture(0.2, 1, 0.2, 0.9)
	border:SetPoint("TOPLEFT", -3, 3)
	border:SetPoint("BOTTOMRIGHT", 3, -3)
	tex = icon:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	label = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("TOP", icon, "BOTTOM", 0, -4)
	label:SetText("drag me")
	pulseGroup = icon:CreateAnimationGroup()
	pulseGroup:SetLooping("BOUNCE")
	local a = pulseGroup:CreateAnimation("Alpha")
	a:SetFromAlpha(1); a:SetToAlpha(0.45); a:SetDuration(0.7); a:SetSmoothing("IN_OUT")
	icon:Hide()

	icon:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
	icon:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		if point then db.point, db.relPoint, db.x, db.y = point, relPoint, x, y end
	end)
	icon:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(db.locked and TOOLTIP or "Drag to move. /autotrack lock when done.")
		GameTooltip:Show()
	end)
	icon:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

	for _, name in ipairs({ BUTTON_NAME, LEGACY_BUTTON_NAME }) do
		local b = _G[name] or CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
		-- One key press is one cast: act on the up half only, and say so with useOnKeyDown = false,
		-- which SecureActionButton_ShouldUseOnKeyDown reads before it falls back to the CVar.
		b:RegisterForClicks("AnyUp")
		b:SetAttribute("useOnKeyDown", false)
		buttons[#buttons + 1] = b
	end
end

-- Saved data. AutoTrackDB may hold keys from AutoTrack 0.1.x (enabled, scope, default, version):
-- only the keys this add-on uses are kept, so scope, default and version go. Values from the
-- HunterHelper_AutoTrackDB of AutoTrack 0.3.0 are copied in once, when that variable is present,
-- and win over the older ones. The `migrated` flag makes this safe to run any number of times.
local KEEP = { log = true, logPos = true, migrated = true }
local function migrate()
	for k in pairs(DEFAULTS) do KEEP[k] = true end
	for k in pairs(db) do
		if not KEEP[k] then db[k] = nil end
	end
	for k, v in pairs(DEFAULTS) do
		if type(db[k]) ~= type(v) then db[k] = v end
	end
	local old = HunterHelper_AutoTrackDB
	if not db.migrated and type(old) == "table" then
		for k, v in pairs(DEFAULTS) do
			if type(old[k]) == type(v) then db[k] = old[k] end
		end
		db.migrated = true
	end
end

local function init()
	AutoTrackDB = AutoTrackDB or {}
	db = AutoTrackDB
	migrate()
	if type(db.log) ~= "table" or type(db.logPos) ~= "number" then resetLog() end
	for _, e in ipairs(pending) do
		db.logPos = db.logPos % LOG_SIZE + 1
		db.log[db.logPos] = e
	end
	pending = {}
	build()
	applyPlacement()
	applyLock()
	SlashCmdList["AUTOTRACK"] = function(msg) guard(function() slash(msg) end) end
	_G["SLASH_AUTOTRACK1"] = "/autotrack"
	driver:RegisterEvent("PLAYER_TARGET_CHANGED")
	driver:RegisterEvent("PLAYER_REGEN_ENABLED")
	driver:RegisterEvent("MINIMAP_UPDATE_TRACKING")
	driver:RegisterEvent("SPELLS_CHANGED")
	driver:RegisterEvent("PLAYER_ENTERING_WORLD")
	driver:RegisterUnitEvent("UNIT_FLAGS", "target")
	driver:RegisterUnitEvent("UNIT_TARGETABLE_CHANGED", "target")
	driver:RegisterEvent("PLAYER_LOGIN")
	refresh()
end

local function adviseOldAddon()
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	if isLoaded and (isLoaded("HunterHelper") or isLoaded("HunterHelper_AutoTrack")) then
		say("an older version of this add-on is also loaded. Please remove the HunterHelper and HunterHelper_AutoTrack folders from your AddOns folder.")
	end
end

driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:SetScript("OnEvent", function(_, event, a1)
	if event == "ADDON_LOADED" then
		if a1 ~= addonName then return end
		driver:UnregisterEvent("ADDON_LOADED")
		guard(init)
	elseif event == "PLAYER_LOGIN" then
		driver:UnregisterEvent("PLAYER_LOGIN")
		guard(function()
			-- The old add-on's variable can arrive after ours: try the import again once everything is loaded.
			if not db.migrated and type(HunterHelper_AutoTrackDB) == "table" then
				migrate(); applyPlacement(); applyLock(); refresh()
			end
			adviseOldAddon()
		end)
	elseif db then
		curEvent, curArg1 = event, a1
		guard(dispatch)
	end
end)
driver:SetScript("OnUpdate", function(_, elapsed)
	if not db then return end
	acc = acc + elapsed
	if acc < TICK then return end
	acc = 0
	guard(tick)
end)
