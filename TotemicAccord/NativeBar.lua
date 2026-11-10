--[[
	NativeBar.lua -- the game's own totem bar: capture it, and write profiles into it so
	Call of the Elements drops the profile's totems.

	The native bar (MultiCastActionBarFrame) has pages of 4 buttons; page 1 is the one
	Call of the Elements casts. Its buttons are ordinary action slots on the multicast
	bar. From MultiCastActionBarFrame.lua and SecureActionButtonMixin:CalculateAction:

	    actionSlot = (C_ActionBar.GetMultiCastBarIndex() - 1) * NUM_ACTIONBAR_BUTTONS
	               + (page - 1) * NUM_MULTI_CAST_BUTTONS_PER_PAGE + <element's TOTEM_SLOT>

	  read:  GetActionInfo(actionSlot)            -> "spell", spellID
	  write: SetMultiCastSpell(actionSlot, spellID) -- protected; 0 clears the slot

	SetMultiCastSpell can only be reached through a secure button of type "multispell".
	So there are four hidden buttons, TotemicAccordSync1..4 (Earth, Fire, Water, Air),
	whose attributes say "put spell X into slot Y". The Action button in Call of the
	Elements mode is a macro that /clicks all four, then casts Call of the Elements: one
	key press writes the profile into the native bar and casts it.

	Two traps, both handled:
	  * The multispell action reads its slot via CalculateAction, which only honours our
	    "action" attribute when the button's ID is 0. Never SetID these buttons.
	  * A /click from a macro arrives as a key-up. With "cast on key down" enabled, the
	    secure template ignores key-ups -- unless the button says useOnKeyDown = false.

	The captured snapshot is a COPY of the native page taken before we start writing to
	it, used as the last fallback profile.
]]

local _, ns = ...
local L = ns.L

local Native = {}
ns.NativeBar = Native
LibStub("AceEvent-3.0"):Embed(Native)

local COTE_PAGE = 1

local function db()
	return ns.addon.db.global
end

--- The action slot of an element on the Call of the Elements page.
function Native.ActionSlot(element)
	local barIndex = C_ActionBar.GetMultiCastBarIndex()
	return (barIndex - 1) * NUM_ACTIONBAR_BUTTONS
		+ (COTE_PAGE - 1) * NUM_MULTI_CAST_BUTTONS_PER_PAGE
		+ element.slot
end

function Native.CallOfTheElementsID()
	return TOTEM_MULTI_CAST_SUMMON_SPELLS[COTE_PAGE]
end

function Native.CallOfTheElementsName()
	return C_Spell.GetSpellName(Native.CallOfTheElementsID())
end

-- ------------------------------------------------------------------ capture

--- What the native Call of the Elements page holds now: { earth = {spellID, name}, ... }.
function Native:Read()
	local page = {}
	for _, e in ipairs(ns.Data.ELEMENTS) do
		local kind, id = GetActionInfo(Native.ActionSlot(e))
		if kind == "spell" and id and id > 0 then
			page[e.key] = { spellID = id, name = C_Spell.GetSpellName(id) }
		end
	end
	return page
end

--- Store the native page as the "captured" fallback profile. Returns the number of
--- elements captured.
function Native:Capture()
	local page = self:Read()
	local count = 0
	for _ in pairs(page) do
		count = count + 1
	end
	if count > 0 then
		db().captured = page
		ns.Profiles:Update("captured")
	end
	return count
end

-- ------------------------------------------------------------------ sync buttons

function Native:CreateSyncButtons()
	self.sync = {}
	for i, e in ipairs(ns.Data.ELEMENTS) do
		local b = CreateFrame("Button", "TotemicAccordSync" .. i, UIParent, "SecureActionButtonTemplate")
		b:Hide() -- /click works on hidden buttons
		b:SetAttribute("type", "multispell")
		b:SetAttribute("useOnKeyDown", false)
		b.element = e
		-- Once we have written to the native page, it no longer holds only the player's
		-- own setup, so automatic first-run capture must stop.
		b:HookScript("PostClick", function() db().nativeWritten = true end)
		self.sync[i] = b
	end
end

--- Spell ID the native slot should hold for each element: the applied profile's totem,
--- or 0 (clear) when the profile leaves the element empty.
function Native:DesiredSpells()
	local totems = ns.Profiles:DisplayedTotems()
	local out = {}
	for _, e in ipairs(ns.Data.ELEMENTS) do
		local t = totems[e.key]
		out[e.key] = t and t.spellID or 0
	end
	return out
end

--- Point the sync buttons at the applied profile. Attributes: out of combat only, so a
--- change mid-fight is queued (the Action button then keeps syncing the old profile,
--- matching what it shows).
function Native:ApplySync()
	if not self.sync then
		return
	end
	if InCombatLockdown() then
		self.pending = true
		return
	end
	self.pending = false
	local want = self:DesiredSpells()
	for _, b in ipairs(self.sync) do
		local slot = Native.ActionSlot(b.element)
		if b:GetAttribute("action") ~= slot then
			b:SetAttribute("action", slot)
		end
		if b:GetAttribute("spell") ~= want[b.element.key] then
			b:SetAttribute("spell", want[b.element.key])
		end
	end
end

--- The Action button's macro in Call of the Elements mode.
function Native:MacroText()
	local lines = {}
	for i = 1, #ns.Data.ELEMENTS do
		lines[#lines + 1] = "/click TotemicAccordSync" .. i
	end
	lines[#lines + 1] = "/cast " .. (Native.CallOfTheElementsName() or "Call of the Elements")
	return "#showtooltip " .. (Native.CallOfTheElementsName() or "") .. "\n" .. table.concat(lines, "\n")
end

-- ------------------------------------------------------------------ hiding it

--- The game has no option to hide its totem bar: TotemActionBarMixin:UpdateShownState
--- shows it whenever an element has totems, and Edit Mode's "Totem Bar" box only shows it
--- for positioning. So it is reparented to a hidden frame: Blizzard's own SetShown calls
--- keep working, the bar just never draws. Its action slots, which Call of the Elements
--- and our sync buttons use, don't depend on the frame being visible. It holds secure
--- buttons, so SetParent waits for combat to end.
local hider

function Native:ApplyHidden()
	local frame = MultiCastActionBarFrame
	if not frame then
		return
	end
	if InCombatLockdown() then
		self.hidePending = true
		return
	end
	self.hidePending = nil
	if db().settings.hideNativeBar then
		if not hider then
			hider = CreateFrame("Frame")
			hider:Hide()
		end
		frame:SetParent(hider)
	elseif hider and frame:GetParent() == hider then
		frame:SetParent(UIParent) -- its parent in MultiCastActionBarFrame.xml
	end
end

-- ------------------------------------------------------------------ wiring

function Native:OnRegenEnabled()
	if self.pending then
		self:ApplySync()
	end
	if self.hidePending then
		self:ApplyHidden()
	end
end

--- First run: snapshot the native page before we ever write to it, so the player's own
--- setup survives as the last fallback.
function Native:CaptureIfFirstRun()
	if next(db().captured) == nil and not db().nativeWritten then
		local n = self:Capture()
		if n > 0 then
			ns.addon:Log(L.CAPTURED_FIRST_RUN, n)
		end
	end
end

function Native:Init()
	if not InCombatLockdown() then
		self:CreateSyncButtons()
		self:ApplySync()
	end
	self:CaptureIfFirstRun()
	self:ApplyHidden()
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if not self.sync then
			self:CreateSyncButtons()
		end
		self:OnRegenEnabled()
	end)
	-- The native bar fills in after login and when Call of the Elements is learned.
	self:RegisterEvent("UPDATE_MULTI_CAST_ACTIONBAR", "CaptureIfFirstRun")
end
