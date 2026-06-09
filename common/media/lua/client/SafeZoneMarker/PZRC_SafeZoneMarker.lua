if isServer() then return end

-- =========================================================================
-- SafeZoneMarker — static base-zone marker on the player's world map.
-- Coordinates come from PZRC_Config.BASE_X/BASE_Y (sandbox-backed).
-- =========================================================================

local PZRC_SafeZoneMarker = {}
PZRC_SafeZoneMarker.zone   = nil
PZRC_SafeZoneMarker.RADIUS = 90

-- Cyan/teal so it doesn't blend with the green event markers.
PZRC_SafeZoneMarker.R = 0.2
PZRC_SafeZoneMarker.G = 0.75
PZRC_SafeZoneMarker.B = 1.0
PZRC_SafeZoneMarker.A = 0.45

local function log(msg)
    print("[PZRC_SafeZoneMarker] " .. tostring(msg))
end

local function getWorldMap()
    return _G.ISWorldMap_instance or (ISWorldMap and ISWorldMap.instance) or nil
end

local function getCoords()
    local x = (PZRC_Config and PZRC_Config.BASE_X) or 9492
    local y = (PZRC_Config and PZRC_Config.BASE_Y) or 11190
    return math.floor(x), math.floor(y)
end

function PZRC_SafeZoneMarker.render()
    -- Marker already in the map layer — PZ keeps it across openings, so don't
    -- add it again or it stacks.
    if PZRC_SafeZoneMarker.zone then return end

    local worldMap = getWorldMap()
    if not worldMap or not worldMap.isVisible or not worldMap:isVisible() then return end

    local mapAPI = worldMap.mapAPI
    if not mapAPI then return end

    if mapAPI.getBoolean and mapAPI.setBoolean then
        if not mapAPI:getBoolean("Symbols") then
            mapAPI:setBoolean("Symbols", true)
        end
    end

    local markersAPI = mapAPI.getMarkersAPI and mapAPI:getMarkersAPI() or nil
    if not markersAPI then return end

    local x, y = getCoords()
    local ok, zone = pcall(function()
        return markersAPI:addGridSquareMarker(
            x, y,
            PZRC_SafeZoneMarker.RADIUS,
            PZRC_SafeZoneMarker.R, PZRC_SafeZoneMarker.G, PZRC_SafeZoneMarker.B, PZRC_SafeZoneMarker.A
        )
    end)
    if ok and zone then
        PZRC_SafeZoneMarker.zone = zone
        log("SafeZone marker placed at " .. x .. "," .. y)
    end
end

-- Hook into ShowWorldMap so render fires each time the map opens.
local function patchWorldMap()
    if PZRC_SafeZoneMarker._patched then return end
    if not ISWorldMap or not ISWorldMap.ShowWorldMap then return end

    local orig = ISWorldMap.ShowWorldMap
    -- Forward args verbatim (...) — the map-item read path (ISReadWorldMap)
    -- calls ShowWorldMap with a different arg set than opening the map with M;
    -- a fixed signature would drop args and break vanilla initDataAndStyle.
    ISWorldMap.ShowWorldMap = function(...)
        orig(...)
        pcall(PZRC_SafeZoneMarker.render)
    end
    PZRC_SafeZoneMarker._patched = true
    log("ISWorldMap patched")
end

Events.OnGameStart.Add(patchWorldMap)
