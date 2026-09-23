-- Guildhall Exporter
-- Reads Guildhall's own-character and synced-guild profession/recipe tables and
-- serializes them into a copyable JSON blob for the Desperado Club website's
-- crafting-database import. Does no scanning or syncing of its own -- Guildhall
-- already does that; this addon only reads Guildhall's tables and formats them.

local GHE = {}
_G.GuildhallExporter = GHE

GHE.SCHEMA = "GUILDHALL_EXPORTER_V1"

local function EscapeJSON(str)
	str = tostring(str)
	str = str:gsub("\\", "\\\\")
	str = str:gsub("\"", "\\\"")
	str = str:gsub("\n", "\\n")
	str = str:gsub("\r", "\\r")
	str = str:gsub("\t", "\\t")
	return str
end

-- Encodes one character's craftable professions (gathering professions and
-- professions with zero known recipes are skipped). Returns nil if the
-- character has nothing craftable to report.
--
-- Guildhall's guild-wide table holds data relayed from *other* players'
-- clients, not just what this client scanned itself -- so a stale/buggy
-- Guildhall version (or a deliberately malformed relay) on any guildmate's
-- end could hand this addon a non-numeric rank/level/recipe ID. Without
-- tonumber() guards, string.format("%d",...)/table.concat/table.sort all
-- throw a hard Lua error on that, breaking /ghe for whoever runs it --
-- over one bad record anywhere in the guild, not just skipping it.
local function EncodeCharacter(name, charData)
	if type(charData) ~= "table" then
		return nil
	end

	local profs = {}
	for skillLineIDRaw, prof in pairs(charData.profs or {}) do
		local skillLineID = tonumber(skillLineIDRaw)
		if skillLineID and type(prof) == "table" then
			local isGathering = Guildhall.Scan and Guildhall.Scan.GATHERING_LINES
				and Guildhall.Scan.GATHERING_LINES[skillLineID]
			if not isGathering then
				local recipeIDs = {}
				for spellIDRaw in pairs(prof.recipes or {}) do
					local spellID = tonumber(spellIDRaw)
					if spellID then
						recipeIDs[#recipeIDs + 1] = spellID
					end
				end
				if #recipeIDs > 0 then
					table.sort(recipeIDs)
					profs[#profs + 1] = {
						id = skillLineID,
						rank = tonumber(prof.rank) or 0,
						max = tonumber(prof.max) or 0,
						recipes = recipeIDs,
					}
				end
			end
		end
	end

	if #profs == 0 then
		return nil
	end

	table.sort(profs, function(a, b) return a.id < b.id end)

	local profParts = {}
	for _, p in ipairs(profs) do
		profParts[#profParts + 1] = string.format(
			'"%d":{"rank":%d,"max":%d,"recipes":[%s]}',
			p.id, p.rank, p.max, table.concat(p.recipes, ",")
		)
	end

	return string.format(
		'"%s":{"class":"%s","level":%d,"rev":%d,"professions":{%s}}',
		EscapeJSON(name),
		EscapeJSON(charData.class or ""),
		tonumber(charData.level) or 0,
		tonumber(charData.rev) or 0,
		table.concat(profParts, ",")
	)
end

-- Builds the full export JSON string.
-- Returns json, nil, characterCount on success, or nil, errorMessage on failure.
-- Own characters are always included; guild members are included only when
-- the player is actually in a guild (Guildhall.GuildKey() returns a value).
function GHE.BuildExportJSON()
	if not Guildhall then
		return nil, "Guildhall isn't loaded."
	end

	local db = Guildhall.DB()
	local guildKey = Guildhall.GuildKey and Guildhall.GuildKey()
	local guildDB = guildKey and Guildhall.GuildDB and Guildhall.GuildDB()

	local seen = {}
	local charEntries = {}

	local function addChar(name, data)
		if seen[name] then return end
		seen[name] = true
		local encoded = EncodeCharacter(name, data)
		if encoded then
			charEntries[#charEntries + 1] = encoded
		end
	end

	for name, charData in pairs(db.chars or {}) do
		addChar(name, charData)
	end
	if guildDB then
		for name, memberData in pairs(guildDB.members or {}) do
			addChar(name, memberData)
		end
	end

	table.sort(charEntries)

	local now = time and time() or os.time()
	local json = string.format(
		'{"schema":"%s","guild":"%s","generatedBy":"%s","generatedAt":%d,"characters":{%s}}',
		GHE.SCHEMA,
		EscapeJSON(guildKey or ""),
		EscapeJSON(Guildhall.Me and Guildhall.Me() or ""),
		now,
		table.concat(charEntries, ",")
	)

	return json, nil, #charEntries
end

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------

local frame

local function EnsureFrame()
	if frame then return frame end

	frame = CreateFrame("Frame", "GuildhallExporterFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(520, 420)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame.TitleText:SetText("Guildhall Exporter")

	local scrollFrame = CreateFrame("ScrollFrame", "GuildhallExporterScroll", frame, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", 12, -32)
	scrollFrame:SetPoint("BOTTOMRIGHT", -30, 42)

	local editBox = CreateFrame("EditBox", nil, scrollFrame)
	editBox:SetMultiLine(true)
	editBox:SetFontObject(ChatFontNormal)
	editBox:SetWidth(scrollFrame:GetWidth())
	editBox:SetAutoFocus(false)
	editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
	scrollFrame:SetScrollChild(editBox)
	frame.editBox = editBox

	local status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	status:SetPoint("BOTTOMLEFT", 16, 14)
	status:SetPoint("BOTTOMRIGHT", -140, 14)
	status:SetJustifyH("LEFT")
	frame.status = status

	local generateButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	generateButton:SetSize(110, 22)
	generateButton:SetPoint("BOTTOMRIGHT", -16, 10)
	generateButton:SetText("Generate")
	generateButton:SetScript("OnClick", function()
		local json, err, count = GHE.BuildExportJSON()
		if not json then
			editBox:SetText("")
			frame.status:SetText(err or "Export failed.")
			return
		end
		editBox:SetText(json)
		editBox:HighlightText()
		editBox:SetFocus()
		if count == 0 then
			frame.status:SetText("No craftable recipes found yet. Log in on your characters or wait for guild sync.")
		else
			frame.status:SetText(string.format("%d character(s) exported. Selected - press Ctrl+C to copy.", count))
		end
	end)

	frame:Hide()
	return frame
end

-- Mirrors Guildhall's own short slash-command style ("/gh") -- "/ghe" for
-- Guildhall Exporter. Can't reuse "/gh" itself, that's Guildhall's command.
SLASH_GUILDHALLEXPORTER1 = "/ghe"
SlashCmdList["GUILDHALLEXPORTER"] = function()
	if not Guildhall then
		print("|cffff0000Guildhall Exporter:|r Guildhall isn't loaded. Install it (github.com/vBaustad/Guildhall or the CurseForge \"Guildhall\" addon) and log in once so it can scan/sync before exporting.")
		return
	end
	EnsureFrame():Show()
end
