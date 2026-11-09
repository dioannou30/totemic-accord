--[[
	Profiles.lua -- profile keys, resolution, triggers, manual override, combat queue.

	Forever has one Shaman spec, so the build prompt's spec axis is replaced by the saved
	TALENT LOADOUT (Dio's choice; see docs/decisions.md). A profile is the totem per
	element for one key:

	  "global"              Global default
	  "global:<situation>"  Global, for one situation (the options grid's Global row)
	  "L<id>:default"       a saved loadout's default
	  "L<id>:<situation>"   a saved loadout, for one situation
	  "captured"            the native totem bar snapshot (M8) -- the last fallback

	Resolution, first that exists wins:
	  loadout:situation -> loadout:default -> global:situation -> global -> captured
	The global:situation step keeps automatic world/dungeon/raid/BG/arena switching
	working for characters with no saved loadout (level 18 has none).

	Loadouts are keyed by config ID, which survives renaming; the name is remembered
	only for labels.

	Combat: a switch that becomes due mid-fight is QUEUED (not half-applied) and lands
	on PLAYER_REGEN_ENABLED, so the buttons never show one totem and cast another.
]]

local _, ns = ...
local L = ns.L

local Profiles = {}
ns.Profiles = Profiles
LibStub("AceEvent-3.0"):Embed(Profiles)

-- ------------------------------------------------------------------ situations

--- IsInInstance() instance type -> our situation key, in options-grid column order.
Profiles.SITUATIONS = {
	{ key = "world", instance = "none", code = "OW", label = L.SIT_WORLD },
	{ key = "dungeon", instance = "party", code = "DGN", label = L.SIT_DUNGEON },
	{ key = "raid", instance = "raid", code = "RAID", label = L.SIT_RAID },
	{ key = "bg", instance = "pvp", code = "BG", label = L.SIT_BG },
	{ key = "arena", instance = "arena", code = "ARN", label = L.SIT_ARENA },
}
local SIT_BY_KEY, SIT_BY_INSTANCE = {}, {}
for _, s in ipairs(Profiles.SITUATIONS) do
	SIT_BY_KEY[s.key] = s
	SIT_BY_INSTANCE[s.instance] = s
end

local function db()
	return ns.addon.db.global
end

-- ------------------------------------------------------------------ context

function Profiles:CurrentSituation()
	local _, instanceType = IsInInstance()
	-- Scenarios and anything new count as open world rather than matching nothing.
	return (SIT_BY_INSTANCE[instanceType] or SIT_BY_KEY.world).key
end

local function currentSpecID()
	local S = C_SpecializationInfo
	local index = S.GetSpecialization()
	return index and S.GetSpecializationInfo(index)
end

--- id, name of the selected saved talent loadout, or nil when none is saved.
function Profiles:CurrentLoadout()
	local specID = currentSpecID()
	if not specID then
		return nil
	end
	local id = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
	if not id then
		return nil
	end
	local info = C_Traits.GetConfigInfo(id)
	local name = info and info.name
	if name then
		db().loadoutNames[id] = name -- for labels when another loadout is active
	end
	return id, name
end

-- ------------------------------------------------------------------ keys + labels

local function loadoutPrefix(id)
	return "L" .. id
end

--- Parse a key into its parts: kind ("global"|"loadout"|"captured"), loadout id, situation.
function Profiles.Parse(key)
	if key == "captured" then
		return "captured"
	end
	local head, sit = key:match("^([^:]+):?(.*)$")
	sit = sit ~= "" and sit or "default"
	if head == "global" then
		return "global", nil, sit
	end
	local id = head and tonumber(head:match("^L(%d+)$"))
	if id then
		return "loadout", id, sit
	end
end

--- Friendly key from slash commands -> stored key, or nil.
---   "global", "global:dungeon", "loadout" (= current loadout's default),
---   "loadout:bg", "captured", or an already-stored key like "L102:raid".
function Profiles:NormalizeKey(input)
	input = (input or ""):lower()
	local head, sit = input:match("^([^:]+):?(.*)$")
	if not head then
		return nil
	end
	sit = sit ~= "" and sit or "default"
	if sit ~= "default" and not SIT_BY_KEY[sit] then
		return nil
	end
	if head == "captured" then
		return "captured"
	elseif head == "global" then
		return sit == "default" and "global" or ("global:" .. sit)
	elseif head == "loadout" then
		local id = self:CurrentLoadout()
		return id and (loadoutPrefix(id) .. ":" .. sit) or nil
	elseif head:match("^l%d+$") then
		return "L" .. head:sub(2) .. ":" .. sit
	end
end

--- Candidate keys for the current context, most specific first.
function Profiles:Chain()
	local sit = self:CurrentSituation()
	local chain = {}
	local id = self:CurrentLoadout()
	if id then
		chain[#chain + 1] = loadoutPrefix(id) .. ":" .. sit
		chain[#chain + 1] = loadoutPrefix(id) .. ":default"
	end
	chain[#chain + 1] = "global:" .. sit
	chain[#chain + 1] = "global"
	chain[#chain + 1] = "captured"
	return chain
end

function Profiles:Exists(key)
	if key == "captured" then
		return next(db().captured) ~= nil
	end
	return db().profiles[key] ~= nil
end

--- The profile automatic switching would pick, or nil if none exist at all.
function Profiles:Resolve()
	for _, key in ipairs(self:Chain()) do
		if self:Exists(key) then
			return key
		end
	end
end

--- What should be applied: the manual pin if it still exists, else automatic.
function Profiles:Target()
	local manual = db().manual
	if manual and self:Exists(manual) then
		return manual
	end
	return self:Resolve()
end

function Profiles:Label(key)
	if not key then
		return L.PROFILE_NONE
	end
	local kind, id, sit = Profiles.Parse(key)
	if kind == "captured" then
		return L.PROFILE_CAPTURED
	end
	local who = kind == "global" and L.PROFILE_GLOBAL
		or (db().loadoutNames[id] or (L.PROFILE_LOADOUT):format(id))
	if sit == "default" then
		return kind == "global" and L.PROFILE_GLOBAL_DEFAULT or (L.PROFILE_X_DEFAULT):format(who)
	end
	return (L.PROFILE_X_SIT):format(who, SIT_BY_KEY[sit] and SIT_BY_KEY[sit].label or sit)
end

--- Two-line code for the Profile button: "ENH\nBG", "ALL\nDGN", "DEF\nBAR".
function Profiles:ShortCode(key)
	if not key then
		return "--\n--"
	end
	local kind, id, sit = Profiles.Parse(key)
	if kind == "captured" then
		return "DEF\nBAR"
	end
	local top = "ALL"
	if kind == "loadout" then
		local name = db().loadoutNames[id] or "?"
		top = name:gsub("[^%w]", ""):sub(1, 3):upper()
		if top == "" then
			top = "L" .. tostring(id):sub(-2)
		end
	end
	local bottom = sit == "default" and "DEF" or (SIT_BY_KEY[sit] and SIT_BY_KEY[sit].code or "?")
	return top .. "\n" .. bottom
end

-- ------------------------------------------------------------------ totems

--- The totem entries the bar shows for the applied profile, per element key.
--- With no profile at all (a fresh character), it previews the first known totems.
function Profiles:DisplayedTotems()
	local out = {}
	local key = self.applied
	local profile = key and (key == "captured" and db().captured or db().profiles[key])
	for _, e in ipairs(ns.Data.ELEMENTS) do
		if profile then
			local stored = profile[e.key]
			if stored then
				out[e.key] = ns.Data:FindTotem(stored.name) or {
					spellID = stored.spellID, name = stored.name,
					code = ns.Data.Abbreviate(stored.name), source = "profile",
				}
			end
		else
			out[e.key] = ns.Data:GetTotems(e.key)[1]
		end
	end
	return out
end

local function snapshot(totems)
	local copy = {}
	for key, t in pairs(totems) do
		copy[key] = { spellID = t.spellID, name = t.name }
	end
	return copy
end

--- Save what the bar shows now under `key`.
function Profiles:SaveAs(key)
	if not Profiles.Parse(key) or key == "captured" then
		return false
	end
	db().profiles[key] = snapshot(self:DisplayedTotems())
	self:Update("saved")
	return true
end

function Profiles:Delete(key)
	if not db().profiles[key] then
		return false
	end
	db().profiles[key] = nil
	db().sequences[key] = nil
	if db().manual == key then
		db().manual = nil
	end
	self:Update("deleted")
	return true
end

--- Set one element of any profile cell (the options grid), creating the profile if
--- needed. Out of combat only, like every edit that can change a secure button.
function Profiles:SetElementFor(key, elementKey, totemName)
	if InCombatLockdown() then
		ns.addon:Log(L.COMBAT_NO_TOTEM_CHANGE)
		return false
	end
	if not Profiles.Parse(key) or key == "captured" then
		return false
	end
	local profile = db().profiles[key] or {}
	db().profiles[key] = profile
	if totemName then
		local t = ns.Data:FindTotem(totemName)
		profile[elementKey] = { spellID = t and t.spellID, name = totemName }
	else
		profile[elementKey] = nil
	end
	if key == self.applied then
		self.applied = nil -- force a re-apply of the same key
	end
	self:Update("edited", true)
	ns.Options:Refresh()
	return true
end

--- Set one element of the APPLIED profile (creating "global" if nothing is applied yet).
--- Out of combat only: it changes what a secure button casts. Used by the flyouts (M6).
function Profiles:SetElement(elementKey, totemName)
	if InCombatLockdown() then
		ns.addon:Log(L.COMBAT_NO_TOTEM_CHANGE)
		return false
	end
	local key = self.applied
	if not key or key == "captured" then
		key = "global"
		db().profiles[key] = db().profiles[key] or snapshot(self:DisplayedTotems())
	end
	local profile = db().profiles[key]
	if totemName then
		local t = ns.Data:FindTotem(totemName)
		profile[elementKey] = { spellID = t and t.spellID, name = totemName }
	else
		profile[elementKey] = nil
	end
	self.applied = nil -- force a re-apply of the same key
	self:Update("edited", true)
	return true
end

-- ------------------------------------------------------------------ switching

--- Re-evaluate and apply. `quiet` suppresses the switch announcement.
function Profiles:Update(reason, quiet)
	local target = self:Target()
	if target == self.applied then
		if self.queued then
			-- A switch queued in combat became moot (e.g. zoned back): cancel it.
			self.queued = nil
			ns.Bar:Refresh()
		end
		return
	end
	if InCombatLockdown() then
		-- Applying means rewriting secure attributes: queue the whole switch instead.
		if self.queued ~= target then
			self.queued = target
			self.queuedReason = reason
			ns.addon:Log(L.PROFILE_QUEUED, self:Label(target))
			ns.Bar:Refresh()
		end
		return
	end
	self:Apply(target, reason, quiet)
end

function Profiles:Apply(key, reason, quiet)
	local previous = self.applied
	self.applied = key
	self.queued = nil
	ns.Bar:Refresh()
	-- New profile, new castsequence: restart the counter and keep "TA Sequence" in step.
	ns.Sequence:ResetCounter()
	ns.Sequence:SyncGameMacro(false)
	ns.Options:Refresh()
	ns.addon:Debug("profile %s -> %s (%s)", tostring(previous), tostring(key), tostring(reason))
	if key and key ~= previous and not quiet and previous ~= nil then
		self:Announce(key)
	end
end

--- Chat line, plus a short on-screen message unless turned off.
function Profiles:Announce(key)
	ns.addon:Log(L.PROFILE_SWITCHED, self:Label(key))
	if db().settings.showSwitchMessage then
		self:Flash(self:Label(key))
	end
end

function Profiles:Flash(text)
	local f = self.flash
	if not f then
		f = CreateFrame("Frame", nil, UIParent)
		f:SetSize(600, 30)
		f:SetPoint("TOP", UIParent, "TOP", 0, -150)
		f:SetFrameStrata("HIGH")
		f.text = f:CreateFontString(nil, "OVERLAY")
		f.text:SetFontObject(GameFontNormalLarge)
		f.text:SetPoint("CENTER")
		f.fade = f:CreateAnimationGroup()
		local a = f.fade:CreateAnimation("Alpha")
		a:SetFromAlpha(1)
		a:SetToAlpha(0)
		a:SetStartDelay(2.5)
		a:SetDuration(0.5)
		f.fade:SetScript("OnFinished", function() f:Hide() end)
		self.flash = f
	end
	local theme = ns.Themes:Current()
	f.text:SetFont(ns.Themes.FONTS.heading, 16, "")
	f.text:SetTextColor(ns.Themes.RGB(theme.accent))
	f.text:SetShadowColor(0, 0, 0, 1)
	f.text:SetShadowOffset(1, -1)
	f.text:SetText(text)
	f.fade:Stop()
	f:SetAlpha(1)
	f:Show()
	f.fade:Play()
end

--- Pin a profile until "Auto" is chosen again. Zone and loadout changes don't move it.
function Profiles:Pin(key)
	if not self:Exists(key) then
		return false
	end
	db().manual = key
	self:Update("manual")
	return true
end

function Profiles:Auto()
	db().manual = nil
	self:Update("auto")
	ns.Bar:Refresh() -- the dot changes colour even if the profile does not
end

-- Zone data can settle a moment after the event, and several events arrive together
-- on login and talent changes: wait briefly, then evaluate once.
function Profiles:Schedule(reason)
	self.pendingReason = reason
	if self.timer then
		return
	end
	self.timer = true
	C_Timer.After(0.5, function()
		self.timer = false
		self:Update(self.pendingReason)
	end)
end

function Profiles:OnRegenEnabled()
	if self.queued ~= nil or self.applied ~= self:Target() then
		local target = self:Target()
		self.queued = nil
		self:Apply(target, self.queuedReason or "after combat")
	end
end

-- ------------------------------------------------------------------ chooser menu

--- Menu entries: "Auto (currently: X)", then profiles grouped General / per loadout,
--- then the captured native bar. Drawn by Menu.lua in the bar's theme.
function Profiles:MenuEntries()
	local manual = db().manual
	local entries = {
		{ kind = "item", text = (L.MENU_AUTO):format(self:Label(self:Resolve())),
			checked = manual == nil, onClick = function() self:Auto() end },
	}
	local keys = {}
	for key in pairs(db().profiles) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	local groups, order = {}, {}
	for _, key in ipairs(keys) do
		local kind, id = Profiles.Parse(key)
		local group = kind == "global" and L.MENU_GENERAL
			or (db().loadoutNames[id] or (L.PROFILE_LOADOUT):format(id))
		if not groups[group] then
			groups[group] = {}
			order[#order + 1] = group
		end
		table.insert(groups[group], key)
	end
	local function item(key)
		return { kind = "item", text = self:Label(key), checked = manual == key,
			onClick = function() self:Pin(key) end }
	end
	for _, group in ipairs(order) do
		entries[#entries + 1] = { kind = "title", text = group }
		for _, key in ipairs(groups[group]) do
			entries[#entries + 1] = item(key)
		end
	end
	if self:Exists("captured") then
		entries[#entries + 1] = { kind = "divider" }
		entries[#entries + 1] = item("captured")
	end
	return entries
end

function Profiles:OpenMenu(owner)
	ns.Menu:Toggle(owner, self:MenuEntries())
end

-- ------------------------------------------------------------------ wiring

function Profiles:Init()
	local g = db()
	g.loadoutNames = g.loadoutNames or {}
	if g.manual and not self:Exists(g.manual) then
		g.manual = nil
	end
	for _, ev in ipairs({
		"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "SELECTED_LOADOUT_CHANGED",
		"TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED",
	}) do
		self:RegisterEvent(ev, "Schedule")
	end
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
	-- First evaluation is silent: logging in is not a "switch".
	self:Update("login", true)
end
