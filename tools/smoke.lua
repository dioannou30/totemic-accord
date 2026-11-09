--[[
	Offline smoke test for Totemic Accord M1.

	Stubs just enough of the WoW API and Ace3 to load our files in Lua 5.1 and drive
	them: OnInitialize, OnEnable, every slash command, and /ta selftest -- as a Shaman
	and as a non-Shaman. Catches nil-indexing and typos that luacheck cannot see.

	Not a substitute for testing in game; it only proves the code runs at all.
	Run from the repo root:  lua5.1 tools/smoke.lua
	Or point it somewhere:   lua5.1 tools/smoke.lua <path to repo>
]]

local repo = (...) or "."
local ADDON = "TotemicAccord"

-- ------------------------------------------------------------------ WoW stubs
local scenario = { class = "SHAMAN", spec = 1, instance = "none", knowsCOE = true }

local output = {}
local realPrint = print
function print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	output[#output + 1] = table.concat(parts, " ")
end

C_AddOns = {
	GetAddOnMetadata = function(_, field)
		local meta = {
			Title = "Totemic Accord",
			Version = "0.1.0",
		}
		return meta[field]
	end,
	GetAddOnInterfaceVersion = function() return 16001 end,
}

C_Spell = {
	GetSpellName = function(id) return NAME_BY_ID and NAME_BY_ID[id] end,
	GetSpellInfo = function(idOrName)
		if idOrName == 66842 then return { name = "Call of the Elements", spellID = 66842 } end
		if idOrName == "Totemic Projection" then
			return { name = "Totemic Projection", spellID = 108287 }
		end
		return nil
	end,
}

function UnitClass() return "Shaman", scenario.class, 7 end
-- What the Forever client reported in game: one Shaman spec, 1489 "Shaman".
function GetNumSpecializations() return 1 end
function IsPlayerInitialSpec() return false end
function GetSpecializationInfoForClassID(_, i) if i == 1 then return 1489, "Shaman" end end
function GetBuildInfo() return "1.60.1", "70862", "Nov 7 2026", 16001 end
function UnitLevel() return 60 end
C_SpecializationInfo = { GetNumSpecializationsForClassID = function() return 1 end }
function C_SpecializationInfo.GetSpecialization() return scenario.spec end
function C_SpecializationInfo.GetSpecializationInfo(i)
	local t = { [1] = { 1489, "Shaman" } }
	local e = t[i]
	if e then return e[1], e[2] end
end
function IsInInstance()
	return scenario.instance ~= "none", scenario.instance
end
function IsPlayerSpell(id) return id == 66842 and scenario.knowsCOE or false end
function IsSpellKnown(id) return IsPlayerSpell(id) end
function GetNumTotemSlots() return 4 end

FIRE_TOTEM_SLOT, EARTH_TOTEM_SLOT, WATER_TOTEM_SLOT, AIR_TOTEM_SLOT = 1, 2, 3, 4
MAX_TOTEMS = 4
TOTEM_MULTI_CAST_SUMMON_SPELLS = { 66842, 66843, 66844 }
TOTEM_MULTI_CAST_RECALL_SPELLS = { 36936 }
SHAMAN_TOTEM_PRIORITIES = { EARTH_TOTEM_SLOT, FIRE_TOTEM_SLOT, WATER_TOTEM_SLOT, AIR_TOTEM_SLOT }

-- A level-18 spellbook: some totems learned, the native bar absent (no multicast),
-- one totem name nothing knows, plus not-yet-learned spells.
scenario.multicast = {}
scenario.inCombat = false
scenario.activeTotem = {}   -- [slot] = spellID currently down
local SPELLBOOK = {
	{ "Stoneskin Totem", 8071 }, { "Earthbind Totem", 2484 }, { "Strength of Earth Totem", 8075 },
	{ "Searing Totem", 3599 }, { "Fire Nova Totem", 1535 },
	{ "Healing Stream Totem", 5394 }, { "Mana Spring Totem", 5675 },
	{ "Grounding Totem", 8177 }, { "Mysterious Forever Totem", 999001 },
	{ "Lightning Bolt", 403 }, { "Totemic Recall", 36936 },
	{ "Searing Totem", 3599 },  -- a second rank entry with the same name
}
local FUTURE = { { "Call of the Elements", 66842, 20 }, { "Totemic Projection", 108287, 30 } }
NAME_BY_ID = {}  -- global on purpose: the C_Spell stub above reads it
for _, e in ipairs(SPELLBOOK) do NAME_BY_ID[e[2]] = e[1] end
for _, e in ipairs(FUTURE) do NAME_BY_ID[e[2]] = e[1] end
NAME_BY_ID[8512] = "Windfury Totem"

Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 }, SpellBookItemType = { Spell = 1, FutureSpell = 2 } }
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 1 end,
	GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #SPELLBOOK + #FUTURE, shouldHide = false } end,
	GetSpellBookItemInfo = function(i)
		local e = SPELLBOOK[i]
		if e then return { name = e[1], actionID = e[2], itemType = 1, isPassive = false } end
		local f = FUTURE[i - #SPELLBOOK]
		return { name = f[1], actionID = f[2], itemType = 2, isPassive = false }
	end,
	GetSpellBookItemLevelLearned = function(i) local f = FUTURE[i - #SPELLBOOK]; return f and f[3] or 0 end,
}
function GetMultiCastTotemSpells(slot) return unpack(scenario.multicast[slot] or {}) end
function GetTotemInfo(slot)
	local id = scenario.activeTotem[slot]
	if id then return true, NAME_BY_ID[id], 0, 120, 0, 1, id end
	return false, "", 0, 0, 0, 1, 0
end
function InCombatLockdown() return scenario.inCombat end
function issecretvalue() return false end
C_Timer = { After = function(_, fn) fn() end }

-- ---- M3: a permissive fake widget. Unknown methods are no-ops; geometry and
-- ---- visibility are recorded so layouts can be asserted.
local function newWidget(name)
	local w = { _name = name, _shown = true, _points = {}, _scale = 1, _level = 1, _scripts = {} }
	local methods = {}
	function methods:GetName() return self._name end
	function methods:SetSize(wd, ht) self._w, self._h = wd, ht end
	function methods:SetWidth(v) self._w = v end
	function methods:SetHeight(v) self._h = v end
	function methods:GetWidth() return self._w end
	function methods:GetHeight() return self._h end
	function methods:ClearAllPoints() self._points = {} end
	function methods:SetPoint(p, rel, rp, x, y)
		if type(rel) == "number" then rel, rp, x, y = nil, p, rel, rp end
		self._points[#self._points + 1] = { p, rel, rp, x or 0, y or 0 }
	end
	function methods:GetPoint(i) local q = self._points[i or 1]; if q then return q[1], q[2], q[3], q[4], q[5] end end
	function methods:SetAllPoints() self._points = { { "ALL" } } end
	function methods:Show() self._shown = true end
	function methods:Hide() self._shown = false end
	function methods:SetShown(v) self._shown = not not v end
	function methods:IsShown() return self._shown end
	function methods:SetScale(v) self._scale = v end
	function methods:GetEffectiveScale() return 1 end
	function methods:GetFrameLevel() return self._level end
	function methods:SetFont() return true end
	function methods:GetFont() return "Fonts\FRIZQT__.TTF", 12, "" end
	function methods:SetText(t) self._text = t end
	function methods:GetText() return self._text end
	function methods:SetTexture(t) self._texture = t end
	function methods:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
	function methods:SetTextColor(r, g, b, a) self._textColor = { r, g, b, a } end
	function methods:SetGradient(...) self._gradient = { ... } end
	function methods:SetScript(k, fn) self._scripts[k] = fn end
	function methods:HookScript(k, fn) self._scripts[k] = fn end
	function methods:SetAttribute(k, v)
		-- Real secure frames refuse this in combat; so does the fake, loudly.
		assert(not scenario.inCombat, "SetAttribute called in combat")
		self._attrs = self._attrs or {}
		self._attrs[k] = v
	end
	function methods:GetAttribute(k) return self._attrs and self._attrs[k] end
	function methods:RegisterForClicks(...) self._clicks = { ... } end
	function methods:CreateTexture() return newWidget() end
	function methods:CreateFontString() return newWidget() end
	-- Only Capitalized names are faked as no-op methods (all WoW widget methods are);
	-- our own fields are lowercase and must read as nil when unset.
	return setmetatable(w, { __index = function(_, k)
		if methods[k] then return methods[k] end
		if type(k) == "string" and k:match("^%u") then return function() end end
	end })
end
UIParent = newWidget("UIParent")
FRAMES = {}
function CreateFrame(_, name, parent)
	local f = newWidget(name)
	f._parent = parent
	if name then FRAMES[name] = f; _G[name] = f end
	return f
end
GameFontNormal, GameFontNormalSmall = newWidget(), newWidget()
GameTooltip = newWidget("GameTooltip")
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
PixelUtil = { GetNearestPixelSize = function(size, _, minPixels)
	if minPixels and size < minPixels then return minPixels end
	return size
end }
scenario.bindings = {}
function GetBindingKey(cmd) return scenario.bindings[cmd] end
C_Spell.GetSpellTexture = function(id) return "icon:" .. tostring(id) end

-- M4: bindings and the confirmation popup
NAME_BY_ID[437009] = "Totemic Projection"
scenario.bindingActions = {}  -- key -> command
scenario.saved = 0
scenario.popup = nil
function SetBinding(key, command)
	assert(not scenario.inCombat, "SetBinding called in combat")
	scenario.bindingActions[key] = command
	scenario.bindings[command] = key
end
function SaveBindings() scenario.saved = scenario.saved + 1 end
function GetCurrentBindingSet() return 1 end
function GetBindingAction(key) return scenario.bindingActions[key] or "" end
function GetBindingText(action) return "Name of " .. action end
function StaticPopup_ShowCustomGenericConfirmation(data) scenario.popup = data end

-- ------------------------------------------------------------------ Ace stubs
local registered = {}
local addonObj

LibStub = setmetatable({
	GetLibrary = function(_, name, silent)
		-- Pretend every library we vendor is present.
		local known = {
			["AceAddon-3.0"] = true, ["AceDB-3.0"] = true, ["AceEvent-3.0"] = true,
			["AceConsole-3.0"] = true, ["AceConfig-3.0"] = true,
			["AceConfigRegistry-3.0"] = true, ["AceConfigDialog-3.0"] = true,
			["AceGUI-3.0"] = true, ["LibSerialize"] = true, ["LibDeflate"] = true,
			["LibDataBroker-1.1"] = true, ["LibDBIcon-1.0"] = true,
		}
		if known[name] then return registered[name] or {} end
		if silent then return nil end
		error("LibStub: missing " .. name)
	end,
}, {
	__call = function(self, name, silent) return self:GetLibrary(name, silent) end,
})

registered["AceAddon-3.0"] = {
	NewAddon = function(_, name, ...)
		local o = { name = name, _enabled = true }
		function o:SetEnabledState(v) self._enabled = v end
		function o:RegisterChatCommand(cmd, handler) self["_cmd_" .. cmd] = handler end
		addonObj = o
		return o
	end,
}

-- A deliberately simple AceDB: scope tables with defaults copied in, which is all
-- our code relies on at M1.
local function deepcopy(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do r[k] = deepcopy(v) end
	return r
end
registered["AceEvent-3.0"] = {
	-- Events are recorded per object (one handler each, like the real AceEvent);
	-- messages go through a shared bus so SendMessage reaches every listener.
	bus = {},
	Embed = function(lib, target)
		target.events = {}
		function target:RegisterEvent(ev, handler) self.events[ev] = handler end
		function target:RegisterMessage(msg, handler)
			lib.bus[msg] = lib.bus[msg] or {}
			lib.bus[msg][self] = handler
		end
		function target:SendMessage(msg, ...)
			for obj, handler in pairs(lib.bus[msg] or {}) do
				if type(handler) == "string" then obj[handler](obj, msg, ...) else handler(msg, ...) end
			end
		end
		return target
	end,
}

registered["AceDB-3.0"] = {
	New = function(_, _, defaults)
		local db = {}
		for scope, values in pairs(defaults or {}) do db[scope] = deepcopy(values) end
		return db
	end,
}

-- ------------------------------------------------------------------ load
local ns = {}
local function loadFile(rel)
	local path = repo .. "/TotemicAccord/" .. rel
	local chunk, err = loadfile(path)
	if not chunk then error("could not load " .. path .. ": " .. tostring(err)) end
	return chunk(ADDON, ns)
end

local failures = 0
local function step(label, fn)
	local ok, err = pcall(fn)
	if ok then
		realPrint(("  PASS  %s"):format(label))
	else
		failures = failures + 1
		realPrint(("  FAIL  %s\n          %s"):format(label, tostring(err)))
	end
end

realPrint("Totemic Accord -- offline smoke test (Lua " .. _VERSION .. ")\n")

realPrint("Shaman, Enhancement, open world:")
step("load Locales/enUS.lua", function() loadFile("Locales/enUS.lua") end)
step("locale fallback returns key for a missing string", function()
	assert(ns.L.NO_SUCH_STRING == "NO_SUCH_STRING", "expected key fallback")
	assert(ns.L.CHAT_PREFIX == "[Totemic Accord]", "wrong chat prefix")
end)
step("load Core.lua", function() loadFile("Core.lua") end)
step("load Data.lua", function() loadFile("Data.lua") end)
for _, f in ipairs({ "Themes.lua", "Keybinds.lua", "Bar.lua" }) do
	step("load " .. f, function() loadFile(f) end)
end
step("load SelfTest.lua", function() loadFile("SelfTest.lua") end)
step("global TotemicAccord was exposed", function()
	assert(_G[ADDON] == ns.addon, "addon not exposed as a global")
end)
step("identity read back from the TOC", function()
	assert(ns.addon.DISPLAY_NAME == "Totemic Accord", "bad display name")
	assert(ns.addon.VERSION == "0.1.0", "bad version")
end)
step("OnInitialize", function() ns.addon:OnInitialize() end)
step("saved-variable defaults present", function()
	local s = ns.addon.db.global.settings
	assert(s.theme == "emerald", "theme default missing")
	assert(s.layout == "horizontal", "layout default missing")
	assert(ns.addon.db.global.version == 1, "version default missing")
	assert(type(ns.addon.db.global.profiles) == "table", "profiles table missing")
end)
step("OnEnable", function() ns.addon:OnEnable() end)
step("/ta (help)", function() ns.addon:OnSlashCommand("") end)
step("/ta debug toggles twice", function()
	ns.addon:OnSlashCommand("debug")
	assert(ns.addon.db.global.settings.debug == true, "debug did not turn on")
	ns.addon:OnSlashCommand("debug")
	assert(ns.addon.db.global.settings.debug == false, "debug did not turn off")
end)
step("/ta selftest", function() ns.addon:OnSlashCommand("selftest") end)
step("every not-yet command answers", function()
	for _, c in ipairs({ "lock", "unlock", "auto", "profile enh:bg", "capture", "macro", "minimap" }) do
		ns.addon:OnSlashCommand(c)
	end
end)
step("unknown command does not error", function() ns.addon:OnSlashCommand("zzzz") end)

-- selftest under other conditions
realPrint("\nSelf-test across situations:")
for _, s in ipairs({
	{ spec = 1, instance = "party" },
	{ spec = 3, instance = "pvp" },
	{ spec = 1, instance = "arena", knowsCOE = false },
}) do
	scenario.spec = s.spec
	scenario.instance = s.instance
	scenario.knowsCOE = s.knowsCOE ~= false
	step(("selftest spec=%d instance=%s coe=%s"):format(s.spec, s.instance,
		tostring(scenario.knowsCOE)), function()
		ns.SelfTest:Run()
	end)
end

-- M2: abbreviations, exactly the examples in build prompt section 6.7
realPrint("\nAbbreviations (build prompt 6.7):")
local D = ns.Data
for _, case in ipairs({
	{ "Strength of Earth Totem", "SE" }, { "Healing Stream Totem", "HS" }, { "Grace of Air Totem", "GA" },
	{ "Searing Totem", "Se" }, { "Tremor Totem", "Tr" }, { "Magma Totem", "Ma" }, { "Grounding Totem", "Gr" },
	{ "Stoneskin Totem", "SS" }, { "Stoneclaw Totem", "SC" }, { "Earthbind Totem", "EB" },
	{ "Windfury Totem", "WF" }, { "Windwall Totem", "WW" }, { "Flametongue Totem", "FT" },
	{ "Frost Resistance Totem", "FrR" }, { "Fire Resistance Totem", "FiR" },
	{ "Totem of Wrath", "Wr" }, { "Wrath of Air Totem", "WA" }, { "Mana Spring Totem", "MS" },
}) do
	step(("%-24s -> %s"):format(case[1], case[2]), function()
		local got = D.Abbreviate(case[1])
		assert(got == case[2], "got " .. tostring(got))
	end)
end

realPrint("\nDiscovery, level 18 (no native bar):")
step("element display order is earth, fire, water, air", function()
	local keys = {}
	for i, e in ipairs(D.ELEMENTS) do keys[i] = e.key end
	assert(table.concat(keys, ",") == "earth,fire,water,air", table.concat(keys, ","))
	assert(D.ELEMENT_BY_KEY.earth.slot == 2 and D.ELEMENT_BY_KEY.fire.slot == 1, "slots not from constants")
end)
step("spellbook totems placed by fallback, non-totems ignored", function()
	D:Discover()
	local earth = {}
	for _, t in ipairs(D:GetTotems("earth")) do earth[#earth + 1] = t.code .. ":" .. t.source end
	assert(table.concat(earth, ",") == "EB:fallback,SS:fallback,SE:fallback", table.concat(earth, ","))
	assert(#D:GetTotems("fire") == 2, "duplicate rank entry not collapsed")
	assert(D:ElementOf("Lightning Bolt") == nil and D:ElementOf("Totemic Recall") == nil)
end)
step("unknown totem is reported, not guessed", function()
	assert(#D.unplaced == 1 and D.unplaced[1] == "Mysterious Forever Totem", table.concat(D.unplaced, ","))
end)
step("future spells carry their learn level", function()
	assert(D.future["Call of the Elements"].level == 20, "no level for CotE")
	assert(D.future["Totemic Projection"].spellID == 108287)
end)
step("dropping a totem out of combat teaches its element", function()
	scenario.activeTotem[AIR_TOTEM_SLOT] = 999001
	D:LearnFromActiveTotems()
	assert(ns.addon.db.global.learnedElements["Mysterious Forever Totem"] == "air", "not learned")
	assert(D:ElementOf("Mysterious Forever Totem") == "air", "not rediscovered")
	assert(#D.unplaced == 0, "still unplaced")
end)
step("in combat nothing is learned", function()
	scenario.inCombat = true
	scenario.activeTotem[WATER_TOTEM_SLOT] = 403
	D:LearnFromActiveTotems()
	assert(ns.addon.db.global.learnedElements["Lightning Bolt"] == nil, "learned in combat")
	scenario.inCombat = false
	scenario.activeTotem = {}
end)
step("native bar lists win over the fallback table", function()
	scenario.multicast[EARTH_TOTEM_SLOT] = { 8071, 2484 }
	scenario.multicast[AIR_TOTEM_SLOT] = { 8512 }
	D:Discover()
	for _, t in ipairs(D:GetTotems("earth")) do
		if t.name == "Stoneskin Totem" then assert(t.source == "multicast", t.source) end
	end
	assert(D:ElementOf("Windfury Totem") == "air", "multicast-only totem missing")
	scenario.multicast = {}
end)
step("a clash within an element is detected", function()
	local saved = D.ABBREVIATION_OVERRIDES["Stoneskin"]
	D.ABBREVIATION_OVERRIDES["Stoneskin"] = "EB"
	D:Discover()
	assert(#D.clashes == 1 and D.clashes[1]:find("earth EB"), table.concat(D.clashes, ";"))
	D.ABBREVIATION_OVERRIDES["Stoneskin"] = saved
	D:Discover()
	assert(#D.clashes == 0)
end)
step("selftest with M2 section", function() ns.SelfTest:Run() end)

-- M3: keybind labels, bar geometry, combat queue, themes
realPrint("\nKeybind labels:")
for _, case in ipairs({
	{ "ALT-SHIFT-Q", "asQ" }, { "CTRL-1", "c1" }, { "SHIFT-BUTTON4", "sM4" }, { "NUMPAD5", "N5" },
	{ "ALT-CTRL-SHIFT-F", "acsF" }, { "MOUSEWHEELUP", "WU" }, { "F", "F" }, { nil, "" },
}) do
	step(("%-18s -> %q"):format(tostring(case[1]), case[2]), function()
		local got = ns.Keybinds.Format(case[1])
		assert(got == case[2], "got " .. tostring(got))
	end)
end

realPrint("\nBar (M3):")
local B = ns.Bar
local S = ns.addon.db.global.settings
local function topleft(frame)
	local p = frame._points[1]
	assert(p and p[1] == "TOPLEFT", "not anchored TOPLEFT")
	return p[4], -p[5]
end
local function btn(name) return FRAMES["TotemicAccord" .. name] end
step("seven named secure buttons exist", function()
	for _, n in ipairs({ "Earth", "Fire", "Water", "Air", "Action", "Projection", "Profile" }) do
		assert(btn(n), "missing TotemicAccord" .. n)
	end
	assert(#B.buttons == 7)
end)
step("horizontal: 44px buttons, 6px gaps, separator before Action", function()
	B:Set("layout", "horizontal")
	local xs = {}
	for _, n in ipairs({ "Earth", "Fire", "Water", "Air", "Action", "Projection", "Profile" }) do
		xs[#xs + 1] = (topleft(btn(n)))
	end
	-- 6,56,106,156 | sep at 206 (1px) | 213, 263, 313
	assert(table.concat(xs, ",") == "6,56,106,156,213,263,313", table.concat(xs, ","))
	assert(B.frame._w == 363 and B.frame._h == 56, ("bar %sx%s"):format(B.frame._w, B.frame._h))
	assert(B.frame.sep._shown and B.frame.sep._w == 1, "separator")
end)
step("vertical: same spacing down the y axis", function()
	B:Set("layout", "vertical")
	local _, y = topleft(btn("Profile"))
	assert(y == 313, "profile y " .. y)
	assert(B.frame._w == 56 and B.frame._h == 363, ("bar %sx%s"):format(B.frame._w, B.frame._h))
end)
step("grid: 2x2 elements, Action over Projection, Profile centred", function()
	B:Set("layout", "grid")
	local function at(n) local x, y = topleft(btn(n)); return x .. ":" .. y end
	assert(at("Earth") == "6:6" and at("Fire") == "56:6" and at("Water") == "6:56" and at("Air") == "56:56", "elements")
	assert(at("Action") == "106:6" and at("Projection") == "106:56", "action/projection")
	assert(at("Profile") == "156:31", "profile " .. at("Profile"))
	assert(not B.frame.sep._shown, "separator should be hidden in grid")
	assert(B.frame._w == 206 and B.frame._h == 106, ("bar %sx%s"):format(B.frame._w, B.frame._h))
end)
step("empty element: grey keeps it, hide removes it and closes the gap", function()
	B:Set("layout", "horizontal")
	local saved = ns.Data.totems.water
	ns.Data.totems.water = {}
	B:Refresh()
	assert(btn("Water")._shown and btn("Water").text._text == "-", "grey slot should show '-'")
	B:Set("emptySlot", "hide")
	assert(not btn("Water")._shown, "water should be hidden")
	assert((topleft(btn("Air"))) == 106, "air should move into water's place")
	B:Set("emptySlot", "grey")
	ns.Data.totems.water = saved
	B:Refresh()
end)
step("in combat, layout is queued and applied when combat ends", function()
	scenario.inCombat = true
	B:Set("layout", "vertical")
	assert(B.layoutPending, "not queued")
	assert(B.frame._w == 363, "geometry changed in combat")
	scenario.inCombat = false
	B:OnRegenEnabled()
	assert(not B.layoutPending and B.frame._w == 56, "not applied after combat")
	B:Set("layout", "horizontal")
end)
step("scale accepts 0.5-2 only", function()
	assert(B:Set("scale", "1.25") and B.frame._scale == 1.25)
	assert(not B:Set("scale", "5") and not B:Set("scale", "abc"))
	B:Set("scale", "1")
end)
step("all five themes apply; classic uses gradients, flat themes don't", function()
	for _, key in ipairs(ns.Themes.ORDER) do
		assert(ns.Themes:Set(key), key)
		local g = btn("Earth").bg._gradient
		if key == "classic" then assert(g, "classic should set a gradient") end
	end
	assert(not ns.Themes:Set("neon"), "unknown theme accepted")
	ns.Themes:Set("emerald")
	local r, g, b = unpack(btn("Earth").text._color or { ns.Themes.RGB("#d9a35b") })
	assert(r and g and b)
end)
step("icons style shows the spell icon, initials shows the code", function()
	B:Set("buttonStyle", "icons")
	local earth = btn("Earth")
	assert(earth.icon._shown and earth.icon._texture == "icon:" .. earth.totem.spellID, "icon")
	assert(not earth.text._shown, "text should hide behind an icon")
	assert(btn("Profile").text._shown, "profile keeps its text code")
	B:Set("buttonStyle", "initials")
	assert(earth.text._shown and earth.text._text == earth.totem.code, "initials")
end)
step("keybind label follows UPDATE_BINDINGS", function()
	scenario.bindings["CLICK TotemicAccordEarth:LeftButton"] = "ALT-SHIFT-Q"
	B:UpdateKeys()
	assert(btn("Earth").key._text == "asQ", tostring(btn("Earth").key._text))
	scenario.bindings = {}
	B:UpdateKeys()
end)
step("lock hides the drag handle, unlock shows it", function()
	ns.addon:OnSlashCommand("lock")
	assert(not B.mover._shown and S.locked)
	ns.addon:OnSlashCommand("unlock")
	assert(B.mover._shown and not S.locked)
end)
step("dragging is refused in combat", function()
	local started = false
	B.frame.StartMoving = function() started = true end
	scenario.inCombat = true
	B.mover._scripts.OnDragStart()
	assert(not started, "moved in combat")
	scenario.inCombat = false
	B.mover._scripts.OnDragStart()
	assert(started, "did not move out of combat")
end)
step("slash commands: theme, layout, style, scale, empty, reset, bad values", function()
	for _, c in ipairs({ "theme tokyo", "layout grid", "style icons", "scale 1.1", "empty hide",
		"reset", "theme nope", "layout diagonal", "theme emerald", "layout horizontal",
		"style initials", "scale 1", "empty grey" }) do
		ns.addon:OnSlashCommand(c)
	end
	assert(S.theme == "emerald" and S.layout == "horizontal" and S.point == nil)
end)
step("a font that fails at login is retried and then used", function()
	local earthText = btn("Earth").text
	local fails, used = 2, nil
	earthText.SetFont = function(_, path)
		if path:find("Manrope") and fails > 0 then fails = fails - 1; return false end
		used = path
		return true
	end
	B.fontRetries, B.fontRetryScheduled = 0, false
	ns.Themes:Apply() -- fails once, schedules a retry (the stub timer runs it at once)
	assert(B.fontRetries >= 1, "no retry scheduled")
	assert(used and used:find("Manrope%-Bold"), "font not used after retry: " .. tostring(used))
	earthText.SetFont = nil
end)
realPrint("\nCasting + keybinds (M4):")
step("element buttons cast their totem by NAME (highest rank)", function()
	B:Refresh()
	local earth = btn("Earth")
	assert(earth:GetAttribute("type") == "spell", tostring(earth:GetAttribute("type")))
	assert(earth:GetAttribute("spell") == earth.totem.name, tostring(earth:GetAttribute("spell")))
	assert(type(earth:GetAttribute("spell")) == "string", "spell must be a name, not an ID")
end)
step("buttons take both click halves so 'cast on key down' is honoured", function()
	local c = btn("Earth")._clicks
	assert(c and c[1] == "AnyUp" and c[2] == "AnyDown", "RegisterForClicks")
end)
step("projection casts by the name its spell ID resolves to", function()
	local p = btn("Projection")
	assert(p:GetAttribute("type") == "spell" and p:GetAttribute("spell") == "Totemic Projection",
		tostring(p:GetAttribute("spell")))
end)
step("projection reads as muted until learned", function()
	assert(B.projection[3] == false, "should be unknown at level 18")
	local muted = { ns.Themes.RGB(ns.Themes:Current().muted) }
	local c = btn("Projection").text._textColor
	assert(c and c[1] == muted[1] and c[2] == muted[2] and c[3] == muted[3], "projection text not muted")
	local e = btn("Earth").text._textColor
	local earthInk = { ns.Themes.RGB(ns.Themes:Current().earth) }
	assert(e and e[1] == earthInk[1], "earth text not in the element colour")
end)
step("action and profile buttons do nothing yet", function()
	assert(btn("Action"):GetAttribute("type") == nil and btn("Profile"):GetAttribute("type") == nil)
end)
step("an element with no totem casts nothing", function()
	local saved = ns.Data.totems.air
	ns.Data.totems.air = {}
	B:Refresh()
	assert(btn("Air"):GetAttribute("type") == nil and btn("Air"):GetAttribute("spell") == nil)
	ns.Data.totems.air = saved
	B:Refresh()
end)
step("a totem change in combat is queued, then applied after combat", function()
	local before = btn("Earth"):GetAttribute("spell")
	local list = ns.Data.totems.earth
	table.insert(list, 1, { spellID = 1, name = "Tremor Totem", code = "Tr", source = "fallback" })
	scenario.inCombat = true
	B:Refresh()
	assert(B.securePending and btn("Earth"):GetAttribute("spell") == before, "changed in combat")
	scenario.inCombat = false
	B:OnRegenEnabled()
	assert(not B.securePending and btn("Earth"):GetAttribute("spell") == "Tremor Totem", "not applied")
	table.remove(list, 1)
	B:Refresh()
end)
step("Key Bindings menu names exist for all seven buttons", function()
	assert(BINDING_HEADER_TOTEMICACCORD == "Totemic Accord")
	for _, n in ipairs({ "Earth", "Fire", "Water", "Air", "Action", "Projection", "Profile" }) do
		assert(_G["BINDING_NAME_CLICK TotemicAccord" .. n .. ":LeftButton"], n)
	end
end)
step("/ta keys asks first and lists what it would replace", function()
	scenario.bindingActions["ALT-SHIFT-Q"] = "TOGGLEWORLDMAP"
	scenario.popup = nil
	ns.addon:OnSlashCommand("keys")
	assert(scenario.popup, "no confirmation shown")
	assert(scenario.popup.text:find("ALT%-SHIFT%-Q: Name of TOGGLEWORLDMAP"), scenario.popup.text)
	assert(scenario.saved == 0 and not scenario.bindings["CLICK TotemicAccordEarth:LeftButton"],
		"bound before confirming")
end)
step("accepting binds all five and saves once", function()
	scenario.popup.callback()
	assert(scenario.bindingActions["ALT-SHIFT-Q"] == "CLICK TotemicAccordEarth:LeftButton")
	assert(scenario.bindingActions["ALT-SHIFT-G"] == "CLICK TotemicAccordAction:LeftButton")
	assert(scenario.saved == 1, "SaveBindings calls: " .. scenario.saved)
	B:UpdateKeys()
	assert(btn("Earth").key._text == "asQ" and btn("Action").key._text == "asG")
end)
step("running /ta keys again says they are already set", function()
	scenario.popup = nil
	ns.addon:OnSlashCommand("keys")
	assert(scenario.popup == nil, "asked again for nothing")
end)
step("keybinds are never changed in combat", function()
	scenario.bindingActions, scenario.bindings = {}, {}
	scenario.inCombat = true
	scenario.popup = nil
	ns.addon:OnSlashCommand("keys")
	assert(scenario.popup == nil, "asked in combat")
	scenario.inCombat = false
	ns.addon:OnSlashCommand("keys")
	scenario.inCombat = true -- entered combat with the dialog open
	scenario.popup.callback()
	assert(next(scenario.bindingActions) == nil, "bound in combat")
	scenario.inCombat = false
	scenario.bindingActions, scenario.bindings = {}, {}
	B:UpdateKeys()
end)

step("built only after combat if the UI loads mid-fight", function()
	local saved = B.frame
	B.frame = nil
	scenario.inCombat = true
	B:Init()
	assert(B.frame == nil, "built in combat")
	scenario.inCombat = false
	B:OnRegenEnabled()
	assert(B.frame ~= nil, "not built after combat")
	B.frame = saved
end)

-- non-Shaman path, with a completely fresh namespace
realPrint("\nNon-Shaman character:")
scenario.class = "WARRIOR"
local ns2 = {}
local addon2
step("load + OnInitialize as a Warrior", function()
	for _, f in ipairs({ "Locales/enUS.lua", "Core.lua", "Data.lua", "Themes.lua", "Keybinds.lua", "Bar.lua", "SelfTest.lua" }) do
		local chunk = assert(loadfile(repo .. "/TotemicAccord/" .. f))
		chunk(ADDON, ns2)
	end
	addon2 = ns2.addon
	addon2:OnInitialize()
end)
step("disabled, and no DB was created", function()
	assert(addon2._enabled == false, "addon should be disabled for a Warrior")
	assert(addon2.db == nil, "no per-character DB should exist for a Warrior")
	assert(addon2.disabledReason == "notShaman", "disabledReason not set")
end)
step("/ta explains instead of erroring", function()
	addon2:OnSlashCommandDisabled()
	local last = output[#output]
	assert(last:find("Shaman", 1, true), "expected the not-a-Shaman message, got: " .. tostring(last))
end)

realPrint("")
if failures == 0 then
	realPrint(("ALL SMOKE TESTS PASSED  (%d lines of in-game output produced)"):format(#output))
else
	realPrint(("SMOKE TESTS FAILED: %d"):format(failures))
end

realPrint("\n--- sample of the in-game output ---")
for i = 1, math.min(#output, 28) do realPrint("  " .. output[i]) end

os.exit(failures == 0 and 0 or 1)
