require "PZRC_Config"

-- =========================================================================
-- VehicleClaim — shared helpers.
--
-- Model: when a vehicle crosses INTO the safe zone (radius
-- PZRC_Config.VEHICLE_CLAIM_RADIUS around BASE_X/BASE_Y), the server records
-- every current occupant's SteamID into vehicle:getModData().PZRC_Owners.
-- Inside the SZ only those SteamIDs (plus admins) can interact with the
-- vehicle. Outside the SZ everyone has vanilla access.
--
-- "Reset on each entry": the owners list is REPLACED at every OUT→IN
-- transition, not appended. Unclaimed (empty list) vehicles in SZ are free.
-- =========================================================================

PZRC_VehicleClaim = PZRC_VehicleClaim or {}

PZRC_VehicleClaim.OWNERS_KEY      = "PZRC_Owners"        -- array of SteamIDs
PZRC_VehicleClaim.OWNER_NAMES_KEY = "PZRC_OwnerNames"    -- parallel array of usernames (display only)
PZRC_VehicleClaim.WAS_IN_SZ_KEY   = "PZRC_WasInSZ"       -- bool — last observed SZ state

--- Squared distance from (x, y) to SZ center vs radius² — cheaper than sqrt.
function PZRC_VehicleClaim.isInSZ(x, y)
    local cx = PZRC_Config.BASE_X or 9492
    local cy = PZRC_Config.BASE_Y or 11190
    local r  = PZRC_Config.VEHICLE_CLAIM_RADIUS or 90
    local dx = x - cx
    local dy = y - cy
    return (dx * dx + dy * dy) <= (r * r)
end

function PZRC_VehicleClaim.isVehicleInSZ(vehicle)
    if not vehicle then return false end
    return PZRC_VehicleClaim.isInSZ(vehicle:getX(), vehicle:getY())
end

--- SteamID for ownership keying. Falls back to username for local/sp.
function PZRC_VehicleClaim.getPlayerSteamID(player)
    if not player then return nil end
    if player.getSteamID then
        local sid = player:getSteamID()
        if sid and sid ~= "" and tostring(sid) ~= "0" then
            return tostring(sid)
        end
    end
    if player.getUsername then
        return player:getUsername()
    end
    return nil
end

function PZRC_VehicleClaim.isAdminLike(player)
    if not player or not player.getAccessLevel then return false end
    local lvl = player:getAccessLevel()
    return lvl == "admin" or lvl == "moderator"
end

function PZRC_VehicleClaim.getOwners(vehicle)
    if not vehicle or not vehicle.getModData then return nil end
    local md = vehicle:getModData()
    return md and md[PZRC_VehicleClaim.OWNERS_KEY]
end

function PZRC_VehicleClaim.getOwnerNames(vehicle)
    if not vehicle or not vehicle.getModData then return nil end
    local md = vehicle:getModData()
    return md and md[PZRC_VehicleClaim.OWNER_NAMES_KEY]
end

function PZRC_VehicleClaim.isOwner(vehicle, steamID)
    if not steamID then return false end
    local owners = PZRC_VehicleClaim.getOwners(vehicle)
    if not owners then return false end
    for _, id in ipairs(owners) do
        if id == steamID then return true end
    end
    return false
end

--- Outside SZ → free. Inside SZ + admin → free. Inside SZ + empty owners → free.
--- Inside SZ + claimed → owner-only.
function PZRC_VehicleClaim.isAccessible(vehicle, player)
    if not vehicle or not player then return true end
    if PZRC_VehicleClaim.isAdminLike(player) then return true end
    if not PZRC_VehicleClaim.isVehicleInSZ(vehicle) then return true end
    local owners = PZRC_VehicleClaim.getOwners(vehicle)
    if not owners or #owners == 0 then return true end
    return PZRC_VehicleClaim.isOwner(vehicle, PZRC_VehicleClaim.getPlayerSteamID(player))
end

return PZRC_VehicleClaim
