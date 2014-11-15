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

local char, RECIPE

function core:OnLoad()
    self:InitDB()

    local name = UnitName("player")
    if not core.db.characters[name] then
        core.db.characters[name] = {
            class = select(2, UnitClass('player')),
            professions = {},
        }
    end
    char = core.db.characters[name].professions

    -- TODO: is this order constant across locales?
    RECIPE = select(7, GetAuctionItemClasses())

    self:HookScript(GameTooltip, "OnTooltipSetItem")
    self:HookScript(ItemRefTooltip, "OnTooltipSetItem")
    self:HookScript(ShoppingTooltip1, "OnTooltipSetItem")
    self:HookScript(ShoppingTooltip2, "OnTooltipSetItem")

    self:RegisterEvent("TRADE_SKILL_SHOW")
end

local last_item
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
    if last_item == name then
        -- this happens twice, because of how recipes work. We want to happen on the second go-throuh
        last_item = nil
        return
    end
    last_item = name

    for alt, details in pairs(core.db.characters) do
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

-- Scanning recipes

function core:TRADE_SKILL_SHOW()
    if not char then return end

    local skill = GetTradeSkillLine()
    if not skill or skill == UNKNOWN then return end

    -- just throw away old recipes
    char[skill] = {}

    local numRecipes = GetNumTradeSkills()
    if not numRecipes or numRecipes == 0 then return end
    
    -- First line: a header?
    local skillName, skillType = GetTradeSkillInfo(1)   -- test the first line
    if skillType ~= "header" then return end

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
