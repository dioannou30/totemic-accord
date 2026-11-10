--[[
	ImportExport.lua -- "TA1:" strings for sharing profiles, sequences and settings.

	Format: "TA1:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(
	                     LibSerialize:Serialize(payload)))

	Everything imported is validated and rebuilt from scratch: unknown keys are dropped,
	types are checked, enums must match. A broken or foreign string is rejected with a
	reason, never half-applied.

	Loadout profiles are keyed by talent-loadout config ID, which is different on every
	character. So the payload carries each loadout's NAME, and on import a loadout profile
	is mapped onto the importing character's loadout of the same name; with no such
	loadout it is skipped and counted.
]]

local _, ns = ...
local L = ns.L

local IE = {}
ns.ImportExport = IE

local PREFIX = "TA1:"
local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

-- Settings that travel. Screen position, minimap position and debug stay local.
local SETTING_RULES = {
	theme = { enum = { emerald = true, tokyo = true, mocha = true, classic = true } },
	buttonStyle = { enum = { initials = true, icons = true } },
	layout = { enum = { horizontal = true, vertical = true, grid = true } },
	flyoutDir = { enum = { up = true, down = true, left = true, right = true } },
	emptySlot = { enum = { grey = true, hide = true } },
	actionMode = { enum = { auto = true, cote = true, seq = true } },
	scale = { min = 0.5, max = 2 },
	barOpacity = { min = 0, max = 1 },
	locked = { bool = true },
	showSwitchMessage = { bool = true },
	flyoutArrows = { bool = true },
	vividInitials = { bool = true },
	buttonSpacing = { min = 0, max = 8 },
	showProfileLabel = { bool = true },
	hideNativeBar = { bool = true },
}

local function db()
	return ns.addon.db.global
end

-- ------------------------------------------------------------------ export

function IE:Payload()
	local g = db()
	local settings = {}
	for key in pairs(SETTING_RULES) do
		settings[key] = g.settings[key]
	end
	return {
		v = 1,
		profiles = g.profiles,
		sequences = g.sequences,
		settings = settings,
		loadoutNames = g.loadoutNames,
	}
end

function IE:Export()
	local serialized = LibSerialize:Serialize(self:Payload())
	local compressed = LibDeflate:CompressDeflate(serialized)
	return PREFIX .. LibDeflate:EncodeForPrint(compressed)
end

-- ------------------------------------------------------------------ validation

local function validTotem(t)
	return type(t) == "table" and type(t.name) == "string" and t.name ~= ""
		and (t.spellID == nil or type(t.spellID) == "number")
end

local function cleanProfile(p)
	if type(p) ~= "table" then
		return nil
	end
	local out = {}
	for _, e in ipairs(ns.Data.ELEMENTS) do
		if p[e.key] ~= nil then
			if not validTotem(p[e.key]) then
				return nil
			end
			out[e.key] = { spellID = p[e.key].spellID, name = p[e.key].name }
		end
	end
	return out
end

local function cleanSequence(s)
	if type(s) ~= "table" or type(s.order) ~= "table" or type(s.include) ~= "table" then
		return nil
	end
	local seen, order, include = {}, {}, {}
	for _, element in ipairs(s.order) do
		if not ns.Data.ELEMENT_BY_KEY[element] or seen[element] then
			return nil
		end
		seen[element] = true
		order[#order + 1] = element
	end
	if #order ~= #ns.Data.ELEMENTS then
		return nil
	end
	for _, e in ipairs(ns.Data.ELEMENTS) do
		include[e.key] = s.include[e.key] == true
	end
	local seconds = s.resetSeconds
	if seconds ~= nil and (type(seconds) ~= "number" or seconds < 1 or seconds > 600) then
		return nil
	end
	return { order = order, include = include, resetCombat = s.resetCombat == true, resetSeconds = seconds }
end

local function cleanSettings(s)
	local out = {}
	if type(s) ~= "table" then
		return out
	end
	for key, rule in pairs(SETTING_RULES) do
		local v = s[key]
		if rule.enum and rule.enum[v] then
			out[key] = v
		elseif rule.bool and type(v) == "boolean" then
			out[key] = v
		elseif rule.min and type(v) == "number" and v >= rule.min and v <= rule.max then
			out[key] = v
		end
	end
	return out
end

--- Name -> config ID of the importing character's saved loadouts.
local function localLoadoutsByName()
	local byName = {}
	local S = C_SpecializationInfo
	local index = S.GetSpecialization()
	local specID = index and S.GetSpecializationInfo(index)
	if specID then
		for _, id in ipairs(C_ClassTalents.GetConfigIDsBySpecID(specID) or {}) do
			local info = C_Traits.GetConfigInfo(id)
			if info and info.name then
				byName[info.name] = id
			end
		end
	end
	return byName
end

--- Decode and validate. Returns a clean result table, or nil and a reason.
function IE:Decode(text)
	text = (text or ""):gsub("%s+", "")
	if text:sub(1, #PREFIX) ~= PREFIX then
		return nil, L.IMPORT_ERR_PREFIX
	end
	local decoded = LibDeflate:DecodeForPrint(text:sub(#PREFIX + 1))
	if not decoded then
		return nil, L.IMPORT_ERR_DECODE
	end
	local decompressed = LibDeflate:DecompressDeflate(decoded)
	if not decompressed then
		return nil, L.IMPORT_ERR_DECODE
	end
	local ok, payload = LibSerialize:Deserialize(decompressed)
	if not ok or type(payload) ~= "table" or payload.v ~= 1 then
		return nil, L.IMPORT_ERR_FORMAT
	end

	local names = type(payload.loadoutNames) == "table" and payload.loadoutNames or {}
	local localByName = localLoadoutsByName()
	local result = { profiles = {}, sequences = {}, settings = cleanSettings(payload.settings),
		skipped = 0, count = 0 }

	local function mapKey(key)
		local kind, id, sit = ns.Profiles.Parse(key)
		if kind == "global" then
			return key
		elseif kind == "loadout" then
			local localID = localByName[names[id]]
			if localID then
				return "L" .. localID .. ":" .. sit
			end
		end
		return nil
	end

	for key, p in pairs(type(payload.profiles) == "table" and payload.profiles or {}) do
		if type(key) == "string" and key ~= "captured" then
			local clean = cleanProfile(p)
			if not clean then
				return nil, (L.IMPORT_ERR_PROFILE):format(key)
			end
			local target = mapKey(key)
			if target then
				result.profiles[target] = clean
				result.count = result.count + 1
				-- `and ... or nil`: without it a payload with no sequences gives `false`,
				-- which then failed validation as a "malformed sequence".
				local seq = type(payload.sequences) == "table" and payload.sequences[key] or nil
				if seq ~= nil then
					local cleanSeq = cleanSequence(seq)
					if not cleanSeq then
						return nil, (L.IMPORT_ERR_SEQUENCE):format(key)
					end
					result.sequences[target] = cleanSeq
				end
			else
				result.skipped = result.skipped + 1
			end
		end
	end
	return result
end

-- ------------------------------------------------------------------ apply

--- Replace profiles and sequences, merge settings. Out of combat: it rewrites the bar.
function IE:Apply(result)
	if InCombatLockdown() then
		ns.addon:Log(L.COMBAT_QUEUED)
		return false
	end
	local g = db()
	g.profiles = result.profiles
	g.sequences = result.sequences
	for key, v in pairs(result.settings) do
		g.settings[key] = v
	end
	if g.manual and not g.profiles[g.manual] then
		g.manual = nil
	end
	ns.Profiles.applied = nil
	ns.Bar:Layout()
	ns.Themes:Apply()
	ns.Profiles:Update("import", true)
	ns.Bar:Refresh()
	ns.addon:Log(L.IMPORT_DONE, result.count, result.skipped)
	return true
end

--- Validate, then ask before overwriting.
function IE:BeginImport(text)
	local result, err = self:Decode(text)
	if not result then
		ns.addon:Log(L.IMPORT_FAILED, err)
		self.lastError = err
		return false
	end
	self.lastError = nil
	StaticPopup_ShowCustomGenericConfirmation({
		text = (L.IMPORT_CONFIRM):format(result.count, result.skipped),
		acceptText = L.IMPORT_ACCEPT,
		showAlert = true,
		callback = function() IE:Apply(result) end,
	})
	return true
end
