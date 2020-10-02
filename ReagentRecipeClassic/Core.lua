local LibStub = _G.LibStub
ReagentRecipeClassic = LibStub("AceAddon-3.0"):NewAddon("ReagentRecipeClassic", "AceConsole-3.0", "AceEvent-3.0", "AceHook-3.0", "AceSerializer-3.0", "AceTimer-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("ReagentRecipeClassic")

local cache = {}
local recipeCache = {}

local debug = false
local options = {
    name = L["Reagent Recipe Classic"],
    handler = ReagentRecipeClassic,
    type = "group",
    args = {
        enabled = {
            type = "toggle",
            name = L["Enabled"],
            get = "GetEnabled",
            set = "SetEnabled",
            order=1,
        },
        hotkeys = {
            type = "toggle",
            name = L["Hot Key Reveal"],
            desc = "Only works when other specific options are enabled.  When checked will only show tooltips when holding Shift (this alts recipes), Alt (alt recipes), Ctrl (unknown recipes)",
            get = "GetHotKeys",
            set = "SetHotKeys",
            order = 2,
            width = 2.5
        },
        threshold = {
            type = "select",
            name = L["Threshold"],
            values = {"Optimal", "Medium", "Easy", "Trivial"},
            desc = L["The minimum difficulty for a recipe to be shown"],
            get = "GetThreshold",
            set = "SetThreshold",
            order=3,
            width = "normal"
        },
        recipesListed = {
            type = "range",
            name = L["Recipes Listed"],
            desc = L["The number of recipes displayed per character per tree level"],
            get = "GetRecipesListed",
            set = "SetRecipesListed",
            step=1,
            min = 1,
            max = 50,
            order=4,
        },
        unknown = {
            type = "toggle",
            name = L["Include unknown recipes"],
            get = "GetShowUnknown",
            set = "SetShowUnknown",
            order=5,
            width="full"
        },
        tree = {
            type = "toggle",
            name = L["Tree View"],
            desc = L["Toggles between tree and list"],
            get = "IsUsedInTree",
            set = "ToggleUsedInTree",
            order=8,
            width="full"
        },
        showAlts = {
            type = "toggle",
            name = L["Show Alts"],
            desc = L["Toggles the display of alts"],
            get = "GetShowAlts",
            set = "SetShowAlts",
            order=6,
            width="full"
        },
        showReagents = {
            type = "toggle",
            name = L["Show Reagents"],
            desc = L["Toggles the reagents line"],
            get = "GetShowReagents",
            set = "SetShowReagents",
            order=7,
            width="full"
        },
        delete= {
            type = "input",
            name = L["Erase"],
            desc = L["Erase data for a character."],
            usage = L["<Character Name>"],
            set = "EraseData",
            order=9
        },
    },
}

local defaults = {
    profile = {
        threshold = "trivial",
        usedInTree = true,
        showAlts = true,
        showFriends = true,
        recipesListed = 20,
        version = false,
        unknown = true,
        enabled = true,
        showReagents = true,
        hotkeys = false
    },
}

function ReagentRecipeClassic:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("ReagentRecipeClassicDB", defaults, "Default")

    LibStub("AceConfig-3.0"):RegisterOptionsTable("ReagentRecipeClassic",  options)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ReagentRecipeClassic", "ReagentRecipeClassic")
    if not self.db.factionrealm.player then
        self.db.factionrealm.player = {}
        self.db.factionrealm.friends = {}
    end
    if not self.db.factionrealm.characters then
        self.db.factionrealm.characters = {}
    end
    local characterName = UnitName("player")
    if not self.db.factionrealm.characters[characterName] then
        self.db.factionrealm.characters[characterName] = {
            enchanting = false,
            jewelcrafting = false,
            inscription = false,
        }
    end
    if self.db.profile.version and self.db.profile.version < .6 then
        self.db.factionrealm.version = nil
    end
    if not self.db.profile then
        self:Print("no version detected")
        for reagent, reagentData in pairs(self.db.factionrealm.player) do
            for character, data in pairs(reagentData) do
                for recipe, recipeData in pairs(data) do
                    if not recipeData.level then
                        self.db.factionrealm.player[reagent][character][recipe].level = 0
                    end
                end
            end
        end
    end
    self.db.profile.version = 1.3
    cache, recipeCache = unpack(self:BuildCache())
end

function ReagentRecipeClassic:EraseData(info, character)
    self.db.factionrealm.characters[character] = {
        enchanting = false,
        jewelcrafting = false,
        inscription = false,
    }
    for a, types in pairs(self.db.factionrealm) do
        for b, reagents in pairs(types) do
            for name, recipes in pairs(reagents) do
                if (name == character) then
                    reagents[name] = nil
                end
            end
        end
    end
    cache, recipeCache = unpack(self:BuildCache())
end

--function ReagentRecipeClassic:GetCharacterList()
--    local characters = {};
--    for types in ipairs(self.db.factionrealm) do
--        for reagents in ipairs(types) do
--            for name in pairs(reagents) do
--                table.insert(characters, name);
--            end
--        end
--    end
--    return characters;
--end


function ReagentRecipeClassic:ChatCommand(input)
    if not input or input:trim() == "" then
        InterfaceOptionsFrame_OpenToFrame(self.optionsFrame)
    else
        LibStub("AceConfigCmd-3.0").HandleCommand(ReagentRecipeClassic, "rt", "ReagentRecipeClassic", input)
    end
end

function ReagentRecipeClassic:SetShowFriends(info, newValue)
    self.db.profile.showFriends = newValue
end

function ReagentRecipeClassic:GetShowFriends(info)
    return self.db.profile.showFriends
end

function ReagentRecipeClassic:GetRecipesListed(info)
    return self.db.profile.recipesListed
end


function ReagentRecipeClassic:SetRecipesListed(info, newValue)
    self.db.profile.recipesListed = newValue
end

local function ShouldBeShown(which)
    if which == 1 then
        return ReagentRecipeClassic:GetEnabled() and ((ReagentRecipeClassic:GetHotKeys() and IsShiftKeyDown()) or not ReagentRecipeClassic:GetHotKeys())
    elseif which == 2 then
        return ReagentRecipeClassic:GetShowAlts() and ((ReagentRecipeClassic:GetHotKeys() and IsAltKeyDown()) or not ReagentRecipeClassic:GetHotKeys())
    elseif which == 3 then
        return ReagentRecipeClassic:GetShowUnknown() and ((ReagentRecipeClassic:GetHotKeys() and IsControlKeyDown()) or not ReagentRecipeClassic:GetHotKeys())
    end
end

function ReagentRecipeClassic:GetShowAlts(info)
    return self.db.profile.showAlts
end
function ReagentRecipeClassic:GetShowUnknown(info)
    return self.db.profile.showUnknown
end
function ReagentRecipeClassic:SetShowUnknown(info, newValue)
    self.db.profile.showUnknown = newValue
end
function ReagentRecipeClassic:SetShowAlts(info, newValue)
    self.db.profile.showAlts = newValue
end
function ReagentRecipeClassic:GetShowReagents()
    return self.db.profile.showReagents
end
function ReagentRecipeClassic:SetShowReagents(info, value)
    self.db.profile.showReagents = value
end
function ReagentRecipeClassic:GetEnabled(info)
    return self.db.profile.enabled
end
function ReagentRecipeClassic:SetEnabled(info, value)
    self.db.profile.enabled = value
end
function ReagentRecipeClassic:GetThreshold(info)
    local threshold = self.db.profile.threshold
    if (threshold == "optimal") then
        return 1
    end
    if (threshold == "medium") then
        return 2
    end
    if (threshold == "easy") then
        return 3
    end
    if (threshold == "trivial") then
        return 4
    end
end

function ReagentRecipeClassic:GetHotKeys()
    return self.db.profile.hotkeys
end
function ReagentRecipeClassic:SetHotKeys(info, value)
    self.db.profile.hotkeys = value
end

function ReagentRecipeClassic:SetThreshold(info, newValue)
    local db = self.db.profile
    if (newValue == 1) then        
        db.threshold = "optimal"
    elseif (newValue == 2) then
        db.threshold = "medium"
    elseif (newValue == 3) then
        db.threshold = "easy"
    elseif (newValue == 4) then
        db.threshold = "trivial"
    else
        self:Print(newValue .. " is not a valid threshold.")
    end
    self:Print("Threshold set to " .. self.db.profile.threshold)
end

function ReagentRecipeClassic:IsUsedInTree(info)
    return self.db.profile.usedInTree
end

function ReagentRecipeClassic:ToggleUsedInTree(info, value)
    self.db.profile.usedInTree = value
end

local rh_tradeskill = GameTooltip.SetRecipeReagentItem
function GameTooltip:SetRecipeReagentItem(...)
    local link = GetCraftReagentItemLink(...)
    if link then return self:SetHyperlink(link) end
    return rh_tradeskill(self, ...)
end

local function AttachTooltip(tooltip, ...)
    if ReagentRecipeClassic:GetShowReagents() then
        ReagentRecipeClassic:ListReagents(tooltip)
    end

    if (not IsShiftKeyDown() and ReagentRecipeClassic:GetEnabled() and not ReagentRecipeClassic:GetHotKeys()) or
            ( (ReagentRecipeClassic:GetEnabled() and ReagentRecipeClassic:GetHotKeys()) and (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown())) then
        ReagentRecipeClassic:MakeTree(tooltip, select(1, tooltip:GetItem()), true, {})
    end
end

function ReagentRecipeClassic:OnEnable()
    self:RegisterEvent("TRADE_SKILL_SHOW")
    self:RegisterEvent("CRAFT_UPDATE")
    self:RegisterEvent("CHAT_MSG_SKILL")
    self:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
--new
    self:RegisterEvent("MODIFIER_STATE_CHANGED")
    GameTooltip:HookScript("OnTooltipSetItem", AttachTooltip)
    ItemRefTooltip:HookScript("OnTooltipSetItem", AttachTooltip)
    ItemRefShoppingTooltip1:HookScript("OnTooltipSetItem", AttachTooltip)
    ItemRefShoppingTooltip2:HookScript("OnTooltipSetItem", AttachTooltip)
    if debug then print("queueing from enable") end
    ReagentRecipeClassic:QueueRecipes(false)

    self:RegisterChatCommand("rrc", "HandleSlash")

end



function ReagentRecipeClassic:CHAT_MSG_SKILL(info, msg)
    if strfind(msg, "Inscription") or strfind(msg, "Jewelcrafting") then
        local skill
        for i = -4, -1 do
            skill = tonumber(strsub(msg, i))
            if skill then
                break
            end
            if i == -1 then
                skill = 1
            end
        end
    end
end

function ReagentRecipeClassic:OnDisable()
    -- Called when the addon is disabled
end

function ReagentRecipeClassic:QueueRecipes(fromSkill)
    if (fromSkill) then
        local skill = GetTradeSkillLine()
        if debug and not skill then print("no skill in queue") end
        if not skill then return end
    end


    if ReagentRecipeClassic.CR_Timer then return end -- we already have scheduled refresh, wait for it

    ReagentRecipeClassic.CR_Timer = ReagentRecipeClassic:ScheduleTimer(function() ReagentRecipeClassic:ReadRecipes() end, 1)
end


function ReagentRecipeClassic:ReadTrade()
    local recipeIDs = GetNumTradeSkills()
    local recipeInfo = {};
    for i=1,recipeIDs do
        local recName, recDifficulty = GetTradeSkillInfo(i)
        if recDifficulty ~= "header" then
            if debug then print("adding "..recName.. " "..recDifficulty) end
            for reagentIndex = 1, GetTradeSkillNumReagents(i) do
                local reagentName, _, reagentCount = GetTradeSkillReagentInfo(i, reagentIndex)
                if reagentName == nil then reagentName = "no Name" end
                if debug then print("adding "..reagentName) end
                local db = self.db.factionrealm.player
                db[reagentName] = db[reagentName] or {}
                local characterName = UnitName("player")
                db[reagentName][characterName] = db[reagentName][characterName] or {}
                --("trivial", "easy", "medium", "optimal", "difficult")
                local d = ""
                db[reagentName][characterName][recName] = {
                    count = reagentCount,
                    difficulty = recDifficulty,
                    level = 0
                }
            end
        end
    end
end
function ReagentRecipeClassic:ReadCraft()
    local recipeIDs = GetNumCrafts()
    if debug then print("recipes: ",recipeIDs) end
    local recipeInfo = {};
    for i=1,recipeIDs do
        local recName, _, recDifficulty = GetCraftInfo(i)
        if debug then print("info: ",recName, recDifficulty) end
        if recDifficulty ~= "header" then
            for reagentIndex = 1, GetCraftNumReagents(i) do
                local reagentName, _, reagentCount = GetCraftReagentInfo(i, reagentIndex)
                if reagentName == nil then reagentName = "no Name" end
                if debug then print("adding "..reagentName) end
                local db = self.db.factionrealm.player
                db[reagentName] = db[reagentName] or {}
                local characterName = UnitName("player")
                db[reagentName][characterName] = db[reagentName][characterName] or {}
                --("trivial", "easy", "medium", "optimal", "difficult")
                local d = ""
                db[reagentName][characterName][recName] = {
                    count = reagentCount,
                    difficulty = recDifficulty,
                    level = 0
                }
            end
        end
    end
end

function ReagentRecipeClassic:ReadRecipes()
    if debug then print("Reading Recipes") end
    if ReagentRecipeClassic.CR_Timer then ReagentRecipeClassic:CancelTimer(ReagentRecipeClassic.CR_Timer) ReagentRecipeClassic.CR_Timer=nil end
    --if not C_TradeSkillUI.IsTradeSkillReady() then return end -- prevents missing reagents in recipes

    local skill,_ = GetTradeSkillLine()
    if debug then print(skill) end
    if debug and not skill then print("no skill in read") end
    if not skill then return end
    --if not C_TradeSkillUI.IsTradeSkillLinked() then
    if debug then print("about to get recipes") end
    if skill == "UNKNOWN" then
        if debug then print("Going to craft") end
        ReagentRecipeClassic:ReadCraft()
    else
        if debug then print("Going to trade") end
        ReagentRecipeClassic:ReadTrade()
    end

    cache, recipeCache = unpack(self:BuildCache())
    --end
end
function ReagentRecipeClassic:TRADE_SKILL_SHOW()
    if debug then print("queueing from show") end
	self:QueueRecipes(true)
end

function ReagentRecipeClassic:TRADE_SKILL_LIST_UPDATE()
    if debug then print("queueing from update") end

    self:QueueRecipes(true)
end

function ReagentRecipeClassic:CRAFT_UPDATE()
    if debug then print("queueing from craft update") end

    self:QueueRecipes(true)
end

function ReagentRecipeClassic:TRADE_SKILL_CLOSE()

end

function ReagentRecipeClassic:MODIFIER_STATE_CHANGED()
--    local key, state = select(1, ...)
--        -- Switch the dynamic tooltip when the SHIFT key is held.
--        if myAddonFrame:IsMouseOver() and not ((key == "LSHIFT") or (key == "RSHIFT")) then
--            myAddon_GenerateTooltip(frame)
--        end
end

local function UnknownNeeded(recipeName)
    if debug then print("is unknown needed for", recipeName) end
    if (cache[recipeName] == nil) then return true end
    if (type(cache[recipeName]) == "table") then return true end
    local n = 0
    for i,j in cache[recipeName] do
        n = n + 1
        if n > 1 then break end
    end
    if n > 1 then return false else return true end
end

function ReagentRecipeClassic:ListReagents(tooltip)
    local s = ""
    local _,i = tooltip:GetItem()
    if i == nil then return end
    local _, _, _, _, Id, _ = string.find(i,
            "|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*):?(%d*):?(%-?%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?")
    local sp = LibStub("LibRecipes-1.0a"):GetSpellFromItem(Id)
    if (sp == nil) then return end
    if recipeCache[sp] ~= nil then
        for i,j in pairs(recipeCache[sp]) do
            if s ~= "" then s = s..", " end
            local n = C_Item.GetItemNameByID(i)
            if n == nil then return end
            s = s..n.." ("..j..")"
        end
        tooltip:AddLine(s)
    end
end

local total = 0
--Cached format  cache.itemName.characterName.recipe{name, difficulty, count, level}
function ReagentRecipeClassic:MakeTree(tooltip, itemName, top, exclude)
    local buffer = {}
    local useful = false
    local spellNum = 0
    local total = 0
    if exclude[itemName] then
        if debug then print("returning cause exclude: ",itemName) end
        return false
    end
    if cache and cache[itemName] then
        for characterName, recipe in pairs(cache[itemName]) do
            buffer[characterName] = {}
            for _, recipeData in ipairs(recipe) do
				local recipeName = recipeData.name
                local nested = false
                if ReagentRecipeClassic:IsUsedInTree() then
                    exclude[itemName] = true
                    nested = ReagentRecipeClassic:MakeTree(tooltip, recipeName, false, exclude)
                end
                --if this recipe is already in the tree and this is unknown character then skip it
                if not buffer[characterName][recipeData.difficulty] then
                    buffer[characterName][recipeData.difficulty] = {}
                end
                if recipeData.difficulty == nil then recipeData.difficulty = "trivial" end
                if ReagentRecipeClassic:compareDifficulty(recipeData.difficulty, self.db.profile.threshold) >= 0
                        or nested
                        and (not UnknownNeeded(recipeName) or nested)
                        and total <= tonumber(self:GetRecipesListed()) then
                    table.insert(buffer[characterName][recipeData.difficulty], {
						name = recipeName,
						count = recipeData.count,
						nested = nested,
						level = recipeData.level
					})
                    total = total + 1
                    useful = true
                end
            end
        end

        if useful then
            if top then
                tooltip:AddLine("Reagent Recipes", 0,1,1)
                ReagentRecipeClassic:displayTree(tooltip, buffer, 0)
            else
                return buffer
            end
        else
            return false
        end
    end

    return false
end

--Tree format tree.characterName.difficulty{name, count, nested, level}
function ReagentRecipeClassic:displayTree(tooltip, tree, depth, prevChar)

    if tree[UnitName("Player")] and ShouldBeShown(1) then
        self:displayCharacterTree(tooltip, tree[UnitName("Player")], depth, UnitName("Player"), prevChar)
    end
    if self:GetShowAlts() and ShouldBeShown(2) then
        for character, recipe in pairs(tree) do
            if ( character ~= UnitName("Player") and character ~= "Unknown" ) then
                self:displayCharacterTree(tooltip, recipe, depth, character, prevChar)
            end
        end
    end
    if self:GetShowUnknown() and ShouldBeShown(3) then
        self:displayCharacterTree(tooltip, tree["Unknown"], depth, "Unknown", prevChar)
    end
end

function ReagentRecipeClassic:displayCharacterTree(tooltip, recipe, depth, characterName, prevChar)
    if recipe == nil then return end
    for i=0, depth do
        characterName = "   " .. characterName
    end
    local characterListed = false
    for d=3, 0, -1 do
        local difficulty = ReagentRecipeClassic:numberToDifficulty(d)
        local red, green, blue = ReagentRecipeClassic:getDifficultyColor(difficulty)
        if recipe[difficulty] then
            for _, recipeData in ipairs(recipe[difficulty]) do
				local recipeName = recipeData.name
                recipeName = " " .. recipeName
                for i=0, depth do
                    recipeName = "   " .. recipeName
                end
                if not characterListed then --added this variable and moved the printing of the character name to the loop in order to prevent names from appearing without recipes attached
                    characterListed = true
                    if not (depth == 0 and trim(characterName) == UnitName("Player")) and trim(characterName) ~= prevChar then
                        tooltip:AddLine(characterName)
                    end
                end
                if (recipeData.level and recipeData.level > 0) then
                    tooltip:AddDoubleLine(recipeName.." ("..recipeData.level..")", recipeData.count, red, green, blue, red, green, blue)
                else
                    tooltip:AddDoubleLine(recipeName, recipeData.count, red, green, blue, red, green, blue)
                end
                if recipeData.nested then
                    if debug then print("Calling display tree from nested") end

                    ReagentRecipeClassic:displayTree(tooltip, recipeData.nested, depth + 1, trim(characterName))
                end

            end
        end
    end
end

-- remove trailing and leading whitespace from string.
-- http://en.wikipedia.org/wiki/Trim_(8programming)
function trim(s)
  -- from PiL2 20.4
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end


--Returns a positive number if difficulty1 is harder than difficulty2, 0 if they're even, or a negative number otherwise
function ReagentRecipeClassic:compareDifficulty(difficulty1, difficulty2)
    difficulty1 = ReagentRecipeClassic:difficultyToNumber(difficulty1)
    difficulty2 = ReagentRecipeClassic:difficultyToNumber(difficulty2)
    return difficulty1 - difficulty2
end

function ReagentRecipeClassic:difficultyToNumber(difficulty)
    if difficulty == "trivial" then
        return 0
    elseif difficulty == "easy" then
        return 1
    elseif difficulty == "medium" then
        return 2
    elseif difficulty == "optimal" then
        return 3
    end
end

function ReagentRecipeClassic:numberToDifficulty(x)
    if x == 0 then
        return "trivial"
    elseif x == 1 then
        return "easy"
    elseif x == 2 then
        return "medium"
    elseif x == 3 then
        return "optimal"
    end
end

function ReagentRecipeClassic:getDifficultyColor(difficulty)
    if difficulty == "trivial" then
        return .7, .7, .7
    elseif difficulty == "easy" then
        return .05, .8, .05
    elseif difficulty == "medium" then
        return 1, 1, 0
    elseif difficulty == "optimal" then
        return 1, .5, 0
    end
end

function ReagentRecipeClassic:BuildCache()
    local db = self.db.factionrealm.player
    local ans = {}
    local used = {}
    local r = {}
    for reagent, characters in pairs(db) do
        ans[reagent] = {}
        for character, recipes in pairs(characters) do
            ans[reagent][character] = {}
			local n = 1
            if recipes ~= true then
                for recipeName, recipeData in pairs(recipes) do
                    used[recipeName]=true
                    ans[reagent][character][n] = {
                        name = recipeName,
                        count = recipeData.count,
                        difficulty = recipeData.difficulty,
                        level = recipeData.level
                    }
                    n=n+1
                end
                table.sort(ans[reagent][character], function(a,b) return a.level > b.level end)
            end
        end
    end
    for reagent, recipe in pairs(ReagentRecipeClassic_Reagents) do
        for id, qty in pairs(recipe) do
            if r[id] == nil then r[id] = {} end
            r[id][reagent] = qty
        end
    end

    local reagent = ""
    for reagentID, recipes in pairs(ReagentRecipeClassic_Reagents) do
        reagent = C_Item.GetItemNameByID(reagentID)
        if reagent == nil then
--            self:Print("no name found for reagentID: ",reagentID)
        else
            if not ans[reagent] then
                ans[reagent] = {}
            end
            ans[reagent]["Unknown"] = {}
            local n = 1
            for recipeID, qty in pairs(recipes) do
                local m,_ = GetSpellInfo(recipeID)
                if not used[m] and m ~= nil then
                    ans[reagent]["Unknown"][n]={
                        name = m,
                        count = qty,
                        difficulty = "trivial",
                        level = 0
                    }
                    n=n+1
                end
                table.sort(ans[reagent]["Unknown"], function(a,b) return a.name < b.name end)
            end
            table.sort(ans[reagent], function(a,b) if a=="Unknown" then return false else return a < b end end)
        end
    end
    return {ans, r}
end

function ReagentRecipeClassic:HandleSlash(msg)
    local input = string.lower(string.trim(msg, " "))
    if input == "on" then
        ReagentRecipeClassic:SetEnabled(self, true)
    elseif input == "off" then
        ReagentRecipeClassic:SetEnabled(self, false)
    end
end
--
--function ReagentRecipeClassic:checkMissingRecipes()
--    local cnt = 0
--    for i,j in pairs(ReagentRecipeClassic_Reagents) do
--        for k,l in pairs(j) do
--            --if k == 12622 then print(i,k) end
--            if (LibStub("LibRecipes-1.0a"):GetItemFromSpell(tonumber(k)) == nil) then
--                local a,_ = GetSpellInfo(k)
--                print(a,k)
--                cnt = cnt + 1
--            end
--        end
--    end
--    print("count is ",cnt)
--end