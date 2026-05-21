require "PZRC_Utils"

local function isFuelPump(obj)
    return obj and obj.getPipedFuelAmount and obj:getPipedFuelAmount() >= 0
end

local function findFuelPump(worldobjects)
    for _, obj in ipairs(worldobjects) do
        if isFuelPump(obj) then
            return obj
        end
        local square = obj:getSquare()
        if square then
            for i = 0, square:getObjects():size() - 1 do
                local sqObj = square:getObjects():get(i)
                if isFuelPump(sqObj) then
                    return sqObj
                end
            end
        end
    end
    return nil
end

local function onRefillPump(playerNum, pump)
    local playerObj = getSpecificPlayer(playerNum)
    sendClientCommand(playerObj, "PZRC_Fuel", "refill", {
        x = pump:getSquare():getX(),
        y = pump:getSquare():getY(),
        z = pump:getSquare():getZ(),
    })
end

local function onDrainPump(playerNum, pump)
    local playerObj = getSpecificPlayer(playerNum)
    sendClientCommand(playerObj, "PZRC_Fuel", "drain", {
        x = pump:getSquare():getX(),
        y = pump:getSquare():getY(),
        z = pump:getSquare():getZ(),
    })
end

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    if test then return end
    if not PZRC_Utils.IsAdminPlayer() then return end

    local pump = findFuelPump(worldobjects)
    if not pump then return end

    local current = pump:getPipedFuelAmount()
    local cap = PZRC_Config.sbox("FuelPumpMaxCapacity", 14000)

    context:addOption("Fuel: Refill (" .. current .. " -> " .. cap .. ")",
        player, onRefillPump, pump)
    context:addOption("Fuel: Drain (" .. current .. " -> 0)",
        player, onDrainPump, pump)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
