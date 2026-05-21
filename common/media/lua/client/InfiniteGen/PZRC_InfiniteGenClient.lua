require "PZRC_Utils"

-- Block non-admin from picking up infinite generators
if ISTakeGenerator and ISTakeGenerator.isValid then
    local _oldIsValid = ISTakeGenerator.isValid

    function ISTakeGenerator:isValid()
        if self.generator and self.generator.getModData then
            local data = self.generator:getModData()
            if data and data["_isFuelInfinite"] and not PZRC_Utils.IsAdminPlayer() then
                getPlayer():addLineChatElement(
                    getText("IGUI_PZRC_InfGen_AdminOnly"),
                    1, 0, 0
                )
                return false
            end
        end
        return _oldIsValid(self)
    end
end

local function makeInfinite(gen)
    local sq = gen:getSquare()
    if not sq then return end
    sendClientCommand(getPlayer(), "PZRC_InfGen", "makeInfinite", {
        x = sq:getX(), y = sq:getY(), z = sq:getZ()
    })
    gen:getModData()['_isFuelInfinite'] = true
    getPlayer():addLineChatElement(getText("IGUI_PZRC_InfGen_SetInfinite"), 1, 1, 0)
end

local function makeNormal(gen)
    local sq = gen:getSquare()
    if not sq then return end
    sendClientCommand(getPlayer(), "PZRC_InfGen", "makeNormal", {
        x = sq:getX(), y = sq:getY(), z = sq:getZ()
    })
    gen:getModData()['_isFuelInfinite'] = nil
    getPlayer():addLineChatElement(getText("IGUI_PZRC_InfGen_SetNormal"), 1, 1, 0)
end

local function onWorldContextMenu(_player, context, worldObjects, _test)
    if not PZRC_Utils.IsAdminPlayer() then return end

    for _, obj in ipairs(worldObjects) do
        if obj:getObjectName() == "IsoGenerator" then
            local data = obj:getModData()
            local subMenu = PZRC_ContextMenu.getSection(context, "InfGen")
            if data and data['_isFuelInfinite'] then
                subMenu:addOption(getText("IGUI_PZRC_InfGen_MakeNormal"), obj, makeNormal)
            else
                subMenu:addOption(getText("IGUI_PZRC_InfGen_MakeInfinite"), obj, makeInfinite)
            end
            return
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onWorldContextMenu)
