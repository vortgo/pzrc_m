if not isServer() then return end

local function log(msg)
    print("[PZRC_InfGen] " .. tostring(msg))
end

-- ----- Authorized registry (game-time ModData) -----------------------------

local authorized = {} -- "x,y,z" -> true

local function genKey(x, y, z)
    return math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z)
end

local function loadAuthorized()
    local modData = getGameTime():getModData()
    local saved = modData["PZRC_InfiniteGens"]
    if saved and type(saved) == "table" then
        authorized = saved
        local count = 0
        for _ in pairs(authorized) do count = count + 1 end
        log("Loaded " .. count .. " authorized generators")
    else
        authorized = {}
    end
end

local function saveAuthorized()
    getGameTime():getModData()["PZRC_InfiniteGens"] = authorized
end

-- ----- Helpers -------------------------------------------------------------

local function findGeneratorAt(x, y, z)
    local square = getSquare(x, y, z)
    if not square then return nil end
    for i = 0, square:getObjects():size() - 1 do
        local obj = square:getObjects():get(i)
        if obj and obj:getObjectName() == "IsoGenerator" then
            return obj
        end
    end
    return nil
end

-- ----- Command handler -----------------------------------------------------

local function onClientCommand(module, command, player, args)
    if module ~= "PZRC_InfGen" then return end

    if not PZRC_Utils.isAdminAccess(player) then
        log("WARN: non-admin " .. player:getUsername() .. " attempted generator command")
        return
    end

    local x = tonumber(args.x)
    local y = tonumber(args.y)
    local z = tonumber(args.z)
    if not x or not y or not z then return end

    local gen = findGeneratorAt(x, y, z)
    if not gen then
        log("No generator found at " .. x .. "," .. y .. "," .. z)
        return
    end

    local username = player:getUsername()
    local data = gen:getModData()
    if not data then return end
    local key = genKey(x, y, z)

    if command == "makeInfinite" then
        data['_isFuelInfinite'] = true
        gen:setFuel(10)
        gen:setCondition(100)
        gen:transmitModData()
        gen:transmitCompleteItemToClients()
        authorized[key] = true
        saveAuthorized()
        log(username .. " set infinite generator at " .. key)

    elseif command == "makeNormal" then
        data['_isFuelInfinite'] = nil
        gen:transmitModData()
        gen:transmitCompleteItemToClients()
        authorized[key] = nil
        saveAuthorized()
        log(username .. " set normal generator at " .. key)
    end
end

-- ----- Periodic maintenance: reset unauthorized infinite generators ---------

local function validateIntervalMs()
    return PZRC_Config.sbox("InfiniteGenValidateIntervalSeconds", 60) * 1000
end
local lastValidateTime = 0

local function maintainGenerators()
    local now = getTimestampMs()
    if now - lastValidateTime < validateIntervalMs() then return end
    lastValidateTime = now

    local cell = getCell()
    if not cell then return end

    for key, _ in pairs(authorized) do
        local sx, sy, sz = key:match("([^,]+),([^,]+),([^,]+)")
        local x, y, z = tonumber(sx), tonumber(sy), tonumber(sz)
        if x and y and z then
            local gen = findGeneratorAt(x, y, z)
            if gen then
                local data = gen:getModData()
                if data then
                    if not data['_isFuelInfinite'] then
                        data['_isFuelInfinite'] = true
                        gen:transmitModData()
                    end
                    if gen:getFuel() < 10 then
                        gen:setFuel(10)
                    end
                    gen:setCondition(100)
                    if not gen:isActivated() then
                        gen:setActivated(true)
                    end
                end
            end
        end
    end
end

local function onLoadGridsquare(square)
    if not square then return end
    for i = 0, square:getObjects():size() - 1 do
        local obj = square:getObjects():get(i)
        if obj and obj:getObjectName() == "IsoGenerator" then
            local data = obj:getModData()
            if data and data['_isFuelInfinite'] then
                local sq = obj:getSquare()
                local key = genKey(sq:getX(), sq:getY(), sq:getZ())
                if not authorized[key] then
                    data['_isFuelInfinite'] = nil
                    obj:transmitModData()
                    log("Reset unauthorized infinite generator at " .. key)
                end
            end
        end
    end
end

local function onServerStarted()
    loadAuthorized()
    Events.OnClientCommand.Add(onClientCommand)
    Events.LoadGridsquare.Add(onLoadGridsquare)
    log("InfiniteGen server initialized")
end

Events.OnServerStarted.Add(onServerStarted)
Events.OnTickEvenPaused.Add(maintainGenerators)
