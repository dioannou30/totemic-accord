--[[
	Sequence.lua -- per-profile castsequence, its macro text, the "TA Sequence" game
	macro, and the n/N step counter.

	Each profile has its own sequence: element order, which elements are included (to save
	mana in open-world fights), and reset rules (after combat, and/or after N seconds
	without a press). The Action button in Sequence mode is a secure `type=macro` button
	with this text as `macrotext`:

	    #showtooltip
	    /castsequence reset=combat/20 Strength of Earth Totem, Searing Totem

	The counter follows real casts: an Action button press opens a short window, and a
	successful cast of one of the sequence's spells in that window moves the counter past
	that step. Verified in game that the spell ID is readable in combat. Totems dropped from
	their own element buttons do not count, because the game's castsequence doesn't see
	those either. Following the cast (rather than counting presses) also keeps the counter
	right whether or not the game restarts a sequence when its macro text changes.
]]

local _, ns = ...
local L = ns.L

local Sequence = {}
ns.Sequence = Sequence
LibStub("AceEvent-3.0"):Embed(Sequence)

Sequence.MACRO_NAME = "TA Sequence"
Sequence.MACRO_LIMIT = 255
local PRESS_WINDOW = 1.0 -- seconds between an Action press and the cast it caused

local function db()
	return ns.addon.db.global
end

-- ------------------------------------------------------------------ data

local function defaultSequence()
	local order, include = {}, {}
	for _, e in ipairs(ns.Data.ELEMENTS) do
		order[#order + 1] = e.key
		include[e.key] = true
	end
	return { order = order, include = include, resetCombat = true, resetSeconds = nil }
end

--- The sequence for a profile key (stored, or the default without storing it).
function Sequence:Get(key)
	return (key and db().sequences[key]) or defaultSequence()
end

--- Like Get, but stores a copy first so it can be edited.
function Sequence:Edit(key)
	if not db().sequences[key] then
		db().sequences[key] = defaultSequence()
	end
	return db().sequences[key]
end

--- Spell names in cast order, for the applied profile: included elements that have a totem.
function Sequence:Steps(key)
	key = key or ns.Profiles.applied
	local seq = self:Get(key)
	local totems = ns.Profiles:DisplayedTotems()
	local steps = {}
	for _, element in ipairs(seq.order) do
		local t = totems[element]
		if seq.include[element] and t then
			steps[#steps + 1] = t.name
		end
	end
	return steps
end

--- "#showtooltip\n/castsequence reset=combat/20 A, B" -- omitting what is off. "" if empty.
function Sequence:MacroText(key)
	local steps = self:Steps(key)
	if #steps == 0 then
		return ""
	end
	local seq = self:Get(key or ns.Profiles.applied)
	local resets = {}
	if seq.resetCombat then
		resets[#resets + 1] = "combat"
	end
	if seq.resetSeconds then
		resets[#resets + 1] = tostring(seq.resetSeconds)
	end
	local reset = #resets > 0 and ("reset=" .. table.concat(resets, "/") .. " ") or ""
	return "#showtooltip\n/castsequence " .. reset .. table.concat(steps, ", ")
end

-- ------------------------------------------------------------------ counter

Sequence.position = 1 -- the step the next press will cast

function Sequence:ResetCounter()
	self.position = 1
	self.lastPress = nil
	ns.Bar:UpdateCounter()
end

--- "2/3", or "" when not in Sequence mode or there is nothing to sequence.
function Sequence:CounterText()
	if ns.Bar.actionMode ~= "seq" then
		return ""
	end
	local n = #self:Steps()
	if n == 0 then
		return ""
	end
	return ("%d/%d"):format(math.min(self.position, n), n)
end

--- Called after every Action button click (PostClick hook, non-secure).
function Sequence:OnActionPressed()
	local now = GetTime()
	local seconds = self:Get(ns.Profiles.applied).resetSeconds
	-- castsequence's reset=N restarts after N seconds without a press.
	if seconds and self.lastPress and now - self.lastPress >= seconds then
		self.position = 1
	end
	self.lastPress = now
	self.pressedAt = now
	if seconds then
		C_Timer.After(seconds, function()
			if self.lastPress == now then
				self.position = 1
				ns.Bar:UpdateCounter()
			end
		end)
	end
end

function Sequence:OnSpellcast(_, unit, _, spellID)
	if unit ~= "player" or not self.pressedAt or GetTime() - self.pressedAt > PRESS_WINDOW then
		return
	end
	-- Readable in combat on Forever (verified); stay safe if that ever changes.
	if issecretvalue(spellID) then
		return
	end
	local name = C_Spell.GetSpellName(spellID)
	local steps = self:Steps()
	for i, step in ipairs(steps) do
		if step == name then
			self.position = i % #steps + 1
			self.pressedAt = nil
			ns.Bar:UpdateCounter()
			return
		end
	end
end

function Sequence:OnRegenEnabled()
	if self:Get(ns.Profiles.applied).resetCombat then
		self:ResetCounter()
	end
end

-- ------------------------------------------------------------------ game macro

--- Index of a macro by name. GetMacroIndexByName is not part of Forever's API surface
--- (Blizzard's own macro UI never uses it), so scan the way Blizzard_MacroUI does:
--- character macros live after the account ones.
local function findMacro(name)
	local C = Constants.MacroConsts
	local first, last = C.MAX_ACCOUNT_MACROS + 1, C.MAX_ACCOUNT_MACROS + C.MAX_CHARACTER_MACROS
	for i = first, last do
		if GetMacroInfo(i) == name then
			return i
		end
	end
	for i = 1, C.MAX_ACCOUNT_MACROS do
		if GetMacroInfo(i) == name then
			return i
		end
	end
end

local function characterSlotFree()
	local _, numCharacter = GetNumMacros()
	return numCharacter < Constants.MacroConsts.MAX_CHARACTER_MACROS
end

--- Create (create = true) or update the character macro "TA Sequence". Updating only
--- happens if it already exists, so a deleted macro stays deleted. Macro editing is
--- blocked in combat; an update due then waits for combat to end.
function Sequence:SyncGameMacro(create)
	local text = self:MacroText()
	local index = findMacro(self.MACRO_NAME)
	if not index and not create then
		return
	end
	if InCombatLockdown() then
		self.macroPending = true
		if create then
			ns.addon:Log(L.COMBAT_QUEUED)
		end
		return
	end
	self.macroPending = false
	if #text > self.MACRO_LIMIT then
		ns.addon:Log(L.MACRO_TOO_LONG, #text, self.MACRO_LIMIT)
		return
	end
	local body = text ~= "" and text or L.MACRO_EMPTY_BODY
	if index then
		EditMacro(index, self.MACRO_NAME, "INV_MISC_QUESTIONMARK", body)
		if create then
			ns.addon:Log(L.MACRO_UPDATED, self.MACRO_NAME)
		end
	elseif not characterSlotFree() then
		ns.addon:Log(L.MACRO_NO_SLOT)
	else
		CreateMacro(self.MACRO_NAME, "INV_MISC_QUESTIONMARK", body, true)
		ns.addon:Log(findMacro(self.MACRO_NAME) and L.MACRO_CREATED or L.MACRO_NO_SLOT, self.MACRO_NAME)
	end
end

-- ------------------------------------------------------------------ editing

--- Something about the sequence changed: rewrite the Action button and game macro and
--- restart the counter (castsequence restarts too, or the counter re-syncs on the next cast).
function Sequence:Changed()
	self:ResetCounter()
	ns.Bar:Refresh()
	self:SyncGameMacro(false)
end

function Sequence:SetOrder(order)
	local seen, clean = {}, {}
	for _, element in ipairs(order) do
		if ns.Data.ELEMENT_BY_KEY[element] and not seen[element] then
			seen[element] = true
			clean[#clean + 1] = element
		end
	end
	if #clean ~= #ns.Data.ELEMENTS then
		return false
	end
	self:Edit(ns.Profiles.applied or "global").order = clean
	self:Changed()
	return true
end

function Sequence:SetIncluded(element, included)
	if not ns.Data.ELEMENT_BY_KEY[element] then
		return false
	end
	self:Edit(ns.Profiles.applied or "global").include[element] = included
	self:Changed()
	return true
end

function Sequence:SetResetCombat(on)
	self:Edit(ns.Profiles.applied or "global").resetCombat = on
	self:Changed()
end

function Sequence:SetResetSeconds(seconds)
	if seconds ~= nil and (seconds < 1 or seconds > 600) then
		return false
	end
	self:Edit(ns.Profiles.applied or "global").resetSeconds = seconds
	self:Changed()
	return true
end

-- ------------------------------------------------------------------ wiring

function Sequence:Init()
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcast")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		self:OnRegenEnabled()
		if self.macroPending then
			self:SyncGameMacro(false)
		end
	end)
end
