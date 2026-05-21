if not isServer() then return end

local function fuelMax()
    return PZRC_Config.sbox("FuelPumpMaxCapacity", 14000)
end

local function log(msg)
    print("[PZRC_FuelPump] " .. tostring(msg))
end

local function findPumpAt(x, y, z)
    local square = getSquare(x, y, z)
    if not square then return nil end
    for i = 0, square:getObjects():size() - 1 do
        local obj = square:getObjects():get(i)
        if obj and obj.getPipedFuelAmount and obj:getPipedFuelAmount() >= 0 then
            return obj
        end
    end
    return nil
end

local function onClientCommand(module, command, player, args)
    if module ~= "PZRC_Fuel" then return end

    if not PZRC_Utils.isAdminAccess(player) then
        log("WARN: non-admin " .. player:getUsername() .. " attempted fuel command")
        return
    end

    local x = tonumber(args.x)
    local y = tonumber(args.y)
    local z = tonumber(args.z)
    if not x or not y or not z then return end

    local pump = findPumpAt(x, y, z)
    if not pump then
        log("No fuel pump found at " .. x .. "," .. y .. "," .. z)
        return
    end

    local username = player:getUsername()

    if command == "refill" then
        local before = pump:getPipedFuelAmount()
        local target = fuelMax()
        pump:setPipedFuelAmount(target)
        log(username .. " refilled pump at " .. x .. "," .. y .. " (" .. before .. " -> " .. target .. ")")

    elseif command == "drain" then
        local before = pump:getPipedFuelAmount()
        pump:setPipedFuelAmount(0)
        log(username .. " drained pump at " .. x .. "," .. y .. " (" .. before .. " -> 0)")
    end
end

local function onServerStarted()
    Events.OnClientCommand.Add(onClientCommand)
    log("FuelPump server initialized")
end

Events.OnServerStarted.Add(onServerStarted)
