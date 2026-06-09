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
--
-- Installed on OnGameStart (not at file load) to guarantee the wrap runs
-- after every other mod has had its chance to define/replace createMenu.

local function installCreateMenuWrap()
    if not ISWorldObjectContextMenu or not ISWorldObjectContextMenu.createMenu then
        print("[PZRC_VehicleClaim] WARN: ISWorldObjectContextMenu.createMenu not present, "
            .. "right-click filter NOT installed")
        return
    end
    if ISWorldObjectContextMenu._PZRC_VehicleClaim_wrapped then
        return  -- idempotent
    end
    ISWorldObjectContextMenu._PZRC_VehicleClaim_wrapped = true

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
        local hidden = 0
        for i = 1, #worldobjects do
            local obj = worldobjects[i]
            local hide = false
            if obj and instanceof(obj, "BaseVehicle")
                and not PZRC_VehicleClaim.isAccessible(obj, plObj)
            then
                hide = true
            end
            if hide then
                hidden = hidden + 1
            else
                table.insert(filtered, obj)
            end
        end
        if hidden > 0 then
            print("[PZRC_VehicleClaim] filtered " .. hidden ..
                  " inaccessible vehicle(s) from right-click menu")
            return _origCreateMenu(player, filtered, x, y, test)
        end
        return _origCreateMenu(player, worldobjects, x, y, test)
    end

    print("[PZRC_VehicleClaim] right-click filter installed on ISWorldObjectContextMenu.createMenu")
end

Events.OnGameStart.Add(installCreateMenuWrap)

-- ----- Vehicle-menu second-line defence ---------------------------------
-- ISVehicleMenu.OnFillWorldObjectContextMenu finds the vehicle by direct
-- IsoObjectPicker.Instance:PickVehicle(x, y) call — that path NEVER touches
-- the worldobjects list, so the createMenu filter above doesn't catch it.
-- Wrapping ISVehicleMenu.FillMenuOutsideVehicle is the chokepoint: every
-- vehicle-related option (vanilla + every mod that hooked it, including
-- VRO Salvage / "Утилизировать транспорт" / 10YrsVehicles add-ons) is added
-- inside this function. Returning early prevents ALL of them.

local function installFillMenuOutsideVehicleWrap()
    if not ISVehicleMenu or not ISVehicleMenu.FillMenuOutsideVehicle then
        print("[PZRC_VehicleClaim] WARN: ISVehicleMenu.FillMenuOutsideVehicle not present")
        return
    end
    if ISVehicleMenu._PZRC_VehicleClaim_fillMenu_wrapped then return end
    ISVehicleMenu._PZRC_VehicleClaim_fillMenu_wrapped = true

    local _orig = ISVehicleMenu.FillMenuOutsideVehicle
    ISVehicleMenu.FillMenuOutsideVehicle = function(player, context, vehicle, test)
        if PZRC_VehicleClaim.isEnabled() and vehicle then
            local plObj = getSpecificPlayer(player)
            if plObj and not PZRC_VehicleClaim.isAccessible(vehicle, plObj) then
                -- Don't call original — no vehicle options at all.
                return
            end
        end
        return _orig(player, context, vehicle, test)
    end

    print("[PZRC_VehicleClaim] vehicle-menu filter installed on ISVehicleMenu.FillMenuOutsideVehicle")
end

Events.OnGameStart.Add(installFillMenuOutsideVehicleWrap)

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
        -- Append remaining time for temporary claims; legacy claims (no expiry)
        -- have no countdown and read as permanent.
        local expiry = PZRC_VehicleClaim.getClaimExpiry(vehicle)
        if expiry then
            local mins = math.ceil((expiry - os.time()) / 60)
            if mins > 0 then
                label = label .. " (" .. tostring(mins) .. " min left)"
            end
        end
        local info = context:addOption(label, nil, nil)
        info.notAvailable = true  -- gray it out, info-only
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
