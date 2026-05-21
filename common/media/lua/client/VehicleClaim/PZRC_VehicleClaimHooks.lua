if isServer() then return end

require "PZRC_VehicleClaim"

-- =========================================================================
-- VehicleClaim client hooks — block actions on owned vehicles inside the SZ
-- for players who are not in the owners list (and aren't admins).
--
-- All hooks delegate to PZRC_VehicleClaim.isAccessible(vehicle, player).
-- Outside SZ → vanilla behaviour. Empty owners list → vanilla behaviour.
-- =========================================================================

local DENY_R, DENY_G, DENY_B = 1.0, 0.3, 0.3

local function denyMessage(character, vehicle)
    if not character or not character.addLineChatElement then return end
    local ownerNames = PZRC_VehicleClaim.getOwnerNames(vehicle)
    local who = (ownerNames and #ownerNames > 0) and table.concat(ownerNames, ", ") or "another player"
    character:addLineChatElement(
        "This vehicle belongs to " .. who .. ".",
        DENY_R, DENY_G, DENY_B
    )
end

local function block(vehicle, character)
    if PZRC_VehicleClaim.isAccessible(vehicle, character) then return false end
    denyMessage(character, vehicle)
    return true
end

-- ----- ISVehicleMenu hooks (radial / context-menu callbacks) ------------
-- Each wrapper short-circuits to _orig immediately when the feature flag
-- is off, so a disabled mod behaves like an absent one even if the wrapper
-- itself has bugs.

local function hookISVehicleMenuFunc(fname, vehicleArg)
    if not ISVehicleMenu or not ISVehicleMenu[fname] then return end
    local _orig = ISVehicleMenu[fname]
    ISVehicleMenu[fname] = function(playerObj, ...)
        if not PZRC_VehicleClaim.isEnabled() then return _orig(playerObj, ...) end
        local args = { ... }
        local veh = args[vehicleArg]
        if veh and block(veh, playerObj) then return end
        return _orig(playerObj, ...)
    end
end

-- onEnter(player, vehicle, seat) — second arg is the vehicle
hookISVehicleMenuFunc("onEnter",         1)
hookISVehicleMenuFunc("onEnter2",        1)
hookISVehicleMenuFunc("onHotwire",       1)
hookISVehicleMenuFunc("onSmashWindow",   1)
hookISVehicleMenuFunc("onSiphonGas",     1)
hookISVehicleMenuFunc("onMechanic",      1)
hookISVehicleMenuFunc("onSleep",         1)
hookISVehicleMenuFunc("onLockDoor",      1)
hookISVehicleMenuFunc("onUnlockDoor",    1)
hookISVehicleMenuFunc("onAttachTrailer", 1)

-- ----- ISVehicleMechanics — V-key panel ---------------------------------

if ISVehicleMechanics and ISVehicleMechanics.new then
    local _origNew = ISVehicleMechanics.new
    ISVehicleMechanics.new = function(self, x, y, width, height, character, vehicle)
        if not PZRC_VehicleClaim.isEnabled() then
            return _origNew(self, x, y, width, height, character, vehicle)
        end
        if vehicle and character and not PZRC_VehicleClaim.isAccessible(vehicle, character) then
            denyMessage(character, vehicle)
            return nil
        end
        return _origNew(self, x, y, width, height, character, vehicle)
    end
end

-- ----- TimedAction isValid wrappers -------------------------------------

local function hookActionByVehicleField(actionClass)
    if not actionClass or not actionClass.isValid then return end
    local _orig = actionClass.isValid
    actionClass.isValid = function(self)
        if not PZRC_VehicleClaim.isEnabled() then return _orig(self) end
        local veh = self.vehicle
        if not veh and self.part and self.part.getVehicle then
            veh = self.part:getVehicle()
        end
        if veh and self.character and not PZRC_VehicleClaim.isAccessible(veh, self.character) then
            denyMessage(self.character, veh)
            return false
        end
        return _orig(self)
    end
end

hookActionByVehicleField(ISInstallVehiclePart)
hookActionByVehicleField(ISUninstallVehiclePart)
hookActionByVehicleField(ISRepairVehiclePartAction)
hookActionByVehicleField(ISTakeGasFromVehicle)
hookActionByVehicleField(ISAddGasFromPump)

-- ----- Inventory transfer (trunk / glove box) ---------------------------
-- Vehicles can appear as srcContainer or destContainer. ItemContainer has
-- :getVehicle() when it's a vehicle part container.
-- NB: PZRC_LibraryMenu.lua already wraps ISInventoryTransferAction.isValid
-- for library books — composes fine, our wrapper runs first and only short-
-- circuits on vehicle containers; otherwise falls through to the prior wrap.

if ISInventoryTransferAction and ISInventoryTransferAction.isValid then
    local _orig = ISInventoryTransferAction.isValid

    local function containerVehicle(container)
        if not container or not container.getVehicle then return nil end
        local ok, veh = pcall(container.getVehicle, container)
        if ok then return veh end
        return nil
    end

    function ISInventoryTransferAction:isValid()
        if not PZRC_VehicleClaim.isEnabled() then return _orig(self) end
        local who = self.character
        if who then
            local srcVeh = containerVehicle(self.srcContainer)
            if srcVeh and not PZRC_VehicleClaim.isAccessible(srcVeh, who) then
                denyMessage(who, srcVeh)
                return false
            end
            local dstVeh = containerVehicle(self.destContainer)
            if dstVeh and not PZRC_VehicleClaim.isAccessible(dstVeh, who) then
                denyMessage(who, dstVeh)
                return false
            end
        end
        return _orig(self)
    end
end

-- ----- OnContainerUpdate — close UI for already-open vehicle containers -

local function onContainerUpdate(container)
    if not PZRC_VehicleClaim.isEnabled() then return end
    if not container or not container.getVehicle then return end
    local ok, veh = pcall(container.getVehicle, container)
    if not ok or not veh then return end
    local player = getPlayer()
    if not player then return end
    if PZRC_VehicleClaim.isAccessible(veh, player) then return end
    pcall(function()
        if ISInventoryPage and ISInventoryPage.closeContainerUI then
            ISInventoryPage.closeContainerUI(container)
        end
    end)
end
Events.OnContainerUpdate.Add(function(container) pcall(onContainerUpdate, container) end)

-- Init-log deferred to OnGameStart — SandboxVars are populated by then,
-- whereas at module-require time on client they may still be empty.
Events.OnGameStart.Add(function()
    if PZRC_VehicleClaim.isEnabled() then
        print("[PZRC_VehicleClaim] Client hooks installed")
    end
end)
