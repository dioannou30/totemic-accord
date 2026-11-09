--[[
	Core.lua -- addon object, lifecycle, saved variables, slash commands, logging.

	WoW calls every addon Lua file with (addonFolderName, privateTable), so ADDON below
	is the folder name and ns is a table shared by all our files. That makes the folder
	the single source of truth for the name; the display name and version are read back
	out of the TOC with C_AddOns.GetAddOnMetadata rather than duplicated here.
]]

local ADDON, ns = ...
local L = ns.L

local AceAddon = LibStub("AceAddon-3.0")
local AceDB = LibStub("AceDB-3.0")

-- AceAddon mixes in the AceConsole and AceEvent methods we ask for here.
local addon = AceAddon:NewAddon(ADDON, "AceConsole-3.0", "AceEvent-3.0")
ns.addon = addon

-- Exposed as a global purely so it can be poked at in game (/dump TotemicAccord).
-- Declared in .luacheckrc and tools/check_api.py as one of our few allowed globals.
_G[ADDON] = addon

-- ---------------------------------------------------------------- identity

addon.ADDON_NAME = ADDON
addon.DISPLAY_NAME = C_AddOns.GetAddOnMetadata(ADDON, "Title") or ADDON
addon.VERSION = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "0.0.0"

-- ---------------------------------------------------------------- saved variables
--[[
	Two saved-variable tables, as the build prompt specifies:
	  TotemicAccordCharDB  per character -- profiles, sequences, captured bar, settings
	  TotemicAccordDB      account-wide  -- things worth sharing across characters

	A note on shape: AceDB always nests data under a scope key, so the per-character
	data lives at TotemicAccordCharDB.global rather than at the top level as sketched
	in the build prompt. "global" is AceDB's name for "unscoped", and since the file
	itself is already per-character that is exactly this character's data. We take
	AceDB's defaults and migration machinery in exchange for one level of nesting.

	AceDB's own "profile" concept is deliberately unused -- our profiles are totem sets
	keyed by spec and situation, and overloading the word would be a trap later.
]]

local CHAR_DEFAULTS = {
	global = {
		version = 1,
		profiles = {},   -- ["<spec>:<situation>"] = { earth=, fire=, water=, air= }
		sequences = {},  -- ["<profile key>"]      = { order=, include=, reset... }
		captured = {},   -- snapshot of the native Call of the Elements page
		manual = nil,    -- a profile key while manually pinned, else nil
		learnedElements = {}, -- ["<totem spell name>"] = "earth" etc., seen via GetTotemInfo
		settings = {
			theme = "emerald",
			buttonStyle = "initials",
			layout = "horizontal",
			flyoutDir = "up",
			emptySlot = "grey",
			actionMode = "auto",
			scale = 1,
			locked = false,
			point = nil,
			showSwitchMessage = true,
			debug = false,
			minimap = { hide = false },
		},
	},
}

local ACCOUNT_DEFAULTS = {
	global = {
		version = 1,
	},
}

-- ---------------------------------------------------------------- logging

local PREFIX = "|cff0cd29d" .. L.CHAT_PREFIX .. "|r "

function addon:Log(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or fmt
	print(PREFIX .. msg)
end

--- Verbose logging, off unless /ta debug turned it on.
function addon:Debug(fmt, ...)
	if not (self.db and self.db.global.settings.debug) then
		return
	end
	local msg = select("#", ...) > 0 and fmt:format(...) or fmt
	print(PREFIX .. "|cff8a929c" .. msg .. "|r")
end

-- ---------------------------------------------------------------- lifecycle

function addon:OnInitialize()
	-- Shaman-only, and quiet about it on other characters: no bar, no spam, no events.
	-- SetEnabledState(false) means OnEnable never runs, so nothing else has to re-check.
	local _, class = UnitClass("player")
	self.playerClass = class
	if class ~= "SHAMAN" then
		self:SetEnabledState(false)
		self.disabledReason = "notShaman"
		-- Quiet means no unsolicited output, not stonewalling: /ta still answers,
		-- so a non-Shaman who types it learns why nothing is happening.
		self:RegisterChatCommand("ta", "OnSlashCommandDisabled")
		self:RegisterChatCommand("totemicaccord", "OnSlashCommandDisabled")
		return
	end

	self.charDB = AceDB:New("TotemicAccordCharDB", CHAR_DEFAULTS)
	self.accountDB = AceDB:New("TotemicAccordDB", ACCOUNT_DEFAULTS)
	-- self.db is the per-character data: that is what almost everything wants.
	self.db = self.charDB

	self:RegisterChatCommand("ta", "OnSlashCommand")
	self:RegisterChatCommand("totemicaccord", "OnSlashCommand")
end

function addon:OnEnable()
	ns.Data:Init()
	ns.Bar:Init()
	ns.Profiles:Init()
	self:Debug("OnEnable: %s %s, interface %s", self.DISPLAY_NAME, self.VERSION,
		tostring(select(4, GetBuildInfo())))
	self:Log("%s %s " .. L.LOADED, self.DISPLAY_NAME, self.VERSION)
end

-- ---------------------------------------------------------------- slash commands

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Milestones that have not landed yet answer honestly rather than doing nothing.
function addon:NotYet(milestone)
	self:Log(L.SELFTEST_NOT_IMPLEMENTED, milestone)
end

function addon:PrintHelp()
	self:Log(L.SLASH_HELP_HEADER)
	for _, line in ipairs({
		L.CMD_OPTIONS, L.CMD_LOCK, L.CMD_UNLOCK, L.CMD_THEME, L.CMD_LAYOUT, L.CMD_STYLE,
		L.CMD_SCALE, L.CMD_EMPTY, L.CMD_RESET, L.CMD_KEYS, L.CMD_AUTO, L.CMD_PROFILE,
		L.CMD_PROFILES, L.CMD_SAVE, L.CMD_DELETE, L.CMD_SET, L.CMD_MESSAGE,
		L.CMD_CAPTURE, L.CMD_MACRO, L.CMD_MINIMAP, L.CMD_DEBUG, L.CMD_SELFTEST,
	}) do
		print("  " .. line)
	end
end

--- /ta profile|save|delete <key>
function addon:ProfileCommand(cmd, rest)
	local P = ns.Profiles
	local key = P:NormalizeKey(rest)
	if not key then
		self:Log(L.PROFILE_BAD_KEY, rest)
		return
	end
	local ok
	if cmd == "profile" then
		ok = P:Pin(key)
	elseif cmd == "save" then
		ok = P:SaveAs(key)
	else
		ok = P:Delete(key)
	end
	local msg = cmd == "profile" and L.PROFILE_PINNED or cmd == "save" and L.PROFILE_SAVED or L.PROFILE_DELETED
	self:Log(ok and msg or L.PROFILE_MISSING, P:Label(key))
end

function addon:ListProfiles()
	local P = ns.Profiles
	self:Log(L.PROFILE_LIST_HEADER, P:Label(P.applied), self.db.global.manual and L.TIP_MANUAL or L.TIP_AUTO)
	for _, key in ipairs(P:Chain()) do
		print(("  %s %s"):format(P:Exists(key) and "|cff0cd29d+|r" or "|cff8a929c-|r", P:Label(key)))
	end
end

--- /ta set <element> <code|name|none> -- edits the applied profile. Stand-in for the
--- flyouts (M6), which call the same Profiles:SetElement.
function addon:SetCommand(rest)
	local element, query = (rest or ""):match("^(%S+)%s*(.*)$")
	element = element and element:lower()
	if not (element and ns.Data.ELEMENT_BY_KEY[element]) then
		self:Log(L.SET_USAGE)
		return
	end
	if query:lower() == "none" then
		ns.Profiles:SetElement(element, nil)
		return
	end
	local t = ns.Data:FindInElement(element, query)
	if not t then
		self:Log(L.SET_UNKNOWN, query, element)
		return
	end
	if ns.Profiles:SetElement(element, t.name) then
		self:Log(L.SET_DONE, element, t.name, ns.Profiles:Label(ns.Profiles.applied))
	end
end

--- The only command handler on a non-Shaman character. Deliberately touches no DB:
--- OnInitialize returned before creating one.
function addon:OnSlashCommandDisabled()
	self:Log(L.NOT_SHAMAN)
end

-- Temporary bar commands until the options window (M9) covers them.
local SETTING_COMMANDS = {
	layout = { setting = "layout", choices = "horizontal, vertical, grid" },
	style = { setting = "buttonStyle", choices = "initials, icons" },
	empty = { setting = "emptySlot", choices = "grey, hide" },
	scale = { setting = "scale", choices = "0.5 - 2" },
}

function addon:OnSlashCommand(input)
	input = trim(input or "")
	local cmd, rest = input:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()

	if cmd == "" then
		-- Options are M9; until then /ta is the help text rather than a dead key.
		self:PrintHelp()
	elseif cmd == "debug" then
		local s = self.db.global.settings
		s.debug = not s.debug
		self:Log(s.debug and L.DEBUG_ON or L.DEBUG_OFF)
	elseif cmd == "selftest" then
		ns.SelfTest:Run()
	elseif cmd == "help" then
		self:PrintHelp()
	elseif cmd == "lock" or cmd == "unlock" then
		ns.Bar:SetLocked(cmd == "lock")
		self:Log(cmd == "lock" and L.BAR_LOCKED or L.BAR_UNLOCKED)
	elseif cmd == "keys" then
		ns.Keybinds:ApplySuggested()
	elseif cmd == "reset" then
		ns.Bar:ResetPosition()
		self:Log(L.BAR_RESET)
	elseif cmd == "theme" then
		if ns.Themes:Set(rest) then
			self:Log(L.SETTING_SET, cmd, rest)
		else
			self:Log(L.SETTING_INVALID, cmd, table.concat(ns.Themes.ORDER, ", "))
		end
	elseif SETTING_COMMANDS[cmd] then
		local c = SETTING_COMMANDS[cmd]
		if ns.Bar:Set(c.setting, rest:lower()) then
			self:Log(L.SETTING_SET, cmd, rest)
		else
			self:Log(L.SETTING_INVALID, cmd, c.choices)
		end
	elseif cmd == "auto" then
		ns.Profiles:Auto()
		self:Log(L.PROFILE_AUTO_ON, ns.Profiles:Label(ns.Profiles:Resolve()))
	elseif cmd == "profile" or cmd == "save" or cmd == "delete" then
		self:ProfileCommand(cmd, rest)
	elseif cmd == "profiles" then
		self:ListProfiles()
	elseif cmd == "set" then
		self:SetCommand(rest)
	elseif cmd == "message" then
		local on = rest:lower() ~= "off"
		self.db.global.settings.showSwitchMessage = on
		self:Log(L.SETTING_SET, cmd, on and "on" or "off")
	elseif cmd == "capture" then
		self:NotYet("M8")
	elseif cmd == "macro" then
		self:NotYet("M7")
	elseif cmd == "minimap" then
		self:NotYet("M9")
	else
		self:Log(L.CMD_UNKNOWN, cmd)
		self:PrintHelp()
	end
	self:Debug("slash: cmd=%q rest=%q", cmd, rest or "")
end
