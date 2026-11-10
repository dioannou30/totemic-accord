--[[
	Minimap.lua -- minimap button (LibDataBroker launcher + LibDBIcon) and the minimap's
	addon compartment entry.

	  Left-click        open the options window
	  Right-click       the profile chooser (the same menu as the bar's Profile button)
	  Shift+Left-click  lock / unlock the bar

	The addon compartment (Blizzard's addon dropdown on the minimap) calls the global
	functions named in the TOC: TotemicAccord_OnAddonCompartmentClick(addonName, mouseButton)
	and ...OnEnter / ...OnLeave(addonName, menuButtonFrame). They are the only globals
	besides the addon itself (build prompt 6.9).
]]

local ADDON, ns = ...
local L = ns.L

local Minimap = {}
ns.Minimap = Minimap

local LDB = LibStub("LibDataBroker-1.1")
local DBIcon = LibStub("LibDBIcon-1.0")

local function settings()
	return ns.addon.db.global.settings
end

--- Shared click behaviour for the minimap button and the compartment entry.
function Minimap:Click(owner, button)
	if button == "RightButton" then
		ns.Profiles:OpenMenu(owner)
	elseif IsShiftKeyDown() then
		local locked = not settings().locked
		ns.Bar:SetLocked(locked)
		ns.addon:Log(locked and L.BAR_LOCKED or L.BAR_UNLOCKED)
	else
		ns.Options:Open()
	end
end

function Minimap:Tooltip(tt)
	local P = ns.Profiles
	tt:AddLine(ns.addon.DISPLAY_NAME)
	tt:AddLine(P:Label(P.applied) .. "  (" .. (ns.addon.db.global.manual and L.TIP_MANUAL or L.TIP_AUTO) .. ")", 1, 1, 1)
	tt:AddLine(" ")
	tt:AddLine(L.MINIMAP_HINT_LEFT, 0.7, 0.7, 0.7)
	tt:AddLine(L.MINIMAP_HINT_RIGHT, 0.7, 0.7, 0.7)
	tt:AddLine(L.MINIMAP_HINT_SHIFT, 0.7, 0.7, 0.7)
end

function Minimap:Init()
	local icon = C_Spell.GetSpellTexture(TOTEM_MULTI_CAST_SUMMON_SPELLS[1])
	self.broker = LDB:NewDataObject(ADDON, {
		type = "launcher",
		label = ns.addon.DISPLAY_NAME,
		icon = icon,
		OnClick = function(frame, button) Minimap:Click(frame, button) end,
		OnTooltipShow = function(tt) Minimap:Tooltip(tt) end,
	})
	-- LibDBIcon stores the button's angle and hidden state in this table.
	DBIcon:Register(ADDON, self.broker, settings().minimap)
end

function Minimap:SetShown(shown)
	settings().minimap.hide = not shown
	if shown then
		DBIcon:Show(ADDON)
	else
		DBIcon:Hide(ADDON)
	end
end

function Minimap:Toggle()
	self:SetShown(settings().minimap.hide)
	return not settings().minimap.hide
end

function Minimap:IsRegistered()
	return DBIcon:IsRegistered(ADDON)
end

-- ------------------------------------------------------------------ addon compartment

function TotemicAccord_OnAddonCompartmentClick(_, mouseButton)
	if not ns.addon:IsEnabled() then
		ns.addon:OnSlashCommandDisabled()
		return
	end
	Minimap:Click(AddonCompartmentFrame or UIParent, mouseButton)
end

function TotemicAccord_OnAddonCompartmentEnter(_, menuButtonFrame)
	if not ns.addon:IsEnabled() then
		return
	end
	GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
	Minimap:Tooltip(GameTooltip)
	GameTooltip:Show()
end

function TotemicAccord_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
