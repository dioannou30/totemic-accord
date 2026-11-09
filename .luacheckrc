-- Totemic Accord -- luacheck configuration
--
-- WoW runs Lua 5.1, so that is the standard library we lint against.
--
-- The WoW API surface is NOT hardcoded here. tools/check_api.py extracts it from
-- Blizzard's own UI source for Forever and writes tools/wow_globals.lua; this file
-- loads that. So "does this function exist on Forever?" has exactly one source of
-- truth, and luacheck -- which understands real Lua scoping, unlike a regex -- is
-- what enforces it.
--
-- Regenerate the list with:
--     python tools/check_api.py --emit-luacheck tools/wow_globals.lua
-- tools/check.ps1 / check.sh do this for you.
--
-- Paths below are relative to the repo root, so run luacheck from there.

std = "lua51"

-- Our own deliberate globals. Everything else of ours must be local or live on the
-- addon object; this list is short on purpose (build prompt section 7).
globals = {
	"TotemicAccord",
	"TotemicAccordDB",
	"TotemicAccordCharDB",
	-- TOC AddonCompartment handlers have to be globals -- the only allowed extras.
	"TotemicAccord_OnAddonCompartmentClick",
	"TotemicAccord_OnAddonCompartmentEnter",
	"TotemicAccord_OnAddonCompartmentLeave",
	-- Referenced from Bindings.xml
	"BINDING_HEADER_TOTEMICACCORD",
}

-- The generated Forever API surface.
local generated = {}
local ok, api = pcall(dofile, "tools/wow_globals.lua")
if ok and type(api) == "table" and api.globals then
	generated = api.globals
	-- C_ namespaces as read-only tables with exactly the fields Forever documents,
	-- so e.g. C_Spell.NoSuchFunction() is caught rather than silently accepted.
	for ns, fields in pairs(api.namespaces or {}) do
		local entry = { fields = {} }
		for _, field in ipairs(fields) do
			entry.fields[field] = {}
		end
		generated[ns] = entry
	end
else
	-- No generated list (fresh clone with no reference/ yet). Fall back to a small
	-- curated set so luacheck still runs instead of flagging every API call.
	-- The check scripts warn when this path is taken.
	generated = {
		"CreateFrame", "UIParent", "InCombatLockdown", "GetTime", "print",
		"GetBuildInfo", "UnitClass", "UnitName", "IsInInstance", "GetInstanceInfo",
		"GetSpecialization", "GetSpecializationInfo", "IsPlayerSpell", "IsSpellKnown",
		"GetTotemInfo", "GetTotemTimeLeft", "GetTotemDuration", "GetNumTotemSlots",
		"GetMultiCastTotemSpells", "SetMultiCastSpell", "DestroyTotem",
		"EARTH_TOTEM_SLOT", "FIRE_TOTEM_SLOT", "WATER_TOTEM_SLOT", "AIR_TOTEM_SLOT",
		"MAX_TOTEMS", "SHAMAN_TOTEM_PRIORITIES",
		"TOTEM_MULTI_CAST_SUMMON_SPELLS", "TOTEM_MULTI_CAST_RECALL_SPELLS",
		"CreateMacro", "EditMacro", "GetMacroIndexByName",
		"SetBinding", "SaveBindings", "GetBindingKey", "GetBindingText",
		"SendAddonMessage", "RegisterAddonMessagePrefix",
		"hooksecurefunc", "PixelUtil", "GameTooltip", "LibStub", "Enum",
		"C_Spell", "C_Timer", "C_AddOns", "C_SpecializationInfo",
		"strsplit", "strjoin", "strtrim", "tinsert", "tremove", "wipe",
		"format", "gsub", "strupper", "strlower", "max", "min", "floor", "ceil",
		"abs", "mod", "sort", "bit", "Mixin", "CreateFromMixins", "securecall",
	}
end

read_globals = generated

-- Vendored libraries are not ours to lint.
exclude_files = {
	"TotemicAccord/Libs/**",
	"reference/**",
	"tools/wow_globals.lua",
}

-- Blizzard-style code and long macro/locale strings make a hard column limit noise.
max_line_length = false

-- Unused self in methods is idiomatic here.
self = false
