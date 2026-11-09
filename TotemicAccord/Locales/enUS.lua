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
L.LOADED = "loaded. Type /ta for commands."
L.NOT_SHAMAN = "Totemic Accord is for Shamans; staying out of the way on this character."

-- Slash command descriptions
L.CMD_OPTIONS = "/ta - this help (an options window arrives in M9)"
L.CMD_LOCK = "/ta lock - lock the bar in place"
L.CMD_UNLOCK = "/ta unlock - unlock the bar so it can be dragged"
L.CMD_AUTO = "/ta auto - return to automatic profile switching"
L.CMD_PROFILE = "/ta profile <key> - pin a profile until /ta auto"
L.CMD_CAPTURE = "/ta capture - capture the native totem bar as the global default"
L.CMD_MACRO = "/ta macro - create or update the 'TA Sequence' game macro"
L.CMD_MINIMAP = "/ta minimap - toggle the minimap button"
L.CMD_THEME = "/ta theme <emerald|tokyo|mocha|latte|classic>"
L.CMD_LAYOUT = "/ta layout <horizontal|vertical|grid>"
L.CMD_STYLE = "/ta style <initials|icons>"
L.CMD_SCALE = "/ta scale <0.5-2>"
L.CMD_EMPTY = "/ta empty <grey|hide> - what an element with no totem shows"
L.CMD_FLYOUT = "/ta flyout <up|down|left|right> - which way the totem chooser opens"
L.CMD_ARROWS = "/ta arrows <on|off> - arrow tabs on the element buttons (right-click works either way)"
L.TIP_RIGHT_CLICK = "Right-click: choose a totem"
L.FLYOUT_NONE = "No totem - leave this element empty"
L.CMD_RESET = "/ta reset - move the bar back to the centre"
L.CMD_KEYS = "/ta keys - apply the suggested keybinds (asks first)"
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

-- Bar (M3)
L.THEME_EMERALD = "Emerald"
L.THEME_EMERALD_DESC = "Flat and dark with a green accent; pairs well with EllesmereUI."
L.THEME_TOKYO = "Tokyo Night"
L.THEME_MOCHA = "Catppuccin Mocha"
L.THEME_LATTE = "Catppuccin Latte"
L.THEME_CLASSIC = "Blizzard classic"
L.ACTION_COTE = "CotE"
L.ACTION_SEQ = "Seq"
L.PROJECTION_SHORT = "TP"
L.PROFILE_CODE_GLOBAL = "ALL\nDEF"
L.EMPTY_SLOT = "-"
L.EMPTY_EARTH = "No earth totem"
L.EMPTY_FIRE = "No fire totem"
L.EMPTY_WATER = "No water totem"
L.EMPTY_AIR = "No air totem"
L.TIP_ACTION_COTE = "Call of the Elements"
L.TIP_ACTION_SEQ = "Totem sequence"
L.TIP_PROJECTION = "Totemic Projection"
L.TIP_PROJECTION_UNKNOWN = "Totemic Projection (not learned yet)"
L.TIP_PROFILE = "Choose profile"
L.BAR_PREVIEW = "Preview - first known totems (profiles arrive in M5)"
L.MOVER_HINT = "Drag to move - /ta lock when done"
L.BAR_LOCKED = "Bar locked."
L.BAR_UNLOCKED = "Bar unlocked - drag it, then /ta lock."
L.BAR_RESET = "Bar position reset."
L.SETTING_SET = "%s set to %s."
L.SETTING_INVALID = "Invalid %s. Choose from: %s"

-- Keybinds (M4)
L.BIND_HEADER = "Totemic Accord"
L.BIND_EARTH = "Cast Earth totem"
L.BIND_FIRE = "Cast Fire totem"
L.BIND_WATER = "Cast Water totem"
L.BIND_AIR = "Cast Air totem"
L.BIND_ACTION = "Action (Call of the Elements / sequence)"
L.BIND_PROJECTION = "Totemic Projection"
L.BIND_PROFILE = "Open profile chooser"
L.KEYS_CONFIRM = "Apply the suggested Totemic Accord keybinds?\n\n%s"
L.KEYS_CONFIRM_REPLACES = "This replaces:\n%s"
L.KEYS_CONFIRM_NOTHING = "Nothing else is bound to these keys."
L.KEYS_ACCEPT = "Apply"
L.KEYS_APPLIED = "Suggested keybinds applied: %s"
L.KEYS_ALREADY = "The suggested keybinds are already set."
L.KEYS_COMBAT = "Can't change keybinds in combat."

-- Profiles (M5)
L.SIT_WORLD = "Open world"
L.SIT_DUNGEON = "Dungeon"
L.SIT_RAID = "Raid"
L.SIT_BG = "Battleground"
L.SIT_ARENA = "Arena"
L.PROFILE_NONE = "No profile yet"
L.PROFILE_GLOBAL = "Global"
L.PROFILE_GLOBAL_DEFAULT = "Global default"
L.PROFILE_CAPTURED = "Captured default bar"
L.PROFILE_LOADOUT = "Loadout %s"
L.PROFILE_X_DEFAULT = "%s · Default"
L.PROFILE_X_SIT = "%s · %s"
L.PROFILE_SWITCHED = "Profile: %s"
L.PROFILE_QUEUED = "In combat - switching to %s when combat ends."
L.PROFILE_PINNED = "Pinned %s until /ta auto."
L.PROFILE_SAVED = "Saved %s."
L.PROFILE_DELETED = "Removed %s."
L.PROFILE_MISSING = "No such profile: %s"
L.PROFILE_BAD_KEY = "Unknown profile key '%s'. Use global, global:<situation>, loadout, loadout:<situation> (situations: world, dungeon, raid, bg, arena)."
L.PROFILE_AUTO_ON = "Automatic switching on (now: %s)."
L.PROFILE_LIST_HEADER = "Using %s (%s). Resolution order here:"
L.TIP_AUTO = "Automatic"
L.TIP_MANUAL = "Pinned manually - /ta auto to resume"
L.TIP_QUEUED = "Switching to %s after combat"
L.MENU_TITLE = "Totemic Accord profile"
L.MENU_AUTO = "Auto (currently: %s)"
L.MENU_GENERAL = "General"
L.SET_USAGE = "Usage: /ta set <earth|fire|water|air> <code, name or none>"
L.SET_UNKNOWN = "No known %s totem matches '%s'."
L.SET_DONE = "%s: %s in %s."
L.CMD_PROFILES = "/ta profiles - list the resolution order and which profiles exist"
L.CMD_SAVE = "/ta save <key> - save the bar's current totems as a profile"
L.CMD_DELETE = "/ta delete <key> - remove a profile so it falls back"
L.CMD_SET = "/ta set <element> <code|none> - change a totem in the current profile"
L.CMD_MESSAGE = "/ta message <on|off> - on-screen message when the profile switches"

-- Sequences (M7)
L.CMD_SEQ = "/ta seq [order e,f,w,a | skip <element> | use <element> | combat on|off | seconds <n|off>]"
L.SEQ_USAGE = "Usage: /ta seq order earth,fire,water,air | skip <element> | use <element> | combat on|off | seconds <1-600|off>"
L.SEQ_HEADER = "Sequence for %s (%d/%d characters):"
L.SEQ_EMPTY = "(nothing to cast - no included element has a totem)"
L.MACRO_TOO_LONG = "Sequence macro is %d characters; the game allows %d. Include fewer totems."
L.MACRO_EMPTY_BODY = "#showtooltip\n/run print(\"TA Sequence: the current profile has no totems in its sequence.\")"
L.MACRO_CREATED = "Created the character macro '%s' - drag it from the Macros window to any bar. It follows your profile."
L.MACRO_UPDATED = "Updated the character macro '%s'."
L.MACRO_NO_SLOT = "Couldn't create the macro: no free character macro slot."
L.TEST_SEQUENCE = "Sequence"
L.TEST_GAME_MACRO = "Game macro 'TA Sequence'"

-- Native bar (M8)
L.CAPTURED_FIRST_RUN = "Captured your native totem bar (%d element(s)) as the last-resort profile."
L.CAPTURE_DONE = "Captured the native totem bar (%d element(s)) as the 'Captured default bar' profile."
L.CAPTURE_EMPTY = "The native totem bar's Call of the Elements page is empty - nothing to capture."
L.TEST_NATIVE_SYNC = "Native bar sync buttons"
L.TEST_CAPTURED = "Captured default bar"

-- Combat guards
L.COMBAT_NO_TOTEM_CHANGE = "Can't change totems in combat."
L.COMBAT_QUEUED = "In combat - queued, will apply when combat ends."

ns.L = setmetatable(L, {
	-- A missing string should be obvious but harmless, never a nil concatenation error.
	__index = function(_, key)
		return key
	end,
})
