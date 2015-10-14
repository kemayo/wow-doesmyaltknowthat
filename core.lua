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

local char, chars, RECIPE, ENCHANTING

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
        }
    end
    char = chars[name].professions

    -- TODO: is this order constant across locales?
    RECIPE = select(7, GetAuctionItemClasses())
    ENCHANTING = select(9, GetAuctionItemSubClasses(7))

    self:HookScript(GameTooltip, "OnTooltipSetItem")
    self:HookScript(ItemRefTooltip, "OnTooltipSetItem")
    self:HookScript(ShoppingTooltip1, "OnTooltipSetItem")
    self:HookScript(ShoppingTooltip2, "OnTooltipSetItem")

    self:HookScript(GameTooltip, "OnTooltipCleared")
    self:HookScript(ItemRefTooltip, "OnTooltipCleared")
    self:HookScript(ShoppingTooltip1, "OnTooltipCleared")
    self:HookScript(ShoppingTooltip2, "OnTooltipCleared")

    self:RegisterEvent("TRADE_SKILL_SHOW")
end

local tooltip_modified = {}
function core:OnTooltipSetItem(tooltip)
    local name, link = tooltip:GetItem()
    -- Debug("OnTooltipSetItem", name, link)
    if not name then return end
    local itemid = tonumber(link:match("item:(%d+)"))
    if not itemid or itemid == 0 then
        local owner = tooltip:GetOwner()
        if owner and owner.link then
            link = owner.link
            itemid = tonumber(link:match("item:(%d+)"))
        end
        if not itemid or itemid == 0 then return end
    end
    if not ns.itemid_to_spellid[itemid] then return end
    local spellid = ns.itemid_to_spellid[itemid]

    local class, subclass = select(6, GetItemInfo(link))
    if class ~= RECIPE then return end

    -- we're on a recipe here!
    if tooltip_modified[tooltip:GetName()] then
        -- this happens twice, because of how recipes work
        return
    end
    tooltip_modified[tooltip:GetName()] = true

    for alt, details in pairs(chars) do
        Debug("Known on?", alt, details and details.professions[subclass])
        if details and details.professions[subclass] then
            -- alt knows this profession
            local color = RAID_CLASS_COLORS[details.class] or NORMAL_FONT_COLOR
            if details.professions[subclass][spellid] then
                tooltip:AddDoubleLine(alt, ITEM_SPELL_KNOWN, color.r, color.g, color.b, GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
            else
                -- ...and doesn't know this recipe!
                tooltip:AddDoubleLine(alt, LEARN, color.r, color.g, color.b, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
            end
        end
    end

    tooltip:Show()
end

function core:OnTooltipCleared(tooltip)
    tooltip_modified[tooltip:GetName()] = nil
end

-- Scanning recipes

function core:TRADE_SKILL_SHOW()
    if not char then return end
    if not IsTradeSkillReady() then return end
    if IsNPCCrafting() then return end

    local skill = GetTradeSkillLine()
    if not skill or skill == UNKNOWN then
        Debug("Couldn't GetTradeSkillLine")
        return
    end

    if IsTradeSkillLinked() then
        Debug("Don't scan someone else's skills")
        return
    end

    if TradeSkillFilterBar:IsShown() then
        Debug("Don't scan if we're filtering")
        return
    end

    local numRecipes = GetNumTradeSkills()
    if not numRecipes or numRecipes == 0 then
        Debug("We know no recipes", numRecipes)
        return
    end

    -- First line: a header?
    local skillName, skillType, numAvailable, isExpanded = GetTradeSkillInfo(1)   -- test the first line
    if skillType ~= "header" then
        Debug("First line isn't a header", skillName)
        return
    end

    local skills = {}

    for i = 1, numRecipes do
        skillName, skillType, numAvailable, isExpanded = GetTradeSkillInfo(i)

        if skillType == "header" or skillType == "subheader" then
            -- bypass it
            if not isExpanded then
                Debug("Aborting skill scan, non-expanded header", skillName)
                return
            end
        else
            -- this gets the spellid... but that's not linkable to recipes without a huge mining job. Woo.
            Debug("recording skill line", skillName, skillType)
            link = GetTradeSkillRecipeLink(i)
            -- spellid
            local makes = link and tonumber(link:match("enchant:(%d+)"))
            if makes then
                skills[makes] = true
            else
                Debug("Couldn't extract spellid", link)
            end
        end
    end

    -- just throw away old recipes
    Debug("Actually recorded skills")
    char[skill] = skills
end
