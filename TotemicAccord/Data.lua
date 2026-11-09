--[[
	Data.lua -- totem discovery, element mapping, abbreviations.

	Elements vs slots: the engine's totem slots are FIRE=1, EARTH=2, WATER=3, AIR=4
	(Constants.lua), while the bar shows Earth, Fire, Water, Air -- which is exactly
	SHAMAN_TOTEM_PRIORITIES. We keep the two ideas apart: an element has a display
	position and a slot constant, and neither is ever a hardcoded number.
	GetNumTotemSlots() returns 8 on Forever, so never loop 1..GetNumTotemSlots().

	Where the element of a totem comes from, best source first:
	  1. multicast  GetMultiCastTotemSpells(slot) -- the native totem bar's own list.
	                Authoritative. Verified in game: already populated at level 18,
	                before Call of the Elements, for every element that has a totem.
	  2. learned    After you drop a totem, GetTotemInfo(slot) says which slot it went
	                into. We remember that per character. Out of combat only: totem
	                info is secret in combat.
	  3. fallback   A table of known totem names. Needed because Sequence mode is what
	                you use BEFORE level 20, exactly when source 1 is empty.
	A totem the spellbook has but none of these can place is reported, not guessed.

	Totems are recognised by the word "Totem" in the spell name, so discovery assumes
	an English client for now (sources 1 and 2 are language-independent).
]]

local _, ns = ...

local Data = {}
ns.Data = Data
-- Own event registry: AceEvent keeps one handler per event per object, so sharing the
-- addon object would let a later module silently replace these handlers.
LibStub("AceEvent-3.0"):Embed(Data)

-- ------------------------------------------------------------------ elements

local SLOT_TO_KEY = {
	[EARTH_TOTEM_SLOT] = "earth",
	[FIRE_TOTEM_SLOT] = "fire",
	[WATER_TOTEM_SLOT] = "water",
	[AIR_TOTEM_SLOT] = "air",
}

--- Elements in display order: { key = "earth", slot = <EARTH_TOTEM_SLOT> }, ...
Data.ELEMENTS = {}
for _, slot in ipairs(SHAMAN_TOTEM_PRIORITIES) do
	Data.ELEMENTS[#Data.ELEMENTS + 1] = { key = SLOT_TO_KEY[slot], slot = slot }
end

Data.ELEMENT_BY_KEY = {}
for _, e in ipairs(Data.ELEMENTS) do
	Data.ELEMENT_BY_KEY[e.key] = e
end

-- ------------------------------------------------------------------ fallback names
-- Source 3 only. Keyed by the name with "Totem" removed, as Abbreviate sees it.
-- A totem here that Forever doesn't have is harmless; one Forever has that is missing
-- here shows up in /ta selftest as "unplaced" until it is cast once (source 2).

local FALLBACK_ELEMENT = {
	-- earth
	["Stoneskin"] = "earth", ["Stoneclaw"] = "earth", ["Earthbind"] = "earth",
	["Strength of Earth"] = "earth", ["Tremor"] = "earth", ["Earth Elemental"] = "earth",
	-- fire
	["Searing"] = "fire", ["Fire Nova"] = "fire", ["Magma"] = "fire",
	["Flametongue"] = "fire", ["Frost Resistance"] = "fire", ["of Wrath"] = "fire",
	["Fire Elemental"] = "fire",
	-- water
	["Healing Stream"] = "water", ["Mana Spring"] = "water", ["Mana Tide"] = "water",
	["Poison Cleansing"] = "water", ["Disease Cleansing"] = "water",
	["Fire Resistance"] = "water", ["Cleansing"] = "water",
	-- air
	["Grounding"] = "air", ["Windfury"] = "air", ["Windwall"] = "air",
	["Grace of Air"] = "air", ["Nature Resistance"] = "air", ["Sentry"] = "air",
	["Tranquil Air"] = "air", ["Wrath of Air"] = "air",
}

-- ------------------------------------------------------------------ abbreviations

--- Compound words and clashes the generic rules get wrong (build prompt 6.7).
Data.ABBREVIATION_OVERRIDES = {
	["Stoneskin"] = "SS",
	["Stoneclaw"] = "SC",
	["Earthbind"] = "EB",
	["Windfury"] = "WF",
	["Windwall"] = "WW",
	["Flametongue"] = "FT",
	["Frost Resistance"] = "FrR",
	["Fire Resistance"] = "FiR",
}

local SKIP_WORDS = { ["of"] = true, ["the"] = true }

--- "Strength of Earth Totem" -> "Strength of Earth". "Totem of Wrath" -> "of Wrath".
local function baseName(name)
	local s = name:gsub("%f[%a]Totem%f[%A]", ""):gsub("%s+", " ")
	return (s:gsub("^ ", ""):gsub(" $", ""))
end
Data.BaseName = baseName

--- Button initials for a totem spell name.
---   several words -> initials, skipping "of"/"the" and "Totem"  (Healing Stream -> HS)
---   one word      -> first two letters                         (Searing -> Se)
---   overrides win                                               (Stoneskin -> SS)
function Data.Abbreviate(name)
	local base = baseName(name)
	local override = Data.ABBREVIATION_OVERRIDES[base]
	if override then
		return override
	end
	local words = {}
	for word in base:gmatch("%S+") do
		if not SKIP_WORDS[word:lower()] then
			words[#words + 1] = word
		end
	end
	if #words == 0 then
		return "?"
	elseif #words == 1 then
		local w = words[1]
		return w:sub(1, 1):upper() .. w:sub(2, 2):lower()
	end
	local initials = {}
	for _, w in ipairs(words) do
		initials[#initials + 1] = w:sub(1, 1):upper()
	end
	return table.concat(initials)
end

-- ------------------------------------------------------------------ discovery

local function isTotemName(name)
	return name ~= nil and name:find("%f[%a]Totem%f[%A]") ~= nil
end

--- Every multicast spell, per element slot. Empty before Call of the Elements.
local function readMulticast()
	local byKey = {}
	if not GetMultiCastTotemSpells then
		return byKey
	end
	for _, e in ipairs(Data.ELEMENTS) do
		-- The native bar's own update calls this with the slot constant; on the Call
		-- of the Elements page the action ID equals the slot, so both uses agree.
		local ids = { GetMultiCastTotemSpells(e.slot) }
		byKey[e.key] = ids
	end
	return byKey
end

--- Player spellbook: learned spells plus not-yet-learned ("future") ones.
--- Ranks may appear as separate entries, so results are keyed by name.
local function readSpellbook()
	local learned, future = {}, {}
	local bank = Enum.SpellBookSpellBank.Player
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info and not info.shouldHide then
			for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
				if item and item.name and not item.isPassive then
					if item.itemType == Enum.SpellBookItemType.Spell then
						learned[item.name] = item.actionID
					elseif item.itemType == Enum.SpellBookItemType.FutureSpell then
						future[item.name] = {
							spellID = item.actionID,
							level = C_SpellBook.GetSpellBookItemLevelLearned(i, bank),
						}
					end
				end
			end
		end
	end
	return learned, future
end

--- Rebuild Data.totems / Data.unplaced / Data.future from the client.
--- Data.totems[elementKey] = list of { spellID, name, code, source }, sorted by name.
function Data:Discover()
	local learnedElements = ns.addon.db and ns.addon.db.global.learnedElements or {}
	local multicast = readMulticast()
	local spellbook, future = readSpellbook()

	local totems, seen = {}, {}
	for _, e in ipairs(Data.ELEMENTS) do
		totems[e.key] = {}
	end

	local function add(key, spellID, name, source)
		if seen[name] then
			return
		end
		seen[name] = true
		local list = totems[key]
		list[#list + 1] = { spellID = spellID, name = name, code = Data.Abbreviate(name), source = source }
	end

	-- 1. multicast: authoritative, and language-independent.
	local multicastCount = 0
	for key, ids in pairs(multicast) do
		for _, id in ipairs(ids) do
			local name = C_Spell.GetSpellName(id)
			if name then
				add(key, id, name, "multicast")
				multicastCount = multicastCount + 1
			end
		end
	end

	-- 2 + 3. spellbook totems placed by what we learned, then by name.
	local unplaced = {}
	for name, spellID in pairs(spellbook) do
		if isTotemName(name) and not seen[name] then
			local key = learnedElements[name]
			local source = "learned"
			if not key then
				key = FALLBACK_ELEMENT[baseName(name)]
				source = "fallback"
			end
			if key then
				add(key, spellID, name, source)
			else
				unplaced[#unplaced + 1] = name
			end
		end
	end

	for _, list in pairs(totems) do
		table.sort(list, function(a, b) return a.name < b.name end)
	end
	table.sort(unplaced)

	self.totems = totems
	self.unplaced = unplaced
	self.future = future
	self.spellbook = spellbook
	self.multicastCount = multicastCount
	self:CheckAbbreviations()
	self:SendMessage("TOTEMICACCORD_TOTEMS_CHANGED")
	return totems
end

--- Known totems for an element key, in name order.
function Data:GetTotems(key)
	return self.totems and self.totems[key] or {}
end

--- Find which element a totem name belongs to, from what discovery saw.
function Data:ElementOf(name)
	for key, list in pairs(self.totems or {}) do
		for _, t in ipairs(list) do
			if t.name == name then
				return key
			end
		end
	end
end

--- Codes must be unique within an element, or two buttons in one flyout would read
--- the same. New Forever totems may need an override; this is where that shows up.
function Data:CheckAbbreviations()
	local clashes = {}
	for _, e in ipairs(Data.ELEMENTS) do
		local byCode = {}
		for _, t in ipairs(self:GetTotems(e.key)) do
			byCode[t.code] = byCode[t.code] or {}
			table.insert(byCode[t.code], t.name)
		end
		for code, names in pairs(byCode) do
			if #names > 1 then
				clashes[#clashes + 1] = ("%s %s: %s"):format(e.key, code, table.concat(names, ", "))
			end
		end
	end
	table.sort(clashes)
	self.clashes = clashes
	for _, c in ipairs(clashes) do
		ns.addon:Debug("abbreviation clash -- %s", c)
	end
	return clashes
end

-- ------------------------------------------------------------------ learning (source 2)

--- After a totem goes down, record which slot (= element) it landed in. Skipped in
--- combat: GetTotemInfo is SecretWhenTotemSlotSecret there, and comparing a secret
--- value raises an error. issecretvalue guards the case where a slot is secret for
--- some other reason we have not seen yet.
function Data:LearnFromActiveTotems()
	if InCombatLockdown() then
		return
	end
	local store = ns.addon.db.global.learnedElements
	local changed = false
	for _, e in ipairs(Data.ELEMENTS) do
		local haveTotem, _, _, _, _, _, spellID = GetTotemInfo(e.slot)
		if issecretvalue(haveTotem) or issecretvalue(spellID) then
			return
		end
		if haveTotem and spellID and spellID > 0 then
			local name = C_Spell.GetSpellName(spellID)
			if name and store[name] ~= e.key then
				store[name] = e.key
				changed = true
				ns.addon:Debug("learned: %s -> %s", name, e.key)
			end
		end
	end
	if changed then
		self:Discover()
	end
end

-- ------------------------------------------------------------------ wiring

--- SPELLS_CHANGED can fire in bursts; coalesce into one rediscovery.
function Data:ScheduleDiscover()
	if self.pending then
		return
	end
	self.pending = true
	C_Timer.After(0.2, function()
		self.pending = false
		self:Discover()
	end)
end

function Data:Init()
	self:Discover()
	self:RegisterEvent("SPELLS_CHANGED", "ScheduleDiscover")
	self:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", "ScheduleDiscover")
	self:RegisterEvent("UPDATE_MULTI_CAST_ACTIONBAR", "ScheduleDiscover")
	self:RegisterEvent("PLAYER_TOTEM_UPDATE", "LearnFromActiveTotems")
end
