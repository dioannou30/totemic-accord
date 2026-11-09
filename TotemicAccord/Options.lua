--[[
	Options.lua -- the options window (AceConfig), opened with /ta, the minimap button,
	or the game's Options > AddOns > Totemic Accord.

	Four tabs, per build prompt 6.8:
	  Profiles            pick a row (Global or a talent loadout) and a column (Default or
	                      a situation) to edit that cell's four totems; a status matrix
	                      shows which cells are set and which one is in use, and the
	                      current resolution chain
	  Sequence            the applied profile's castsequence: order, includes, resets,
	                      macro preview + length, game macro, copy box
	  Appearance & keys   every bar setting, the minimap button, suggested keybinds
	  Import / Export     TA1: strings

	AceConfig was chosen over a hand-built themed window (Dio's call): it draws in
	Blizzard's style, not the bar's theme.

	Every setter goes through the module that owns the setting, so combat queueing and
	validation behave exactly as with the slash commands.
]]

local ADDON, ns = ...
local L = ns.L

local Options = {}
ns.Options = Options

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

local function g()
	return ns.addon.db.global
end

local function settings()
	return g().settings
end

-- Which profile cell the Profiles tab is editing.
Options.editRow = "global"
Options.editCol = "default"

-- ------------------------------------------------------------------ helpers

local function colored(hexKey, text)
	local theme = ns.Themes:Current()
	return "|cff" .. theme[hexKey]:sub(2) .. text .. "|r"
end

--- Row keys: "global" plus every talent loadout we know (saved now or named before).
local function rows()
	local list, seen = { { key = "global", label = L.PROFILE_GLOBAL } }, {}
	local S = C_SpecializationInfo
	local index = S.GetSpecialization()
	local specID = index and S.GetSpecializationInfo(index)
	local ids = specID and C_ClassTalents.GetConfigIDsBySpecID(specID) or {}
	for _, id in ipairs(ids) do
		seen[id] = true
		local info = C_Traits.GetConfigInfo(id)
		if info and info.name then
			g().loadoutNames[id] = info.name
		end
		list[#list + 1] = { key = "L" .. id, label = g().loadoutNames[id] or (L.PROFILE_LOADOUT):format(id) }
	end
	for id, name in pairs(g().loadoutNames) do
		if not seen[id] then
			list[#list + 1] = { key = "L" .. id, label = name }
		end
	end
	return list
end

local function columns()
	local list = { { key = "default", label = L.SIT_DEFAULT } }
	for _, s in ipairs(ns.Profiles.SITUATIONS) do
		list[#list + 1] = { key = s.key, label = s.label }
	end
	return list
end

local function cellKey(row, col)
	if row == "global" then
		return col == "default" and "global" or ("global:" .. col)
	end
	return row .. ":" .. col
end

local function editKey()
	return cellKey(Options.editRow, Options.editCol)
end

--- The status matrix: one line per row, each cell marked set / not set / in use.
local function matrixText()
	local lines = {}
	local applied = ns.Profiles.applied
	for _, r in ipairs(rows()) do
		local cells = {}
		for _, c in ipairs(columns()) do
			local key = cellKey(r.key, c.key)
			if key == applied then
				cells[#cells + 1] = colored("accent", "[" .. c.label .. "]")
			elseif g().profiles[key] then
				cells[#cells + 1] = colored("text", c.label)
			else
				cells[#cells + 1] = colored("muted", c.label)
			end
		end
		lines[#lines + 1] = r.label .. ":  " .. table.concat(cells, "  ")
	end
	return table.concat(lines, "\n")
end

local function chainText()
	local P = ns.Profiles
	local parts = {}
	for _, key in ipairs(P:Chain()) do
		local label = P:Label(key)
		if key == P.applied then
			parts[#parts + 1] = colored("accent", label)
		elseif P:Exists(key) then
			parts[#parts + 1] = label
		else
			parts[#parts + 1] = colored("muted", label)
		end
	end
	return table.concat(parts, "  >  ")
end

local function totemValues(element)
	local values = { [""] = L.OPT_NONE }
	for _, t in ipairs(ns.Data:GetTotems(element)) do
		values[t.name] = t.code .. "  " .. t.name
	end
	return values
end

-- ------------------------------------------------------------------ tabs

local function profilesTab()
	local args = {
		status = {
			type = "description", order = 1, fontSize = "medium",
			name = function()
				local P = ns.Profiles
				return (L.OPT_USING):format(P:Label(P.applied), g().manual and L.TIP_MANUAL or L.TIP_AUTO)
			end,
		},
		chain = { type = "description", order = 2, name = function() return L.OPT_CHAIN .. "\n" .. chainText() end },
		matrix = { type = "description", order = 3, name = function() return "\n" .. matrixText() .. "\n" end },
		row = {
			type = "select", order = 10, name = L.OPT_ROW, width = 1.2,
			values = function()
				local v = {}
				for _, r in ipairs(rows()) do v[r.key] = r.label end
				return v
			end,
			get = function() return Options.editRow end,
			set = function(_, v) Options.editRow = v end,
		},
		col = {
			type = "select", order = 11, name = L.OPT_COLUMN, width = 1.2,
			values = function()
				local v = {}
				for _, c in ipairs(columns()) do v[c.key] = c.label end
				return v
			end,
			sorting = function()
				local order = {}
				for _, c in ipairs(columns()) do order[#order + 1] = c.key end
				return order
			end,
			get = function() return Options.editCol end,
			set = function(_, v) Options.editCol = v end,
		},
		editing = {
			type = "header", order = 20,
			name = function()
				local key = editKey()
				return ns.Profiles:Label(key) .. (g().profiles[key] and "" or ("  " .. L.OPT_NOT_SET))
			end,
		},
		howTo = { type = "description", order = 12, name = L.OPT_HOWTO },
		create = {
			type = "execute", order = 39, name = L.OPT_CREATE, desc = L.OPT_CREATE_DESC,
			disabled = function() return g().profiles[editKey()] ~= nil end,
			func = function() ns.Profiles:SaveAs(editKey()) end,
		},
		fromBar = {
			type = "execute", order = 40, name = L.OPT_FROM_BAR, desc = L.OPT_FROM_BAR_DESC,
			disabled = function() return g().profiles[editKey()] == nil end,
			func = function() ns.Profiles:SaveAs(editKey()) end,
		},
		remove = {
			type = "execute", order = 41, name = L.OPT_REMOVE, desc = L.OPT_REMOVE_DESC,
			confirm = true, confirmText = L.OPT_REMOVE_CONFIRM,
			disabled = function() return not g().profiles[editKey()] end,
			func = function() ns.Profiles:Delete(editKey()) end,
		},
	}
	for i, e in ipairs(ns.Data.ELEMENTS) do
		args["el_" .. e.key] = {
			type = "select", order = 20 + i, width = 0.9,
			name = colored(e.key, L["ELEMENT_" .. e.key:upper()]),
			values = function() return totemValues(e.key) end,
			get = function()
				local p = g().profiles[editKey()]
				return p and p[e.key] and p[e.key].name or ""
			end,
			set = function(_, v) ns.Profiles:SetElementFor(editKey(), e.key, v ~= "" and v or nil) end,
		}
	end
	return { type = "group", name = L.TAB_PROFILES, order = 1, args = args }
end

local function sequenceTab()
	local S = ns.Sequence
	local function key() return ns.Profiles.applied or "global" end
	local args = {
		which = {
			type = "description", order = 1, fontSize = "medium",
			name = function() return (L.OPT_SEQ_FOR):format(ns.Profiles:Label(ns.Profiles.applied)) end,
		},
		orderHeader = { type = "header", order = 10, name = L.OPT_ORDER },
		resetHeader = { type = "header", order = 30, name = L.OPT_RESET },
		resetCombat = {
			type = "toggle", order = 31, name = L.OPT_RESET_COMBAT, width = "full",
			get = function() return S:Get(key()).resetCombat end,
			set = function(_, v) S:SetResetCombat(v) end,
		},
		resetSeconds = {
			type = "range", order = 32, name = L.OPT_RESET_SECONDS, desc = L.OPT_RESET_SECONDS_DESC,
			min = 0, max = 600, softMax = 120, step = 1,
			get = function() return S:Get(key()).resetSeconds or 0 end,
			set = function(_, v) S:SetResetSeconds(v > 0 and v or nil) end,
		},
		macroHeader = { type = "header", order = 40, name = L.OPT_MACRO },
		preview = {
			type = "description", order = 41, fontSize = "medium",
			name = function()
				local text = S:MacroText()
				local len = (L.OPT_LENGTH):format(#text, S.MACRO_LIMIT)
				if #text > S.MACRO_LIMIT then
					len = "|cfff2523f" .. len .. "  " .. L.OPT_TOO_LONG .. "|r"
				end
				return (text ~= "" and text or L.SEQ_EMPTY) .. "\n\n" .. len
			end,
		},
		gameMacro = {
			type = "execute", order = 42, name = L.OPT_GAME_MACRO, desc = L.OPT_GAME_MACRO_DESC,
			func = function() S:SyncGameMacro(true) end,
		},
		copy = {
			type = "input", order = 43, name = L.OPT_COPY, multiline = 3, width = "full",
			get = function() return S:MacroText() end,
			set = function() end,
		},
	}
	for i = 1, #ns.Data.ELEMENTS do
		args["step" .. i] = {
			type = "select", order = 10 + i, width = 0.8, name = (L.OPT_STEP):format(i),
			values = function()
				local v = {}
				for _, e in ipairs(ns.Data.ELEMENTS) do v[e.key] = L["ELEMENT_" .. e.key:upper()] end
				return v
			end,
			get = function() return S:Get(key()).order[i] end,
			set = function(_, v)
				-- Swap, so the order stays a permutation of the four elements.
				local order = { unpack(S:Get(key()).order) }
				for j, element in ipairs(order) do
					if element == v then order[j] = order[i] end
				end
				order[i] = v
				S:SetOrder(order)
			end,
		}
	end
	for i, e in ipairs(ns.Data.ELEMENTS) do
		args["inc_" .. e.key] = {
			type = "toggle", order = 20 + i, width = 0.8,
			name = (L.OPT_INCLUDE):format(L["ELEMENT_" .. e.key:upper()]),
			get = function() return S:Get(key()).include[e.key] end,
			set = function(_, v) S:SetIncluded(e.key, v) end,
		}
	end
	return { type = "group", name = L.TAB_SEQUENCE, order = 2, args = args }
end

local function barSelect(order, setting, name, values)
	return {
		type = "select", order = order, name = name, values = values,
		get = function() return settings()[setting] end,
		set = function(_, v) ns.Bar:Set(setting, v) end,
	}
end

--- A key-capture control for one of our buttons; Escape clears it.
local function keybind(order, frame, name)
	return {
		type = "keybinding", order = order, name = name,
		get = function() return (GetBindingKey(ns.Keybinds.Command(frame))) or "" end,
		set = function(_, key) ns.Keybinds:Bind(frame, key) end,
	}
end

local function appearanceTab()
	local themeValues = {}
	for _, key in ipairs(ns.Themes.ORDER) do
		themeValues[key] = ns.Themes.LIST[key].name
	end
	return { type = "group", name = L.TAB_APPEARANCE, order = 3, args = {
		theme = {
			type = "select", order = 1, name = L.OPT_THEME, desc = L.THEME_EMERALD_DESC,
			values = themeValues,
			sorting = ns.Themes.ORDER,
			get = function() return settings().theme end,
			set = function(_, v) ns.Themes:Set(v) end,
		},
		buttonStyle = barSelect(2, "buttonStyle", L.OPT_STYLE, { initials = L.OPT_STYLE_INITIALS, icons = L.OPT_STYLE_ICONS }),
		layout = barSelect(3, "layout", L.OPT_LAYOUT,
			{ horizontal = L.OPT_LAYOUT_H, vertical = L.OPT_LAYOUT_V, grid = L.OPT_LAYOUT_G }),
		flyoutDir = barSelect(4, "flyoutDir", L.OPT_FLYOUT,
			{ up = L.OPT_DIR_UP, down = L.OPT_DIR_DOWN, left = L.OPT_DIR_LEFT, right = L.OPT_DIR_RIGHT }),
		emptySlot = barSelect(5, "emptySlot", L.OPT_EMPTY, { grey = L.OPT_EMPTY_GREY, hide = L.OPT_EMPTY_HIDE }),
		actionMode = {
			type = "select", order = 6, name = L.OPT_ACTION, desc = L.OPT_ACTION_DESC,
			values = { auto = L.OPT_ACTION_AUTO, cote = L.TIP_ACTION_COTE, seq = L.TIP_ACTION_SEQ },
			get = function() return settings().actionMode end,
			set = function(_, v) ns.Bar:Set("actionMode", v) end,
		},
		scale = {
			type = "range", order = 10, name = L.OPT_SCALE, min = 0.5, max = 2, step = 0.05, isPercent = true,
			get = function() return settings().scale end,
			set = function(_, v) ns.Bar:Set("scale", v) end,
		},
		barOpacity = {
			type = "range", order = 11, name = L.OPT_OPACITY, desc = L.OPT_OPACITY_DESC,
			min = 0, max = 1, step = 0.05, isPercent = true,
			get = function() return settings().barOpacity end,
			set = function(_, v) settings().barOpacity = v; ns.Themes:Apply() end,
		},
		vividInitials = {
			type = "toggle", order = 12, name = L.OPT_VIVID, desc = L.OPT_VIVID_DESC,
			get = function() return settings().vividInitials end,
			set = function(_, v) settings().vividInitials = v; ns.Themes:Apply() end,
		},
		toggles = { type = "header", order = 20, name = "" },
		locked = {
			type = "toggle", order = 21, name = L.OPT_LOCKED,
			get = function() return settings().locked end,
			set = function(_, v) ns.Bar:SetLocked(v) end,
		},
		showSwitchMessage = {
			type = "toggle", order = 22, name = L.OPT_MESSAGE,
			get = function() return settings().showSwitchMessage end,
			set = function(_, v) settings().showSwitchMessage = v end,
		},
		minimap = {
			type = "toggle", order = 23, name = L.OPT_MINIMAP,
			get = function() return not settings().minimap.hide end,
			set = function(_, v) ns.Minimap:SetShown(v) end,
		},
		profileLabel = {
			type = "toggle", order = 25, name = L.OPT_LABEL, desc = L.OPT_LABEL_DESC,
			get = function() return settings().showProfileLabel end,
			set = function(_, v) settings().showProfileLabel = v; ns.Bar:Refresh() end,
		},
		arrows = {
			type = "toggle", order = 24, name = L.OPT_ARROWS, desc = L.OPT_ARROWS_DESC,
			get = function() return settings().flyoutArrows ~= false end,
			set = function(_, v) settings().flyoutArrows = v; ns.Flyout:LayoutArrows() end,
		},
		keysHeader = { type = "header", order = 30, name = L.OPT_KEYS },
		keysInfo = { type = "description", order = 31, name = L.OPT_KEYS_DESC },
		keys = {
			type = "execute", order = 32, name = L.OPT_KEYS_APPLY,
			func = function() ns.Keybinds:ApplySuggested() end,
		},
		bind_earth = keybind(41, "TotemicAccordEarth", L.BIND_EARTH),
		bind_fire = keybind(42, "TotemicAccordFire", L.BIND_FIRE),
		bind_water = keybind(43, "TotemicAccordWater", L.BIND_WATER),
		bind_air = keybind(44, "TotemicAccordAir", L.BIND_AIR),
		bind_action = keybind(45, "TotemicAccordAction", L.BIND_ACTION),
		bind_projection = keybind(46, "TotemicAccordProjection", L.BIND_PROJECTION),
		bind_profile = keybind(47, "TotemicAccordProfile", L.BIND_PROFILE),
	} }
end

local function importExportTab()
	return { type = "group", name = L.TAB_IMPORT, order = 4, args = {
		exportInfo = { type = "description", order = 1, name = L.OPT_EXPORT_DESC },
		export = {
			type = "input", order = 2, name = L.OPT_EXPORT, multiline = 6, width = "full",
			get = function() return ns.ImportExport:Export() end,
			set = function() end,
		},
		importInfo = { type = "description", order = 10, name = L.OPT_IMPORT_DESC },
		import = {
			type = "input", order = 11, name = L.OPT_IMPORT, multiline = 6, width = "full",
			get = function() return "" end,
			set = function(_, v) ns.ImportExport:BeginImport(v) end,
		},
		importError = {
			type = "description", order = 12,
			hidden = function() return not ns.ImportExport.lastError end,
			name = function() return "|cfff2523f" .. (ns.ImportExport.lastError or "") .. "|r" end,
		},
	} }
end

function Options:Build()
	return {
		type = "group", name = ns.addon.DISPLAY_NAME, childGroups = "tab",
		args = {
			profiles = profilesTab(),
			sequence = sequenceTab(),
			appearance = appearanceTab(),
			importexport = importExportTab(),
		},
	}
end

-- ------------------------------------------------------------------ wiring

function Options:Init()
	AceConfig:RegisterOptionsTable(ADDON, function() return Options:Build() end)
	AceConfigDialog:SetDefaultSize(ADDON, 720, 600)
	-- Also listed in the game's Options > AddOns.
	AceConfigDialog:AddToBlizOptions(ADDON, ns.addon.DISPLAY_NAME)
	self.registered = true
end

--- Open the window, optionally on a tab ("profiles", "sequence", "appearance", "importexport").
function Options:Open(tab)
	AceConfigDialog:Open(ADDON)
	if tab then
		AceConfigDialog:SelectGroup(ADDON, tab)
	end
end

--- Re-draw an open options window after something changed elsewhere (zone switch,
--- flyout pick, slash command).
function Options:Refresh()
	if self.registered then
		AceConfigRegistry:NotifyChange(ADDON)
	end
end
