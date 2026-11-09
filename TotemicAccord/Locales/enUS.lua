--[[
	Locales/enUS.lua -- every user-facing string lives here (build prompt section 7).

	Nothing else in the addon should contain a sentence shown to the player. Adding a
	language later means adding a sibling file and a lookup, not hunting strings.

	Access as ns.L.KEY. Missing keys fall back to the key name itself, so a typo shows
	up as SHOUTY_TEXT in game instead of a nil error mid-fight.
]]

local _, ns = ...

local L = {}

-- Chat / general
L.CHAT_PREFIX = "[Totemic Accord]"
L.SLASH_HELP_HEADER = "Commands:"
L.LOADED = "loaded. Type /ta for options."
L.NOT_SHAMAN = "Totemic Accord is for Shamans; staying out of the way on this character."

-- Slash command descriptions
L.CMD_OPTIONS = "/ta - open options"
L.CMD_LOCK = "/ta lock - lock the bar in place"
L.CMD_UNLOCK = "/ta unlock - unlock the bar so it can be dragged"
L.CMD_AUTO = "/ta auto - return to automatic profile switching"
L.CMD_PROFILE = "/ta profile <key> - pin a profile"
L.CMD_CAPTURE = "/ta capture - capture the native totem bar as the global default"
L.CMD_MACRO = "/ta macro - create or update the 'TA Sequence' game macro"
L.CMD_MINIMAP = "/ta minimap - toggle the minimap button"
L.CMD_DEBUG = "/ta debug - toggle verbose logging"
L.CMD_SELFTEST = "/ta selftest - run diagnostics"
L.CMD_UNKNOWN = "Unknown command: %s"

-- Debug
L.DEBUG_ON = "Debug logging ON."
L.DEBUG_OFF = "Debug logging OFF."

-- Self-test
L.SELFTEST_HEADER = "Self-test"
L.SELFTEST_PASS = "PASS"
L.SELFTEST_FAIL = "FAIL"
L.SELFTEST_INFO = "INFO"
L.SELFTEST_SUMMARY = "%d passed, %d failed."
L.SELFTEST_NOT_IMPLEMENTED = "not implemented yet (milestone %s)"

L.TEST_ACE3 = "Ace3 loaded"
L.TEST_CLASS = "Class is Shaman"
L.TEST_SPEC = "Spec detection"
L.TEST_INSTANCE = "Instance type readable"
L.TEST_INTERFACE = "Interface version"
L.TEST_SAVEDVARS = "Saved variables ready"
L.TEST_TOTEM_SPELLS = "Totem spell lists per element"
L.TEST_PROFILE_SPELLS = "Profile spells are known"
L.TEST_ABBREVIATIONS = "Abbreviations unique per element"
L.TEST_CALL_OF_ELEMENTS = "Call of the Elements"
L.TEST_PROJECTION = "Totemic Projection"
L.TEST_SECURE_BUTTONS = "Secure buttons and attributes"
L.TEST_MACRO_LENGTH = "Sequence macro under 255 characters"
L.TEST_MINIMAP = "Minimap button registered"
L.TEST_COMPARTMENT = "Addon compartment entry"

-- Combat guards
L.COMBAT_NO_TOTEM_CHANGE = "Can't change totems in combat."
L.COMBAT_QUEUED = "In combat - queued, will apply when combat ends."

ns.L = setmetatable(L, {
	-- A missing string should be obvious but harmless, never a nil concatenation error.
	__index = function(_, key)
		return key
	end,
})
