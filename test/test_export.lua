-- Standalone check for Guildhall Exporter's JSON-building logic.
-- Mocks a fake Guildhall table so it runs with plain `lua test_export.lua`,
-- no WoW client needed. Only exercises GHE.BuildExportJSON (pure data code) --
-- the UI half (EnsureFrame) touches real WoW frame APIs and can only be
-- verified in-game.

local function assertContains(json, needle, msg)
	assert(json:find(needle, 1, true), (msg or "missing") .. ": " .. needle)
end

-- 1. Guildhall not loaded at all.
_G.SlashCmdList = {}
_G.Guildhall = nil
dofile("../GuildhallExporter/GuildhallExporter.lua")
local json, err = GuildhallExporter.BuildExportJSON()
assert(json == nil and err == "Guildhall isn't loaded.", "should fail without Guildhall")

-- 2. Guildhall loaded, solo (no guild) -- only own characters, gathering
--    profession and empty profession both excluded, guild member ignored.
_G.Guildhall = {
	DB = function()
		return {
			chars = {
				["Bob-Emberstorm"] = {
					class = "WARRIOR", level = 60, rev = 4821,
					profs = {
						[164] = { rank = 300, max = 300, recipes = { [3275] = true, [3276] = true } }, -- Blacksmithing
						[186] = { rank = 300, max = 300, recipes = {} }, -- Mining, gathering, has scan.GATHERING_LINES flag but no recipes anyway
						[182] = { rank = 300, max = 300, recipes = { [999] = true } }, -- flagged gathering below, should be dropped even though it has "recipes"
					},
				},
			},
		}
	end,
	GuildKey = function() return nil end,
	GuildDB = function() return nil end,
	Me = function() return "Bob-Emberstorm" end,
	Scan = { GATHERING_LINES = { [186] = true, [182] = true } },
}
dofile("../GuildhallExporter/GuildhallExporter.lua")
local json2, err2, count2 = GuildhallExporter.BuildExportJSON()
assert(json2 and not err2, "solo export should succeed")
assert(count2 == 1, "expected exactly 1 character, got " .. tostring(count2))
assertContains(json2, '"Bob-Emberstorm"')
assertContains(json2, '"164":{"rank":300,"max":300,"recipes":[3275,3276]}')
assert(not json2:find('"186"'), "gathering profession (empty) leaked into export")
assert(not json2:find('"182"'), "gathering profession (flagged) leaked into export")
assertContains(json2, '"guild":""', "solo export should have empty guild key")

-- 3. In a guild -- own char + a synced guild member both present, and a
--    duplicate of the owner's own name in the guild cache doesn't double up.
_G.Guildhall.GuildKey = function() return "The Desperado Club-Emberstorm" end
_G.Guildhall.GuildDB = function()
	return {
		members = {
			["Bob-Emberstorm"] = _G.Guildhall.DB().chars["Bob-Emberstorm"], -- relayed copy of self
			["Patrick-Emberstorm"] = {
				class = "PALADIN", level = 60, rev = 991,
				profs = { [333] = { rank = 300, max = 300, recipes = { [7935] = true } } }, -- Enchanting
			},
		},
	}
end
dofile("../GuildhallExporter/GuildhallExporter.lua")
local json3, err3, count3 = GuildhallExporter.BuildExportJSON()
assert(json3 and not err3, "guild export should succeed")
assert(count3 == 2, "expected 2 distinct characters (no duplicate self), got " .. tostring(count3))
assertContains(json3, '"Patrick-Emberstorm"')
assertContains(json3, '"guild":"The Desperado Club-Emberstorm"')

print("All Guildhall Exporter export checks passed.")
