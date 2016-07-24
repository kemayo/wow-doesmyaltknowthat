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

    self:HookScript(GameTooltip, "OnTooltipSetItem")
    self:HookScript(ItemRefTooltip, "OnTooltipSetItem")
    self:HookScript(ShoppingTooltip1, "OnTooltipSetItem")
    self:HookScript(ShoppingTooltip2, "OnTooltipSetItem")

    self:HookScript(GameTooltip, "OnTooltipCleared")
    self:HookScript(ItemRefTooltip, "OnTooltipCleared")
    self:HookScript(ShoppingTooltip1, "OnTooltipCleared")
    self:HookScript(ShoppingTooltip2, "OnTooltipCleared")

    self:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
end

local tooltip_modified = {}
function core:OnTooltipSetItem(tooltip)
    local name, link = tooltip:GetItem()
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
    if class == LE_ITEM_CLASS_RECIPE then
        if not ns.itemid_to_spellid[itemid] then return end
        local spellid = ns.itemid_to_spellid[itemid]
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

    local _, skill = C_TradeSkillUI.GetTradeSkillLine()
    if not skill or skill == UNKNOWN then
        return Debug("Not recording skill", "Couldn't GetTradeSkillLine")
    end

    local recipes = C_TradeSkillUI.GetAllRecipeIDs()

    if not recipes or #recipes == 0 then
        return Debug("Not recording skill", "We know no recipes", numRecipes)
    end

    local skills = {}

    local recipe = {}
    for i, recipeid in pairs(recipes) do
        C_TradeSkillUI.GetRecipeInfo(recipeid, recipe)
        if recipe.type == 'recipe' and recipe.learned then
            skills[recipeid] = true
        end
    end

    -- just throw away old recipes
    Debug("Actually recorded skills")
    char.professions[skill] = skills
end
