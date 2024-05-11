local myname, ns = ...
local myfullname = GetAddOnMetadata(myname, "Title")

DMAKT = ns

local core = ns:NewModule("core")
local Debug = core.Debug

core.defaults = {
    characters = {},
}
core.defaultsPC = {
}

local char, chars

local function GetTooltipItem(tooltip)
    if _G.TooltipDataProcessor then
        return TooltipUtil.GetDisplayedItem(tooltip)
    end
    return tooltip:GetItem()
end

function core:OnLoad()
    self:InitDB()

    local name = UnitName("player")
    local realm = GetRealmName()
    if not core.db.characters[realm] then
        core.db.characters[realm] = {}
    end
    chars = core.db.characters[realm]
    if not chars[name] then
        chars[name] = {
            class = select(2, UnitClass('player')),
            professions = {},
            glyphs = {},
        }
    end
    char = chars[name]

    if _G.TooltipDataProcessor then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            self:OnTooltipSetItem(tooltip)
        end)
    else
        self:HookScript(GameTooltip, "OnTooltipSetItem")
        self:HookScript(ItemRefTooltip, "OnTooltipSetItem")
        self:HookScript(ShoppingTooltip1, "OnTooltipSetItem")
        self:HookScript(ShoppingTooltip2, "OnTooltipSetItem")
    end

    self:HookScript(GameTooltip, "OnTooltipCleared")
    self:HookScript(ItemRefTooltip, "OnTooltipCleared")
    self:HookScript(ShoppingTooltip1, "OnTooltipCleared")
    self:HookScript(ShoppingTooltip2, "OnTooltipCleared")

    self:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
end

function core:OnLogin()
    -- Clean up professions the character no longer knows
    local professions_to_parent = {}
    for _, professionid in ipairs(C_TradeSkillUI.GetAllProfessionTradeSkillLines()) do
        local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(professionid)
        if info and info.parentProfessionName then
            professions_to_parent[info.professionName] = info.parentProfessionName
        end
    end
    local char_professions = {}
    for _, profession in ipairs({GetProfessions()}) do
        -- We know "Blacksmithing"
        char_professions[GetProfessionInfo(profession)] = true
    end
    for profession in pairs(char.professions) do
        -- A recipe is associated with "Kul Tiran Blacksmithing"
        if professions_to_parent[profession] and not char_professions[professions_to_parent[profession]] then
            self.Print(("%s doesn't know %s any more, forgetting its recipes"):format(UnitName('player'), professions_to_parent[profession]))
            char.professions[profession] = nil
        end
    end
end

local tooltip_modified = {}
function core:OnTooltipSetItem(tooltip)
    local name, link = GetTooltipItem(tooltip)
    -- Debug("OnTooltipSetItem", name, link)
    if not name then return end
    local itemid = tonumber(link:match("item:(%d+)"))
    if not itemid or itemid == 0 then
        local owner = tooltip:GetOwner()
        if owner then
            if owner.link then
                link = owner.link
            elseif TradeSkillFrame and owner:GetParent() == TradeSkillFrame.DetailsFrame.Contents then
                link = C_TradeSkillUI.GetRecipeItemLink(TradeSkillFrame.RecipeList:GetSelectedRecipeID())
            elseif owner.BuyItem then
                -- Basically: GnomishVendorShrinker
                link = GetMerchantItemLink(owner:GetID())
            end
            itemid = tonumber(link:match("item:(%d+)"))
        end
        if not itemid or itemid == 0 then return end
    end

    if tooltip_modified[tooltip:GetName()] then
        -- this happens twice, because of how recipes work
        return
    end
    tooltip_modified[tooltip:GetName()] = true

    local _, _, recipetype, _, _, class, subclass = GetItemInfoInstant(link)
    if class == Enum.ItemClass.Recipe then
        if not ns.itemid_to_spellid[itemid] then return end
        local spellid = ns.itemid_to_spellid[itemid]
        Debug("Updating tooltip", link, itemid, spellid, recipetype)
        -- we're on a recipe here!
        for alt, details in pairs(chars) do
            Debug("Known on?", alt, details and details.professions[recipetype])
            if details and details.professions[recipetype] then
                -- alt knows this profession
                local color = RAID_CLASS_COLORS[details.class] or NORMAL_FONT_COLOR
                if details.professions[recipetype][spellid] then
                    tooltip:AddDoubleLine(alt, ITEM_SPELL_KNOWN, color.r, color.g, color.b, GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
                else
                    -- ...and doesn't know this recipe!
                    tooltip:AddDoubleLine(alt, LEARN, color.r, color.g, color.b, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
                end
            end
        end
    end

    tooltip:Show()
end

function core:OnTooltipCleared(tooltip)
    tooltip_modified[tooltip:GetName()] = nil
end

-- Scanning recipes

-- /spew DMAKT:GetModule("core").db.characters[GetRealmName()][UnitName("player")]

function core:TRADE_SKILL_LIST_UPDATE()
    if not (char and char.professions) then return Debug("Not recording skill", "DB not ready") end
    if not C_TradeSkillUI.IsTradeSkillReady() then return Debug("Not recording skill", "not ready") end
    if C_TradeSkillUI.IsNPCCrafting() then return Debug("Not recording skill", "NPC crafting") end
    if C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild() then
        return Debug("Not recording skill", "Don't scan someone else's skills")
    end

    local info = C_TradeSkillUI.GetBaseProfessionInfo()
    if not info or info.professionName == UNKNOWN then
        return Debug("Not recording skill", "Couldn't GetBaseProfessionInfo")
    end

    local recipes = C_TradeSkillUI.GetAllRecipeIDs()

    if not recipes or #recipes == 0 then
        return Debug("Not recording skill", "We know no recipes", numRecipes)
    end

    local skills = {}
    local count = 0

    for _, recipeid in pairs(recipes) do
        local recipe = C_TradeSkillUI.GetRecipeInfo(recipeid)
        if recipe and recipe.learned then
            skills[recipeid] = true
            count = count + 1
        end
    end

    -- just throw away old recipes
    Debug("Actually recorded recipes", info.professionName, count)
    char.professions[info.professionName] = skills
end
