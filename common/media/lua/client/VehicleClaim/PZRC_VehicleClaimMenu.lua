if isServer() then return end

require "PZRC_VehicleClaim"

-- =========================================================================
-- VehicleClaim context menu.
--
-- For owners (or accessible vehicles): adds a non-interactive "Owners: X, Y"
-- info line as the menu's first entry.
--
-- For non-owners: the vehicle is FILTERED OUT of worldobjects before PZ
-- builds the menu, so no vehicle-related options ever get added by anyone
-- (vanilla createMenuEntries, this mod, or third-party). If the vehicle
-- was the only thing under the cursor, PZ hides the empty menu via its
-- existing `context.numOptions == 1 → setVisible(false)` path.
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

-- ----- Filter inaccessible vehicles out of worldobjects -----------------
-- Wraps ISWorldObjectContextMenu.createMenu to rebuild its worldobjects
-- list, dropping any vehicle the right-clicking player can't access. Runs
-- BEFORE ISWorldObjectContextMenuLogic.fetch / createMenuEntries iterate
-- the list (line ~182 in vanilla createMenu), so vehicle options never
-- get added to the context in the first place.

if ISWorldObjectContextMenu and ISWorldObjectContextMenu.createMenu then
    local _origCreateMenu = ISWorldObjectContextMenu.createMenu
    ISWorldObjectContextMenu.createMenu = function(player, worldobjects, x, y, test)
        if not PZRC_VehicleClaim.isEnabled() or not worldobjects then
            return _origCreateMenu(player, worldobjects, x, y, test)
        end
        local plObj = getSpecificPlayer(player)
        if not plObj then
            return _origCreateMenu(player, worldobjects, x, y, test)
        end

        local filtered = {}
        local hadHidden = false
        for i = 1, #worldobjects do
            local obj = worldobjects[i]
            local hide = false
            if obj and instanceof(obj, "BaseVehicle")
                and not PZRC_VehicleClaim.isAccessible(obj, plObj)
            then
                hide = true
            end
            if hide then
                hadHidden = true
            else
                table.insert(filtered, obj)
            end
        end
        if hadHidden then
            return _origCreateMenu(player, filtered, x, y, test)
        end
        return _origCreateMenu(player, worldobjects, x, y, test)
    end
end

-- ----- "Owners: X, Y" info line for accessible vehicles -----------------
-- Runs only when the vehicle survived the filter above (i.e. the player has
-- access to it). Useful for the owner / allowed riders to see who else is
-- on the list. Non-owners never reach this path.

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test then return end
    if not PZRC_VehicleClaim.isEnabled() then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local vehicle = findVehicleInWorldObjects(worldObjects)
    if not vehicle then return end

    local owners = PZRC_VehicleClaim.getOwners(vehicle)
    local names  = PZRC_VehicleClaim.getOwnerNames(vehicle)
    if owners and #owners > 0 then
        local label = "Owners: " .. ((names and #names > 0) and table.concat(names, ", ") or "?")
        local info = context:addOption(label, nil, nil)
        info.notAvailable = true  -- gray it out, info-only
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
