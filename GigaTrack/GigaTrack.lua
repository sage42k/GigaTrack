-- GigaTrack. A reminder icon that is also the track button. Nothing switches by itself.
--
-- The icon shows the Track spell your target needs, until that track is active, and clicking it
-- casts that track. The icon IS the secure button GigaTrackButton, so a /click macro or a keybind
-- works too. AutoTrackButton and HunterHelperAutoTrackButton are alias buttons that follow the same attributes.
-- While the old AutoTrack add-on is loaded, GigaTrack builds nothing and only imports its settings.
-- A minimap button toggles the reminder and builds the one-key macro. It is a plain frame, never secure.
--
-- Rules this file keeps:
--  * C_Minimap.SetTracking is never called.
--  * Unit queries can return secret values. A secret is only passed to issecretvalue, never
--    compared or indexed. A secret means "unknown", and then nothing is shown.
--  * The button's attributes change only out of combat. In combat the button is marked dirty and
--    is brought up to date on PLAYER_REGEN_ENABLED.
--  * The icon is a secure frame: Show, Hide, EnableMouse, StartMoving and SetPoint are used only
--    out of combat. In combat visibility changes only through SetAlpha, inside pcall. If a client
--    refuses SetAlpha on the secure frame, the change waits for combat end (the 0.5s re-check
--    and PLAYER_REGEN_ENABLED retry it).
--  * Macros are created or edited only out of combat.
--  * No Blizzard global is written, nothing is hooked.
--  * Every handler runs inside xpcall. Errors go to a 20 entry ring in the SavedVariables and are
--    shown by /gigatrack report. Nothing is printed for them.
--  * The 0.5s re-check creates no tables or closures of its own. (GetTrackingInfo returns a
--    table, which belongs to the client.)
--
-- APIs, checked against the forever branch of Gethe/wow-ui-source (Blizzard_APIDocumentationGenerated
-- and Blizzard_FrameXML/SecureTemplates.lua): C_Minimap.GetNumTrackingTypes and GetTrackingInfo
-- (returns name, texture, active, type, subType, spellID), C_Spell.GetSpellTexture, UnitCreatureType
-- (name, id), UnitIsDeadOrGhost, UnitIsPlayer, UnitExists, events UNIT_FLAGS,
-- UNIT_TARGETABLE_CHANGED and MINIMAP_UPDATE_TRACKING, C_AddOns.IsAddOnLoaded. The secure "spell" action accepts a spell ID
-- (tonumber, then CastSpellByID). Macros: GetNumMacros, GetMacroInfo, CreateMacro(name, icon, body,
-- perCharacter), EditMacro(index, name, icon, body), PickupMacro, Constants.MacroConsts (Blizzard_MacroUI).
local addonName = ...

local BUTTON_NAME = "GigaTrackButton"
local ALIAS_NAMES = { "AutoTrackButton", "HunterHelperAutoTrackButton" } -- names macros already use; keep them working
local TICK = 0.5
local TEST_SECONDS = 5
local LOG_SIZE = 20
local FALLBACK_ICON = "Interface\\Icons\\Ability_Tracking"
local MACRO_NAME = "GigaTrack"
local OLD_MACRO_NAME = "AutoTrack" -- updated in place to the new body
local MACRO_ICON = "Ability_Tracking"
local MACRO_BODY = "/click " .. BUTTON_NAME
local PREFIX = "GigaTrack: "

-- The binding label is our own global, set for every class so the key bindings screen reads well.
-- The key bindings screen looks up BINDING_HEADER_<header> from Bindings.xml and shows the raw
-- key when it is missing, so the header label is set here too.
_G["BINDING_NAME_CLICK " .. BUTTON_NAME .. ":LeftButton"] = "Track my target's creature type"
_G.BINDING_HEADER_GigaTrack = "GigaTrack"

local _, class = UnitClass("player")
if class ~= "HUNTER" then return end

local issecret = issecretvalue or function() return false end

local HUMANOID = 19883
-- UnitCreatureType second return: 1 Beast, 2 Dragonkin, 3 Demon, 4 Elemental, 5 Giant, 6 Undead, 7 Humanoid
local TRACK_BY_TYPE = {
	[1] = 1494, [2] = 19879, [3] = 19878, [4] = 19880, [5] = 19882, [6] = 19884, [7] = HUMANOID,
}

local TYPE_NAME = {
	[1494] = "Beast", [19879] = "Dragonkin", [19878] = "Demon", [19880] = "Elemental",
	[19882] = "Giant", [19884] = "Undead", [HUMANOID] = "Humanoid",
}

local DEFAULTS = {
	enabled = true, locked = true, scale = 0.75, point = "CENTER", relPoint = "CENTER", x = 0, y = 0,
	minimap = true, minimapAngle = 225,
}

local db
local driver, icon, tex, border, label, mmButton, mmTex
local buttons = {} -- GigaTrackButton (the icon) and its aliases, always kept identical
local dormant = false -- the old AutoTrack add-on is loaded: build nothing, only import settings
local frameShown, alphaNow = false, 1 -- what the secure icon frame really is
local iconSpell, iconDesat, pendingSpell = nil, false, nil
local dragging = false
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

-- The icon is a secure frame. Out of combat it is shown and hidden. In combat only SetAlpha is
-- used, and only on a frame that is already shown. If SetAlpha is refused, or the frame is hidden
-- and would have to be shown, nothing changes until combat ends: refresh runs again then.
local function applyVisibility(want)
	if not InCombatLockdown() then
		if frameShown ~= want then
			if want then icon:Show() else icon:Hide() end
			frameShown = want
		end
		if alphaNow ~= 1 and pcall(icon.SetAlpha, icon, 1) then alphaNow = 1 end
		return
	end
	if not frameShown then return end
	local a = want and 1 or 0
	if alphaNow ~= a and pcall(icon.SetAlpha, icon, a) then alphaNow = a end
end

-- The icon always shows what a click will cast. `pending` is a different track the target needs
-- but that cannot be set until combat ends: then the icon keeps the current spell, desaturated.
local function showIcon(spell, pending)
	if iconSpell ~= spell then
		iconSpell = spell
		tex:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell)) or FALLBACK_ICON)
	end
	local desat = pending ~= nil
	if iconDesat ~= desat then iconDesat = desat; tex:SetDesaturated(desat) end
	pendingSpell = pending
	applyVisibility(true)
end

local function hideIcon()
	pendingSpell = nil
	applyVisibility(false)
end

-- Border and label are regions of the icon, not the secure frame itself. The icon is always
-- clickable and movable (set once at build, out of combat); this only shows the placement aids.
local function applyLock()
	local unlocked = not db.locked
	border:SetShown(unlocked)
	label:SetShown(unlocked)
end

local function applyPlacement()
	icon:SetScale(db.scale)
	icon:ClearAllPoints()
	icon:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
end

-- ------------------------------------------------------------ minimap button --

local function mmRadius()
	return ((Minimap and Minimap:GetWidth()) or 140) / 2 + 5
end

local function applyMinimapPosition()
	if not mmButton then return end
	local r, a = mmRadius(), math.rad(db.minimapAngle)
	mmButton:ClearAllPoints()
	mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function applyMinimapLook()
	if not mmButton then return end
	mmButton:SetAlpha(db.enabled and 1 or 0.4)
	mmTex:SetDesaturated(not db.enabled)
	mmButton:SetShown(db.minimap)
end

-- ----------------------------------------------------------------- refresh --

local function refresh()
	if testUntil and GetTime() >= testUntil then testUntil = nil end
	local spell, active = needed()
	if db.enabled and spell and not active then
		if InCombatLockdown() and spell ~= appliedSpell then
			-- The button cannot change now. Show what it will cast, or nothing if it will cast nothing.
			if appliedSpell then showIcon(appliedSpell, spell) else hideIcon() end
		else
			showIcon(spell, nil)
		end
	elseif testUntil or not db.locked then
		showIcon(spell or HUMANOID, nil) -- placement aid
	else
		hideIcon()
	end
	-- Never leave a spell on the button when it is already the active track:
	-- recasting an active Track spell may toggle it off on some clients.
	syncButton((spell and not active) and spell or nil)
end

-- ------------------------------------------------------------------- macro --

-- Finds a macro by name among account macros (1..) and character macros (after the account block).
local function findNamed(name)
	local numAccount, numChar = GetNumMacros()
	local base = (Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS) or 120
	for i = 1, numAccount do
		if GetMacroInfo(i) == name then return i end
	end
	for i = base + 1, base + numChar do
		if GetMacroInfo(i) == name then return i end
	end
end

-- Our macro first, then the old "AutoTrack" one, which is renamed and rewritten instead of duplicated.
local function findMacro()
	return findNamed(MACRO_NAME) or findNamed(OLD_MACRO_NAME)
end

local function makeMacro()
	if InCombatLockdown() then
		say("macros can't be made during combat. Try again after combat, it will work then.")
		return false
	end
	local index = findMacro()
	if index then
		local ok, res = pcall(EditMacro, index, MACRO_NAME, MACRO_ICON, MACRO_BODY)
		if not ok then say("could not update the macro: " .. tostring(res)); return false end
		index = res or index
	else
		local _, numChar = GetNumMacros()
		local max = (Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_CHARACTER_MACROS) or 30
		if numChar >= max then
			say("your character macro slots are full (" .. numChar .. " of " .. max .. "). Delete a macro, then try again.")
			return false
		end
		local ok, res = pcall(CreateMacro, MACRO_NAME, MACRO_ICON, MACRO_BODY, true)
		if not ok or not res then say("could not create the macro: " .. tostring(res)); return false end
		index = res
	end
	local ok = pcall(PickupMacro, index)
	if ok then
		say("GigaTrack macro is on your cursor, drop it on your action bar.")
	else
		say("GigaTrack macro is made. Open /macro and drag it to your action bar.")
	end
	return true
end

local function setLocked(locked)
	db.locked = locked
	applyLock()
	say(locked and "locked" or "unlocked, drag the icon, then /gigatrack lock")
	refresh()
end

local function setMinimap(show)
	db.minimap = show
	applyMinimapLook()
	say(show and "minimap button shown" or "minimap button hidden, /gigatrack minimap shows it again")
end

local function setEnabled(on)
	db.enabled = on
	applyMinimapLook()
	say("reminder " .. (on and "on" or "off"))
	refresh()
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
	say("/gigatrack on | off  reminder icon")
	say("/gigatrack macro  make the one-key track macro")
	say("/gigatrack minimap  show or hide the minimap button")
	say("/gigatrack unlock | lock  move the icon (shift+drag also moves it)")
	say("/gigatrack scale 0.5-2")
	say("/gigatrack test  show the icon for " .. TEST_SECONDS .. " seconds")
	say("/gigatrack report  recent errors")
	say("/gigatrack reset  reset position and the error log")
	say("Macro: /click " .. BUTTON_NAME)
end

local function resetLog()
	db.log, db.logPos = {}, 0
end

local function slash(msg)
	local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	arg = arg:lower()
	if cmd == "on" or cmd == "off" then
		setEnabled(cmd == "on"); return
	elseif cmd == "macro" then
		makeMacro(); return
	elseif cmd == "minimap" then
		if arg == "on" or arg == "show" then setMinimap(true)
		elseif arg == "off" or arg == "hide" then setMinimap(false)
		else setMinimap(not db.minimap) end
		return
	elseif cmd == "unlock" then
		setLocked(false); return
	elseif cmd == "lock" then
		setLocked(true); return
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
		db.minimapAngle = DEFAULTS.minimapAngle
		resetLog(); applyPlacement(); applyMinimapPosition(); say("position and log reset")
	else
		help(); return
	end
	refresh()
end

-- -------------------------------------------------------------------- setup --

local function tooltipFor(self)
	if not GameTooltip then return end
	if alphaNow == 0 then return end -- hidden by alpha in combat
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local name = appliedSpell and TYPE_NAME[appliedSpell]
	if pendingSpell then
		GameTooltip:SetText("Can change after combat: " .. TYPE_NAME[pendingSpell])
	else
		GameTooltip:SetText(name and ("Click to track " .. name) or "Nothing to track")
	end
	GameTooltip:AddLine(db.locked and "Shift+drag to move" or "Drag to move. /gigatrack lock when done.")
	GameTooltip:Show()
end

local function build()
	-- The icon is the secure button. It never moves, shows or hides in combat except by alpha.
	icon = _G[BUTTON_NAME] or CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
	icon:SetSize(48, 48)
	icon:SetFrameStrata("HIGH")
	icon:SetClampedToScreen(true)
	icon:SetMovable(true)
	icon:EnableMouse(true)
	icon:RegisterForDrag("LeftButton")
	-- One click is one cast: act on the up half only, and say so with useOnKeyDown = false,
	-- which SecureActionButton_ShouldUseOnKeyDown reads before it falls back to the CVar.
	icon:RegisterForClicks("AnyUp")
	icon:SetAttribute("useOnKeyDown", false)
	border = icon:CreateTexture(nil, "BACKGROUND")
	border:SetColorTexture(0.2, 1, 0.2, 0.9)
	border:SetPoint("TOPLEFT", -3, 3)
	border:SetPoint("BOTTOMRIGHT", 3, -3)
	tex = icon:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	label = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("TOP", icon, "BOTTOM", 0, -4)
	label:SetText("drag me")
	icon:Hide()
	frameShown = false

	-- Moving is out of combat only. Unlocked: plain drag. Always: shift+drag.
	icon:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		if db.locked and not (IsShiftKeyDown and IsShiftKeyDown()) then return end
		dragging = true
		self:StartMoving()
	end)
	icon:SetScript("OnDragStop", function(self)
		if not dragging then return end
		dragging = false
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		if point then db.point, db.relPoint, db.x, db.y = point, relPoint, x, y end
	end)
	icon:SetScript("OnEnter", tooltipFor)
	icon:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

	-- The old names stay separate secure buttons that follow the same attributes.
	buttons[1] = icon
	for _, name in ipairs(ALIAS_NAMES) do
		local alias = _G[name] or CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
		alias:RegisterForClicks("AnyUp")
		alias:SetAttribute("useOnKeyDown", false)
		buttons[#buttons + 1] = alias
	end
end

local function buildMinimap()
	if not Minimap then return end
	-- A plain Button on the Minimap: not secure, never touches a protected frame.
	mmButton = CreateFrame("Button", "GigaTrackMinimapButton", Minimap)
	mmButton:SetSize(31, 31)
	mmButton:SetFrameStrata("MEDIUM")
	mmButton:SetFrameLevel(8)
	mmButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	mmButton:RegisterForDrag("LeftButton")
	mmTex = mmButton:CreateTexture(nil, "ARTWORK")
	mmTex:SetTexture(FALLBACK_ICON)
	mmTex:SetSize(20, 20)
	mmTex:SetPoint("CENTER", 0, 0)
	mmTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local ring = mmButton:CreateTexture(nil, "OVERLAY")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	ring:SetSize(54, 54)
	ring:SetPoint("TOPLEFT", 0, 0)
	mmButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	mmButton:SetScript("OnClick", function(self, btn)
		guard(function()
			if btn == "RightButton" then setLocked(not db.locked)
			else setEnabled(not db.enabled) end
		end)
	end)
	mmButton:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local cx, cy = Minimap:GetCenter()
			local mx, my = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale() or 1
			if not (cx and cy and mx and my) then return end
			local atan = math.atan2 or math.atan
			db.minimapAngle = math.deg(atan(my / scale - cy, mx / scale - cx)) % 360
			applyMinimapPosition()
		end)
	end)
	mmButton:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	mmButton:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("GigaTrack: reminder " .. (db.enabled and "on" or "off"))
		GameTooltip:AddLine("Left click: reminder on/off")
		GameTooltip:AddLine("Right click: lock/unlock icon")
		GameTooltip:Show()
	end)
	mmButton:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	applyMinimapPosition()
	applyMinimapLook()
end

-- Saved data. GigaTrackDB is ours. Values from AutoTrackDB (the old add-on) are copied in once, when
-- that variable is present, and the `migrated` flag makes this safe to run any number of times. Only
-- the keys this add-on uses are kept and wrong typed values fall back to defaults. AutoTrackDB is only
-- readable while the old AutoTrack folder is installed, so PLAYER_LOGIN tries again. It is never written.
local KEEP = { log = true, logPos = true, migrated = true }
local function migrate()
	for k in pairs(DEFAULTS) do KEEP[k] = true end
	for k in pairs(db) do
		if not KEEP[k] then db[k] = nil end
	end
	for k, v in pairs(DEFAULTS) do
		if type(db[k]) ~= type(v) then db[k] = v end
	end
	local old = AutoTrackDB
	if not db.migrated and type(old) == "table" then
		for k, v in pairs(DEFAULTS) do
			if type(old[k]) == type(v) then db[k] = old[k] end
		end
		db.migrated = true
	end
end

local function addonLoaded(name)
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	return isLoaded and isLoaded(name) or false
end

local OLD_LINE = "the old AutoTrack add-on is also loaded, so GigaTrack stays hidden this launch. Remove the AutoTrack folder from your AddOns folder after this launch."

local function init()
	GigaTrackDB = GigaTrackDB or {}
	db = GigaTrackDB
	migrate()
	if type(db.log) ~= "table" or type(db.logPos) ~= "number" then resetLog() end
	for _, e in ipairs(pending) do
		db.logPos = db.logPos % LOG_SIZE + 1
		db.log[db.logPos] = e
	end
	pending = {}
	driver:RegisterEvent("PLAYER_LOGIN")
	_G["SLASH_GIGATRACK1"] = "/gigatrack"
	if addonLoaded("AutoTrack") then
		-- Both add-ons would show an icon. Import the settings, build nothing, ask for the folder to go.
		dormant = true
		SlashCmdList["GIGATRACK"] = function() say(OLD_LINE) end
		return
	end
	build()
	applyPlacement()
	applyLock()
	buildMinimap()
	SlashCmdList["GIGATRACK"] = function(msg) guard(function() slash(msg) end) end
	_G["SLASH_GIGATRACK2"] = "/autotrack"
	driver:RegisterEvent("PLAYER_TARGET_CHANGED")
	driver:RegisterEvent("PLAYER_REGEN_ENABLED")
	driver:RegisterEvent("MINIMAP_UPDATE_TRACKING")
	driver:RegisterEvent("SPELLS_CHANGED")
	driver:RegisterEvent("PLAYER_ENTERING_WORLD")
	driver:RegisterUnitEvent("UNIT_FLAGS", "target")
	driver:RegisterUnitEvent("UNIT_TARGETABLE_CHANGED", "target")
	refresh()
end

local function adviseOldAddon()
	if dormant then say(OLD_LINE); return end
	if addonLoaded("HunterHelper") or addonLoaded("HunterHelper_AutoTrack") then
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
			-- AutoTrackDB can arrive after ours: try the import again once everything is loaded.
			if not db.migrated and type(AutoTrackDB) == "table" then
				migrate()
				if not dormant then applyPlacement(); applyLock(); applyMinimapPosition(); applyMinimapLook(); refresh() end
			end
			adviseOldAddon()
		end)
	elseif db and not dormant then
		curEvent, curArg1 = event, a1
		guard(dispatch)
	end
end)
driver:SetScript("OnUpdate", function(_, elapsed)
	if not db or dormant then return end
	acc = acc + elapsed
	if acc < TICK then return end
	acc = 0
	guard(tick)
end)
