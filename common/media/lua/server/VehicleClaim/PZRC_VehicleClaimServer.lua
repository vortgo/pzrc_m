if not isServer() then return end

require "PZRC_VehicleClaim"

-- =========================================================================
-- VehicleClaim server — detects when a vehicle crosses INTO the safe zone
-- and records all current occupants as owners. Tick-throttled (~1.5s) over
-- vehicles that currently have at least one occupant — empty parked cars
-- never claim anyone.
-- =========================================================================

local TICK_THROTTLE_MS = 1500

local function log(msg)
    print("[PZRC_VehicleClaim] " .. tostring(msg))
end

--- Replace owners list with current occupants of the vehicle.
local function claimVehicle(vehicle)
    local owners = {}
    local names  = {}
    local seen   = {}
    local max    = vehicle:getMaxPassengers() or 0
    for seat = 0, max - 1 do
        local c = vehicle:getCharacter(seat)
        if c then
            local sid = PZRC_VehicleClaim.getPlayerSteamID(c)
            if sid and not seen[sid] then
                seen[sid] = true
                table.insert(owners, sid)
                local name = (c.getUsername and c:getUsername()) or sid
                table.insert(names, name)
            end
        end
    end

    local md = vehicle:getModData()
    md[PZRC_VehicleClaim.OWNERS_KEY]      = owners
    md[PZRC_VehicleClaim.OWNER_NAMES_KEY] = names
    vehicle:transmitModData()
    -- Force the vehicle table to flush to disk now so ownership survives
    -- server restart. Without this, transmitModData syncs to clients but
    -- the vehicle's persistent row only saves on next periodic write —
    -- if the server crashes before that, owners are lost.
    if vehicle.saveToVehicleTable then
        pcall(vehicle.saveToVehicleTable, vehicle)
    end

    if #owners > 0 then
        log("Claimed vehicle for " .. #owners .. " player(s): " .. table.concat(names, ", "))
    else
        log("Vehicle entered SZ empty — no claim")
    end
end

--- Check one vehicle's SZ state. Stores PZRC_WasInSZ on the vehicle so the
--- next observation sees the previous state. On OUT→IN transition, claim.
local function checkVehicle(vehicle)
    if not vehicle or not vehicle.getModData then return end
    local md = vehicle:getModData()

    local isIn  = PZRC_VehicleClaim.isVehicleInSZ(vehicle)
    local wasIn = md[PZRC_VehicleClaim.WAS_IN_SZ_KEY]

    -- First observation — initialize without firing a claim. Otherwise a
    -- vehicle parked in SZ before mod loaded would re-claim on first tick.
    if wasIn == nil then
        md[PZRC_VehicleClaim.WAS_IN_SZ_KEY] = isIn
        return
    end

    if isIn and not wasIn then
        claimVehicle(vehicle)
    end

    if isIn ~= wasIn then
        md[PZRC_VehicleClaim.WAS_IN_SZ_KEY] = isIn
        vehicle:transmitModData()
    end
end

-- ----- Tick -------------------------------------------------------------

local lastTickMs = 0

local function onTick()
    if not PZRC_VehicleClaim.isEnabled() then return end

    local now = getTimestampMs()
    if now - lastTickMs < TICK_THROTTLE_MS then return end
    lastTickMs = now

    local players = getOnlinePlayers()
    if not players then return end

    local processed = {}
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and not p:isDead() then
            local veh = p:getVehicle()
            if veh and not processed[veh] then
                processed[veh] = true
                checkVehicle(veh)
            end
        end
    end
end

Events.OnTickEvenPaused.Add(onTick)

-- Init-log is deferred to OnServerStarted because SandboxVars aren't fully
-- populated at module-require time on dedicated server. By the time
-- OnServerStarted fires, SandboxVars.pzrc_m.EnableVehicleClaim reflects
-- the true configured value (file or default).
Events.OnServerStarted.Add(function()
    if PZRC_VehicleClaim.isEnabled() then
        log("VehicleClaim server initialized (radius=" ..
            tostring(PZRC_Config.VEHICLE_CLAIM_RADIUS) ..
            " around " .. tostring(PZRC_Config.BASE_X) .. "," ..
            tostring(PZRC_Config.BASE_Y) .. ")")
    end
end)
