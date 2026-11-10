--[[
	Flyout.lua -- per-element totem chooser, mouse only.

	Each element button gets a small arrow tab (in the bar's theme). Clicking it, or
	right-clicking the button, opens Blizzard's context menu with that element's known
	totems plus "none"; picking one changes that element in the APPLIED profile
	(Profiles:SetElement, which creates the Global default if nothing is applied yet).

	Nothing here is secure: the chooser only edits saved data, then the bar rewrites its
	secure buttons. That rewrite is blocked in combat, so the chooser refuses to open in
	combat (chat message instead) and refuses picks made in combat. It is not a keyboard
	chooser -- OPie covers that.
]]

local _, ns = ...
local L = ns.L
local Themes = ns.Themes
local RGB = Themes.RGB

local Flyout = {}
ns.Flyout = Flyout

-- UI-SortArrow's triangle occupies this part of the file and points down.
local ARROW_COORDS = { 0, 0.5625, 0, 1 }
local ROTATION = { down = 0, up = math.pi, left = -math.pi / 2, right = math.pi / 2 }

local function settings()
	return ns.addon.db.global.settings
end

-- ------------------------------------------------------------------ arrows

--- Where a button's arrow tab sits (and points): above it in the horizontal layout, to
--- its left in vertical (as in the mock). In the 2x2 grid the bottom row's tabs go BELOW
--- the block -- above, they collided with the top row (seen in game).
local function tabSide(index)
	local layout = settings().layout
	if layout == "vertical" then
		return "left"
	elseif layout == "grid" and index > 2 then
		return "down"
	end
	return "up"
end

function Flyout:CreateArrow(button)
	local bar = ns.Bar.frame
	local a = CreateFrame("Button", nil, bar)
	a:SetFrameLevel(button:GetFrameLevel() + 2)
	a.bg = a:CreateTexture(nil, "BACKGROUND")
	a.bg:SetAllPoints()
	a.glyph = a:CreateTexture(nil, "ARTWORK")
	a.glyph:SetTexture("Interface\\Buttons\\UI-SortArrow")
	a.glyph:SetTexCoord(unpack(ARROW_COORDS))
	a.glyph:SetSize(8, 8)
	a.glyph:SetPoint("CENTER")
	a.button = button
	a:SetScript("OnClick", function() Flyout:Toggle(button) end)
	a:SetScript("OnEnter", function(tab) tab.hover = true; Flyout:StyleArrow(tab) end)
	a:SetScript("OnLeave", function(tab) tab.hover = false; Flyout:StyleArrow(tab) end)
	button.arrow = a
	return a
end

function Flyout:StyleArrow(a, theme)
	theme = theme or Themes:Current()
	a.bg:SetColorTexture(RGB(theme.panel, 0.95))
	a.glyph:SetVertexColor(RGB(a.hover and theme.accent or theme.muted))
end

--- Place every arrow against its button. Called from Bar:Layout (out of combat).
function Flyout:LayoutArrows()
	for i, b in ipairs(ns.Bar.buttons or {}) do
		if b.spec.kind == "element" then
			local a = b.arrow or self:CreateArrow(b)
			local side = tabSide(i)
			a:ClearAllPoints()
			if side == "left" then
				a:SetSize(12, 20)
				a:SetPoint("RIGHT", b, "LEFT", -1, 0)
			elseif side == "down" then
				a:SetSize(20, 12)
				a:SetPoint("TOP", b, "BOTTOM", 0, -1)
			else
				a:SetSize(20, 12)
				a:SetPoint("BOTTOM", b, "TOP", 0, 1)
			end
			a.glyph:SetRotation(ROTATION[side])
			-- Arrows can be turned off (/ta arrows off); right-click still opens the chooser.
			a:SetShown(b:IsShown() and settings().flyoutArrows ~= false)
			self:StyleArrow(a)
		end
	end
end

-- ------------------------------------------------------------------ the chooser

local ELEMENT_NAMES = {
	earth = L.ELEMENT_EARTH, fire = L.ELEMENT_FIRE, water = L.ELEMENT_WATER, air = L.ELEMENT_AIR,
}

--- The chooser's entries for one element button: "none" first, then every known totem.
--- Each is { text, totem (nil for none), checked }.
function Flyout:Entries(button)
	local current = button.totem and button.totem.name
	local entries = { { text = L.FLYOUT_NONE, checked = current == nil } }
	for _, t in ipairs(ns.Data:GetTotems(button.spec.key)) do
		local icon = C_Spell.GetSpellTexture(t.spellID)
		entries[#entries + 1] = {
			text = (icon and ("|T%s:16:16:0:0:64:64:5:59:5:59|t "):format(icon) or "") .. t.name,
			totem = t,
			checked = t.name == current,
		}
	end
	return entries
end

--- Open Blizzard's context menu for this element (Dio preferred it to the themed strip).
function Flyout:Toggle(button)
	if InCombatLockdown() then
		ns.addon:Log(L.COMBAT_NO_TOTEM_CHANGE)
		return
	end
	local element = button.spec.key
	local entries = self:Entries(button)
	MenuUtil.CreateContextMenu(button, function(_, root)
		root:CreateTitle(ELEMENT_NAMES[element] or element)
		for _, e in ipairs(entries) do
			local radio = root:CreateRadio(e.text, function() return e.checked end,
				function() Flyout:Pick(element, e.totem) end)
			if e.totem and radio and radio.SetTooltip then
				radio:SetTooltip(function(tooltip) tooltip:SetSpellByID(e.totem.spellID) end)
			end
		end
	end)
end

--- The menu can still be open when combat starts (Blizzard owns and closes it), so a
--- pick made in combat is refused here: the bar can't rewrite secure buttons then.
function Flyout:Pick(element, totem)
	if InCombatLockdown() then
		ns.addon:Log(L.COMBAT_NO_TOTEM_CHANGE)
		return
	end
	ns.Profiles:SetElement(element, totem and totem.name or nil)
end

function Flyout:Init()
	Themes:Register(function(theme)
		for _, b in ipairs(ns.Bar.buttons or {}) do
			if b.arrow then
				Flyout:StyleArrow(b.arrow, theme)
			end
		end
	end)
end
