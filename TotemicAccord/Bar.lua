--[[
	Bar.lua -- the bar frame, its seven buttons, layouts, theming, drag/lock/scale.

	M3 scope: everything you can see, nothing that casts. The buttons are already
	SecureActionButtonTemplate so M4 only has to set attributes on them.

	Combat lockdown, briefly: while you are in combat, WoW forbids addon code from
	moving, resizing, showing or hiding secure (protected) frames -- that is how it stops
	addons from automating combat decisions. So anything that changes the bar's GEOMETRY
	(layout, scale, hiding an empty slot) is queued and applied on PLAYER_REGEN_ENABLED.
	Recolouring textures and font strings is not protected, so themes apply instantly
	even mid-fight.

	Until profiles exist (M5), each element shows the first totem discovery knows for it,
	labelled as a preview.
]]

local _, ns = ...
local L = ns.L
local Themes = ns.Themes
local RGB = Themes.RGB

local Bar = {}
ns.Bar = Bar
LibStub("AceEvent-3.0"):Embed(Bar)

local SIZE, GAP, PAD = 44, 6, 6
-- Blizzard's UI-Quickslot2 frame is drawn at 66px around a 36px button.
local CLASSIC_FRAME_RATIO = 66 / 36

-- ------------------------------------------------------------------ helpers

--- Exactly one physical pixel, in this region's UI units, so 1px lines stay crisp at
--- any UI scale. PixelUtil marks these helpers deprecated in favour of the native
--- SetRoundLayoutToNearestPixel, but that is a protected function (restricted in
--- combat, like StartMoving); PixelUtil's plain Lua maths is safe at any time.
local function onePixel(region)
	return PixelUtil.GetNearestPixelSize(0, region:GetEffectiveScale(), 1)
end

local function snap(region, value)
	return PixelUtil.GetNearestPixelSize(value, region:GetEffectiveScale())
end

local function makeBorder(frame)
	local b = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		b[side] = frame:CreateTexture(nil, "OVERLAY", nil, 6)
	end
	b.TOP:SetPoint("TOPLEFT")
	b.TOP:SetPoint("TOPRIGHT")
	b.BOTTOM:SetPoint("BOTTOMLEFT")
	b.BOTTOM:SetPoint("BOTTOMRIGHT")
	b.LEFT:SetPoint("TOPLEFT")
	b.LEFT:SetPoint("BOTTOMLEFT")
	b.RIGHT:SetPoint("TOPRIGHT")
	b.RIGHT:SetPoint("BOTTOMRIGHT")
	function b:SetThickness(px)
		self.TOP:SetHeight(px)
		self.BOTTOM:SetHeight(px)
		self.LEFT:SetWidth(px)
		self.RIGHT:SetWidth(px)
	end
	function b:SetColor(r, g, bl, a)
		for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
			self[side]:SetColorTexture(r, g, bl, a)
		end
	end
	function b:SetShown(shown)
		for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
			self[side]:SetShown(shown)
		end
	end
	return b
end

--- Addon font files can fail to load on the first attempt during login and succeed a
--- moment later (DialogueUI, which ships its own fonts on Forever, retries after 0.2s
--- for the same reason). So: fall back to the game font for now, and restyle the whole
--- bar again shortly -- a few times at most -- which re-attempts every font.
local FONT_RETRY_DELAYS = { 0.2, 1, 3 }

local function setFont(fs, path, size, flags)
	if fs:SetFont(path, size, flags or "") then
		return
	end
	fs:SetFont((GameFontNormal:GetFont()), size, flags or "")
	local attempt = (Bar.fontRetries or 0) + 1
	if not Bar.fontRetryScheduled and FONT_RETRY_DELAYS[attempt] then
		Bar.fontRetryScheduled = true
		Bar.fontRetries = attempt
		C_Timer.After(FONT_RETRY_DELAYS[attempt], function()
			Bar.fontRetryScheduled = false
			Themes:Apply()
		end)
	end
end

local function settings()
	return ns.addon.db.global.settings
end

-- ------------------------------------------------------------------ button specs

local function frameName(suffix)
	return "TotemicAccord" .. suffix
end

local function buildSpecs()
	local specs = {}
	for _, e in ipairs(ns.Data.ELEMENTS) do
		specs[#specs + 1] = {
			kind = "element", key = e.key,
			name = frameName(e.key:sub(1, 1):upper() .. e.key:sub(2)),
		}
	end
	specs[#specs + 1] = { kind = "action", key = "action", name = frameName("Action") }
	specs[#specs + 1] = { kind = "projection", key = "projection", name = frameName("Projection") }
	specs[#specs + 1] = { kind = "profile", key = "profile", name = frameName("Profile") }
	return specs
end

-- ------------------------------------------------------------------ state

--- Which totem each element shows: the applied profile's (Profiles.lua).
function Bar:ResolveTotems()
	return ns.Profiles:DisplayedTotems()
end

--- "cote" or "seq". Auto picks Call of the Elements once it is learned.
function Bar:ActionMode()
	local mode = settings().actionMode
	if mode == "cote" or mode == "seq" then
		return mode
	end
	local coe = TOTEM_MULTI_CAST_SUMMON_SPELLS and TOTEM_MULTI_CAST_SUMMON_SPELLS[1]
	return (coe and IsPlayerSpell(coe)) and "cote" or "seq"
end

-- ------------------------------------------------------------------ creation

function Bar:CreateButton(spec)
	local b = CreateFrame("Button", spec.name, self.frame, "SecureActionButtonTemplate")
	b.spec = spec
	b:SetSize(SIZE, SIZE)

	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	b.line = b:CreateTexture(nil, "OVERLAY", nil, 2)
	b.border = makeBorder(b)

	b.classicFrame = b:CreateTexture(nil, "OVERLAY", nil, 7)
	b.classicFrame:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	b.classicFrame:SetPoint("CENTER")
	b.classicFrame:SetSize(SIZE * CLASSIC_FRAME_RATIO, SIZE * CLASSIC_FRAME_RATIO)

	b.text = b:CreateFontString(nil, "OVERLAY")
	b.text:SetFontObject(GameFontNormal)
	b.text:SetPoint("CENTER", 0, 1)

	b.key = b:CreateFontString(nil, "OVERLAY")
	b.key:SetFontObject(GameFontNormalSmall)
	b.key:SetPoint("TOPRIGHT", -3, -2)

	b.count = b:CreateFontString(nil, "OVERLAY")
	b.count:SetFontObject(GameFontNormalSmall)
	b.count:SetPoint("BOTTOMLEFT", 3, 2)

	if spec.kind == "profile" then
		b.dot = b:CreateTexture(nil, "OVERLAY", nil, 3)
		b.dot:SetSize(5, 5)
		b.dot:SetPoint("TOPLEFT", 4, -4)
	end

	-- Receive both halves of a click: the secure template then fires on key-down or
	-- key-up according to the player's "cast on key down" setting (ActionButtonUseKeyDown).
	b:RegisterForClicks("AnyUp", "AnyDown")

	-- Hooks, not SetScript: these are secure buttons and we only observe.
	b:HookScript("OnEnter", function(btn) Bar:OnEnterButton(btn) end)
	b:HookScript("OnLeave", function(btn) Bar:OnLeaveButton(btn) end)
	if spec.kind == "profile" then
		-- Not a casting button: open the chooser once per click (on release), also
		-- when clicked through its keybind.
		b:RegisterForClicks("AnyUp")
		b:HookScript("OnClick", function(btn) ns.Profiles:OpenMenu(btn) end)
	end
	return b
end

function Bar:Create()
	if self.frame then
		return
	end
	local f = CreateFrame("Frame", "TotemicAccordBar", UIParent)
	self.frame = f
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	-- We save the position ourselves; stop the client's layout cache fighting us.
	f:SetDontSavePosition(true)

	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.border = makeBorder(f)
	f.sep = f:CreateTexture(nil, "ARTWORK")

	f.label = f:CreateFontString(nil, "OVERLAY")
	f.label:SetFontObject(GameFontNormalSmall)

	self.buttons = {}
	self.byKey = {}
	for _, spec in ipairs(buildSpecs()) do
		local b = self:CreateButton(spec)
		self.buttons[#self.buttons + 1] = b
		self.byKey[spec.key] = b
	end

	self:CreateMover()
	self:RestorePosition()
end

--- Drag handle shown while unlocked. A separate plain frame on top of the bar, so
--- dragging never needs scripts on the secure buttons themselves.
function Bar:CreateMover()
	local f = self.frame
	local m = CreateFrame("Frame", nil, f)
	m:SetAllPoints()
	m:SetFrameLevel(f:GetFrameLevel() + 20)
	m:EnableMouse(true)
	m:RegisterForDrag("LeftButton")
	m.tint = m:CreateTexture(nil, "BACKGROUND")
	m.tint:SetAllPoints()
	m.hint = m:CreateFontString(nil, "OVERLAY")
	m.hint:SetFontObject(GameFontNormalSmall)
	m.hint:SetPoint("BOTTOM", m, "TOP", 0, 4)
	m.hint:SetText(L.MOVER_HINT)
	m:SetScript("OnDragStart", function()
		-- Moving a frame that holds secure buttons is blocked in combat.
		if InCombatLockdown() then
			return
		end
		f:StartMoving()
	end)
	m:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		Bar:SavePosition()
	end)
	self.mover = m
end

-- ------------------------------------------------------------------ position

function Bar:SavePosition()
	local point, _, relPoint, x, y = self.frame:GetPoint(1)
	settings().point = { point, relPoint, x, y }
end

function Bar:RestorePosition()
	local f = self.frame
	local p = settings().point
	f:ClearAllPoints()
	if p and p[1] then
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
	end
end

function Bar:ResetPosition()
	if InCombatLockdown() then
		ns.addon:Log(L.COMBAT_QUEUED)
		self.resetPending = true
		return
	end
	settings().point = nil
	self:RestorePosition()
end

-- ------------------------------------------------------------------ layout

--- Place every visible button for the current layout. Geometry only: protected in
--- combat, so it is queued then.
function Bar:Layout()
	if not self.frame then
		return
	end
	if InCombatLockdown() then
		self.layoutPending = true
		return
	end
	self.layoutPending = false

	local s = settings()
	local f = self.frame
	f:SetScale(s.scale or 1)
	local px = onePixel(f)

	local layout = s.layout
	local elements, extras = {}, {}
	for _, b in ipairs(self.buttons) do
		local hidden = b.spec.kind == "element" and not b.totem and s.emptySlot == "hide"
		b:SetShown(not hidden)
		b.border:SetThickness(onePixel(b))
		b:ClearAllPoints()
		if not hidden then
			if b.spec.kind == "element" then
				elements[#elements + 1] = b
			else
				extras[#extras + 1] = b
			end
		end
	end
	f.border:SetThickness(px)

	local function place(region, x, y)
		region:SetPoint("TOPLEFT", f, "TOPLEFT", snap(f, x), -snap(f, y))
	end

	local width, height
	f.sep:ClearAllPoints()
	if layout == "grid" then
		-- Elements in a 2x2 block in their slot positions (no collapsing, so the
		-- block keeps its shape), Action over Projection, Profile centred at the end.
		f.sep:Hide()
		for i, b in ipairs(self.buttons) do
			if b.spec.kind == "element" and b:IsShown() then
				local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
				place(b, PAD + col * (SIZE + GAP), PAD + row * (SIZE + GAP))
			end
		end
		place(self.byKey.action, PAD + 2 * (SIZE + GAP), PAD)
		place(self.byKey.projection, PAD + 2 * (SIZE + GAP), PAD + SIZE + GAP)
		place(self.byKey.profile, PAD + 3 * (SIZE + GAP), PAD + (SIZE + GAP) / 2)
		width = PAD * 2 + 4 * SIZE + 3 * GAP
		height = PAD * 2 + 2 * SIZE + GAP
	else
		local vertical = layout == "vertical"
		local pos = PAD
		local function advance(b)
			if vertical then place(b, PAD, pos) else place(b, pos, PAD) end
			pos = pos + SIZE + GAP
		end
		for _, b in ipairs(elements) do
			advance(b)
		end
		if #elements > 0 then
			f.sep:Show()
			if vertical then
				f.sep:SetPoint("TOPLEFT", f, "TOPLEFT", snap(f, PAD), -snap(f, pos))
				f.sep:SetSize(SIZE, px)
			else
				f.sep:SetPoint("TOPLEFT", f, "TOPLEFT", snap(f, pos), -snap(f, PAD))
				f.sep:SetSize(px, SIZE)
			end
			pos = pos + px + GAP
		else
			f.sep:Hide()
		end
		for _, b in ipairs(extras) do
			advance(b)
		end
		local along = pos - GAP + PAD
		local across = PAD * 2 + SIZE
		width, height = vertical and across or along, vertical and along or across
	end
	f:SetSize(snap(f, width), snap(f, height))

	f.label:ClearAllPoints()
	if layout == "vertical" then
		f.label:SetPoint("BOTTOM", f, "TOP", 0, 4)
	else
		f.label:SetPoint("TOP", f, "BOTTOM", 0, -4)
	end

	ns.Flyout:LayoutArrows()
	ns.Flyout:Close()
	self:ApplyLock()
end

function Bar:ApplyLock()
	if self.mover then
		self.mover:SetShown(not settings().locked)
	end
end

function Bar:SetLocked(locked)
	settings().locked = locked
	self:ApplyLock()
end

-- ------------------------------------------------------------------ content + style

--- Recompute what each button shows, then restyle. Text and textures are safe in
--- combat; if visibility changed, Layout() queues itself.
function Bar:Refresh()
	if not self.frame then
		return
	end
	local totems = self:ResolveTotems()
	local visibilityChanged = false
	for _, b in ipairs(self.buttons) do
		if b.spec.kind == "element" then
			local before = b.totem ~= nil
			b.totem = totems[b.spec.key]
			if before ~= (b.totem ~= nil) then
				visibilityChanged = true
			end
		end
	end
	self.actionMode = self:ActionMode()
	self.projection = { ns.Data:Projection() }
	self.frame.label:SetText(self:LabelText())
	self:ApplySecure()
	if visibilityChanged or self.layoutPending then
		self:Layout()
	end
	Themes:Apply()
	self:UpdateKeys()
end

--- "Profile name", or "Old -> New" while a switch waits for combat to end.
function Bar:LabelText()
	local P = ns.Profiles
	if not P.applied and not P.queued then
		return L.BAR_PREVIEW
	end
	local text = P:Label(P.applied)
	if P.queued then
		text = text .. " -> " .. P:Label(P.queued)
	end
	return text
end

--- What each secure button should do: { type, spell } or nil for nothing.
--- Spells are set by NAME, so the game casts the highest rank you know (Forever has
--- ranks); a spell ID would pin one rank.
function Bar:SecureSpec(b)
	local kind = b.spec.kind
	if kind == "element" and b.totem then
		return "spell", b.totem.name
	elseif kind == "projection" then
		return "spell", self.projection[1]
	end
	-- Action (M7/M8) and Profile (M5) do nothing yet.
	return nil, nil
end

--- Write the casting attributes. SetAttribute on a secure button is blocked in
--- combat, so a change that lands mid-fight is queued for PLAYER_REGEN_ENABLED --
--- the button keeps casting what it had until then.
function Bar:ApplySecure()
	if not self.buttons then
		return
	end
	if InCombatLockdown() then
		self.securePending = true
		return
	end
	self.securePending = false
	for _, b in ipairs(self.buttons) do
		local actionType, spell = self:SecureSpec(b)
		if b:GetAttribute("type") ~= actionType then
			b:SetAttribute("type", actionType)
		end
		if b:GetAttribute("spell") ~= spell then
			b:SetAttribute("spell", spell)
		end
	end
end

function Bar:UpdateKeys()
	for _, b in ipairs(self.buttons or {}) do
		b.key:SetText(ns.Keybinds.LabelFor(b.spec.name))
	end
end

--- Face text for a button in Initials style (and whenever there is no icon).
local function faceText(b, mode)
	local kind = b.spec.kind
	if kind == "element" then
		return b.totem and b.totem.code or L.EMPTY_SLOT
	elseif kind == "action" then
		return mode == "cote" and L.ACTION_COTE or L.ACTION_SEQ
	elseif kind == "projection" then
		-- From the spell's real name: Forever renamed Totemic Projection to Totemic Call.
		return Bar.projection and ns.Data.Abbreviate(Bar.projection[1]) or L.PROJECTION_SHORT
	end
	return ns.Profiles:ShortCode(ns.Profiles.applied)
end

--- Icon for Blizzard-icon style, or nil to keep text.
local function faceIcon(b, mode)
	local kind = b.spec.kind
	if kind == "element" and b.totem then
		return C_Spell.GetSpellTexture(b.totem.spellID)
	elseif kind == "action" and mode == "cote" then
		return C_Spell.GetSpellTexture(TOTEM_MULTI_CAST_SUMMON_SPELLS[1])
	elseif kind == "projection" and Bar.projection and Bar.projection[3] then
		return C_Spell.GetSpellTexture(Bar.projection[2])
	end
	return nil
end

function Bar:StyleButton(b, theme)
	local s = settings()
	local kind, key = b.spec.kind, b.spec.key
	-- "empty" = nothing to cast: an element without a totem, or Projection not learned.
	local empty = (kind == "element" and not b.totem)
		or (kind == "projection" and not (self.projection and self.projection[3]))
	local mode = self.actionMode

	-- Ink: element colour for elements, accent for the action button.
	local ink = (kind == "element" and theme[key]) or (kind == "action" and theme.accent) or theme.text
	if empty then
		ink = theme.muted
	end

	local icon = s.buttonStyle == "icons" and faceIcon(b, mode) or nil
	b.icon:SetShown(icon ~= nil)
	if icon then
		b.icon:SetTexture(icon)
		b.icon:SetDesaturated(false)
	end
	b.text:SetShown(icon == nil)

	if theme.flat then
		b.bg:SetColorTexture(RGB(empty and theme.panel or theme.button))
		b.border:SetShown(true)
		b.border:SetColor(RGB(b.hovered and theme.accent or theme.border))
		b.classicFrame:Hide()
		setFont(b.text, kind == "profile" and Themes.FONTS.mono or Themes.FONTS.initials,
			kind == "profile" and 8 or 13)
		b.text:SetShadowOffset(0, 0)
		b.text:SetTextColor(RGB(ink))
	else
		local grad = theme.gradients[(empty and kind == "element") and "empty" or key]
		b.bg:SetColorTexture(1, 1, 1, 1)
		b.bg:SetGradient("VERTICAL", CreateColor(RGB(grad[2])), CreateColor(RGB(grad[1])))
		b.border:SetShown(true)
		b.border:SetColor(0, 0, 0, 1)
		b.classicFrame:Show()
		b.classicFrame:SetVertexColor(b.hovered and 1 or 0.9, b.hovered and 0.9 or 0.8, b.hovered and 0.6 or 0.6)
		setFont(b.text, kind == "profile" and Themes.FONTS.mono or Themes.FONTS.initials,
			kind == "profile" and 8 or 13, "OUTLINE")
		b.text:SetShadowOffset(1, -1)
		-- Nothing-to-cast faces use the theme's muted colour. They were 40% grey, which
		-- vanished on the dark gradients (Totemic Projection read as blank in game).
		if empty then
			b.text:SetTextColor(RGB(theme.muted))
		else
			b.text:SetTextColor(1, 1, 1)
		end
	end
	b.text:SetText(faceText(b, mode))

	-- 2px element line along the bottom, flat themes only (classic has bevels instead).
	if kind == "element" and theme.flat then
		b.line:Show()
		b.line:ClearAllPoints()
		b.line:SetPoint("BOTTOMLEFT", 3, 2)
		b.line:SetPoint("BOTTOMRIGHT", -3, 2)
		b.line:SetHeight(2 * onePixel(b))
		b.line:SetColorTexture(RGB(theme[key], empty and 0.25 or 0.9))
	else
		b.line:Hide()
	end

	setFont(b.key, Themes.FONTS.mono, 8, theme.flat and "" or "OUTLINE")
	b.key:SetTextColor(RGB(theme.text))
	b.key:SetShadowColor(RGB(theme.bg))
	b.key:SetShadowOffset(1, -1)
	setFont(b.count, Themes.FONTS.mono, 9, theme.flat and "" or "OUTLINE")
	b.count:SetTextColor(RGB(theme.accent))
	b.count:SetText("") -- sequence step counter arrives in M7

	if b.dot then
		-- Success colour = automatic profile switching, warning = manually pinned (M5).
		b.dot:SetColorTexture(RGB(ns.addon.db.global.manual and theme.warn or theme.ok))
	end
end

function Bar:ApplyTheme(theme)
	if not self.frame then
		return
	end
	local f = self.frame
	f.bg:SetColorTexture(RGB(theme.bg, 0.86))
	f.border:SetColor(RGB(theme.border))
	f.sep:SetColorTexture(RGB(theme.border))
	setFont(f.label, Themes.FONTS.heading, 11)
	f.label:SetTextColor(RGB(theme.text))
	f.label:SetShadowColor(0, 0, 0, 1)
	f.label:SetShadowOffset(1, -1)
	if self.mover then
		self.mover.tint:SetColorTexture(RGB(theme.accent, 0.18))
		setFont(self.mover.hint, Themes.FONTS.heading, 11)
		self.mover.hint:SetTextColor(RGB(theme.accent))
	end
	for _, b in ipairs(self.buttons) do
		self:StyleButton(b, theme)
	end
end

-- ------------------------------------------------------------------ hover

function Bar:OnEnterButton(b)
	b.hovered = true
	self:StyleButton(b, Themes:Current())
	GameTooltip:SetOwner(b, "ANCHOR_TOP")
	local kind = b.spec.kind
	if kind == "element" and b.totem then
		GameTooltip:SetSpellByID(b.totem.spellID)
	elseif kind == "element" then
		GameTooltip:SetText(L["EMPTY_" .. b.spec.key:upper()])
	elseif kind == "action" then
		GameTooltip:SetText(self.actionMode == "cote" and L.TIP_ACTION_COTE or L.TIP_ACTION_SEQ)
	elseif kind == "projection" and self.projection[3] then
		GameTooltip:SetSpellByID(self.projection[2])
	elseif kind == "projection" then
		GameTooltip:SetText(L.TIP_PROJECTION_UNKNOWN)
	else
		local P = ns.Profiles
		GameTooltip:SetText(P:Label(P.applied))
		GameTooltip:AddLine(ns.addon.db.global.manual and L.TIP_MANUAL or L.TIP_AUTO, 1, 1, 1)
		if P.queued then
			GameTooltip:AddLine((L.TIP_QUEUED):format(P:Label(P.queued)), 1, 0.8, 0.3)
		end
		GameTooltip:AddLine(L.TIP_PROFILE, 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

function Bar:OnLeaveButton(b)
	b.hovered = false
	self:StyleButton(b, Themes:Current())
	GameTooltip:Hide()
end

-- ------------------------------------------------------------------ settings API

local VALID = {
	layout = { horizontal = true, vertical = true, grid = true },
	buttonStyle = { initials = true, icons = true },
	emptySlot = { grey = true, hide = true },
	flyoutDir = { up = true, down = true, left = true, right = true },
}

--- Change a bar setting by name. Returns false for an invalid value.
function Bar:Set(name, value)
	if VALID[name] and not VALID[name][value] then
		return false
	end
	if name == "scale" then
		value = tonumber(value)
		if not value or value < 0.5 or value > 2 then
			return false
		end
	end
	settings()[name] = value
	if InCombatLockdown() and (name == "layout" or name == "scale" or name == "emptySlot") then
		ns.addon:Log(L.COMBAT_QUEUED)
	end
	self:Layout()
	Themes:Apply()
	return true
end

-- ------------------------------------------------------------------ wiring

function Bar:OnRegenEnabled()
	if not self.frame then
		self:Build()
		return
	end
	if self.resetPending then
		self.resetPending = false
		self:ResetPosition()
	end
	if self.layoutPending then
		self:Layout()
	end
	if self.securePending then
		self:ApplySecure()
	end
end

function Bar:Build()
	self:Create()
	Themes:Register(function(theme) Bar:ApplyTheme(theme) end)
	self:Refresh()
	self:Layout()
end

function Bar:Init()
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
	self:RegisterEvent("UPDATE_BINDINGS", "UpdateKeys")
	self:RegisterEvent("UI_SCALE_CHANGED", "Layout")
	self:RegisterEvent("DISPLAY_SIZE_CHANGED", "Layout")
	self:RegisterEvent("SPELLS_CHANGED", "Refresh")
	self:RegisterMessage("TOTEMICACCORD_TOTEMS_CHANGED", "Refresh")
	-- Secure frames should be created out of combat. A /reload mid-fight lands here
	-- in combat, so wait for it to end.
	if InCombatLockdown() then
		return
	end
	self:Build()
end
