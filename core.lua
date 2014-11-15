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

local char, chars, RECIPE

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
    local class, subclass = select(6, GetItemInfo(link))
    if class ~= RECIPE then return end

    local created_item = self:recipeNameFromTooltip(tooltip)
    if not created_item then
        -- Debug("Couldn't find item")
        return
    end

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
            if details.professions[subclass][created_item] then
                tooltip:AddDoubleLine(alt, ITEM_SPELL_KNOWN, color.r, color.g, color.b, GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
            else
                -- ...and doesn't know this recipe!
                tooltip:AddDoubleLine(alt, LEARN, color.r, color.g, color.b, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
            end
        end
    end

    tooltip:Show()
end

do
    local function GetLineAfterPattern(pattern, ...)
        local matched
        for i = 1, select("#", ...) do
            local region = select(i, ...)
            if region and region:GetObjectType() == "FontString" then
                -- Debug(region:GetName(), region:GetText())
                local text = region:GetText()
                if text then
                    if matched then
                        return text
                    end
                    matched = text:match(pattern)
                end
            end
        end
    end
    function core:recipeNameFromTooltip(tooltip)
        -- If this is a fairly unmeddled-with tooltip, which I hope it is...
        line = GetLineAfterPattern(USE_COLON, tooltip:GetRegions())
        if line then
            return line:gsub("\n", "")
        end
    end
end

function core:OnTooltipCleared(tooltip)
    tooltip_modified[tooltip:GetName()] = nil
end

-- Scanning recipes

function core:TRADE_SKILL_SHOW()
    if not char then return end

    local skill = GetTradeSkillLine()
    if not skill or skill == UNKNOWN then
        Debug("Couldn't GetTradeSkillLine")
        return
    end

    -- just throw away old recipes
    char[skill] = {}

    local numRecipes = GetNumTradeSkills()
    if not numRecipes or numRecipes == 0 then
        Debug("We know no recipes", numRecipes)
        return
    end

    -- First line: a header?
    local skillName, skillType = GetTradeSkillInfo(1)   -- test the first line
    if skillType ~= "header" then
        Debug("First line isn't a header", skillName)
        return
    end

    for i = 1, numRecipes do
        skillName, skillType = GetTradeSkillInfo(i)

        if skillType == "header" or skillType == "subheader" then
            -- bypass it
        else
            -- this gets the spellid... but that's not linkable to recipes without a huge mining job. Woo.
            Debug("recording skill line", skillName, skillType)
            link = GetTradeSkillRecipeLink(i)
            -- spellid
            local makes = tonumber(link:match("enchant:(%d+)"))
            char[skill][skillName] = makes or true
        end
    end
    
end
