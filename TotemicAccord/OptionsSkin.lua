--[[
	OptionsSkin.lua -- draws the options window in the bar's theme.

	The window is built by our PRIVATE copies of AceGUI and AceConfigDialog
	("TotemicAccordGUI-1.0", "TotemicAccordConfigDialog-1.0"; see Libs/VERSIONS.md). The
	shared AceGUI recycles widgets between addons (Questie, RareScanner, OpenMap here), so
	restyling it would leak our theme into their windows. Our copy has its own widget pool,
	so every widget it creates can be restyled permanently -- no undo needed.

	How: wrap the private AceGUI:Create; after a widget is built, restyle it for its type
	(flat panel colours, 1px borders, Manrope, accent for selection). Methods that recolour
	or rebuild a widget later (SetDisabled, BuildTabs, SetFontObject, ...) are wrapped per
	instance to re-apply the skin. A theme switch re-skins every live widget.

	Every skin runs in pcall: a skin that hits an unexpected region costs looks, never the
	options window itself. The game's Options > AddOns panel still uses the shared,
	Blizzard-styled AceConfigDialog -- it lives inside Blizzard's settings frame.
]]

local _, ns = ...
local Themes = ns.Themes
local RGB = Themes.RGB

local Skin = {}
ns.OptionsSkin = Skin

local GUI = LibStub("TotemicAccordGUI-1.0")
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground" -- plain white; AceGUI's InlineGroup uses it
local FLAT_BACKDROP = { bgFile = FLAT, edgeFile = FLAT, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }

local live = setmetatable({}, { __mode = "k" }) -- every skinned widget, for theme switches

-- ------------------------------------------------------------------ primitives

local function theme()
	return Themes:Current()
end

local function font(fs, which, size, hex)
	if not fs then
		return
	end
	if not fs:SetFont(Themes.FONTS[which], size, "") then
		fs:SetFont((GameFontNormal:GetFont()), size, "")
	end
	if hex then
		fs:SetTextColor(RGB(hex))
	end
	fs:SetShadowOffset(0, 0)
end

local function flatBackdrop(frame, bgHex, bgAlpha, borderHex)
	if frame and frame.SetBackdrop then
		frame:SetBackdrop(FLAT_BACKDROP)
		frame:SetBackdropColor(RGB(bgHex, bgAlpha or 1))
		frame:SetBackdropBorderColor(RGB(borderHex))
	end
end

--- Hide every texture a Blizzard template put on this frame (keeps fontstrings).
local function hideTemplateTextures(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("Texture") and not region.taOwn then
			region:SetAlpha(0)
		end
	end
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local tex = frame[getter] and frame[getter](frame)
		if tex then
			tex:SetAlpha(0)
		end
	end
end

--- Our own flat face for a frame: background + 1px border, created once. `inset` pulls
--- it in horizontally (Ace overlaps tab buttons by 10px; Blizzard's slanted art hid that).
local function face(frame, bgHex, borderHex, bgAlpha, inset)
	local s = frame.taFace
	if not s then
		s = {}
		s.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
		s.bg.taOwn = true
		s.edges = {}
		for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
			local t = frame:CreateTexture(nil, "BORDER", nil, 7)
			t.taOwn = true
			s.edges[side] = t
		end
		frame.taFace = s
	end
	local x = inset or 0
	local e = s.edges
	for _, t in ipairs({ s.bg, e.TOP, e.BOTTOM, e.LEFT, e.RIGHT }) do t:ClearAllPoints() end
	s.bg:SetPoint("TOPLEFT", x, 0); s.bg:SetPoint("BOTTOMRIGHT", -x, 0)
	e.TOP:SetPoint("TOPLEFT", x, 0); e.TOP:SetPoint("TOPRIGHT", -x, 0); e.TOP:SetHeight(1)
	e.BOTTOM:SetPoint("BOTTOMLEFT", x, 0); e.BOTTOM:SetPoint("BOTTOMRIGHT", -x, 0); e.BOTTOM:SetHeight(1)
	e.LEFT:SetPoint("TOPLEFT", x, 0); e.LEFT:SetPoint("BOTTOMLEFT", x, 0); e.LEFT:SetWidth(1)
	e.RIGHT:SetPoint("TOPRIGHT", -x, 0); e.RIGHT:SetPoint("BOTTOMRIGHT", -x, 0); e.RIGHT:SetWidth(1)
	s.bg:SetColorTexture(RGB(bgHex, bgAlpha or 1))
	for _, t in pairs(s.edges) do
		t:SetColorTexture(RGB(borderHex))
	end
	return s
end

--- Border turns accent on hover, like the bar's buttons.
local function hoverBorder(frame, getWidget)
	if frame.taHover then
		return
	end
	frame.taHover = true
	frame:HookScript("OnEnter", function(f)
		local w = getWidget()
		if f.taFace and not (w and w.disabled) then
			for _, t in pairs(f.taFace.edges) do t:SetColorTexture(RGB(theme().accent)) end
		end
	end)
	frame:HookScript("OnLeave", function(f)
		if f.taFace then
			for _, t in pairs(f.taFace.edges) do t:SetColorTexture(RGB(theme().border)) end
		end
	end)
end

--- A Blizzard panel button (UIPanelButtonTemplate) drawn flat.
local function panelButton(button, disabled)
	local t = theme()
	hideTemplateTextures(button)
	face(button, t.button, t.border)
	local fs = button:GetFontString()
	font(fs, "heading", 12, disabled and t.muted or t.text)
	if fs then
		-- Centre the text; Ace sized some buttons (Accept) for Blizzard's narrower font.
		fs:ClearAllPoints()
		fs:SetPoint("CENTER", button, "CENTER", 0, 0)
		fs:SetJustifyH("CENTER")
		local needed = (fs:GetStringWidth() or 0) + 24
		if (button:GetWidth() or 0) < needed then
			button:SetWidth(needed)
		end
	end
	hoverBorder(button, function() return { disabled = disabled } end)
end

local function scrollbar(bar)
	if not bar then
		return
	end
	local t = theme()
	for _, region in ipairs({ bar:GetRegions() }) do
		if region:IsObjectType("Texture") and region ~= bar:GetThumbTexture() and not region.taOwn then
			region:SetAlpha(0)
		end
	end
	local thumb = bar:GetThumbTexture()
	if thumb then
		thumb:SetColorTexture(RGB(t.border))
		thumb:SetWidth(6)
	end
	for _, child in ipairs({ bar:GetChildren() }) do -- the up/down arrow buttons
		child:SetAlpha(0)
	end
end

-- ------------------------------------------------------------------ per widget type

local skins = {}

skins.Frame = function(w)
	local t = theme()
	local f = w.frame
	flatBackdrop(f, t.panel, 0.98, t.border)
	-- Title art (UI-DialogBox-Header, fileID 131080) and its two caps: hide them all.
	for _, region in ipairs({ f:GetRegions() }) do
		if region:IsObjectType("Texture") and region:GetTexture() == 131080 then
			region:SetAlpha(0)
		end
	end
	-- Ace puts the title on the header art ABOVE the frame; without the art it sat on the
	-- top border. Move it inside, and give the content room under it.
	font(w.titletext, "heading", 14, t.accent)
	w.titletext:ClearAllPoints()
	w.titletext:SetPoint("TOP", f, "TOP", 0, -14)
	if w.content then
		w.content:ClearAllPoints()
		w.content:SetPoint("TOPLEFT", 18, -40)
		w.content:SetPoint("BOTTOMRIGHT", -18, 46)
	end
	font(w.statustext, "heading", 11, t.muted)
	for _, child in ipairs({ f:GetChildren() }) do
		if child.SetBackdrop and child ~= f then -- the status bar
			flatBackdrop(child, t.bg, 0.6, t.border)
		elseif child:IsObjectType("Button") and child.GetFontString and child:GetFontString() then
			panelButton(child) -- Close
		end
	end
end

skins.TabGroup = function(w)
	local t = theme()
	flatBackdrop(w.border, t.bg, 0.55, t.border)
	if w.content then
		w.content:ClearAllPoints()
		w.content:SetPoint("TOPLEFT", 14, -14)
		w.content:SetPoint("BOTTOMRIGHT", -14, 10)
	end
	font(w.titletext, "heading", 12, t.text)
	for _, tab in ipairs(w.tabs or {}) do
		for _, key in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
			if tab[key] then tab[key]:SetAlpha(0) end
		end
		local hl = tab:GetHighlightTexture()
		if hl then hl:SetAlpha(0) end
		local s = face(tab, tab.selected and t.button or t.panel, t.border, 1, 6)
		if not tab.taLine then
			tab.taLine = tab:CreateTexture(nil, "OVERLAY")
			tab.taLine.taOwn = true
			tab.taLine:SetPoint("BOTTOMLEFT", 7, 1)
			tab.taLine:SetPoint("BOTTOMRIGHT", -7, 1)
			tab.taLine:SetHeight(2)
		end
		tab.taLine:SetColorTexture(RGB(t.accent))
		tab.taLine:SetShown(tab.selected == true)
		s.edges.BOTTOM:SetShown(not tab.selected)
		font(tab.Text, "heading", 12, tab.selected and t.accent or (tab.disabled and t.muted or t.text))
		-- Ace drops tab text 2-3px below centre via these fields (for Blizzard's art);
		-- set them so every later re-anchor keeps it centred with air below.
		tab.selectedTextY, tab.deselectedTextY = 2, 2
		tab.Text:ClearAllPoints()
		tab.Text:SetPoint("CENTER", tab, "CENTER", 0, 2)
		hoverBorder(tab, function() return tab end)
	end
end

skins.ScrollFrame = function(w)
	scrollbar(w.scrollbar)
end

skins.InlineGroup = function(w)
	local t = theme()
	for _, child in ipairs({ w.frame:GetChildren() }) do
		if child.SetBackdrop then
			flatBackdrop(child, t.bg, 0.4, t.border)
		end
	end
	font(w.titletext, "heading", 12, t.text)
end

skins.Button = function(w)
	panelButton(w.frame, w.disabled)
end

skins.CheckBox = function(w)
	local t = theme()
	w.checkbg:SetColorTexture(RGB(t.button))
	w.checkbg:SetSize(16, 16)
	-- Centre the smaller box where Blizzard's 24px art was. The gap before the text is set
	-- in the fork's AlignImage, because Ace re-anchors the text on every click.
	w.checkbg:ClearAllPoints()
	w.checkbg:SetPoint("TOPLEFT", w.frame, "TOPLEFT", 4, -4)
	if not w.checkbg.taEdges then
		local holder = CreateFrame("Frame", nil, w.frame)
		holder:SetAllPoints(w.checkbg)
		w.checkbg.taEdges = face(holder, t.button, t.border, 0)
	end
	for _, e in pairs(w.checkbg.taEdges.edges) do e:SetColorTexture(RGB(t.border)) end
	w.check:SetColorTexture(RGB(t.accent))
	w.check:ClearAllPoints()
	w.check:SetPoint("CENTER", w.checkbg, "CENTER")
	w.check:SetSize(8, 8)
	if w.highlight then
		w.highlight:SetColorTexture(RGB(t.accent, 0.12))
		w.highlight:SetAllPoints(w.checkbg)
	end
	font(w.text, "heading", 12, w.disabled and t.muted or t.text)
end

local function dropdownArrow(button)
	if not button.taArrow then
		button.taArrow = button:CreateTexture(nil, "OVERLAY")
		button.taArrow.taOwn = true
		button.taArrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
		button.taArrow:SetTexCoord(0, 0.5625, 0, 1)
		button.taArrow:SetSize(8, 8)
		button.taArrow:SetPoint("CENTER")
	end
	button.taArrow:SetVertexColor(RGB(theme().muted))
end

skins.Dropdown = function(w)
	local t = theme()
	local dd = w.dropdown
	local name = dd:GetName()
	for _, part in ipairs({ "Left", "Middle", "Right" }) do
		local tex = _G[name .. part]
		if tex then tex:SetAlpha(0) end
	end
	-- The visible box is the widget frame minus the label row.
	if not w.taBox then
		w.taBox = CreateFrame("Frame", nil, w.frame)
		w.taBox:SetPoint("TOPLEFT", dd, "TOPLEFT", 17, -2)
		w.taBox:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", -17, 4)
		w.taBox:SetFrameLevel(dd:GetFrameLevel())
	end
	face(w.taBox, t.button, t.border)
	local button = _G[name .. "Button"]
	if button then
		hideTemplateTextures(button)
		dropdownArrow(button)
	end
	font(w.text, "heading", 12, w.disabled and t.muted or t.text)
	w.text:ClearAllPoints()
	w.text:SetPoint("LEFT", w.taBox, "LEFT", 8, 0)
	w.text:SetPoint("RIGHT", w.taBox, "RIGHT", -22, 0)
	w.text:SetJustifyH("LEFT")
	font(w.label, "heading", 11, t.muted)
end

skins["Dropdown-Pullout"] = function(w)
	local t = theme()
	flatBackdrop(w.frame, t.panel, 0.98, t.border)
	if w.slider then
		flatBackdrop(w.slider, t.bg, 0.6, t.border)
		local thumb = w.slider:GetThumbTexture()
		if thumb then thumb:SetColorTexture(RGB(t.border)) end
	end
end

local function dropdownItem(w)
	local t = theme()
	font(w.text, "heading", 12, w.disabled and t.muted or t.text)
	if w.highlight then
		w.highlight:SetColorTexture(RGB(t.button))
	end
	if w.check then
		w.check:SetColorTexture(RGB(t.accent))
		w.check:SetSize(6, 6)
	end
end
for _, itemType in ipairs({ "Dropdown-Item-Toggle", "Dropdown-Item-Execute", "Dropdown-Item-Header",
	"Dropdown-Item-Menu", "Dropdown-Item-Separator" }) do
	skins[itemType] = dropdownItem
end

skins.Slider = function(w)
	local t = theme()
	flatBackdrop(w.slider, t.button, 1, t.border)
	w.slider:SetHeight(8)
	local thumb = w.slider:GetThumbTexture()
	if thumb then
		thumb:SetColorTexture(RGB(t.accent))
		thumb:SetSize(8, 14)
	end
	-- The thin track puts the 14px handle over the min/max labels (anchored 3px up into the
	-- original 15px track). Move the labels and the input below it, and make room.
	w.lowtext:ClearAllPoints()
	w.lowtext:SetPoint("TOPLEFT", w.slider, "BOTTOMLEFT", 2, -7)
	w.hightext:ClearAllPoints()
	w.hightext:SetPoint("TOPRIGHT", w.slider, "BOTTOMRIGHT", -2, -7)
	w.editbox:ClearAllPoints()
	w.editbox:SetPoint("TOP", w.slider, "BOTTOM", 0, -8)
	w.editbox:SetHeight(16)
	w.frame:SetHeight(56)
	flatBackdrop(w.editbox, t.bg, 0.6, t.border)
	font(w.editbox, "heading", 11, t.text)
	font(w.label, "heading", 12, w.disabled and t.muted or t.text)
	font(w.lowtext, "heading", 10, t.muted)
	font(w.hightext, "heading", 10, t.muted)
end

skins.EditBox = function(w)
	local t = theme()
	hideTemplateTextures(w.editbox)
	face(w.editbox, t.button, t.border)
	font(w.editbox, "heading", 12, t.text)
	font(w.label, "heading", 11, t.muted)
	if w.button then panelButton(w.button) end
end

skins.MultiLineEditBox = function(w)
	local t = theme()
	flatBackdrop(w.scrollBG, t.bg, 0.7, t.border)
	if w.button and w.button:IsShown() then
		-- Ace butts the text box against the Accept button; leave a gap.
		w.scrollBG:SetPoint("BOTTOMLEFT", w.button, "TOPLEFT", 0, 8)
	end
	font(w.editBox, "mono", 11, t.text)
	font(w.label, "heading", 11, t.muted)
	if w.button then panelButton(w.button) end
	scrollbar(w.scrollBar)
end

skins.Keybinding = function(w)
	local t = theme()
	panelButton(w.button, w.disabled)
	font(w.button:GetFontString(), "mono", 11, t.text)
	font(w.label, "heading", 11, t.muted)
	if w.msgframe then
		flatBackdrop(w.msgframe, t.panel, 0.98, t.accent)
	end
end

skins.Heading = function(w)
	local t = theme()
	for _, line in ipairs({ w.left, w.right }) do
		line:SetColorTexture(RGB(t.border))
		line:SetHeight(1)
	end
	font(w.label, "heading", 12, t.accent)
end

skins.Label = function(w)
	local _, size = w.label:GetFont()
	font(w.label, "heading", size or 12, theme().text)
end

-- ------------------------------------------------------------------ application

local RESKIN_AFTER = {
	"SetDisabled", "SetFontObject", "BuildTabs", "SelectTab", "SetType", "SetValue",
	"SetTitle", "SetLabel", "SetImage", "DisableButton",
}

function Skin:Apply(w)
	local fn = w and skins[w.type]
	if not fn then
		return
	end
	local ok, err = pcall(fn, w)
	if not ok then
		ns.addon:Debug("options skin %s: %s", tostring(w.type), tostring(err))
		return
	end
	live[w] = true
	if not w.taWrapped then
		w.taWrapped = true
		for _, method in ipairs(RESKIN_AFTER) do
			local orig = w[method]
			if type(orig) == "function" then
				w[method] = function(widget, ...)
					local r1, r2 = orig(widget, ...)
					pcall(fn, widget)
					return r1, r2
				end
			end
		end
	end
end

function Skin:ReskinAll()
	for w in pairs(live) do
		local fn = skins[w.type]
		if fn then
			pcall(fn, w)
		end
	end
end

function Skin:Init()
	local create = GUI.Create
	GUI.Create = function(lib, widgetType, ...)
		local w = create(lib, widgetType, ...)
		Skin:Apply(w)
		return w
	end
	Themes:Register(function() Skin:ReskinAll() end)
end
