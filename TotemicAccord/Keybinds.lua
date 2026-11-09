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

-- ------------------------------------------------------------------ Key Bindings menu
-- Bindings.xml declares the entries; the game looks their display names up in these
-- globals. A CLICK binding's name contains a space and a colon, hence the _G[...] form.

local L = ns.L
BINDING_HEADER_TOTEMICACCORD = L.BIND_HEADER
for frame, label in pairs({
	TotemicAccordEarth = L.BIND_EARTH, TotemicAccordFire = L.BIND_FIRE,
	TotemicAccordWater = L.BIND_WATER, TotemicAccordAir = L.BIND_AIR,
	TotemicAccordAction = L.BIND_ACTION, TotemicAccordProjection = L.BIND_PROJECTION,
	TotemicAccordProfile = L.BIND_PROFILE,
}) do
	_G["BINDING_NAME_" .. Keybinds.Command(frame)] = label
end

-- ------------------------------------------------------------------ suggested binds

--- Build prompt 6.6. Never applied automatically -- only via /ta keys (later also an
--- options button), and only after the player confirms.
Keybinds.SUGGESTED = {
	{ frame = "TotemicAccordEarth", key = "ALT-SHIFT-Q" },
	{ frame = "TotemicAccordFire", key = "ALT-SHIFT-E" },
	{ frame = "TotemicAccordWater", key = "ALT-SHIFT-R" },
	{ frame = "TotemicAccordAir", key = "ALT-SHIFT-F" },
	{ frame = "TotemicAccordAction", key = "ALT-SHIFT-G" },
}

--- Which suggested binds would change something, and what each would replace.
--- Returns a list of { key, command, replaces = <display name or nil> }.
function Keybinds.PendingChanges()
	local changes = {}
	for _, s in ipairs(Keybinds.SUGGESTED) do
		local command = Keybinds.Command(s.frame)
		local current = GetBindingAction(s.key)
		if current ~= command then
			local replaces
			if current and current ~= "" then
				replaces = GetBindingText(current, "BINDING_NAME_")
			end
			changes[#changes + 1] = { key = s.key, command = command, replaces = replaces }
		end
	end
	return changes
end

--- Bind one of our buttons to `key` ("" clears it), replacing its previous keys. Says
--- what the key used to do, if anything. Not in combat (SetBinding is blocked there).
function Keybinds:Bind(frame, key)
	if InCombatLockdown() then
		ns.addon:Log(L.KEYS_COMBAT)
		return false
	end
	local command = Keybinds.Command(frame)
	for _, old in ipairs({ GetBindingKey(command) }) do
		SetBinding(old) -- no command: unbind
	end
	if key and key ~= "" then
		local previous = GetBindingAction(key)
		if previous and previous ~= "" and previous ~= command then
			ns.addon:Log(L.KEYS_REPLACED, Keybinds.Format(key), GetBindingText(previous, "BINDING_NAME_"))
		end
		SetBinding(key, command)
	end
	SaveBindings(GetCurrentBindingSet())
	return true
end

--- SetBinding is blocked in combat, so this is checked both before asking and again
--- when the player clicks Apply (they may have entered combat in between).
function Keybinds:Apply(changes)
	if InCombatLockdown() then
		ns.addon:Log(L.KEYS_COMBAT)
		return false
	end
	local applied = {}
	for _, c in ipairs(changes) do
		SetBinding(c.key, c.command)
		applied[#applied + 1] = Keybinds.Format(c.key)
	end
	-- Persist into whichever binding set is active (account or character).
	SaveBindings(GetCurrentBindingSet())
	ns.addon:Log(L.KEYS_APPLIED, table.concat(applied, ", "))
	return true
end

function Keybinds:ApplySuggested()
	if InCombatLockdown() then
		ns.addon:Log(L.KEYS_COMBAT)
		return
	end
	local changes = Keybinds.PendingChanges()
	if #changes == 0 then
		ns.addon:Log(L.KEYS_ALREADY)
		return
	end
	local replaced = {}
	for _, c in ipairs(changes) do
		if c.replaces then
			replaced[#replaced + 1] = ("%s: %s"):format(c.key, c.replaces)
		end
	end
	local detail = #replaced > 0
		and L.KEYS_CONFIRM_REPLACES:format(table.concat(replaced, "\n"))
		or L.KEYS_CONFIRM_NOTHING
	StaticPopup_ShowCustomGenericConfirmation({
		text = L.KEYS_CONFIRM:format(detail),
		acceptText = L.KEYS_ACCEPT,
		showAlert = #replaced > 0,
		callback = function() Keybinds:Apply(changes) end,
	})
end
