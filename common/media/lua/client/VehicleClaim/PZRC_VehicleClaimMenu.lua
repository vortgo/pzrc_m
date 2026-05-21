if isServer() then return end

require "PZRC_VehicleClaim"

-- =========================================================================
-- VehicleClaim context menu — shows "Owners: X, Y" on owned vehicles and
-- disables every option for players who don't have access. The blanket
-- disable mirrors ApocalipseClaimSystem's approach: simpler than guessing
-- which menu options exist across PZ versions and mods.
-- =========================================================================

local function findVehicleInWorldObjects(worldObjects)
    for i = 1, #worldObjects do
        local obj = worldObjects[i]
        if obj and instanceof(obj, "BaseVehicle") then
            return obj
        end
    end
    return nil
end

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local vehicle = findVehicleInWorldObjects(worldObjects)
    if not vehicle then return end

    -- Show owners as a non-interactive info line (only when actually claimed).
    local owners = PZRC_VehicleClaim.getOwners(vehicle)
    local names  = PZRC_VehicleClaim.getOwnerNames(vehicle)
    if owners and #owners > 0 then
        local label = "Owners: " .. ((names and #names > 0) and table.concat(names, ", ") or "?")
        local info = context:addOption(label, nil, nil)
        info.notAvailable = true  -- gray it out, info-only
    end

    -- Blanket-disable every option for non-accessible vehicles.
    if PZRC_VehicleClaim.isAccessible(vehicle, player) then return end

    local options = context:getOptions()
    if not options then return end

    local denyName = "Owned by another player"
    local denyDesc
    if names and #names > 0 then
        denyDesc = "Belongs to: " .. table.concat(names, ", ")
    else
        denyDesc = "This vehicle is claimed inside the safe zone."
    end

    for i = 0, options:size() - 1 do
        local option = options:get(i)
        if option then
            option.notAvailable = true
            if not option.toolTip then
                option.toolTip = ISWorldObjectContextMenu.addToolTip()
            end
            option.toolTip:setName(denyName)
            option.toolTip.description = denyDesc
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
