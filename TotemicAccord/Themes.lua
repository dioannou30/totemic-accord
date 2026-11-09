--[[
	Themes.lua -- theme tables and the one function that applies the current theme.

	Values are copied from the build prompt's theme table (section 6.7), which in turn
	matches docs/mock/totemic-accord-mock.html. "Blizzard classic" is not in that table
	as hex values, so its colours come from the mock's base palette.

	Switching is instant: every coloured region registers an applier, and Apply() re-runs
	them all. No /reload, no rebuilding frames. Recolouring textures and font strings is
	allowed in combat (none of them are protected), so themes never need queueing.

	`radius` is kept for completeness but not drawn yet: WoW only ships a fixed-radius
	rounded mask, so v1 uses flat corners (which the build prompt explicitly allows).
]]

local ADDON, ns = ...
local L = ns.L

local Themes = {}
ns.Themes = Themes

local FONT_DIR = "Interface\\AddOns\\" .. ADDON .. "\\media\\fonts\\"
Themes.FONTS = {
	initials = FONT_DIR .. "Manrope-Bold.ttf",
	heading = FONT_DIR .. "Manrope-SemiBold.ttf",
	mono = FONT_DIR .. "JetBrainsMono-Bold.ttf",
}

Themes.ORDER = { "emerald", "tokyo", "mocha", "latte", "classic" }

Themes.LIST = {
	emerald = {
		name = L.THEME_EMERALD, desc = L.THEME_EMERALD_DESC, flat = true,
		bg = "#0b0d10", panel = "#121519", button = "#181c21", border = "#2f363f",
		text = "#e6e9ed", muted = "#8a929c", accent = "#0cd29d",
		earth = "#d9a35b", fire = "#f2523f", water = "#4aa3f0", air = "#b8d4e3",
		ok = "#0cd29d", warn = "#f2b54a", radius = 3,
	},
	tokyo = {
		name = L.THEME_TOKYO, flat = true,
		bg = "#16161e", panel = "#1a1b26", button = "#24283b", border = "#3b4261",
		text = "#c0caf5", muted = "#737aa2", accent = "#7aa2f7",
		earth = "#e0af68", fire = "#f7768e", water = "#7aa2f7", air = "#bb9af7",
		ok = "#9ece6a", warn = "#e0af68", radius = 4,
	},
	mocha = {
		name = L.THEME_MOCHA, flat = true,
		bg = "#11111b", panel = "#1e1e2e", button = "#313244", border = "#45475a",
		text = "#cdd6f4", muted = "#a6adc8", accent = "#cba6f7",
		earth = "#f9e2af", fire = "#f38ba8", water = "#89b4fa", air = "#b4befe",
		ok = "#a6e3a1", warn = "#f9e2af", radius = 6,
	},
	latte = {
		name = L.THEME_LATTE, flat = true,
		bg = "#dce0e8", panel = "#eff1f5", button = "#e6e9ef", border = "#bcc0cc",
		text = "#4c4f69", muted = "#6c6f85", accent = "#8839ef",
		earth = "#df8e1d", fire = "#d20f39", water = "#1e66f5", air = "#7287fd",
		ok = "#40a02b", warn = "#df8e1d", radius = 6,
	},
	classic = {
		name = L.THEME_CLASSIC, flat = false,
		bg = "#0e1014", panel = "#161a21", button = "#1d222b", border = "#3a4250",
		text = "#e7e2d4", muted = "#9b9686", accent = "#d6ae58",
		earth = "#b08446", fire = "#de5a2c", water = "#3f8fd8", air = "#a9c3d4",
		ok = "#62b46a", warn = "#e3a33a", radius = 4,
		-- Bevelled faces, light top to dark bottom, from the mock's classic gradients.
		gradients = {
			earth = { "#c49a58", "#6e4c1f" }, fire = { "#f07c42", "#8f2b10" },
			water = { "#5ea8ee", "#1d4f8f" }, air = { "#c9dde9", "#5d7e93" },
			action = { "#d9b864", "#7a5a1d" }, projection = { "#7fb08a", "#2f5a3a" },
			profile = { "#6a6f86", "#2b2f40" }, empty = { "#22262e", "#22262e" },
		},
	},
}

--- "#rrggbb" -> r, g, b in 0..1 (plus the given alpha, default 1).
function Themes.RGB(hex, alpha)
	local r, g, b = hex:match("^#?(%x%x)(%x%x)(%x%x)$")
	return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, alpha or 1
end

function Themes:Get(key)
	return self.LIST[key] or self.LIST.emerald
end

function Themes:Current()
	local s = ns.addon.db and ns.addon.db.global.settings
	return self:Get(s and s.theme), s and s.theme or "emerald"
end

-- ------------------------------------------------------------------ appliers

local appliers = {}

--- Register a function(theme) that recolours something. Called immediately once.
function Themes:Register(fn)
	appliers[#appliers + 1] = fn
	fn(self:Current())
end

function Themes:Apply()
	local theme = self:Current()
	for _, fn in ipairs(appliers) do
		fn(theme)
	end
end

--- Switch theme by key. Returns false for an unknown key.
function Themes:Set(key)
	if not self.LIST[key] then
		return false
	end
	ns.addon.db.global.settings.theme = key
	self:Apply()
	return true
end
