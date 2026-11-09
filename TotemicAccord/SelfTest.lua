--[[
	SelfTest.lua -- /ta selftest

	Build prompt section 6.10 lists what this eventually reports. At M1 the checks that
	can run, run; the rest are listed as pending so the output doubles as a progress map.

	It also prints the M1 VERIFY answers (interface number, spec mapping, instance type,
	Call of the Elements and Totemic Projection) so they come out of one command instead
	of six /dump calls typed in the middle of the game.

	Everything here reads; nothing writes. Not yet checked against combat-time secret
	values -- run it out of combat.
]]

local ADDON, ns = ...
local L = ns.L

local SelfTest = {}
ns.SelfTest = SelfTest

local COLOR_PASS = "|cff0cd29d"
local COLOR_FAIL = "|cfff2523f"
local COLOR_INFO = "|cff4aa3f0"
local COLOR_MUTED = "|cff8a929c"
local COLOR_OFF = "|r"

local results

local function pass(label, detail)
	results.passed = results.passed + 1
	print(("  %s%s%s %s%s"):format(COLOR_PASS, L.SELFTEST_PASS, COLOR_OFF, label,
		detail and (" " .. COLOR_MUTED .. "- " .. detail .. COLOR_OFF) or ""))
end

local function fail(label, detail)
	results.failed = results.failed + 1
	print(("  %s%s%s %s%s"):format(COLOR_FAIL, L.SELFTEST_FAIL, COLOR_OFF, label,
		detail and (" " .. COLOR_MUTED .. "- " .. detail .. COLOR_OFF) or ""))
end

--- Neither pass nor fail: a value we want to see rather than assert.
local function info(label, detail)
	print(("  %s%s%s %s%s"):format(COLOR_INFO, L.SELFTEST_INFO, COLOR_OFF, label,
		detail and (" " .. COLOR_MUTED .. "- " .. detail .. COLOR_OFF) or ""))
end

local function pending(label, milestone)
	print(("  %s....%s %s %s(%s)%s"):format(COLOR_MUTED, COLOR_OFF, label,
		COLOR_MUTED, milestone, COLOR_OFF))
end

--- Spell name lookup that tolerates the API shape changing under us.
local function spellName(idOrName)
	local ok, res = pcall(function()
		if C_Spell and C_Spell.GetSpellInfo then
			local i = C_Spell.GetSpellInfo(idOrName)
			-- Modern clients return a table; older ones a plain name first.
			if type(i) == "table" then return i.name, i.spellID end
			return i
		end
	end)
	if ok and res then return res end
	return nil
end

local function spellKnown(id)
	local ok, known = pcall(function()
		if IsPlayerSpell then return IsPlayerSpell(id) end
		return nil
	end)
	if ok and known ~= nil then return known end
	local ok2, known2 = pcall(function() return IsSpellKnown(id) end)
	return ok2 and known2 or false
end

-- ------------------------------------------------------------------ cast probe
-- VERIFY item 7 for M7: is UNIT_SPELLCAST_SUCCEEDED's spellID readable in combat? The
-- event is documented SecretWhenUnitSpellCastRestricted. Record what we actually see,
-- in and out of combat, without ever comparing or storing a secret value.
local castSeen = {}
do
	local probe = CreateFrame("Frame")
	probe:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	probe:SetScript("OnEvent", function(_, _, _, _, spellID)
		local when = InCombatLockdown() and "combat" or "idle"
		if issecretvalue(spellID) then
			castSeen[when] = "secret"
		else
			castSeen[when] = "readable (" .. tostring(spellID) .. ")"
		end
	end)
end
SelfTest.castSeen = castSeen

function SelfTest:Run()
	local addon = ns.addon
	results = { passed = 0, failed = 0 }

	print(("%s%s %s %s%s"):format(COLOR_PASS, L.CHAT_PREFIX, L.SELFTEST_HEADER,
		addon.VERSION, COLOR_OFF))

	-- ---------------------------------------------------------------- libraries
	if LibStub then
		local missing = {}
		for _, lib in ipairs({
			"AceAddon-3.0", "AceDB-3.0", "AceEvent-3.0", "AceConsole-3.0",
			"AceConfig-3.0", "AceConfigRegistry-3.0", "AceConfigDialog-3.0",
			"AceGUI-3.0", "LibSerialize", "LibDeflate",
			"LibDataBroker-1.1", "LibDBIcon-1.0",
		}) do
			if not LibStub:GetLibrary(lib, true) then
				missing[#missing + 1] = lib
			end
		end
		if #missing == 0 then
			pass(L.TEST_ACE3, "all 12 libraries registered")
		else
			fail(L.TEST_ACE3, "missing: " .. table.concat(missing, ", "))
		end
	else
		fail(L.TEST_ACE3, "LibStub itself is missing")
	end

	-- ---------------------------------------------------------------- class
	local className, classToken = UnitClass("player")
	if classToken == "SHAMAN" then
		pass(L.TEST_CLASS, className)
	else
		fail(L.TEST_CLASS, tostring(className))
	end

	-- ---------------------------------------------------------------- saved variables
	if addon.db and addon.db.global and addon.db.global.settings then
		pass(L.TEST_SAVEDVARS, ("TotemicAccordCharDB v%d"):format(addon.db.global.version or 0))
	else
		fail(L.TEST_SAVEDVARS, "per-character DB not initialised")
	end

	-- ---------------------------------------------------------------- VERIFY values
	-- Interface number: the TOC claims 16001; this is the client's own answer.
	-- GetAddOnMetadata does not expose the Interface field (it returns nil), so the
	-- TOC's value comes from the dedicated API instead.
	local _, build, _, iface = GetBuildInfo()
	local tocIface = C_AddOns.GetAddOnInterfaceVersion(ADDON)
	if tostring(iface) == tostring(tocIface) then
		pass(L.TEST_INTERFACE, ("%s (build %s) matches the TOC"):format(tostring(iface), tostring(build)))
	else
		fail(L.TEST_INTERFACE,
			("client says %s, TOC says %s -- update ## Interface in TotemicAccord.toc")
			:format(tostring(iface), tostring(tocIface)))
	end

	-- Spec: index plus the stable specID, which is what profiles should key on.
	-- Forever only has the namespaced form; Blizzard's own UI never calls a bare
	-- GetSpecialization(). Distinguish "API missing" from "no spec chosen yet" so a
	-- failure here says which it is.
	local Spec = C_SpecializationInfo
	if not (Spec and Spec.GetSpecialization) then
		fail(L.TEST_SPEC, "C_SpecializationInfo.GetSpecialization is missing")
	else
		local specIndex = Spec.GetSpecialization()
		if specIndex and specIndex > 0 then
			local specID, specName = Spec.GetSpecializationInfo(specIndex)
			pass(L.TEST_SPEC, ("index %d, specID %s, %s"):format(
				specIndex, tostring(specID), tostring(specName)))
		else
			fail(L.TEST_SPEC, ("no spec (returned %s) -- character level %s"):format(
				tostring(specIndex), tostring(UnitLevel("player"))))
		end
	end

	-- Which specs does this client offer a Shaman at all? The first in-game run reported
	-- index 1 / specID 1489 / "Shaman" -- a class-named starter spec, not Elemental,
	-- Enhancement or Restoration. Blizzard's IsInitialSpec is "index > GetNumSpecializations()",
	-- so these numbers decide whether profiles can key on spec at all (M5).
	local _, _, classID = UnitClass("player")
	local numSpecs = GetNumSpecializations and GetNumSpecializations()
	local initial = IsPlayerInitialSpec and IsPlayerInitialSpec()
	info("Spec system", ("level %s, GetNumSpecializations=%s, IsPlayerInitialSpec=%s"):format(
		tostring(UnitLevel("player")), tostring(numSpecs), tostring(initial)))
	local forClass = Spec and Spec.GetNumSpecializationsForClassID
		and Spec.GetNumSpecializationsForClassID(classID) or 0
	if forClass == 0 then
		info("Class specs", ("none listed for classID %s"):format(tostring(classID)))
	end
	for i = 1, forClass do
		local id, name = GetSpecializationInfoForClassID(classID, i)
		info("Class spec " .. i, ("specID %s, %s"):format(tostring(id), tostring(name)))
	end

	-- Talent loadouts: the chosen replacement for the spec axis in profile keys (M5).
	-- Profiles will key on the saved loadout's config ID and show its name.
	local specIDForLoadouts = Spec and Spec.GetSpecialization and Spec.GetSpecialization()
		and Spec.GetSpecializationInfo(Spec.GetSpecialization())
	if specIDForLoadouts and C_ClassTalents then
		local ok, ids = pcall(C_ClassTalents.GetConfigIDsBySpecID, specIDForLoadouts)
		local selected = C_ClassTalents.GetLastSelectedSavedConfigID(specIDForLoadouts)
		local names = {}
		for _, id in ipairs(ok and ids or {}) do
			local cfg = C_Traits.GetConfigInfo(id)
			names[#names + 1] = ("%s%s (%d)"):format(id == selected and "*" or "",
				cfg and cfg.name or "?", id)
		end
		info("Talent loadouts", ("%s; active config %s, starter build %s"):format(
			#names > 0 and table.concat(names, ", ") or "none saved",
			tostring(C_ClassTalents.GetActiveConfigID()),
			tostring(C_ClassTalents.GetStarterBuildActive())))
	else
		fail("Talent loadouts", "C_ClassTalents unavailable")
	end

	-- Instance type: drives the situation half of every profile key.
	local inInstance, instanceType = IsInInstance()
	if instanceType then
		pass(L.TEST_INSTANCE, ("%s (inInstance=%s)"):format(
			tostring(instanceType), tostring(inInstance)))
	else
		fail(L.TEST_INSTANCE, "IsInInstance() returned nothing")
	end

	-- Call of the Elements: page 1 of TOTEM_MULTI_CAST_SUMMON_SPELLS per Constants.lua.
	local coeID = TOTEM_MULTI_CAST_SUMMON_SPELLS and TOTEM_MULTI_CAST_SUMMON_SPELLS[1]
	if coeID then
		local name = spellName(coeID)
		local known = spellKnown(coeID)
		info(L.TEST_CALL_OF_ELEMENTS, ("spellID %d, %s, known=%s"):format(
			coeID, tostring(name), tostring(known)))
	else
		fail(L.TEST_CALL_OF_ELEMENTS, "TOTEM_MULTI_CAST_SUMMON_SPELLS missing")
	end

	-- Totemic Projection: the spellID still has to be confirmed in game, so look it
	-- up by name and report whatever the client says.
	-- By name only works once learned. The spellbook does not list unlearned spells on
	-- Forever, so also probe candidate IDs directly: C_Spell resolves any spell in the
	-- client's data. 437009 is Wowhead's Forever ID; it may have been renamed
	-- "Totemic Call", so both names are tried too.
	for _, name in ipairs({ "Totemic Projection", "Totemic Call" }) do
		local found = spellName(name)
		if found then
			info(L.TEST_PROJECTION, ("known by name: %s"):format(tostring(found)))
		end
	end
	for _, id in ipairs({ ns.Data.PROJECTION_SPELL_ID }) do
		info(L.TEST_PROJECTION, ("spellID %d resolves to %s, known=%s"):format(
			id, tostring(spellName(id)), tostring(spellKnown(id))))
	end
	for name, id in pairs(ns.Data.spellbook or {}) do
		if name:find("Projection") or name:find("Totemic") then
			info("Spellbook match", ("%s (%s)"):format(name, tostring(id)))
		end
	end

	-- Totem slots, from the constants rather than hardcoded numbers.
	if EARTH_TOTEM_SLOT and FIRE_TOTEM_SLOT and WATER_TOTEM_SLOT and AIR_TOTEM_SLOT then
		info("Totem slot constants", ("earth=%d fire=%d water=%d air=%d, %d slots"):format(
			EARTH_TOTEM_SLOT, FIRE_TOTEM_SLOT, WATER_TOTEM_SLOT, AIR_TOTEM_SLOT,
			GetNumTotemSlots and GetNumTotemSlots() or -1))
	else
		fail("Totem slot constants", "one of the *_TOTEM_SLOT globals is missing")
	end

	-- ---------------------------------------------------------------- M2: totem data
	local Data = ns.Data
	Data:Discover()

	-- The native bar's lists only exist after Call of the Elements; before that the
	-- spellbook is the source and this is expected, not a failure.
	local multicastSlots = 0
	for _, e in ipairs(Data.ELEMENTS) do
		for _, t in ipairs(Data:GetTotems(e.key)) do
			if t.source == "multicast" then
				multicastSlots = multicastSlots + 1
				break
			end
		end
	end
	if multicastSlots == #Data.ELEMENTS then
		pass(L.TEST_TOTEM_SPELLS, "GetMultiCastTotemSpells lists all 4 elements")
	else
		info(L.TEST_TOTEM_SPELLS, ("native bar lists %d/4 elements -- using the spellbook"):format(multicastSlots))
	end
	for _, e in ipairs(Data.ELEMENTS) do
		local parts = {}
		for _, t in ipairs(Data:GetTotems(e.key)) do
			parts[#parts + 1] = ("%s %s%s"):format(t.code, Data.BaseName(t.name),
				t.source == "multicast" and "" or ("[" .. t.source:sub(1, 1) .. "]"))
		end
		info("  " .. e.key, #parts > 0 and table.concat(parts, ", ") or "none known")
	end
	if #Data.unplaced > 0 then
		fail("Totems with unknown element",
			table.concat(Data.unplaced, ", ") .. " -- drop each once out of combat to teach it")
	end

	if #Data.clashes == 0 then
		pass(L.TEST_ABBREVIATIONS)
	else
		fail(L.TEST_ABBREVIATIONS, table.concat(Data.clashes, "; "))
	end

	-- Not-yet-learned spells the spellbook already shows, with their levels. This is how
	-- Call of the Elements and Totemic Projection get identified before they are learned.
	local upcoming = {}
	for name, f in pairs(Data.future or {}) do
		if name:find("Totem") or name:find("Call of the") then
			upcoming[#upcoming + 1] = ("%s (%s) L%s"):format(name, tostring(f.spellID), tostring(f.level))
		end
	end
	table.sort(upcoming)
	info("Upcoming totem spells", #upcoming > 0 and table.concat(upcoming, ", ") or "none listed")

	-- ---------------------------------------------------------------- M3: bar
	local Bar = ns.Bar
	if Bar.frame then
		pass("Bar built", ("%d buttons, layout %s, theme %s"):format(#Bar.buttons,
			tostring(addon.db.global.settings.layout), tostring(addon.db.global.settings.theme)))
	else
		fail("Bar built", InCombatLockdown() and "waiting for combat to end" or "not created")
	end
	-- Probe each font now, on a scratch font string, rather than trusting what happened
	-- at login: addon fonts can fail on the first attempt and load a moment later.
	SelfTest.probe = SelfTest.probe or UIParent:CreateFontString(nil, "OVERLAY")
	local bad = {}
	for _, key in ipairs({ "initials", "heading", "mono" }) do
		local path = ns.Themes.FONTS[key]
		SelfTest.probe:SetFont((GameFontNormal:GetFont()), 10, "")
		if not SelfTest.probe:SetFont(path, 10, "") then
			bad[#bad + 1] = path:match("[^\\]+$")
		end
	end
	if #bad == 0 then
		pass("Fonts loaded", ("Manrope, JetBrains Mono (bar retried %d time(s) at login)"):format(Bar.fontRetries or 0))
	else
		fail("Fonts loaded", "cannot load " .. table.concat(bad, ", "))
	end

	-- ---------------------------------------------------------------- M4: casting
	if Bar.buttons then
		local wrong, armed = {}, 0
		for _, b in ipairs(Bar.buttons) do
			local wantType, wantSpell = Bar:SecureSpec(b)
			if b:GetAttribute("type") ~= wantType or b:GetAttribute("spell") ~= wantSpell then
				wrong[#wrong + 1] = b.spec.key
			elseif wantType then
				armed = armed + 1
			end
		end
		if #wrong == 0 then
			pass(L.TEST_SECURE_BUTTONS, ("%d button(s) cast by spell name%s"):format(armed,
				Bar.securePending and ", update queued for after combat" or ""))
		else
			fail(L.TEST_SECURE_BUTTONS, "out of date: " .. table.concat(wrong, ", ")
				.. (InCombatLockdown() and " (in combat -- queued)" or ""))
		end
		local keys = {}
		for _, b in ipairs(Bar.buttons) do
			local label = ns.Keybinds.LabelFor(b.spec.name)
			if label ~= "" then
				keys[#keys + 1] = b.spec.key .. "=" .. label
			end
		end
		info("Keybinds", #keys > 0 and table.concat(keys, ", ") or "none -- /ta keys or the Key Bindings menu")
	end

	info("Spell ID after a cast", ("out of combat: %s; in combat: %s"):format(
		castSeen.idle or "no cast seen yet", castSeen.combat or "no cast seen yet"))

	-- ---------------------------------------------------------------- M5: profiles
	local P = ns.Profiles
	local chain = {}
	for _, key in ipairs(P:Chain()) do
		chain[#chain + 1] = (P:Exists(key) and "" or "-") .. P:Label(key)
	end
	info("Profile", ("%s (%s)%s"):format(P:Label(P.applied),
		addon.db.global.manual and "manual" or "auto",
		P.queued and (" -> " .. P:Label(P.queued) .. " after combat") or ""))
	info("Resolution", table.concat(chain, " > ") .. "  (- = not set)")
	local unknown, count = {}, 0
	for key, profile in pairs(addon.db.global.profiles) do
		count = count + 1
		for element, t in pairs(profile) do
			if not ns.Data:FindTotem(t.name) then
				unknown[#unknown + 1] = ("%s %s: %s"):format(P:Label(key), element, t.name)
			end
		end
	end
	table.sort(unknown)
	if #unknown == 0 then
		pass(L.TEST_PROFILE_SPELLS, ("%d profile(s)"):format(count))
	else
		fail(L.TEST_PROFILE_SPELLS, "not known: " .. table.concat(unknown, "; "))
	end
	pending("Native bar sync buttons", "M8")
	-- ---------------------------------------------------------------- M7: sequence
	local Seq = ns.Sequence
	local text = Seq:MacroText()
	info(L.TEST_SEQUENCE, text ~= "" and (text:gsub("\n", " | ")) or "nothing to cast")
	if #text <= Seq.MACRO_LIMIT then
		pass(L.TEST_MACRO_LENGTH, ("%d/%d characters, Action button mode %s, counter %s"):format(
			#text, Seq.MACRO_LIMIT, tostring(Bar.actionMode), Seq:CounterText() ~= "" and Seq:CounterText() or "-"))
	else
		fail(L.TEST_MACRO_LENGTH, ("%d/%d characters"):format(#text, Seq.MACRO_LIMIT))
	end
	local action = Bar.byKey and Bar.byKey.action
	if action and Bar.actionMode == "seq" and text ~= "" then
		if action:GetAttribute("type") == "macro" and action:GetAttribute("macrotext") == text then
			pass("Action button runs the sequence")
		else
			fail("Action button runs the sequence", Bar.securePending and "queued until combat ends"
				or ("type=%s"):format(tostring(action:GetAttribute("type"))))
		end
	end
	pending(L.TEST_MINIMAP, "M9")
	pending(L.TEST_COMPARTMENT, "M9")

	print(("%s%s%s"):format(COLOR_MUTED,
		"  " .. L.SELFTEST_SUMMARY:format(results.passed, results.failed), COLOR_OFF))
end
