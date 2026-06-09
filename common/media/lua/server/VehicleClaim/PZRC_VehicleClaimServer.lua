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
    -- Temporary claim: stamp an absolute expiry = now + configured minutes.
    -- Empty entries clear the expiry so the slot is truly free.
    if #owners > 0 then
        local durationMin = PZRC_Config.VEHICLE_CLAIM_DURATION_MIN or 240
        md[PZRC_VehicleClaim.EXPIRY_KEY] = os.time() + durationMin * 60
    else
        md[PZRC_VehicleClaim.EXPIRY_KEY] = nil
    end
    vehicle:transmitModData()
    -- Force the vehicle table to flush to disk now so ownership survives
    -- server restart. Without this, transmitModData syncs to clients but
    -- the vehicle's persistent row only saves on next periodic write —
    -- if the server crashes before that, owners are lost.
    if vehicle.saveToVehicleTable then
        pcall(vehicle.saveToVehicleTable, vehicle)
    end

    if #owners > 0 then
        log("Claimed vehicle for " .. #owners .. " player(s): " .. table.concat(names, ", ")
            .. " (expires in " .. tostring(PZRC_Config.VEHICLE_CLAIM_DURATION_MIN or 240) .. " min)")
    else
        log("Vehicle entered SZ empty — no claim")
    end
end

--- Drop an expired claim: clear owners/names/expiry so the vehicle becomes
--- free for everyone. Legacy claims (no expiry stored) never reach here.
local function clearExpiredClaim(vehicle)
    local md = vehicle:getModData()
    md[PZRC_VehicleClaim.OWNERS_KEY]      = {}
    md[PZRC_VehicleClaim.OWNER_NAMES_KEY] = {}
    md[PZRC_VehicleClaim.EXPIRY_KEY]      = nil
    vehicle:transmitModData()
    if vehicle.saveToVehicleTable then
        pcall(vehicle.saveToVehicleTable, vehicle)
    end
    log("Claim expired — vehicle released")
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

-- ----- Damage protection (only for owned vehicles INSIDE the safe zone) -
-- Approach borrowed from VehicleClaimWG: every tick snapshot each protected
-- vehicle's per-part conditions in an in-memory cache. If condition drops
-- AND an unauthorized player is nearby (the "griefer"), revert. If only
-- zombies are around (no live players nearby), accept the new condition
-- (so zombie attacks on a parked car still chip away). If an authorized
-- driver is at the wheel, accept and refresh the snapshot (normal usage,
-- crashes etc.).
--
-- Cache is in-memory only (not modData) — rebuilt on server restart from
-- whatever post-restart state the vehicle is in, which is fine: the worst
-- case is a brief window where damage from the very first observation is
-- accepted as the new baseline.

local DMG_THREAT_RADIUS    = 5     -- tiles (Manhattan distance)
local DMG_REPAIR_DELAY_MS  = 2000  -- batch hits within this window before revert

local stateCache = {}              -- [vehicle:getId()] = { parts = { [partId]=cond,... }, repairDue = ms }

local function snapshotVehicle(vehicle)
    local vId = vehicle:getId()
    local parts = {}
    local count = vehicle:getPartCount() or 0
    for i = 0, count - 1 do
        local part = vehicle:getPartByIndex(i)
        if part then
            parts[part:getId()] = part:getCondition()
        end
    end
    stateCache[vId] = stateCache[vId] or {}
    stateCache[vId].parts = parts
    stateCache[vId].repairDue = nil
end

local function revertVehicleDamage(vehicle, cached)
    for partId, cachedCond in pairs(cached.parts) do
        local part = vehicle:getPartById(partId)
        if part then
            local curCond = part:getCondition()
            if curCond < cachedCond then
                -- Restore removed/destroyed part (uninstalled engine, etc).
                local invItem = part.getInventoryItem and part:getInventoryItem()
                if not invItem and cachedCond > 0 and part.getItemType then
                    local types = part:getItemType()
                    if types and not types:isEmpty() then
                        local typeName = types:get(0)
                        local newItem = instanceItem(typeName)
                        if newItem then
                            newItem:setCondition(cachedCond)
                            part:setInventoryItem(newItem)
                            if vehicle.transmitPartItem then
                                pcall(vehicle.transmitPartItem, vehicle, part)
                            end
                        end
                    end
                end
                part:setCondition(cachedCond)
                -- Un-smash window if we restored a windowed part.
                local window = part.getWindow and part:getWindow()
                if window and cachedCond > 0 and window.setSmashed then
                    window:setSmashed(false)
                    if vehicle.transmitPartWindow then
                        pcall(vehicle.transmitPartWindow, vehicle, part)
                    end
                end
                if vehicle.transmitPartCondition then
                    pcall(vehicle.transmitPartCondition, vehicle, part)
                end
            end
        end
    end
end

local function checkAndRestore(vehicle)
    local vId = vehicle:getId()
    local cached = stateCache[vId]
    if not cached or not cached.parts then
        snapshotVehicle(vehicle)
        return
    end

    local damaged = false
    for partId, cachedCond in pairs(cached.parts) do
        local part = vehicle:getPartById(partId)
        if part and part:getCondition() < cachedCond then
            damaged = true
            break
        end
    end

    if not damaged then
        cached.repairDue = nil
        return
    end

    -- Damage detected — batch repair so multi-hit bursts apply in one revert.
    local now = getTimestampMs()
    if not cached.repairDue then
        cached.repairDue = now + DMG_REPAIR_DELAY_MS
        return
    end
    if now < cached.repairDue then return end

    revertVehicleDamage(vehicle, cached)
    cached.repairDue = nil
end

local function damageProtectionPass(onlinePlayers)
    local cell = getCell()
    if not cell then return end
    local vehicles = cell:getVehicles()
    if not vehicles then return end

    local pCount = (onlinePlayers and onlinePlayers:size()) or 0

    local it = vehicles:iterator()
    while it:hasNext() do
        local v = it:next()
        if v and v.getModData then
            -- Release expired claims (owners present but past their expiry).
            -- Legacy claims have no expiry → isClaimExpired is false → kept.
            local owners = PZRC_VehicleClaim.getOwners(v)
            if owners and #owners > 0 and PZRC_VehicleClaim.isClaimExpired(v) then
                clearExpiredClaim(v)
            end

            local hasOwn  = PZRC_VehicleClaim.hasActiveClaim(v)
            local inSZ    = PZRC_VehicleClaim.isVehicleInSZ(v)

            if not (hasOwn and inSZ) then
                -- Not eligible — drop any stale cache entry.
                if stateCache[v:getId()] then stateCache[v:getId()] = nil end
            else
                -- Driver authorized?
                local driver = (v.getDriver and v:getDriver()) or
                               (v.getCharacter and v:getCharacter(0))
                local authDriver = driver and PZRC_VehicleClaim.isAccessible(v, driver)

                -- Threat detection: any unauthorized live player in DMG_THREAT_RADIUS.
                local threat = false
                if not authDriver and pCount > 0 then
                    local vX, vY = v:getX(), v:getY()
                    for i = 0, pCount - 1 do
                        local p = onlinePlayers:get(i)
                        if p and not p:isDead() and p.getX then
                            local d = math.abs(p:getX() - vX) + math.abs(p:getY() - vY)
                            if d < DMG_THREAT_RADIUS
                                and not PZRC_VehicleClaim.isAccessible(v, p)
                            then
                                threat = true
                                break
                            end
                        end
                    end
                end

                if authDriver then
                    -- Legitimate use — keep baseline fresh.
                    snapshotVehicle(v)
                elseif threat then
                    -- SHIELD UP — revert any drop versus cached state.
                    checkAndRestore(v)
                else
                    -- No threat, no driver — accept current as new baseline
                    -- (lets natural zombie damage through).
                    snapshotVehicle(v)
                end
            end
        end
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

    -- 1. SZ-entry detector (only vehicles with an occupant).
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

    -- 2. Damage protection (all owned vehicles in SZ, including empty parked).
    damageProtectionPass(players)
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
