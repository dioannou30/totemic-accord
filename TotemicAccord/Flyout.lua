--[[
	Flyout.lua -- per-element totem chooser, mouse only.

	Each element button gets a small arrow tab. Clicking it opens a strip of that element's
	known totems plus "none"; picking one changes that element in the APPLIED profile
	(Profiles:SetElement, which creates the Global default if nothing is applied yet).

	Nothing here is secure: the flyout only edits saved data, then the bar rewrites its
	secure buttons. That rewrite is blocked in combat, so the flyout refuses to open in
	combat (chat message instead) and closes itself when combat starts. It is not a
	keyboard flyout -- OPie covers that.
]]

local _, ns = ...
local L = ns.L
local Themes = ns.Themes
local RGB = Themes.RGB

local Flyout = {}
ns.Flyout = Flyout
LibStub("AceEvent-3.0"):Embed(Flyout)

local ITEM, GAP, PAD = 36, 4, 4
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

-- ------------------------------------------------------------------ the strip

function Flyout:CreateFrame()
	local f = CreateFrame("Frame", "TotemicAccordFlyout", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		f.edges[side] = f:CreateTexture(nil, "BORDER")
	end
	f.edges.TOP:SetPoint("TOPLEFT"); f.edges.TOP:SetPoint("TOPRIGHT"); f.edges.TOP:SetHeight(1)
	f.edges.BOTTOM:SetPoint("BOTTOMLEFT"); f.edges.BOTTOM:SetPoint("BOTTOMRIGHT"); f.edges.BOTTOM:SetHeight(1)
	f.edges.LEFT:SetPoint("TOPLEFT"); f.edges.LEFT:SetPoint("BOTTOMLEFT"); f.edges.LEFT:SetWidth(1)
	f.edges.RIGHT:SetPoint("TOPRIGHT"); f.edges.RIGHT:SetPoint("BOTTOMRIGHT"); f.edges.RIGHT:SetWidth(1)
	f.items = {}
	f:Hide()
	self.frame = f
	return f
end

function Flyout:Item(i)
	local f = self.frame
	local it = f.items[i]
	if it then
		return it
	end
	it = CreateFrame("Button", nil, f)
	it:SetSize(ITEM, ITEM)
	it.bg = it:CreateTexture(nil, "BACKGROUND")
	it.bg:SetAllPoints()
	it.icon = it:CreateTexture(nil, "ARTWORK")
	it.icon:SetPoint("TOPLEFT", 1, -1)
	it.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	it.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	it.text = it:CreateFontString(nil, "OVERLAY")
	it.text:SetFontObject(GameFontNormal)
	it.text:SetPoint("CENTER")
	it.ring = it:CreateTexture(nil, "OVERLAY")
	it.ring:SetPoint("TOPLEFT", -2, 2)
	it.ring:SetPoint("BOTTOMRIGHT", 2, -2)
	it:SetScript("OnClick", function(item) Flyout:Pick(item.element, item.totem) end)
	it:SetScript("OnEnter", function(item)
		GameTooltip:SetOwner(item, "ANCHOR_TOP")
		if item.totem then
			GameTooltip:SetSpellByID(item.totem.spellID)
		else
			GameTooltip:SetText(L.FLYOUT_NONE)
		end
		GameTooltip:Show()
	end)
	it:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.items[i] = it
	return it
end

--- Which totem name the applied profile has for this element now.
local function currentName(button)
	return button.totem and button.totem.name
end

function Flyout:Fill(button)
	local f = self.frame
	local theme = Themes:Current()
	local element = button.spec.key
	local entries = { false } -- "none" first, nearest the bar
	for _, t in ipairs(ns.Data:GetTotems(element)) do
		entries[#entries + 1] = t
	end
	local icons = settings().buttonStyle == "icons"
	local current = currentName(button)
	for i, t in ipairs(entries) do
		local it = self:Item(i)
		it.element, it.totem = element, t or nil
		it.bg:SetColorTexture(RGB(t and theme.button or theme.panel))
		local icon = icons and t and C_Spell.GetSpellTexture(t.spellID) or nil
		it.icon:SetShown(icon ~= nil)
		if icon then it.icon:SetTexture(icon) end
		it.text:SetShown(icon == nil)
		it.text:SetFont(Themes.FONTS.initials, 11, "")
		it.text:SetText(t and t.code or L.EMPTY_SLOT)
		it.text:SetTextColor(RGB(t and theme[element] or theme.muted))
		local isCurrent = (t and t.name or nil) == current
		it.ring:SetShown(isCurrent)
		it.ring:SetColorTexture(RGB(theme.accent, 0.9))
		it.ring:SetDrawLayer("BACKGROUND", -1)
		it:Show()
	end
	for i = #entries + 1, #f.items do
		f.items[i]:Hide()
	end
	f.bg:SetColorTexture(RGB(theme.panel, 0.97))
	for _, tex in pairs(f.edges) do
		tex:SetColorTexture(RGB(theme.border))
	end
	return #entries
end

--- Position the strip in the configured direction, first item nearest the button.
function Flyout:Place(button, count)
	local f = self.frame
	local dir = settings().flyoutDir
	local vertical = dir == "up" or dir == "down"
	local long = PAD * 2 + count * ITEM + (count - 1) * GAP
	local short = PAD * 2 + ITEM
	f:SetSize(vertical and short or long, vertical and long or short)
	f:SetScale(ns.Bar.frame:GetScale())
	f:ClearAllPoints()
	-- Leave room for the arrow tab on the side it sits.
	local clearance = 16
	if dir == "up" then
		f:SetPoint("BOTTOM", button, "TOP", 0, clearance)
	elseif dir == "down" then
		f:SetPoint("TOP", button, "BOTTOM", 0, -6)
	elseif dir == "left" then
		f:SetPoint("RIGHT", button, "LEFT", -clearance, 0)
	else
		f:SetPoint("LEFT", button, "RIGHT", 6, 0)
	end
	for i = 1, count do
		local it = f.items[i]
		local offset = PAD + (i - 1) * (ITEM + GAP)
		it:ClearAllPoints()
		if dir == "up" then
			it:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, offset)
		elseif dir == "down" then
			it:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -offset)
		elseif dir == "left" then
			it:SetPoint("TOPRIGHT", f, "TOPRIGHT", -offset, -PAD)
		else
			it:SetPoint("TOPLEFT", f, "TOPLEFT", offset, -PAD)
		end
	end
end

-- ------------------------------------------------------------------ open / pick

function Flyout:Toggle(button)
	local f = self.frame or self:CreateFrame()
	if f:IsShown() and self.owner == button then
		self:Close()
		return
	end
	if InCombatLockdown() then
		ns.addon:Log(L.COMBAT_NO_TOTEM_CHANGE)
		return
	end
	self.owner = button
	self:Place(button, self:Fill(button))
	f:Show()
end

function Flyout:Close()
	if self.frame then
		self.frame:Hide()
	end
	self.owner = nil
end

function Flyout:Pick(element, totem)
	-- The flyout closes when combat starts, but a click can still race it.
	if InCombatLockdown() then
		ns.addon:Log(L.COMBAT_NO_TOTEM_CHANGE)
		self:Close()
		return
	end
	ns.Profiles:SetElement(element, totem and totem.name or nil)
	self:Close()
end

-- ------------------------------------------------------------------ settings

local DIRECTIONS = { up = true, down = true, left = true, right = true }

function Flyout:SetDirection(dir)
	if not DIRECTIONS[dir] then
		return false
	end
	settings().flyoutDir = dir
	self:Close()
	return true
end

function Flyout:Init()
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "Close")
	Themes:Register(function(theme)
		for _, b in ipairs(ns.Bar.buttons or {}) do
			if b.arrow then
				Flyout:StyleArrow(b.arrow, theme)
			end
		end
	end)
end
