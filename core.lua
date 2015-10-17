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

local char, chars, RECIPE, GLYPH

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

    -- TODO: is this order constant across locales?
    local _
    _, _, _, _, GLYPH, _, RECIPE = GetAuctionItemClasses()

    self:HookScript(GameTooltip, "OnTooltipSetItem")
    self:HookScript(ItemRefTooltip, "OnTooltipSetItem")
    self:HookScript(ShoppingTooltip1, "OnTooltipSetItem")
    self:HookScript(ShoppingTooltip2, "OnTooltipSetItem")

    self:HookScript(GameTooltip, "OnTooltipCleared")
    self:HookScript(ItemRefTooltip, "OnTooltipCleared")
    self:HookScript(ShoppingTooltip1, "OnTooltipCleared")
    self:HookScript(ShoppingTooltip2, "OnTooltipCleared")

    self:RegisterEvent("TRADE_SKILL_SHOW")

    if IsAddOnLoaded("Blizzard_GlyphUI") then
        self:ScanGlyphs()
    else
        self:RegisterEvent("ADDON_LOADED")
    end
    self:RegisterEvent("GLYPH_ADDED", "GLYPH_UPDATED")
end

function core:ADDON_LOADED(event, addon)
    if addon ~= "Blizzard_GlyphUI" then
        return
    end
    self:ScanGlyphs()
    self:UnregisterEvent("ADDON_LOADED")
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
            elseif owner:GetName() == "TradeSkillSkillIcon" then
                link = GetTradeSkillItemLink(TradeSkillFrame.selectedSkill)
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

    local name, _, _, _, _, class, subclass = GetItemInfo(link)
    if class == RECIPE then
        if not ns.itemid_to_spellid[itemid] then return end
        local spellid = ns.itemid_to_spellid[itemid]
        -- we're on a recipe here!
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
    end
    if class == GLYPH then
        name = name:gsub("^Glyph of ", "")
        for alt, details in pairs(chars) do
            if details and details.glyphs and details.glyphs[name] ~= nil then
                local color = RAID_CLASS_COLORS[details.class] or NORMAL_FONT_COLOR
                if details.glyphs[name] then
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

function core:TRADE_SKILL_SHOW()
    if not (char and char.professions) then return Debug("Not recording skill", "DB not ready") end
    if not IsTradeSkillReady() then return Debug("Not recording skill", "not ready") end
    if IsNPCCrafting() then return Debug("Not recording skill", "NPC crafting") end

    local skill = GetTradeSkillLine()
    if not skill or skill == UNKNOWN then
        return Debug("Not recording skill", "Couldn't GetTradeSkillLine")
    end

    if IsTradeSkillLinked() then
        return Debug("Not recording skill", "Don't scan someone else's skills")
    end

    if TradeSkillFilterBar:IsShown() then
        return Debug("Not recording skill", "Don't scan if we're filtering")
    end

    local numRecipes = GetNumTradeSkills()
    if not numRecipes or numRecipes == 0 then
        return Debug("Not recording skill", "We know no recipes", numRecipes)
    end

    -- First line: a header?
    local skillName, skillType, numAvailable, isExpanded = GetTradeSkillInfo(1)   -- test the first line
    if skillType ~= "header" then
        return Debug("Not recording skill", "First line isn't a header", skillName)
    end

    local skills = {}

    for i = 1, numRecipes do
        skillName, skillType, numAvailable, isExpanded = GetTradeSkillInfo(i)

        if skillType == "header" or skillType == "subheader" then
            -- bypass it
            if not isExpanded then
                return Debug("Not recording skill", "Aborting skill scan, non-expanded header", skillName)
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
    char.professions[skill] = skills
end

function core:ScanGlyphs()
    if not char then return Debug("Not recording glyphs", "DB not ready") end
    if not IsGlyphFlagSet(GLYPH_FILTER_KNOWN) then return Debug("Not recording glyphs", "Known glyphs filter disabled") end
    if GlyphFrameSearchBox and GlyphFrameSearchBox:GetText() ~= "" then return Debug("Not recording glyphs", "Glyph name filter enabled") end

    local glyphs = {}
    for i=1, GetNumGlyphs() do
        local name, glyphType, isKnown, icon, glyphID, link, subText = GetGlyphInfo(i)
        if name ~= "header" then
            glyphs[name] = isKnown
        end
    end
    char.glyphs = glyphs
    Debug("Actually recorded glyphs")
end
core.GLYPH_UPDATED = core.ScanGlyphs
core.GLYPH_ADDED = core.ScanGlyphs
