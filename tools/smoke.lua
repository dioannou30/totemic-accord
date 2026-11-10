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
			Version = "1.0.0",
		}
		return meta[field]
	end,
	GetAddOnInterfaceVersion = function() return 16001 end,
}

C_Spell = {
	GetSpellName = function(id) return NAME_BY_ID and NAME_BY_ID[id] end,
	GetSpellInfo = function(idOrName)
		if idOrName == 66842 then return { name = "Call of the Elements", spellID = 66842 } end
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
local FUTURE = { { "Call of the Elements", 66842, 20 } }
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
	function methods:SetParent(parent)
		-- Reparenting a frame with secure children is blocked in combat, as in game.
		assert(not (self._protected and scenario.inCombat), "SetParent on a protected frame in combat")
		self._parent = parent
	end
	function methods:GetParent() return self._parent end
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
	function methods:GetID() return self._id or 0 end
	function methods:SetID(id) self._id = id end
	function methods:RegisterUnitEvent(ev)
		if ev == "UNIT_SPELLCAST_SUCCEEDED" then FRAMES.__castProbe = self end
	end
	function methods:CreateTexture() return newWidget() end
	function methods:CreateFontString() return newWidget() end
	function methods:CreateAnimationGroup() return newWidget() end
	function methods:CreateAnimation() return newWidget() end
	-- Only Capitalized names are faked as no-op methods (all WoW widget methods are);
	-- our own fields are lowercase and must read as nil when unset.
	return setmetatable(w, { __index = function(_, k)
		if methods[k] then return methods[k] end
		if type(k) == "string" and k:match("^%u") then return function() end end
	end })
end
UIParent = newWidget("UIParent")
-- The game's totem bar: holds secure buttons, so it is protected.
MultiCastActionBarFrame = newWidget("MultiCastActionBarFrame")
MultiCastActionBarFrame._parent = UIParent
MultiCastActionBarFrame._protected = true
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

-- M5 prep: talent loadouts
C_ClassTalents = {
	GetConfigIDsBySpecID = function() return { 101, 102 } end,
	-- nil = no saved loadout, which is what the level-18 test character really has.
	GetLastSelectedSavedConfigID = function() return scenario.loadout end,
	GetActiveConfigID = function() return 900 end,
	GetStarterBuildActive = function() return false end,
}
C_Traits = { GetConfigInfo = function(id) return ({ [101] = { name = "Enh" }, [102] = { name = "Resto" } })[id] end }

-- M5: the context menu records what it was asked to show
scenario.menu = nil
MenuUtil = { CreateContextMenu = function(owner, generator)
	local root = { items = {} }
	function root:CreateTitle(t) table.insert(self.items, { kind = "title", text = t }) end
	function root:CreateDivider() table.insert(self.items, { kind = "divider" }) end
	function root:CreateRadio(t, isSel, setSel, data)
		table.insert(self.items, { kind = "radio", text = t, isSelected = isSel, select = setSel, data = data })
	end
	function root:CreateButton(t, onClick)
		table.insert(self.items, { kind = "button", text = t, select = onClick })
	end
	generator(owner, root)
	scenario.menu = root.items
end }

UISpecialFrames = {}
tinsert = table.insert

-- M8: the native totem bar's action slots
C_ActionBar = { GetMultiCastBarIndex = function() return 13 end }
NUM_ACTIONBAR_BUTTONS, NUM_MULTI_CAST_BUTTONS_PER_PAGE = 12, 4
scenario.native = {} -- action slot -> spellID
function GetActionInfo(slot)
	local id = scenario.native[slot]
	if id then return "spell", id end
end
--- What Blizzard's SECURE_ACTIONS.multispell does when a sync button is /clicked:
--- CalculateAction (ID 0 -> our "action" attribute), then SetMultiCastSpell. A /click
--- arrives as a key-up, which only acts if useOnKeyDown is false.
function emulateSyncClick(b)
	if b:GetAttribute("useOnKeyDown") ~= false then return end
	if b:GetAttribute("type") ~= "multispell" then return end
	local action = (b:GetID() > 0) and -1 or b:GetAttribute("action")
	scenario.native[action] = tonumber(b:GetAttribute("spell"))
	if b._scripts.PostClick then b._scripts.PostClick(b) end
end

-- M7: a clock, the macro store, and character macro slots
scenario.now = 1000
function GetTime() return scenario.now end
Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 18 } }
scenario.macros = {} -- index -> { name, icon, body }
function GetMacroInfo(i) local m = scenario.macros[i]; if m then return m.name, m.icon, m.body end end
function GetNumMacros()
	local a, c = 0, 0
	for i in pairs(scenario.macros) do if i <= 120 then a = a + 1 else c = c + 1 end end
	return a, c
end
function CreateMacro(name, icon, body, perCharacter)
	assert(not scenario.inCombat, "CreateMacro called in combat")
	assert(perCharacter, "should be a character macro")
	for i = 121, 138 do
		if not scenario.macros[i] then scenario.macros[i] = { name = name, icon = icon, body = body }; return i end
	end
end
function EditMacro(i, name, icon, body)
	assert(not scenario.inCombat, "EditMacro called in combat")
	scenario.macros[i] = { name = name, icon = icon, body = body }
end

-- M4: bindings and the confirmation popup
scenario.bindingActions = {}  -- key -> command
scenario.saved = 0
scenario.popup = nil
function SetBinding(key, command)
	assert(not scenario.inCombat, "SetBinding called in combat")
	local old = scenario.bindingActions[key]
	if old then scenario.bindings[old] = nil end
	scenario.bindingActions[key] = command
	if command then scenario.bindings[command] = key end
end
function SaveBindings() scenario.saved = scenario.saved + 1 end
function GetCurrentBindingSet() return 1 end
function GetBindingAction(key) return scenario.bindingActions[key] or "" end
function GetBindingText(action) return "Name of " .. action end
function StaticPopup_ShowCustomGenericConfirmation(data) scenario.popup = data end

-- ------------------------------------------------------------------ Ace stubs
local registered = {}
local addonObj

-- The REAL serialisation libraries (pure Lua): import/export is tested end to end.
-- Loaded before the fake LibStub exists, so they register standalone.
local realLibSerialize = assert(loadfile(repo .. "/TotemicAccord/Libs/LibSerialize/LibSerialize.lua"))()
local realLibDeflate = assert(loadfile(repo .. "/TotemicAccord/Libs/LibDeflate/LibDeflate.lua"))()

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
		function o:IsEnabled() return self._enabled end
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
		function target:UnregisterEvent(ev) self.events[ev] = nil end
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

registered["LibSerialize"] = realLibSerialize
registered["LibDeflate"] = realLibDeflate

-- M9: AceConfig, LibDataBroker and LibDBIcon record what they were asked to do.
registered["AceConfig-3.0"] = { RegisterOptionsTable = function(_, name, fn) scenario.optionsApp, scenario.optionsFn = name, fn end }
registered["AceConfigDialog-3.0"] = {
	SetDefaultSize = function() end,
	AddToBlizOptions = function(_, app, title) scenario.blizOptions = title end,
	Open = function(_, app) scenario.optionsOpened = app end,
	SelectGroup = function(_, app, tab) scenario.optionsTab = tab end,
}
scenario.notified = 0
registered["AceConfigRegistry-3.0"] = { NotifyChange = function() scenario.notified = scenario.notified + 1 end }
registered["LibDataBroker-1.1"] = { NewDataObject = function(_, name, obj) scenario.broker = obj; return obj end }
registered["LibDBIcon-1.0"] = {
	Register = function(_, name, obj, db) scenario.dbicon = { name = name, obj = obj, db = db } end,
	Show = function() scenario.iconShown = true end,
	Hide = function() scenario.iconShown = false end,
	IsRegistered = function() return scenario.dbicon ~= nil end,
}
function IsShiftKeyDown() return scenario.shift end
AddonCompartmentFrame = { registeredAddons = { { text = "Totemic Accord" } } }

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
for _, f in ipairs({ "Themes.lua", "Keybinds.lua", "Bar.lua", "Flyout.lua", "Sequence.lua", "Profiles.lua", "NativeBar.lua", "ImportExport.lua", "Options.lua", "Minimap.lua" }) do
	step("load " .. f, function() loadFile(f) end)
end
step("load SelfTest.lua", function() loadFile("SelfTest.lua") end)
step("global TotemicAccord was exposed", function()
	assert(_G[ADDON] == ns.addon, "addon not exposed as a global")
end)
step("identity read back from the TOC", function()
	assert(ns.addon.DISPLAY_NAME == "Totemic Accord", "bad display name")
	assert(ns.addon.VERSION == "1.0.0", "bad version")
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
	for _, c in ipairs({ "lock", "unlock", "auto", "profile enh:bg", "capture", "minimap" }) do
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
	for _, n in ipairs({ "Earth", "Fire", "Water", "Air", "Action", "Recall", "Profile" }) do
		assert(btn(n), "missing TotemicAccord" .. n)
	end
	assert(#B.buttons == 7)
end)
step("horizontal: 44px buttons, 6px gaps, separator before Action", function()
	B:Set("layout", "horizontal")
	local xs = {}
	for _, n in ipairs({ "Earth", "Fire", "Water", "Air", "Action", "Recall", "Profile" }) do
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
step("grid: 2x2 elements, Action over Recall, Profile centred", function()
	B:Set("layout", "grid")
	local function at(n) local x, y = topleft(btn(n)); return x .. ":" .. y end
	assert(at("Earth") == "6:6" and at("Fire") == "56:6" and at("Water") == "6:56" and at("Air") == "56:56", "elements")
	assert(at("Action") == "106:6" and at("Recall") == "106:56", "action/recall")
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
step("recall casts Totemic Recall by name, its ID from Blizzard's constant", function()
	local p = btn("Recall")
	assert(B.recall[2] == 36936, tostring(B.recall[2]))
	assert(p:GetAttribute("type") == "spell" and p:GetAttribute("spell") == "Totemic Recall",
		tostring(p:GetAttribute("spell")))
	assert(B.recall[3] == true, "Totemic Recall is in the spellbook")
	local e = btn("Earth").text._textColor
	local earthInk = { ns.Themes.RGB(ns.Themes:Current().earth) }
	assert(e and e[1] == earthInk[1], "earth text not in the element colour")
end)
step("recall reads as muted until learned", function()
	local saved = D.spellbook["Totemic Recall"]
	D.spellbook["Totemic Recall"] = nil
	B:Refresh()
	assert(B.recall[3] == false, "should be unknown")
	local muted = { ns.Themes.RGB(ns.Themes:Current().muted) }
	local c = btn("Recall").text._textColor
	assert(c and c[1] == muted[1] and c[2] == muted[2] and c[3] == muted[3], "recall text not muted")
	D.spellbook["Totemic Recall"] = saved
	B:Refresh()
	assert(B.recall[3] == true)
end)
step("profile button never casts (Action is covered by the M7 tests)", function()
	assert(btn("Profile"):GetAttribute("type") == nil)
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
	for _, n in ipairs({ "Earth", "Fire", "Water", "Air", "Action", "Recall", "Profile" }) do
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

realPrint("\nProfiles (M5):")
local P = ns.Profiles
local G = ns.addon.db.global
local function lastLine() return output[#output] or "" end
local function enter(instance)
	scenario.instance = instance
	P:Schedule("ZONE_CHANGED_NEW_AREA") -- the stub timer fires immediately
end
local function earthSpell() return btn("Earth"):GetAttribute("spell") end
step("fresh character: no profile, bar previews first known totems", function()
	scenario.instance, scenario.loadout = "none", nil
	assert(next(G.profiles) == nil and P.applied == nil)
	assert(btn("Profile").text._text == "--\n--", tostring(btn("Profile").text._text))
	assert(B.frame.label._text:find("Preview"), B.frame.label._text)
end)
step("/ta set creates the Global default and edits it", function()
	ns.addon:OnSlashCommand("set earth SS")
	assert(G.profiles.global and G.profiles.global.earth.name == "Stoneskin Totem")
	assert(P.applied == "global" and earthSpell() == "Stoneskin Totem", tostring(earthSpell()))
	assert(btn("Profile").text._text == "ALL\nDEF")
	assert(B.frame.label._text == "Global default", B.frame.label._text)
end)
step("bad keys, unknown totems and edits in combat are refused", function()
	ns.addon:OnSlashCommand("save banana")
	assert(lastLine():find("Unknown profile key"), lastLine())
	ns.addon:OnSlashCommand("set earth ZZ")
	assert(lastLine():find("No known"), lastLine())
	scenario.inCombat = true
	ns.addon:OnSlashCommand("set earth EB")
	assert(lastLine():find("in combat"), lastLine())
	scenario.inCombat = false
	assert(G.profiles.global.earth.name == "Stoneskin Totem")
end)
step("a Global dungeon profile takes over on entering a dungeon", function()
	ns.addon:OnSlashCommand("save global:dungeon")
	G.profiles["global:dungeon"].earth = { spellID = 2484, name = "Earthbind Totem" }
	enter("party")
	assert(P.applied == "global:dungeon", tostring(P.applied))
	assert(earthSpell() == "Earthbind Totem")
	assert(btn("Profile").text._text == "ALL\nDGN")
	assert(lastLine():find("Profile: Global · Dungeon"), lastLine())
end)
step("leaving falls back to the Global default", function()
	enter("none")
	assert(P.applied == "global" and earthSpell() == "Stoneskin Totem")
end)
step("with a saved loadout, its profile wins over Global", function()
	scenario.loadout = 102 -- "Resto"
	ns.addon:OnSlashCommand("save loadout:dungeon")
	assert(G.profiles["L102:dungeon"], "loadout key not created")
	G.profiles["L102:dungeon"].earth = { spellID = 8143, name = "Tremor Totem" }
	enter("party")
	assert(P.applied == "L102:dungeon", tostring(P.applied))
	assert(earthSpell() == "Tremor Totem")
	assert(btn("Profile").text._text == "RES\nDGN", btn("Profile").text._text)
	assert(B.frame.label._text == "Resto · Dungeon", B.frame.label._text)
end)
step("switching loadout switches profile (another loadout -> Global)", function()
	scenario.loadout = 101 -- "Enh", nothing saved for it
	P:Schedule("SELECTED_LOADOUT_CHANGED")
	assert(P.applied == "global:dungeon", tostring(P.applied))
	scenario.loadout = 102
	P:Schedule("SELECTED_LOADOUT_CHANGED")
	assert(P.applied == "L102:dungeon")
end)
step("resolution order is loadout:sit, loadout:default, global:sit, global, captured", function()
	local chain = table.concat(P:Chain(), ",")
	assert(chain == "L102:dungeon,L102:default,global:dungeon,global,captured", chain)
end)
step("a manual pin survives zone and loadout changes; dot turns to warning", function()
	ns.addon:OnSlashCommand("profile global")
	assert(P.applied == "global" and G.manual == "global")
	enter("raid")
	scenario.loadout = 101
	P:Schedule("SELECTED_LOADOUT_CHANGED")
	assert(P.applied == "global", "pin was overridden: " .. tostring(P.applied))
	local warn = { ns.Themes.RGB(ns.Themes:Current().warn) }
	assert(btn("Profile").dot._color[1] == warn[1], "dot not warning colour")
end)
step("/ta auto resumes and the dot goes back to success", function()
	scenario.loadout = 102
	enter("party")
	ns.addon:OnSlashCommand("auto")
	assert(G.manual == nil and P.applied == "L102:dungeon", tostring(P.applied))
	local ok = { ns.Themes.RGB(ns.Themes:Current().ok) }
	assert(btn("Profile").dot._color[1] == ok[1], "dot not success colour")
end)
step("in combat a due switch is queued, label shows Old -> New, casting unchanged", function()
	scenario.inCombat = true
	enter("none") -- Resto has no world profile -> global
	assert(P.applied == "L102:dungeon" and P.queued == "global", tostring(P.queued))
	assert(earthSpell() == "Tremor Totem", "attribute changed in combat")
	assert(B.frame.label._text == "Resto · Dungeon -> Global default", B.frame.label._text)
	assert(lastLine():find("when combat ends"), lastLine())
end)
step("...and applied when combat ends", function()
	scenario.inCombat = false
	P:OnRegenEnabled()
	B:OnRegenEnabled()
	assert(P.applied == "global" and not P.queued and earthSpell() == "Stoneskin Totem")
end)
step("a queued switch that becomes moot is cancelled", function()
	scenario.inCombat = true
	enter("party")
	assert(P.queued == "L102:dungeon")
	enter("none")
	assert(P.queued == nil and P.applied == "global", tostring(P.queued))
	scenario.inCombat = false
end)
step("on-screen message can be turned off; the chat line stays", function()
	local flashes = 0
	local realFlash = P.Flash
	P.Flash = function() flashes = flashes + 1 end
	enter("party")
	assert(flashes == 1)
	ns.addon:OnSlashCommand("message off")
	enter("none")
	assert(flashes == 1 and lastLine():find("Profile:"), "flash shown while off")
	ns.addon:OnSlashCommand("message on")
	P.Flash = realFlash
end)
local function menuItem(text)
	for _, item in ipairs(scenario.menu or {}) do
		if item.text == text then return item end
	end
end
step("Profile button opens Blizzard's context menu; picking pins, Auto unpins", function()
	scenario.menu = nil
	btn("Profile")._scripts.OnClick(btn("Profile"))
	local m = scenario.menu
	assert(m and m[1].kind == "title", "MenuUtil menu not opened")
	assert(m[2].kind == "radio" and m[2].text:find("^Auto %(currently: "), m[2] and m[2].text)
	assert(m[2].isSelected(), "Auto should be selected while not pinned")
	local pick = menuItem("Global · Dungeon")
	assert(pick and pick.kind == "radio", "Global · Dungeon not offered")
	assert(not pick.isSelected())
	pick.select()
	assert(G.manual == "global:dungeon" and P.applied == "global:dungeon")
	btn("Profile")._scripts.OnClick(btn("Profile"))
	assert(menuItem("Global · Dungeon").isSelected(), "pinned profile not shown as selected")
	scenario.menu[2].select()
	assert(G.manual == nil)
end)
step("deleting the pinned profile unpins and falls back", function()
	ns.addon:OnSlashCommand("profile global:dungeon")
	ns.addon:OnSlashCommand("delete global:dungeon")
	assert(G.manual == nil and not G.profiles["global:dungeon"])
	enter("party")
	assert(P.applied == "L102:dungeon", tostring(P.applied))
end)
step("logging in is not announced as a switch", function()
	local before = #output
	P.applied = nil
	P:Update("login", true)
	for i = before + 1, #output do assert(not output[i]:find("Profile:"), "announced at login") end
	scenario.loadout, scenario.instance = nil, "none"
	P:Update("reset", true)
end)

realPrint("\nCast probe (M7 prep):")
step("records readable vs secret spell IDs, in and out of combat", function()
	local probe = FRAMES.__castProbe
	assert(probe, "probe frame not created")
	local onEvent = probe._scripts.OnEvent
	onEvent(probe, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 8071)
	scenario.inCombat = true
	issecretvalue = function() return true end
	onEvent(probe, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 8071)
	issecretvalue = function() return false end
	scenario.inCombat = false
	assert(ns.SelfTest.castSeen.idle == "readable (8071)", tostring(ns.SelfTest.castSeen.idle))
	assert(ns.SelfTest.castSeen.combat == "secret", tostring(ns.SelfTest.castSeen.combat))
end)

realPrint("\nFlyouts (M6):")
local F = ns.Flyout
local function arrow(n) return btn(n).arrow end
step("every element has an arrow tab above it (horizontal)", function()
	B:Set("layout", "horizontal")
	for _, n in ipairs({ "Earth", "Fire", "Water", "Air" }) do
		local p = arrow(n)._points[1]
		assert(p and p[1] == "BOTTOM" and p[2] == btn(n) and p[3] == "TOP", n)
	end
	assert(not btn("Action").arrow, "only elements get arrows")
end)
step("vertical layout puts the tab on the left", function()
	B:Set("layout", "vertical")
	local p = arrow("Earth")._points[1]
	assert(p[1] == "RIGHT" and p[3] == "LEFT", p[1])
	B:Set("layout", "horizontal")
end)
step("a hidden empty element hides its arrow too", function()
	-- Since M5 the bar shows the profile's totems, so empty the element in the profile.
	local before = btn("Water").totem and btn("Water").totem.code
	ns.addon:OnSlashCommand("set water none")
	B:Set("emptySlot", "hide")
	assert(not btn("Water")._shown and not arrow("Water")._shown, "arrow still shown")
	B:Set("emptySlot", "grey")
	if before then ns.addon:OnSlashCommand("set water " .. before) end
end)
step("opening shows none + every known totem, current one ringed", function()
	ns.addon:OnSlashCommand("set earth SS")
	arrow("Earth")._scripts.OnClick()
	assert(F.frame._shown and F.owner == btn("Earth"))
	local shown, ringed = {}, nil
	for _, it in ipairs(F.frame.items) do
		if it._shown then
			shown[#shown + 1] = it.text._text
			if it.ring._shown then ringed = it.text._text end
		end
	end
	assert(table.concat(shown, ",") == "-,EB,SS,SE", table.concat(shown, ","))
	assert(ringed == "SS", "ringed: " .. tostring(ringed))
end)
step("picking changes the applied profile and what the button casts", function()
	for _, it in ipairs(F.frame.items) do
		if it._shown and it.text._text == "EB" then it._scripts.OnClick(it) end
	end
	assert(not F.frame._shown, "flyout stayed open")
	assert(ns.addon.db.global.profiles[P.applied].earth.name == "Earthbind Totem")
	assert(earthSpell() == "Earthbind Totem")
end)
step("picking 'none' empties the element", function()
	arrow("Earth")._scripts.OnClick()
	F.frame.items[1]._scripts.OnClick(F.frame.items[1])
	assert(ns.addon.db.global.profiles[P.applied].earth == nil)
	assert(btn("Earth"):GetAttribute("type") == nil and btn("Earth").text._text == "-")
	ns.addon:OnSlashCommand("set earth SS")
end)
step("clicking the same arrow again closes it", function()
	arrow("Fire")._scripts.OnClick()
	assert(F.frame._shown)
	arrow("Fire")._scripts.OnClick()
	assert(not F.frame._shown)
end)
step("direction setting places the strip; bad values are rejected", function()
	for dir, anchor in pairs({ up = "BOTTOM", down = "TOP", left = "RIGHT", right = "LEFT" }) do
		ns.addon:OnSlashCommand("flyout " .. dir)
		arrow("Earth")._scripts.OnClick()
		assert(F.frame._points[1][1] == anchor, dir .. " -> " .. tostring(F.frame._points[1][1]))
		F:Close()
	end
	assert(not B:Set("flyoutDir", "diagonal"))
	ns.addon:OnSlashCommand("flyout up")
end)
step("right-click opens the chooser; left-click and keybinds still cast", function()
	local earth = btn("Earth")
	assert(earth:GetAttribute("type2") == "taflyout" and type(earth.taflyout) == "function")
	assert(earth:GetAttribute("type") == "spell", "left-click no longer casts")
	F:Close()
	earth.taflyout(earth) -- what SecureActionButton_OnClick calls for type2
	assert(F.frame._shown and F.owner == earth)
	F:Close()
	assert(btn("Action"):GetAttribute("type2") == nil, "only elements get the right-click chooser")
end)
step("grid: bottom-row tabs sit below the block, top-row tabs above", function()
	B:Set("layout", "grid")
	local function anchor(n) local p = arrow(n)._points[1]; return p[1] .. ">" .. p[3] end
	assert(anchor("Earth") == "BOTTOM>TOP" and anchor("Fire") == "BOTTOM>TOP", anchor("Earth"))
	assert(anchor("Water") == "TOP>BOTTOM" and anchor("Air") == "TOP>BOTTOM", anchor("Water"))
	B:Set("layout", "horizontal")
end)
step("/ta arrows off hides the tabs, on brings them back", function()
	ns.addon:OnSlashCommand("arrows off")
	assert(not arrow("Earth")._shown)
	ns.addon:OnSlashCommand("arrows on")
	assert(arrow("Earth")._shown)
end)
step("a font change re-sets the text so glyphs redraw", function()
	local fs = btn("Earth").text
	local calls = {}
	local realSetText = fs.SetText
	fs.SetText = function(self, t) calls[#calls + 1] = tostring(t); realSetText(self, t) end
	fs.taFont = "Fonts\\SOMETHING_ELSE.TTF" -- as if a fallback font had been used
	ns.Themes:Apply()
	fs.SetText = nil
	local seq = table.concat(calls, "|")
	assert(seq:find("^|SS") or seq:find("|SS"), "no blank-then-text reset: " .. seq)
	assert(calls[1] == "", "first call should blank the text: " .. seq)
end)
step("refuses to open in combat, with a chat message", function()
	scenario.inCombat = true
	arrow("Earth")._scripts.OnClick()
	assert(not F.frame._shown and lastLine():find("combat"), lastLine())
	scenario.inCombat = false
end)
step("entering combat closes an open flyout; a racing pick is refused", function()
	arrow("Earth")._scripts.OnClick()
	assert(F.events.PLAYER_REGEN_DISABLED == "Close")
	local item = F.frame.items[2]
	scenario.inCombat = true
	item._scripts.OnClick(item)
	assert(not F.frame._shown, "not closed")
	assert(ns.addon.db.global.profiles[P.applied].earth.name == "Stoneskin Totem", "changed in combat")
	scenario.inCombat = false
end)

realPrint("\nSequences (M7):")
local Q = ns.Sequence
local function cast(name)
	local ids = { ["Stoneskin Totem"] = 8071, ["Searing Totem"] = 3599, ["Healing Stream Totem"] = 5394,
		["Grounding Totem"] = 8177, ["Earthbind Totem"] = 2484 }
	Q:OnSpellcast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", ids[name])
end
local function press() btn("Action")._scripts.PostClick(btn("Action")) end
local function counter() return btn("Action").count._text end
step("setup: a Global default with all four elements", function()
	scenario.instance, scenario.loadout = "none", nil
	G.manual = nil
	for k in pairs(G.profiles) do G.profiles[k] = nil end
	for k in pairs(G.sequences) do G.sequences[k] = nil end
	P.applied = nil
	for _, c in ipairs({ "set earth SS", "set fire Se", "set water HS", "set air Gr" }) do
		ns.addon:OnSlashCommand(c)
	end
	assert(P.applied == "global" and B.actionMode == "seq")
end)
step("default macro: #showtooltip, reset=combat, elements in display order", function()
	local want = "#showtooltip\n/castsequence reset=combat Stoneskin Totem, Searing Totem, "
		.. "Healing Stream Totem, Grounding Totem"
	assert(Q:MacroText() == want, Q:MacroText())
end)
step("Action button is a secure macro button running exactly that text", function()
	local a = btn("Action")
	assert(a:GetAttribute("type") == "macro" and a:GetAttribute("macrotext") == Q:MacroText())
	assert(a:GetAttribute("spell") == nil)
end)
step("order, skip/use, reset seconds and combat all shape the text", function()
	ns.addon:OnSlashCommand("seq order fire,earth,air,water")
	ns.addon:OnSlashCommand("seq skip water")
	ns.addon:OnSlashCommand("seq seconds 20")
	assert(Q:MacroText():find("/castsequence reset=combat/20 Searing Totem, Stoneskin Totem, Grounding Totem$"),
		Q:MacroText())
	ns.addon:OnSlashCommand("seq combat off")
	ns.addon:OnSlashCommand("seq seconds off")
	assert(Q:MacroText():find("/castsequence Searing Totem, Stoneskin Totem, Grounding Totem$"), Q:MacroText())
	assert(btn("Action"):GetAttribute("macrotext") == Q:MacroText(), "button not rewritten")
	ns.addon:OnSlashCommand("seq use water")
	ns.addon:OnSlashCommand("seq combat on")
	ns.addon:OnSlashCommand("seq order earth,fire,water,air")
end)
step("bad sequence input is refused", function()
	ns.addon:OnSlashCommand("seq order earth,fire")
	assert(lastLine():find("Usage"), lastLine())
	ns.addon:OnSlashCommand("seq seconds 9999")
	assert(lastLine():find("Usage"), lastLine())
	assert(Q:Get("global").resetSeconds == nil)
end)
step("the sequence belongs to the profile: another profile has its own", function()
	ns.addon:OnSlashCommand("save global:dungeon")
	enter("party")
	ns.addon:OnSlashCommand("seq skip fire")
	assert(not Q:MacroText():find("Searing"), "dungeon still has fire")
	enter("none")
	assert(Q:MacroText():find("Searing"), "global lost fire")
	ns.addon:OnSlashCommand("delete global:dungeon")
end)
step("counter starts at 1/4 and follows casts after an Action press", function()
	Q:ResetCounter()
	assert(counter() == "1/4", tostring(counter()))
	press(); cast("Stoneskin Totem")
	assert(counter() == "2/4", tostring(counter()))
	press(); cast("Searing Totem")
	assert(counter() == "3/4", tostring(counter()))
end)
step("a totem dropped from its own button does not move the counter", function()
	scenario.now = scenario.now + 5 -- well outside the press window
	cast("Healing Stream Totem")
	assert(counter() == "3/4", tostring(counter()))
end)
step("a failed press (no cast) does not move it; wraps after the last step", function()
	press() -- e.g. on cooldown: no UNIT_SPELLCAST_SUCCEEDED
	scenario.now = scenario.now + 2
	assert(counter() == "3/4")
	press(); cast("Healing Stream Totem")
	press(); cast("Grounding Totem")
	assert(counter() == "1/4", tostring(counter()))
end)
step("the counter re-syncs to whichever step the game actually cast", function()
	press(); cast("Searing Totem") -- the game was really on step 2
	assert(counter() == "3/4", tostring(counter()))
end)
step("a secret spell ID is ignored rather than guessed", function()
	issecretvalue = function() return true end
	press(); cast("Healing Stream Totem")
	issecretvalue = function() return false end
	assert(counter() == "3/4", tostring(counter()))
end)
step("reset after combat (when enabled) and on profile switch", function()
	Q:OnRegenEnabled()
	assert(counter() == "1/4")
	press(); cast("Stoneskin Totem")
	ns.addon:OnSlashCommand("save global:raid")
	enter("raid")
	assert(P.applied == "global:raid" and counter() == "1/4", tostring(counter()))
	enter("none")
	ns.addon:OnSlashCommand("delete global:raid")
end)
step("reset after N seconds without a press", function()
	ns.addon:OnSlashCommand("seq seconds 20")
	press(); cast("Stoneskin Totem")
	assert(counter() == "2/4")
	scenario.now = scenario.now + 25
	press() -- 25s later: castsequence starts over
	assert(Q.position == 1, "position " .. Q.position)
	cast("Stoneskin Totem")
	assert(counter() == "2/4", tostring(counter()))
	ns.addon:OnSlashCommand("seq seconds off")
end)
step("/ta macro creates the character macro 'TA Sequence' with the text", function()
	scenario.macros = {}
	ns.addon:OnSlashCommand("macro")
	local m = scenario.macros[121]
	assert(m and m.name == "TA Sequence" and m.body == Q:MacroText(), m and m.body)
	assert(lastLine():find("Created"), lastLine())
end)
step("it follows profile switches and edits; deleted, it stays deleted", function()
	ns.addon:OnSlashCommand("seq skip air")
	assert(scenario.macros[121].body == Q:MacroText() and not scenario.macros[121].body:find("Grounding"))
	ns.addon:OnSlashCommand("seq use air")
	scenario.macros = {}
	ns.addon:OnSlashCommand("seq skip air")
	assert(next(scenario.macros) == nil, "recreated a macro the player deleted")
	ns.addon:OnSlashCommand("seq use air")
end)
step("macro edits wait for combat to end", function()
	ns.addon:OnSlashCommand("macro")
	scenario.inCombat = true
	ns.Sequence:SyncGameMacro(false) -- e.g. a profile switch landed in combat
	assert(Q.macroPending, "not queued")
	scenario.inCombat = false
	Q.events.PLAYER_REGEN_ENABLED()
	assert(not Q.macroPending)
end)
step("no free character macro slot is reported, not ignored", function()
	scenario.macros = {}
	for i = 121, 138 do scenario.macros[i] = { name = "x" .. i } end
	ns.addon:OnSlashCommand("macro")
	assert(lastLine():find("no free character macro slot"), lastLine())
	scenario.macros = {}
end)
step("over-long macros are refused with the length", function()
	local saved = Q.MACRO_LIMIT
	Q.MACRO_LIMIT = 40
	ns.addon:OnSlashCommand("macro")
	Q.MACRO_LIMIT = saved
	assert(lastLine():find("characters; the game allows 40"), lastLine())
	assert(next(scenario.macros) == nil, "wrote an over-long macro")
end)
step("selftest with sequence section", function() ns.SelfTest:Run() end)

realPrint("\nNative bar (M8):")
local N = ns.NativeBar
local function sync(i) return FRAMES["TotemicAccordSync" .. i] end
local SLOT = { earth = 146, fire = 145, water = 147, air = 148 } -- (13-1)*12 + TOTEM_SLOT
step("four hidden sync buttons: multispell, ID 0, act on key-up", function()
	for i, key in ipairs({ "earth", "fire", "water", "air" }) do
		local b = sync(i)
		assert(b and not b._shown, "TotemicAccordSync" .. i)
		assert(b:GetAttribute("type") == "multispell" and b:GetAttribute("useOnKeyDown") == false)
		assert(b:GetID() == 0, "an ID would make CalculateAction ignore the action attribute")
		assert(b:GetAttribute("action") == SLOT[key], key .. " slot " .. tostring(b:GetAttribute("action")))
	end
end)
step("sync buttons carry the applied profile's totems; empty element -> 0 (clear)", function()
	ns.addon:OnSlashCommand("set air none")
	assert(sync(1):GetAttribute("spell") == 8071, tostring(sync(1):GetAttribute("spell"))) -- Stoneskin
	assert(sync(2):GetAttribute("spell") == 3599) -- Searing
	assert(sync(4):GetAttribute("spell") == 0, "air should clear the slot")
	ns.addon:OnSlashCommand("set air Gr")
	assert(sync(4):GetAttribute("spell") == 8177)
end)
step("Auto mode turns the Action button into the Call of the Elements macro at 20", function()
	scenario.knowsCOE = false
	B:Refresh()
	assert(B.actionMode == "seq")
	scenario.knowsCOE = true -- level 20: learned
	B:Refresh() -- SPELLS_CHANGED
	assert(B.actionMode == "cote")
	local want = "#showtooltip Call of the Elements\n/click TotemicAccordSync1\n/click TotemicAccordSync2\n"
		.. "/click TotemicAccordSync3\n/click TotemicAccordSync4\n/cast Call of the Elements"
	local a = btn("Action")
	assert(a:GetAttribute("type") == "macro" and a:GetAttribute("macrotext") == want, a:GetAttribute("macrotext"))
	assert(#want <= 255 and a.text._text == "CotE" and a.count._text == "", "label/counter")
end)
step("one press writes the profile into the native page (emulated multispell)", function()
	scenario.native = {}
	for i = 1, 4 do emulateSyncClick(sync(i)) end
	assert(scenario.native[146] == 8071 and scenario.native[145] == 3599 and scenario.native[148] == 8177)
	assert(scenario.native[147] == 5394, "water")
	assert(G.nativeWritten, "write not recorded")
end)
step("a profile switch re-points the sync buttons; in combat it waits", function()
	ns.addon:OnSlashCommand("save global:dungeon")
	ns.addon:OnSlashCommand("profile global:dungeon")
	ns.addon:OnSlashCommand("set earth EB")
	ns.addon:OnSlashCommand("auto")
	scenario.inCombat = true
	enter("party")
	assert(sync(1):GetAttribute("spell") == 8071, "changed in combat")
	scenario.inCombat = false
	P:OnRegenEnabled()
	N:OnRegenEnabled()
	assert(sync(1):GetAttribute("spell") == 2484, tostring(sync(1):GetAttribute("spell"))) -- Earthbind
	enter("none")
	ns.addon:OnSlashCommand("delete global:dungeon")
end)
step("/ta capture snapshots the native page as the last-fallback profile", function()
	scenario.native = { [146] = 8075, [145] = 1535 } -- Strength of Earth, Fire Nova
	ns.addon:OnSlashCommand("capture")
	assert(G.captured.earth.name == "Strength of Earth Totem" and G.captured.fire.spellID == 1535)
	assert(G.captured.water == nil)
	local saved = G.profiles
	G.profiles = {}
	P:Update("test")
	assert(P.applied == "captured" and btn("Profile").text._text == "DEF\nBAR", tostring(P.applied))
	assert(btn("Earth").totem.name == "Strength of Earth Totem")
	G.profiles = saved
	P:Update("test")
end)
step("an empty native page is reported, not captured", function()
	scenario.native = {}
	ns.addon:OnSlashCommand("capture")
	assert(lastLine():find("empty"), lastLine())
	assert(G.captured.earth, "previous capture was wiped")
end)
step("automatic first-run capture never captures our own writes", function()
	G.captured, G.nativeWritten = {}, false
	scenario.native = { [146] = 8071 }
	N:CaptureIfFirstRun()
	assert(G.captured.earth, "first run should capture the player's own page")
	G.captured, G.nativeWritten = {}, true
	N:CaptureIfFirstRun()
	assert(next(G.captured) == nil, "captured a page we had written")
	scenario.knowsCOE = false
	B:Refresh()
end)

realPrint("\nOptions, import/export, minimap (M9):")
local function opts() return scenario.optionsFn() end
local function opt(tab, key) return opts().args[tab].args[key] end
step("/ta opens the options window; /ta help prints commands; listed in AddOns settings", function()
	scenario.optionsOpened = nil
	ns.addon:OnSlashCommand("")
	assert(scenario.optionsOpened == "TotemicAccord", tostring(scenario.optionsOpened))
	ns.addon:OnSlashCommand("help")
	assert(lastLine():find("/ta"), lastLine())
	assert(scenario.blizOptions == "Totemic Accord")
end)
step("every option's name, getter and value list runs without error", function()
	local count = 0
	local function walk(node)
		for _, field in ipairs({ "name", "desc", "values", "get", "hidden", "disabled", "sorting" }) do
			if type(node[field]) == "function" then node[field]({}) ; count = count + 1 end
		end
		for _, child in pairs(node.args or {}) do walk(child) end
	end
	walk(opts())
	assert(count > 40, "only " .. count .. " functions walked")
	local tabs = {}
	for k in pairs(opts().args) do tabs[#tabs + 1] = k end
	table.sort(tabs)
	assert(table.concat(tabs, ",") == "appearance,importexport,profiles,sequence", table.concat(tabs, ","))
end)
step("Profiles tab edits any cell, creates it, and Remove makes it fall back", function()
	ns.Options.editRow, ns.Options.editCol = "global", "bg"
	opt("profiles", "el_earth").set({}, "Earthbind Totem")
	assert(G.profiles["global:bg"] and G.profiles["global:bg"].earth.name == "Earthbind Totem")
	assert(opt("profiles", "el_earth").get({}) == "Earthbind Totem")
	assert(opts().args.profiles.args.matrix.name({}):find("Battleground"))
	opt("profiles", "remove").func()
	assert(G.profiles["global:bg"] == nil)
end)
step("Sequence tab: step selects swap so the order stays a permutation", function()
	opt("sequence", "step1").set({}, "air")
	local order = table.concat(ns.Sequence:Get(P.applied).order, ",")
	assert(order == "air,fire,water,earth", order)
	opt("sequence", "step1").set({}, "earth")
	opt("sequence", "inc_water").set({}, false)
	assert(not ns.Sequence:MacroText():find("Healing"))
	opt("sequence", "inc_water").set({}, true)
	opt("sequence", "resetSeconds").set({}, 0)
	assert(ns.Sequence:Get(P.applied).resetSeconds == nil, "0 should mean off")
end)
step("Appearance: transparent background and vivid initials (Dio's requests)", function()
	opt("appearance", "barOpacity").set({}, 0)
	assert(B.frame.bg._color[4] == 0, "background not transparent")
	opt("appearance", "barOpacity").set({}, 0.86)
	local earth = btn("Earth")
	local plain = { unpack(earth.bg._color) }
	opt("appearance", "vividInitials").set({}, true)
	assert(earth.bg._color[1] ~= plain[1] or earth.bg._color[2] ~= plain[2], "face not tinted")
	opt("appearance", "vividInitials").set({}, false)
	assert(earth.bg._color[1] == plain[1], "tint not removed")
end)
step("Appearance: action mode is validated and rewrites the Action button", function()
	opt("appearance", "actionMode").set({}, "cote")
	assert(btn("Action"):GetAttribute("macrotext"):find("/cast Call of the Elements"))
	opt("appearance", "actionMode").set({}, "auto")
	assert(not B:Set("actionMode", "bogus"))
end)
step("export -> import round-trips profiles, sequences and settings (real codecs)", function()
	ns.addon:OnSlashCommand("save global:arena")
	ns.addon:OnSlashCommand("seq seconds 30")
	local text = ns.ImportExport:Export()
	assert(text:sub(1, 4) == "TA1:" and #text > 20, text)
	local before = { profiles = G.profiles, seconds = ns.Sequence:Get(P.applied).resetSeconds }
	G.profiles, G.sequences = {}, {}
	G.settings.theme = "mocha"
	scenario.popup = nil
	assert(ns.ImportExport:BeginImport(text), ns.ImportExport.lastError)
	assert(G.profiles.global == nil, "applied before confirming")
	scenario.popup.callback()
	assert(G.profiles["global:arena"] and G.profiles.global.earth.name == before.profiles.global.earth.name)
	assert(ns.Sequence:Get("global").resetSeconds == 30, "sequence lost")
	assert(G.settings.theme == "emerald", "settings not restored: " .. G.settings.theme)
	ns.addon:OnSlashCommand("seq seconds off")
	ns.addon:OnSlashCommand("delete global:arena")
end)
step("broken, foreign or tampered strings are rejected with a reason, nothing changed", function()
	local snapshot = G.profiles
	assert(not ns.ImportExport:BeginImport("hello"))
	assert(ns.ImportExport.lastError:find("TA1:"), ns.ImportExport.lastError)
	local good = ns.ImportExport:Export()
	assert(not ns.ImportExport:BeginImport(good:sub(1, #good - 12)))
	assert(ns.ImportExport.lastError:find("damaged"), ns.ImportExport.lastError)
	local LS, LD = LibStub("LibSerialize"), LibStub("LibDeflate")
	local evil = "TA1:" .. LD:EncodeForPrint(LD:CompressDeflate(LS:Serialize({ v = 1,
		profiles = { global = { earth = { name = 42 } } } })))
	assert(not ns.ImportExport:BeginImport(evil))
	assert(ns.ImportExport.lastError:find("malformed"), ns.ImportExport.lastError)
	assert(G.profiles == snapshot, "state changed by a failed import")
end)
step("loadout profiles are matched to the importer's loadouts by NAME", function()
	local LS, LD = LibStub("LibSerialize"), LibStub("LibDeflate")
	local payload = { v = 1, loadoutNames = { [7001] = "Resto", [7002] = "Elemental PvP" },
		profiles = { ["L7001:dungeon"] = { earth = { spellID = 8071, name = "Stoneskin Totem" } },
			["L7002:bg"] = { fire = { spellID = 3599, name = "Searing Totem" } } } }
	local text = "TA1:" .. LD:EncodeForPrint(LD:CompressDeflate(LS:Serialize(payload)))
	local result = ns.ImportExport:Decode(text)
	assert(result.profiles["L102:dungeon"], "Resto should map to this character's 102")
	assert(result.count == 1 and result.skipped == 1, result.count .. "/" .. result.skipped)
end)
step("minimap: left opens options, right opens the profile menu, shift-left locks", function()
	assert(scenario.dbicon and scenario.dbicon.db == G.settings.minimap, "LibDBIcon not registered")
	local onClick = scenario.broker.OnClick
	scenario.optionsOpened = nil
	onClick(UIParent, "LeftButton")
	assert(scenario.optionsOpened == "TotemicAccord")
	scenario.menu = nil
	onClick(UIParent, "RightButton")
	assert(scenario.menu and scenario.menu[2].text:find("^Auto"), "profile menu not opened")
	local was = G.settings.locked
	scenario.shift = true
	onClick(UIParent, "LeftButton")
	scenario.shift = false
	assert(G.settings.locked ~= was, "shift-click did not toggle the lock")
	ns.Bar:SetLocked(was)
end)
step("minimap tooltip names the profile, auto/manual and the three click hints", function()
	local lines = {}
	scenario.broker.OnTooltipShow({ AddLine = function(_, t) lines[#lines + 1] = t end })
	local text = table.concat(lines, "|")
	assert(text:find("Totemic Accord") and text:find("Global default") and text:find("Automatic"), text)
	assert(text:find("Left%-click") and text:find("Right%-click") and text:find("Shift"), text)
end)
step("/ta minimap toggles the button (whatever state it starts in)", function()
	local before = G.settings.minimap.hide
	ns.addon:OnSlashCommand("minimap")
	assert(G.settings.minimap.hide == not before and scenario.iconShown == before, "first toggle")
	ns.addon:OnSlashCommand("minimap")
	assert(G.settings.minimap.hide == before and scenario.iconShown == not before, "second toggle")
	ns.Minimap:SetShown(true)
end)
step("addon compartment handlers: click and hover work", function()
	scenario.optionsOpened = nil
	TotemicAccord_OnAddonCompartmentClick("TotemicAccord", "LeftButton")
	assert(scenario.optionsOpened == "TotemicAccord")
	TotemicAccord_OnAddonCompartmentEnter("TotemicAccord", UIParent)
	TotemicAccord_OnAddonCompartmentLeave("TotemicAccord", UIParent)
end)
step("the profile name under the bar is hidden by default; the toggle shows it", function()
	B:Refresh()
	assert(not B.frame.label._shown, "label shown by default")
	opt("appearance", "profileLabel").set({}, true)
	assert(B.frame.label._shown)
	opt("appearance", "profileLabel").set({}, false)
	assert(not B.frame.label._shown)
end)
step("Create makes the selected cell from the bar; disabled once it exists", function()
	ns.Options.editRow, ns.Options.editCol = "global", "raid"
	local create = opt("profiles", "create")
	assert(not create.disabled({}) and create.name({}) == "Create")
	create.func()
	assert(G.profiles["global:raid"] and create.disabled({}), "not created")
	assert(create.name({}) == "Already exists", "a greyed-out Create must say why")
	opt("profiles", "remove").func()
end)
step("per-button key capture: bind, replace (with a note), clear, refused in combat", function()
	local earth = opt("appearance", "bind_earth")
	scenario.bindingActions["ALT-1"] = "ACTIONBUTTON1"
	scenario.bindings["ACTIONBUTTON1"] = "ALT-1"
	earth.set({}, "ALT-1")
	assert(earth.get({}) == "ALT-1" and scenario.bindingActions["ALT-1"] == "CLICK TotemicAccordEarth:LeftButton")
	assert(lastLine():find("was bound to"), lastLine())
	earth.set({}, "ALT-2")
	assert(earth.get({}) == "ALT-2" and scenario.bindingActions["ALT-1"] == nil, "old key not released")
	earth.set({}, "")
	assert(earth.get({}) == "", "not cleared")
	scenario.inCombat = true
	earth.set({}, "ALT-3")
	scenario.inCombat = false
	assert(earth.get({}) == "", "bound in combat")
	assert(opt("appearance", "bind_recall") and opt("appearance", "bind_profile"), "missing controls")
end)
step("the profile menu has 'Edit profiles...', opening the options on that tab", function()
	btn("Profile")._scripts.OnClick(btn("Profile"))
	local last = scenario.menu[#scenario.menu]
	assert(last.kind == "button" and last.text == "Edit profiles...", last.text)
	scenario.optionsOpened, scenario.optionsTab = nil, nil
	last.select()
	assert(scenario.optionsOpened == "TotemicAccord" and scenario.optionsTab == "profiles")
end)
realPrint("\nActive totem outline (M10):")
local function lit(n) return btn(n).activeBorder.TOP._shown == true end
step("the outline shows while the button's own totem is down, in the accent colour", function()
	ns.addon:OnSlashCommand("set earth SS")
	scenario.activeTotem = {}
	B:UpdateActive()
	assert(not lit("Earth"), "lit with nothing down")
	scenario.activeTotem[EARTH_TOTEM_SLOT] = 8071 -- Stoneskin
	assert(B.events.PLAYER_TOTEM_UPDATE == "UpdateActive", "not listening for totem updates")
	B:UpdateActive("PLAYER_TOTEM_UPDATE", EARTH_TOTEM_SLOT)
	assert(lit("Earth"), "Stoneskin down but Earth not outlined")
	assert(not lit("Fire") and not btn("Action").activeBorder, "only element buttons, only when down")
	local accent = { ns.Themes.RGB(ns.Themes:Current().accent) }
	assert(btn("Earth").activeBorder.LEFT._color[1] == accent[1], "not the accent colour")
end)
step("a different totem of that element does not light the button", function()
	scenario.activeTotem[EARTH_TOTEM_SLOT] = 2484 -- Earthbind, button shows Stoneskin
	B:UpdateActive()
	assert(not lit("Earth"))
end)
step("a theme switch keeps the outline, recoloured", function()
	scenario.activeTotem[EARTH_TOTEM_SLOT] = 8071
	B:UpdateActive()
	ns.Themes:Set("mocha")
	local accent = { ns.Themes.RGB(ns.Themes:Current().accent) }
	assert(lit("Earth") and btn("Earth").activeBorder.TOP._color[1] == accent[1])
	ns.Themes:Set("emerald")
end)
step("switching the profile's totem re-checks the outline", function()
	ns.addon:OnSlashCommand("set earth EB")
	assert(not lit("Earth"), "still lit after the button changed to Earthbind")
	ns.addon:OnSlashCommand("set earth SS")
	assert(lit("Earth"))
end)
step("in combat (secret slots) the last known state is kept", function()
	scenario.inCombat = true
	issecretvalue = function() return true end
	scenario.activeTotem = {}
	B:UpdateActive()
	assert(lit("Earth"), "lost the state on a secret read")
end)
step("in combat, casts move the outline: other earth totem off, own totem on", function()
	assert(B.events.UNIT_SPELLCAST_SUCCEEDED == "OnSpellcast")
	issecretvalue = function() return false end -- the cast's spell ID is readable
	B:OnSpellcast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2484) -- Earthbind
	assert(not lit("Earth"), "Earthbind replaced Stoneskin")
	B:OnSpellcast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 3599) -- Searing: fire
	assert(not lit("Earth"), "a fire cast changed earth")
	B:OnSpellcast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 8071)
	assert(lit("Earth"), "own totem cast not lit")
	B:OnSpellcast("UNIT_SPELLCAST_SUCCEEDED", "party1", "guid", 2484)
	assert(lit("Earth"), "someone else's cast counted")
	issecretvalue = function() return true end
	B:OnSpellcast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2484)
	assert(lit("Earth"), "a secret spell ID was used")
	issecretvalue = function() return false end
end)
step("when combat ends the real slot data corrects it", function()
	scenario.inCombat = false
	scenario.activeTotem = {} -- expired during the fight
	B:OnRegenEnabled()
	assert(not lit("Earth"), "stale outline after combat")
end)

realPrint("\nHide the default totem bar:")
local function nativeHidden()
	local parent = MultiCastActionBarFrame:GetParent()
	return parent ~= UIParent and parent ~= nil and not parent:IsShown()
end
step("off by default: the game's totem bar keeps its parent", function()
	assert(MultiCastActionBarFrame:GetParent() == UIParent, "moved without being asked")
end)
step("the option hides it by reparenting to a hidden frame, and shows it again", function()
	local o = opt("appearance", "hideNativeBar")
	assert(o and o.get() == false, "option missing or not off")
	o.set(nil, true)
	assert(nativeHidden(), "not hidden")
	o.set(nil, false)
	assert(MultiCastActionBarFrame:GetParent() == UIParent, "not restored to UIParent")
end)
step("in combat the change waits until combat ends", function()
	local o = opt("appearance", "hideNativeBar")
	scenario.inCombat = true
	o.set(nil, true)
	assert(MultiCastActionBarFrame:GetParent() == UIParent, "reparented in combat")
	scenario.inCombat = false
	ns.NativeBar:OnRegenEnabled()
	assert(nativeHidden(), "not applied after combat")
	o.set(nil, false)
end)

realPrint("\nRound 3 (spacing, clear keys, Latte):")
step("button spacing 0-8 moves the buttons; out of range is refused", function()
	B:Set("layout", "horizontal")
	B:Set("buttonSpacing", 0)
	assert((topleft(btn("Fire"))) == 6 + 44, tostring((topleft(btn("Fire")))))
	B:Set("buttonSpacing", 8)
	assert((topleft(btn("Fire"))) == 6 + 44 + 8)
	assert(not B:Set("buttonSpacing", 12) and not B:Set("buttonSpacing", -1))
	B:Set("buttonSpacing", 6)
end)
step("applying suggested keybinds redraws the options window", function()
	scenario.bindingActions, scenario.bindings = {}, {}
	local before = scenario.notified
	ns.addon:OnSlashCommand("keys")
	scenario.popup.callback()
	assert(scenario.notified > before, "options not refreshed")
	assert(opt("appearance", "bind_earth").get({}) == "ALT-SHIFT-Q")
end)
step("clear all keybinds asks first, then unbinds all seven", function()
	scenario.popup = nil
	ns.addon:OnSlashCommand("keys clear")
	assert(scenario.popup and next(scenario.bindings) ~= nil, "cleared without asking")
	scenario.popup.callback()
	assert(next(scenario.bindings) == nil, "keys left bound")
	assert(lastLine():find("Cleared 5"), lastLine())
	scenario.inCombat = true
	assert(not ns.Keybinds:ClearAll())
	scenario.inCombat = false
end)
step("Latte is gone; a saved 'latte' falls back to Emerald", function()
	assert(not ns.Themes.LIST.latte and not ns.Themes:Set("latte"))
	G.settings.theme = "latte"
	ns.addon:MigrateSettings()
	assert(G.settings.theme == "emerald")
end)
step("selftest: every check implemented, nothing pending", function()
	local before = #output
	ns.SelfTest:Run()
	for i = before + 1, #output do
		assert(not output[i]:find("%.%.%.%."), "still pending: " .. output[i])
	end
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
	for _, f in ipairs({ "Locales/enUS.lua", "Core.lua", "Data.lua", "Themes.lua", "Keybinds.lua", "Bar.lua", "Flyout.lua", "Sequence.lua", "Profiles.lua", "NativeBar.lua", "ImportExport.lua", "Options.lua", "Minimap.lua", "SelfTest.lua" }) do
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
