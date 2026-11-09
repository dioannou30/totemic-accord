--[[
	Layout check for our private AceGUI fork: loads the real LibStub and the forked GUI
	core in plain Lua 5.1 and runs its Flow layout on fake frames, asserting the 10px
	gaps between widgets and rows. Run from the repo root:  lua5.1 tools/gui_layout_test.lua .
]]
-- Load the real LibStub + our forked AceGUI core, run its Flow layout on fake frames.
local repo = ...
local function fake(w, h)
	local f = { w = w, h = h, points = {} }
	function f:GetWidth() return self.w end
	function f:GetHeight() return self.h end
	function f:Show() end
	function f:ClearAllPoints() self.points = {} end
	function f:SetPoint(p, rel, rp, x, y) self.points[#self.points + 1] = { p, rel, rp, x or 0, y or 0 } end
	return f
end
CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end
UIParent = CreateFrame()
geterrorhandler = function() return print end
GetTime = function() return 0 end
hooksecurefunc = function() end
dofile(repo .. "/TotemicAccord/Libs/LibStub/LibStub.lua")
dofile(repo .. "/TotemicAccord/Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
dofile(repo .. "/TotemicAccord/Libs/TotemicAccordGUI/TotemicAccordGUI.lua")
local GUI = LibStub("TotemicAccordGUI-1.0")
local flow = GUI:GetLayout("Flow")
-- content 400 wide; three 120-wide widgets fit two per row with a 10px gap? 120+10+120 = 250,
-- +10+120 = 380 <= 400 -> all three on one row. Then a fourth (120) wraps.
local content = fake(400, 0)
local finished
content.obj = { LayoutFinished = function(_, _, h) finished = h end }
local kids = {}
for i = 1, 4 do kids[i] = { frame = fake(120, 30) } end
flow(content, kids)
local p2, p3, p4 = kids[2].frame.points[1], kids[3].frame.points[1], kids[4].frame.points[1]
print("w2 gap", p2[4], "w3 gap", p3[4])
print("w4 anchored", p4[1], p4[2] == content, "y", p4[5])
print("total height", finished)
assert(p2[4] == 10 and p3[4] == 10, "horizontal gap not 10")
local row1 = kids[1].frame.points[#kids[1].frame.points]
print("row1 y", row1[5], "row2 y", p4[5])
-- Ace adds the row gap above the first row too (3px originally): row1 at -10, its bottom at -40,
-- row2 10px further down at -50.
assert(row1[5] == -10, "row1 top")
assert(p4[2] == content and p4[5] == row1[5] - 30 - 10, "second row not 10px below the first")
-- a row that only fits WITHOUT gaps must wrap now: 3 x 130 = 390 fits 400, but 390 + 20 doesn't
local kids2 = {}
for i = 1, 3 do kids2[i] = { frame = fake(130, 30) } end
local c2 = fake(400, 0); c2.obj = {}; flow(c2, kids2)
assert(kids2[3].frame.points[1][1] == "TOPLEFT" and kids2[3].frame.points[1][3] == "TOPLEFT", "third should wrap")
print("FLOW LAYOUT OK")
