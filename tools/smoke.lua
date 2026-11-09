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
local scenario = { class = "SHAMAN", spec = 2, instance = "none", knowsCOE = true }

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
			Interface = "16001",
		}
		return meta[field]
	end,
}

C_Spell = {
	GetSpellInfo = function(idOrName)
		if idOrName == 66842 then return { name = "Call of the Elements", spellID = 66842 } end
		if idOrName == "Totemic Projection" then
			return { name = "Totemic Projection", spellID = 108287 }
		end
		return nil
	end,
}

function UnitClass() return "Shaman", scenario.class end
function GetBuildInfo() return "1.60.1", "70862", "Nov 7 2026", 16001 end
function GetSpecialization() return scenario.spec end
function GetSpecializationInfo(i)
	local t = { [1] = { 262, "Elemental" }, [2] = { 263, "Enhancement" }, [3] = { 264, "Restoration" } }
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

-- non-Shaman path, with a completely fresh namespace
realPrint("\nNon-Shaman character:")
scenario.class = "WARRIOR"
local ns2 = {}
local addon2
step("load + OnInitialize as a Warrior", function()
	for _, f in ipairs({ "Locales/enUS.lua", "Core.lua", "SelfTest.lua" }) do
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
