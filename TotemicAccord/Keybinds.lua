--[[
	Keybinds.lua -- binding labels on the buttons.

	M3 scope: turn the game's binding strings into the short labels the mock shows
	("ALT-SHIFT-Q" -> "asQ"). The Bindings.xml entries and "Apply suggested keybinds"
	arrive in M4.

	Our buttons are bound through the game's "CLICK <frame name>:LeftButton" commands,
	so GetBindingKey on that command is the source of truth for the label -- whether
	the binding was made in the Key Bindings menu or anywhere else.
]]

local _, ns = ...

local Keybinds = {}
ns.Keybinds = Keybinds

-- Modifiers in the order WoW writes them (ALT-CTRL-SHIFT-key).
local MODIFIERS = { { "ALT", "a" }, { "CTRL", "c" }, { "SHIFT", "s" }, { "META", "m" } }

local KEY_NAMES = {
	MOUSEWHEELUP = "WU", MOUSEWHEELDOWN = "WD",
	LEFTBUTTON = "M1", RIGHTBUTTON = "M2", MIDDLEBUTTON = "M3", MIDDLEMOUSE = "M3",
	SPACE = "Sp", ESCAPE = "Esc", BACKSPACE = "BS", TAB = "Tab", ENTER = "Ent",
	CAPSLOCK = "Cap", INSERT = "Ins", DELETE = "Del", HOME = "Hm", END = "End",
	PAGEUP = "PU", PAGEDOWN = "PD", UP = "Up", DOWN = "Dn", LEFT = "Lt", RIGHT = "Rt",
	NUMPADPLUS = "N+", NUMPADMINUS = "N-", NUMPADMULTIPLY = "N*", NUMPADDIVIDE = "N/",
	NUMPADDECIMAL = "N.",
}

--- "ALT-SHIFT-Q" -> "asQ", "CTRL-BUTTON4" -> "cM4", "NUMPAD5" -> "N5". nil -> "".
function Keybinds.Format(key)
	if not key or key == "" then
		return ""
	end
	local prefix = {}
	local rest = key
	for _, m in ipairs(MODIFIERS) do
		local stripped, n = rest:gsub("%f[%w]" .. m[1] .. "%-", "")
		if n > 0 then
			prefix[#prefix + 1] = m[2]
			rest = stripped
		end
	end
	local short = KEY_NAMES[rest]
		or rest:match("^BUTTON(%d+)$") and ("M" .. rest:match("^BUTTON(%d+)$"))
		or rest:match("^NUMPAD(%d)$") and ("N" .. rest:match("^NUMPAD(%d)$"))
		or rest
	return table.concat(prefix) .. short
end

--- The binding command for one of our buttons, as Bindings.xml will declare it.
function Keybinds.Command(frameName)
	return "CLICK " .. frameName .. ":LeftButton"
end

--- Short label for whatever the first key bound to this frame is.
function Keybinds.LabelFor(frameName)
	return Keybinds.Format((GetBindingKey(Keybinds.Command(frameName))))
end
