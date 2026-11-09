--[[
	Menu.lua -- a small themed popup menu (profile chooser now, minimap right-click later).

	Blizzard's MenuUtil menus draw in Blizzard's own style; Dio asked for the chooser to
	match the bar's theme. This is a plain (non-secure) frame in the theme's panel colour
	with a 1px border, Manrope text, the selected entry in the accent colour, and a hover
	row in the button colour -- the mock's ".pop" styling.

	Entries: { kind = "title", text = ... }, { kind = "divider" },
	         { kind = "item", text = ..., checked = bool, onClick = fn }.
	Closes on: picking an entry, clicking the owner again, clicking anywhere else, Escape.
]]

local _, ns = ...
local Themes = ns.Themes
local RGB = Themes.RGB

local Menu = {}
ns.Menu = Menu
LibStub("AceEvent-3.0"):Embed(Menu)

local PAD, ROW, TITLE, DIVIDER, MIN_WIDTH = 6, 22, 18, 9, 230

local function createFrame()
	local f = CreateFrame("Frame", "TotemicAccordMenu", UIParent)
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
	f.rows = {}
	f:Hide()
	-- Escape closes frames listed here (Blizzard's UIParentPanelManager).
	tinsert(UISpecialFrames, f:GetName())
	return f
end

function Menu:Row(i)
	local f = self.frame
	local r = f.rows[i]
	if r then
		return r
	end
	r = CreateFrame("Button", nil, f)
	r.hover = r:CreateTexture(nil, "BACKGROUND")
	r.hover:SetAllPoints()
	r.mark = r:CreateTexture(nil, "ARTWORK")
	r.mark:SetSize(5, 5)
	r.mark:SetPoint("LEFT", 6, 0)
	r.line = r:CreateTexture(nil, "ARTWORK")
	r.line:SetPoint("LEFT", 4, 0)
	r.line:SetPoint("RIGHT", -4, 0)
	r.line:SetHeight(1)
	r.text = r:CreateFontString(nil, "OVERLAY")
	r.text:SetFontObject(GameFontNormal)
	r.text:SetPoint("LEFT", 16, 0)
	r.text:SetJustifyH("LEFT")
	r:SetScript("OnEnter", function(row) if row.entry.kind == "item" then row.hover:Show() end end)
	r:SetScript("OnLeave", function(row) row.hover:Hide() end)
	r:SetScript("OnClick", function(row)
		local entry = row.entry
		if entry.kind == "item" then
			Menu:Close()
			entry.onClick()
		end
	end)
	f.rows[i] = r
	return r
end

--- Lay out and style rows; returns the menu's content width and height.
function Menu:Fill(entries)
	local theme = Themes:Current()
	local f = self.frame
	local width, y = MIN_WIDTH, PAD
	for i, entry in ipairs(entries) do
		local r = self:Row(i)
		r.entry = entry
		local h = entry.kind == "title" and TITLE or entry.kind == "divider" and DIVIDER or ROW
		r:SetHeight(h)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
		r:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
		y = y + h
		r.hover:SetColorTexture(RGB(theme.button))
		r.hover:Hide()
		r.line:SetShown(entry.kind == "divider")
		r.line:SetColorTexture(RGB(theme.border))
		r.mark:SetShown(entry.kind == "item" and entry.checked == true)
		r.mark:SetColorTexture(RGB(theme.accent))
		r.text:SetShown(entry.kind ~= "divider")
		if entry.kind == "title" then
			r.text:SetFont(Themes.FONTS.heading, 9, "")
			r.text:SetTextColor(RGB(theme.muted))
			r.text:SetText((entry.text or ""):upper())
			r.text:SetPoint("LEFT", 6, -2)
		elseif entry.kind == "item" then
			r.text:SetFont(entry.checked and Themes.FONTS.initials or Themes.FONTS.heading, 12, "")
			r.text:SetTextColor(RGB(entry.checked and theme.accent or theme.text))
			r.text:SetText(entry.text)
			r.text:SetPoint("LEFT", 16, 0)
		end
		r:EnableMouse(entry.kind == "item")
		r:Show()
		local w = r.text:GetStringWidth()
		if type(w) == "number" and w + 16 + 12 + PAD * 2 > width then
			width = w + 16 + 12 + PAD * 2
		end
	end
	for i = #entries + 1, #f.rows do
		f.rows[i]:Hide()
	end
	f.bg:SetColorTexture(RGB(theme.panel, 0.97))
	for _, tex in pairs(f.edges) do
		tex:SetColorTexture(RGB(theme.border))
	end
	return width, y + PAD
end

--- Open beside `owner` (above it, or to its left when the bar is vertical, like the
--- mock's profile popup), or close if it is already open for that owner.
function Menu:Toggle(owner, entries)
	self.frame = self.frame or createFrame()
	local f = self.frame
	if f:IsShown() and self.owner == owner then
		self:Close()
		return
	end
	self.owner = owner
	local w, h = self:Fill(entries)
	f:SetSize(w, h)
	f:ClearAllPoints()
	local vertical = ns.addon.db.global.settings.layout == "vertical"
	if vertical then
		f:SetPoint("TOPRIGHT", owner, "TOPLEFT", -10, 0)
	else
		f:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 10)
	end
	f:Show()
	self:RegisterEvent("GLOBAL_MOUSE_DOWN", "OnGlobalMouseDown")
end

function Menu:Close()
	if self.frame then
		self.frame:Hide()
	end
	self.owner = nil
	self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
end

--- Clicking anywhere outside the menu (and its owner, which toggles) closes it.
function Menu:OnGlobalMouseDown()
	local f = self.frame
	if f and f:IsShown() and not f:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
		self:Close()
	end
end
