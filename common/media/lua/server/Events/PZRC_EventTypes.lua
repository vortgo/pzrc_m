local function log(msg)
    print("[Airdrop] " .. tostring(msg))
end

local Airdrop = {}

local AIRDROP_SCRIPTS = {
    "PZRCVehicles.airdrop",
    "PZRCVehicles.FEMASupplyDrop",
    "PZRCVehicles.SurvivorSupplyDrop",
}

--- Спавн: ящик-аирдроп (vehicle) + лут + зомби
function Airdrop.spawn(x, y, z, eventId)
    local sq = PZRC_EventUtils.findSafeSquare(x, y, z, PZRC_EventConfig.SAFE_SQUARE_RADIUS)
    if not sq then
        return nil, "No safe square found"
    end

    local scriptName = AIRDROP_SCRIPTS[ZombRand(#AIRDROP_SCRIPTS) + 1]
    local vehicle = addVehicleDebug(scriptName, IsoDirections.N, nil, sq)
    if not vehicle then
        return nil, "Failed to spawn airdrop vehicle: " .. scriptName
    end

    vehicle:getModData().PZRC_EventId = eventId
    vehicle:repair()

    -- Лут в TruckBed
    local truckBed = vehicle:getPartById("TruckBed")
    local itemCount = 0
    if truckBed and truckBed:getItemContainer() then
        itemCount = PZRC_EventUtils.generateLoot(truckBed:getItemContainer(), "airdrop", eventId)
    end

    local cx, cy, cz = sq:getX(), sq:getY(), sq:getZ()

    -- Зомби вокруг
    PZRC_EventUtils.spawnZombies(cx, cy, cz, "airdrop")

    log("Spawned " .. scriptName .. " at " .. cx .. "," .. cy .. " loot=" .. itemCount)

    return {
        x = cx,
        y = cy,
        z = cz or 0,
        itemCount = itemCount,
    }
end

--- Cleanup: удаляем аирдроп-машину
function Airdrop.cleanup(spawnData, eventId)
    if not spawnData then return end
    PZRC_EventUtils.removeVehicleByEventId(
        spawnData.x, spawnData.y, spawnData.z, eventId, 5
    )
end

--- Описание
function Airdrop.getDescription(x, y, z)
    return "Airdrop spotted near " .. x .. ", " .. y
end

-- Ящик падает на открытой местности (поляна / поле), не в густом лесу и не
-- в городе — иначе игроки его не найдут или не дотащат.
Airdrop.spawnRequirements = { biome = "clearing", roadMaxDist = 100 }

-- ---------------------------------------------------------------------------
-- Регистрация
-- ---------------------------------------------------------------------------
PZRC_EventRegistry.register("airdrop", Airdrop)
local function log(msg)
    print("[BuildingStash] " .. tostring(msg))
end

local BuildingStash = {}

-- validate не нужен — spawn() сам проверяет наличие контейнера
-- двойной вызов findRandomContainerInBuilding был бы лишней нагрузкой

--- Спавн: найти контейнер → закинуть лут → пометить каждый предмет
function BuildingStash.spawn(x, y, z, eventId)
    local obj, container, sq = PZRC_EventUtils.findRandomContainerInBuilding(
        x, y, z, PZRC_EventConfig.BUILDING_SEARCH_RADIUS
    )
    if not container then
        return nil, "No building with containers found"
    end

    -- Генерируем лут, помечая каждый предмет eventId
    local count = PZRC_EventUtils.generateLoot(container, "buildingstash", eventId)
    if count == 0 then
        return nil, "Loot generation failed: 0 items rolled"
    end
    log("Added " .. count .. " items to container at " .. sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ())

    -- Обновляем визуал контейнера (пустой/полный спрайт)
    PZRC_EventUtils.syncContainerVisual(obj)

    -- Зомби вокруг
    PZRC_EventUtils.spawnZombies(sq:getX(), sq:getY(), sq:getZ(), "buildingstash")

    return {
        x = sq:getX(),
        y = sq:getY(),
        z = sq:getZ(),
        containerX = sq:getX(),
        containerY = sq:getY(),
        containerZ = sq:getZ(),
        itemCount = count,
    }
end

--- Cleanup (spawned, не посещён): удаляем предметы, но не сам контейнер (он часть здания)
function BuildingStash.cleanup(spawnData, eventId)
    if not spawnData then return end
    PZRC_EventUtils.cleanupByEventId(
        spawnData.containerX, spawnData.containerY, spawnData.containerZ,
        eventId,
        { radius = 0, removeItems = true, removeObjects = false }
    )
end

--- Описание для уведомлений
function BuildingStash.getDescription(x, y, z)
    return "Supply stash reported near " .. x .. ", " .. y
end

-- BuildingStash: выбираем случайное здание из grid:getBuildings() в диапазоне
-- 450-950 тайлов от игрока. pickFromBuildings — отдельный путь в pickSpawnLocation
BuildingStash.spawnRequirements = { pickFromBuildings = true }

-- ---------------------------------------------------------------------------
-- Регистрация
-- ---------------------------------------------------------------------------
PZRC_EventRegistry.register("buildingstash", BuildingStash)
local function log(msg)
    print("[ForestStash] " .. tostring(msg))
end

local ForestStash = {}

--- Спавн: найти свободную клетку → поставить ящик → закинуть лут
function ForestStash.spawn(x, y, z, eventId)
    local sq = PZRC_EventUtils.findSafeSquare(x, y, z, PZRC_EventConfig.SAFE_SQUARE_RADIUS)
    if not sq then
        return nil, "No safe square found"
    end

    -- Создаём деревянный ящик. Логируем количество objects на square ДО и ПОСЛЕ
    -- каждого шага, чтобы поймать возможный дубль от IsoObject.new / AddSpecialObject.
    local szBefore = sq:getObjects():size()
    local obj = IsoObject.new(getCell(), sq, PZRC_EventConfig.FOREST_CRATE_SPRITE)
    local szAfterNew = sq:getObjects():size()
    obj:getModData().PZRC_EventId = eventId
    obj:setName("ForestStash")
    sq:AddSpecialObject(obj)
    local szAfterAdd = sq:getObjects():size()
    obj:transmitCompleteItemToClients()
    local szAfterTx = sq:getObjects():size()
    log(string.format("DEBUG crate spawn: objs %d -> new=%d -> addSpecial=%d -> transmit=%d (eventId=%s)",
        szBefore, szAfterNew, szAfterAdd, szAfterTx, tostring(eventId)))

    -- Проверяем что контейнер появился
    local container = obj:getContainer()
    if not container then
        -- Спрайт не поддерживает контейнер — убираем объект
        sq:transmitRemoveItemFromSquare(obj)
        return nil, "Crate has no container (sprite issue)"
    end

    -- Генерируем лут (внутри generateLoot теперь pcall на каждый AddItem,
    -- но обернём ещё один pcall на сам вызов — на случай экзотической Kahlua-NPE
    -- более высокого уровня. Если упало совсем — снимаем orphan-crate.)
    local lootOk, count = pcall(PZRC_EventUtils.generateLoot, container, "foreststash", eventId)
    if not lootOk then
        log("generateLoot crashed for foreststash eventId=" .. tostring(eventId) .. ": " .. tostring(count))
        sq:transmitRemoveItemFromSquare(obj)
        return nil, "Loot generation crashed"
    end
    if count == 0 then
        sq:transmitRemoveItemFromSquare(obj)
        return nil, "Loot generation failed: 0 items rolled"
    end

    local cx, cy, cz = sq:getX(), sq:getY(), sq:getZ()
    log("Placed crate with " .. count .. " items at " .. cx .. "," .. cy .. "," .. cz)

    PZRC_EventUtils.syncContainerVisual(obj)

    -- Зомби вокруг
    PZRC_EventUtils.spawnZombies(cx, cy, cz, "foreststash")

    return {
        x = cx,
        y = cy,
        z = cz,
        itemCount = count,
    }
end

--- Cleanup: удаляем ящик целиком (он наш, не часть мира)
function ForestStash.cleanup(spawnData, eventId)
    if not spawnData then return end
    PZRC_EventUtils.cleanupByEventId(
        spawnData.x, spawnData.y, spawnData.z,
        eventId,
        { radius = 1, removeItems = true, removeObjects = true }
    )
end

--- Описание для уведомлений
function ForestStash.getDescription(x, y, z)
    return "Forest stash reported near " .. x .. ", " .. y
end

-- Нычка в глубоком лесу: биом=forest + нет города в радиусе 30 тайлов
ForestStash.spawnRequirements = {
    biome = "forest",
    roadMaxDist = 200,
    minDistFromCity = 30,
}

-- ---------------------------------------------------------------------------
-- Регистрация
-- ---------------------------------------------------------------------------
PZRC_EventRegistry.register("foreststash", ForestStash)
local function log(msg)
    print("[AbandonedVehicle] " .. tostring(msg))
end

local AbandonedVehicle = {}

--- Спавн: найти клетку → поставить машину → настроить состояние
function AbandonedVehicle.spawn(x, y, z, eventId)
    local sq = PZRC_EventUtils.findSafeSquare(x, y, z, PZRC_EventConfig.SAFE_SQUARE_RADIUS)
    if not sq then
        return nil, "No safe square found"
    end

    -- Reclaim any orphan event-vehicles still sitting in our blocking radius
    -- (previous event's cleanup couldn't reach them because the chunk was unloaded).
    PZRC_EventUtils.removeOrphanEventVehicles(sq:getX(), sq:getY(), sq:getZ(), 3)

    -- Проверяем нет ли машин рядом (предотвращает спавн друг на друге)
    if PZRC_EventUtils.hasVehicleNearby(sq:getX(), sq:getY(), sq:getZ(), 3) then
        return nil, "Vehicle already exists nearby at " .. sq:getX() .. "," .. sq:getY()
    end

    -- Случайный тип машины
    local types = PZRC_EventConfig.Vehicle.types
    local vehicleType = types[ZombRand(#types) + 1]

    -- Случайное направление
    local directions = { IsoDirections.N, IsoDirections.S, IsoDirections.E, IsoDirections.W }
    local dir = directions[ZombRand(#directions) + 1]

    local vehicle = addVehicleDebug(vehicleType, dir, nil, sq)
    if not vehicle then
        return nil, "Failed to spawn vehicle " .. vehicleType
    end

    vehicle:getModData().PZRC_EventId = eventId

    -- Настраиваем состояние: убитый двигатель, мало топлива
    local cond = PZRC_EventConfig.Vehicle.condition
    local engineCondition = ZombRand(cond.engineMin, cond.engineMax + 1)

    -- Двигатель
    local engine = vehicle:getPartById("Engine")
    if engine then
        engine:setCondition(engineCondition)
    end

    -- Топливо
    local gas = vehicle:getPartById("GasTank")
    if gas then
        local fuelAmount = cond.fuelMin + ZombRand(1000) / 1000 * (cond.fuelMax - cond.fuelMin)
        gas:setContainerContentAmount(fuelAmount)
    end

    -- Износ всех ключевых деталей до 10..50% (заброшенная машина
    -- не должна выглядеть как новая — побитая кузовщина, потрескавшиеся
    -- окна, изношенные колёса и лампы).
    local function damagePart(partId, minCond, maxCond)
        local p = vehicle:getPartById(partId)
        if p then p:setCondition(ZombRand(minCond, maxCond + 1)) end
    end

    -- Кузов
    for _, id in ipairs({
        "DoorFrontLeft", "DoorFrontRight", "DoorRearLeft", "DoorRearRight",
        "TrunkDoor", "Hood",
    }) do damagePart(id, 10, 50) end

    -- Окна
    for _, id in ipairs({
        "WindshieldFront", "WindshieldRear",
        "WindowFrontLeft", "WindowFrontRight", "WindowRearLeft", "WindowRearRight",
    }) do damagePart(id, 20, 50) end

    -- Свет / выхлоп
    for _, id in ipairs({ "HeadlightLeft", "HeadlightRight", "Muffler" }) do
        damagePart(id, 0, 40)
    end

    -- Колёса (изношенные, не сдутые до нуля)
    for _, id in ipairs({ "TireFrontLeft", "TireFrontRight", "TireRearLeft", "TireRearRight" }) do
        damagePart(id, 30, 50)
    end

    -- Шанс отсутствия одного колеса (по конфигу)
    if ZombRand(1000) < cond.missingTireChance * 1000 then
        local tires = {"TireFrontLeft", "TireFrontRight", "TireRearLeft", "TireRearRight"}
        local tireName = tires[ZombRand(#tires) + 1]
        local tire = vehicle:getPartById(tireName)
        if tire then
            tire:setCondition(0)
        end
    end

    -- Лут во все item-containers машины (бардачок, багажник, открытый кузов).
    -- Имена частей различаются по типу машины: CarNormal/OffRoad/Van/Police → "TruckBed",
    -- PickUpTruck → "TruckBedOpen". Перебор по getPartCount() + getItemContainer()
    -- автоматически ловит все варианты и игнорирует FluidContainer-части (бензобак,
    -- батарея, радио) у которых getItemContainer() возвращает nil.
    local lootContainers = 0
    for i = 0, vehicle:getPartCount() - 1 do
        local p = vehicle:getPartByIndex(i)
        local c = p and p:getItemContainer()
        if c then
            PZRC_EventUtils.generateLoot(c, "abandonedvehicle", eventId)
            lootContainers = lootContainers + 1
        end
    end
    if lootContainers == 0 then
        log("WARN: " .. vehicleType .. " has no item containers — loot skipped")
    end

    local cx, cy, cz = sq:getX(), sq:getY(), sq:getZ()
    log("Spawned " .. vehicleType .. " at " .. cx .. "," .. cy .. " engine=" .. engineCondition)

    -- Зомби вокруг
    PZRC_EventUtils.spawnZombies(cx, cy, cz, "abandonedvehicle")

    return {
        x = cx,
        y = cy,
        z = cz or 0,
    }
end

--- Cleanup: удаляем машину
function AbandonedVehicle.cleanup(spawnData, eventId)
    if not spawnData then return end
    PZRC_EventUtils.removeVehicleByEventId(
        spawnData.x, spawnData.y, spawnData.z, eventId, 5
    )
end

--- Описание
function AbandonedVehicle.getDescription(x, y, z)
    return "Abandoned vehicle spotted near " .. x .. ", " .. y
end

-- Машина на дороге: ищем Nav в радиусе 200 тайлов, точку переносим НА дорогу (snap)
-- Машина на настоящей дороге, не в лесу и не на лесной грунтовке.
-- snapForbidForest проверяет, что итоговая клетка после snapToRoad не лежит
-- внутри Forest-зоны (forest dirt paths PZ помечает как Nav, мы их отсекаем).
AbandonedVehicle.spawnRequirements = {
    biome           = "clearing",
    roadMaxDist     = 200,
    snapToRoad      = true,
    snapForbidForest = true,
}

-- ---------------------------------------------------------------------------
-- Регистрация
-- ---------------------------------------------------------------------------
PZRC_EventRegistry.register("abandonedvehicle", AbandonedVehicle)
local function log(msg)
    print("[Camp] " .. tostring(msg))
end

local Camp = {}

-- ---------------------------------------------------------------------------
-- Палатки (camping_01, 2 тайла каждая, как в ваниле)
-- Ориентация 1: frontRight(camping_01_0) + backRight(camping_01_1), dy=-1
-- Ориентация 2: frontLeft(camping_01_3) + backLeft(camping_01_2), dx=-1
-- ---------------------------------------------------------------------------
local TENT_ORIENTATIONS = {
    { front = "camping_01_0", back = "camping_01_1", dx = 0, dy = -1 },
    { front = "camping_01_3", back = "camping_01_2", dx = -1, dy = 0 },
}

-- Спальники (2x1)
local SLEEPING_BAG_BASES = { 0, 8, 16, 24 }
local SLEEPING_BAG_OFFSETS = {
    {0, 0, 0},
    {1, 0, 1},
}

local CAMPFIRE_SPRITE = "camping_01_6"  -- потухший костёр
local CHEST_SPRITE = "furniture_storage_02_28"

-- ---------------------------------------------------------------------------
-- Размещение палатки (ванильный подход через IsoThumpable)
-- ---------------------------------------------------------------------------
local function placeTent(sq, orientation, eventId)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local placed = {}

    -- Передний тайл (с контейнером)
    local frontObj = IsoThumpable.new(getCell(), sq, orientation.front, false, {})
    frontObj:setName("Tent")
    frontObj:getModData().PZRC_EventId = eventId
    frontObj:setBlockAllTheSquare(true)
    frontObj:setIsThumpable(false)
    sq:AddSpecialObject(frontObj)
    frontObj:transmitCompleteItemToClients()
    table.insert(placed, frontObj)

    -- Задний тайл
    local backSq = getCell():getGridSquare(x + orientation.dx, y + orientation.dy, z)
    if backSq then
        local backObj = IsoThumpable.new(getCell(), backSq, orientation.back, false, {})
        backObj:setName("Tent")
        backObj:getModData().PZRC_EventId = eventId
        backObj:setBlockAllTheSquare(true)
        backObj:setIsThumpable(false)
        backSq:AddSpecialObject(backObj)
        backObj:transmitCompleteItemToClients()
        table.insert(placed, backObj)
    end

    return placed
end

--- Поставить один объект на клетку
local function placeObject(sq, sprite, eventId, name)
    local obj = IsoObject.new(getCell(), sq, sprite)
    obj:getModData().PZRC_EventId = eventId
    if name then obj:setName(name) end
    sq:AddSpecialObject(obj)
    obj:transmitCompleteItemToClients()
    return obj
end

--- Разместить multi-tile объект (спальник)
local function placeMultiTile(cx, cy, cz, dx, dy, tilesheet, base, offsets, eventId, name)
    local placed = {}
    for _, off in ipairs(offsets) do
        local sq = getCell():getGridSquare(cx + dx + off[1], cy + dy + off[2], cz)
        if sq then
            local sprite = tilesheet .. "_" .. (base + off[3])
            local obj = placeObject(sq, sprite, eventId, name)
            table.insert(placed, obj)
        end
    end
    return placed
end

--- Спавн лагеря
function Camp.spawn(x, y, z, eventId)
    local sq = PZRC_EventUtils.findSafeSquare(x, y, z, PZRC_EventConfig.SAFE_SQUARE_RADIUS)
    if not sq then
        return nil, "No safe square found"
    end

    local cx, cy, cz = sq:getX(), sq:getY(), sq:getZ()
    local placed = 0
    local lootContainers = {}  -- {container, obj} для распределения лута

    -- Костёр в центре (1 тайл)
    placeObject(sq, CAMPFIRE_SPRITE, eventId, "Campfire")
    placed = placed + 1
    log("Campfire at " .. cx .. "," .. cy)

    -- 2 палатки с разными ориентациями
    local tentPositions = {{-3, -2}, {3, 2}}
    for i, pos in ipairs(tentPositions) do
        local tentSq = getCell():getGridSquare(cx + pos[1], cy + pos[2], cz)
        if tentSq then
            local orient = TENT_ORIENTATIONS[((i - 1) % #TENT_ORIENTATIONS) + 1]
            local objs = placeTent(tentSq, orient, eventId)
            placed = placed + #objs

            -- Собираем контейнер палатки (передний тайл)
            if #objs > 0 then
                local container = objs[1]:getContainer()
                if container then
                    table.insert(lootContainers, { container = container, obj = objs[1] })
                end
            end
            log("Tent " .. i .. " (" .. #objs .. " tiles) at " .. tentSq:getX() .. "," .. tentSq:getY())
        end
    end

    -- 1-2 спальника (2x1)
    local bagCount = ZombRand(1, 3)
    local bagPositions = {{-1, 2}, {1, -2}}
    for i = 1, bagCount do
        local pos = bagPositions[i]
        if pos then
            local base = SLEEPING_BAG_BASES[ZombRand(#SLEEPING_BAG_BASES) + 1]
            local objs = placeMultiTile(cx, cy, cz, pos[1], pos[2], "camping_02", base, SLEEPING_BAG_OFFSETS, eventId, "SleepingBag")
            placed = placed + #objs
            log("SleepingBag " .. i .. " (" .. #objs .. " tiles) base=" .. base)
        end
    end

    -- 1-2 ящика
    local chestCount = ZombRand(1, 3)
    local chestPositions = {{0, -3}, {2, 1}}
    for i = 1, chestCount do
        local pos = chestPositions[i]
        if pos then
            local chestSq = getCell():getGridSquare(cx + pos[1], cy + pos[2], cz)
            if chestSq then
                local chestObj = placeObject(chestSq, CHEST_SPRITE, eventId, "SmallChest")
                placed = placed + 1

                local container = chestObj:getContainer()
                if container then
                    table.insert(lootContainers, { container = container, obj = chestObj })
                end
                log("Chest at " .. chestSq:getX() .. "," .. chestSq:getY())
            end
        end
    end

    if placed == 0 then
        return nil, "Failed to place any camp objects"
    end

    -- 1 набор лута, распределённый round-robin по всем контейнерам
    local totalLoot = 0
    if #lootContainers > 0 then
        totalLoot = PZRC_EventUtils.generateLootDistributed(lootContainers, "camp", eventId)
    end

    -- Зомби вокруг
    PZRC_EventUtils.spawnZombies(cx, cy, cz, "camp")

    log("Camp spawned: " .. placed .. " objects, " .. totalLoot .. " items across " .. #lootContainers .. " containers at " .. cx .. "," .. cy)

    return {
        x = cx,
        y = cy,
        z = cz,
        itemCount = totalLoot,
    }
end

--- Cleanup: удаляем все объекты лагеря по eventId
function Camp.cleanup(spawnData, eventId)
    if not spawnData then return end
    PZRC_EventUtils.cleanupByEventId(
        spawnData.x, spawnData.y, spawnData.z,
        eventId,
        { radius = 10, removeItems = true, removeObjects = true }
    )
end

--- Описание
function Camp.getDescription(x, y, z)
    return "Abandoned camp found near " .. x .. ", " .. y
end

-- Заброшенный лагерь в глубоком лесу возле дороги
-- Лагерь выживших: где угодно за городом (поле, лес, поляна), но не в
-- TownZone и не в её пригороде. Дорога/тропа в 4-30 клетках.
Camp.spawnRequirements = {
    excludeCity     = true,
    roadMinDist     = 4,
    roadMaxDist     = 30,
    minDistFromCity = 30,
}

-- ---------------------------------------------------------------------------
-- Регистрация
-- ---------------------------------------------------------------------------
PZRC_EventRegistry.register("camp", Camp)
local function log(msg)
    print("[HelicopterCrash] " .. tostring(msg))
end

local HelicopterCrash = {}

-- Каждый вариант: fuselage + matching tail + matching debris items
local CRASH_VARIANTS = {
    {
        fuselage = "PZRCVehicles.UH60GreenCrash",
        tail     = "PZRCVehicles.UH60GreenTail",
    },
    {
        fuselage = "PZRCVehicles.UH60DesertCrash",
        tail     = "PZRCVehicles.UH60DesertTail",
    },
    {
        fuselage = "PZRCVehicles.UH60MedevacCrash",
        tail     = "PZRCVehicles.UH60MedevacTail",
    },
    {
        fuselage = "PZRCVehicles.Bell206PoliceCrash",
        tail     = "PZRCVehicles.Bell206PoliceTail",
    },
    {
        fuselage = "PZRCVehicles.Bell206SurvivalistCrash",
        tail     = "PZRCVehicles.Bell206SurvivalistTail",
    },
}

-- Радиус разброса обломков (в тайлах)
local DEBRIS_SPREAD = 9
-- Радиус смещения хвоста от фюзеляжа
local TAIL_OFFSET = 4

--- Найти свободную клетку на земле рядом с координатами
local function findGroundSquare(cx, cy, radius)
    for attempt = 1, 15 do
        local dx = ZombRand(-radius, radius + 1)
        local dy = ZombRand(-radius, radius + 1)
        local sq = getSquare(cx + dx, cy + dy, 0)
        if sq and not sq:isBlockedTo(sq) and sq:isFree(false) then
            return sq
        end
    end
    return nil
end

--- Спавн: разбитый вертолёт + хвост + обломки + лут + зомби
function HelicopterCrash.spawn(x, y, z, eventId)
    local sq = PZRC_EventUtils.findSafeSquare(x, y, z, PZRC_EventConfig.SAFE_SQUARE_RADIUS)
    if not sq then
        return nil, "No safe square found"
    end

    -- Случайный вариант крушения (всё консистентно)
    local variant = CRASH_VARIANTS[ZombRand(#CRASH_VARIANTS) + 1]

    -- Случайное направление
    local directions = { IsoDirections.N, IsoDirections.S, IsoDirections.E, IsoDirections.W }
    local dir = directions[ZombRand(#directions) + 1]

    -- Спавн фюзеляжа
    local vehicle = addVehicleDebug(variant.fuselage, dir, nil, sq)
    if not vehicle then
        return nil, "Failed to spawn helicopter: " .. variant.fuselage
    end
    vehicle:getModData().PZRC_EventId = eventId

    -- Лут в TruckBed
    local truckBed = vehicle:getPartById("TruckBed")
    local itemCount = 0
    if truckBed and truckBed:getItemContainer() then
        itemCount = PZRC_EventUtils.generateLoot(truckBed:getItemContainer(), "helicoptercrash", eventId)
    end

    local cx, cy, cz = sq:getX(), sq:getY(), sq:getZ()

    -- Спавн хвостовой секции (отдельный vehicle, рядом с фюзеляжем)
    local tailSq = findGroundSquare(cx, cy, TAIL_OFFSET)
    if tailSq then
        local tailDir = directions[ZombRand(#directions) + 1]
        local tailVeh = addVehicleDebug(variant.tail, tailDir, nil, tailSq)
        if tailVeh then
            tailVeh:getModData().PZRC_EventId = eventId
            log("Tail spawned: " .. variant.tail)
        end
    end

    -- Металлолом вокруг крушения (разнообразные материалы для крафта)
    local debrisCount = 0
    local METAL_LOOT = {
        -- Базовый металлолом
        { item = "Base.ScrapMetal",       weight = 25 },
        { item = "Base.SheetMetal",       weight = 15 },
        { item = "Base.SmallSheetMetal",  weight = 12 },
        { item = "Base.MetalBar",         weight = 10 },
        { item = "Base.SmallMetalBar",    weight = 10 },
        { item = "Base.MetalPipe",        weight = 8 },
        { item = "Base.Pipe",             weight = 6 },
        -- Мелочёвка
        { item = "Base.Nails",            weight = 12 },
        { item = "Base.Screws",           weight = 10 },
        { item = "Base.NutsBolts",        weight = 8 },
        { item = "Base.Hinge",            weight = 6 },
        { item = "Base.Doorknob",         weight = 4 },
        -- Алюминий и цветмет
        { item = "Base.Aluminum",         weight = 8 },
        { item = "Base.AluminumFragments",weight = 10 },
        { item = "Base.CopperScrap",      weight = 6 },
        { item = "Base.CopperWire",       weight = 6 },
        -- Проволока/кабели
        { item = "Base.Wire",             weight = 10 },
        { item = "Base.ElectricWire",     weight = 8 },
        { item = "Base.BarbedWire",       weight = 3 },
        { item = "Base.WeldingRods",      weight = 4 },
        -- Части двигателя/механика
        { item = "Base.EngineParts",      weight = 4 },
        { item = "Base.Spring",           weight = 5 },
        { item = "Base.Gears",            weight = 5 },
        { item = "Base.ElectronicsScrap", weight = 8 },
        -- Стекло/разное
        { item = "Base.GlassPane",        weight = 4 },
        { item = "Base.BrokenGlass",      weight = 6 },
        { item = "Base.Hubcap",           weight = 3 },
    }

    -- Подсчёт общего веса для weighted random
    local totalWeight = 0
    for _, entry in ipairs(METAL_LOOT) do
        totalWeight = totalWeight + entry.weight
    end

    -- Увеличено в ~4x: было 25-50, стало 100-200
    local metalCount = ZombRand(100, 200)
    for i = 1, metalCount do
        local roll = ZombRand(totalWeight)
        local cumulative = 0
        local chosen = METAL_LOOT[1].item
        for _, entry in ipairs(METAL_LOOT) do
            cumulative = cumulative + entry.weight
            if roll < cumulative then
                chosen = entry.item
                break
            end
        end

        local scrapSq = findGroundSquare(cx, cy, DEBRIS_SPREAD)
        if scrapSq then
            local scrap = scrapSq:AddWorldInventoryItem(chosen, 0, 0, 0)
            if scrap then
                scrap:getModData().PZRC_EventId = eventId
                debrisCount = debrisCount + 1
            end
        end
    end

    -- Очаги огня вокруг крушения (4-6 шт) через IsoFire.new + AttachAnim
    if IsoFire and IsoFire.new then
        local fireCount = ZombRand(12, 21)
        local cell = getWorld():getCell()
        local tileScale = Core.getTileScale()
        local animDelay = IsoFireManager.FireAnimDelay
        local tintMod = IsoFireManager.FireTintMod
        local numFrames = IsoFire.NUM_FRAMES_FIRE

        for i = 1, fireCount do
            local fireSq = findGroundSquare(cx, cy, DEBRIS_SPREAD)
            if fireSq then
                local ok, err = pcall(function()
                    local fireObj = IsoFire.new(cell, fireSq)
                    if fireObj then
                        local scale = 0.6 + ZombRand(7) * 0.1
                        fireObj:AttachAnim("Fire", "01", numFrames,
                            animDelay, scale * tileScale,
                            -scale * tileScale, true, 0, false, 0.7, tintMod)
                        fireSq:AddTileObject(fireObj)
                        fireObj:transmitCompleteItemToClients()
                        if fireObj.setLightRadius then
                            fireObj:setLightRadius(10)
                        end
                    end
                end)
                if ok then
                    log("Fire spawned at " .. fireSq:getX() .. "," .. fireSq:getY())
                else
                    log("WARN: Fire spawn failed: " .. tostring(err))
                end
            end
        end
    else
        log("WARN: IsoFire.new not available")
    end

    -- Много зомби вокруг
    PZRC_EventUtils.spawnZombies(cx, cy, cz, "helicoptercrash")

    log("Spawned " .. variant.fuselage .. " at " .. cx .. "," .. cy
        .. " dir=" .. tostring(dir) .. " loot=" .. itemCount .. " debris=" .. debrisCount)

    return {
        x = cx,
        y = cy,
        z = cz or 0,
        itemCount = itemCount,
        debrisCount = debrisCount,
    }
end

--- Cleanup: удаляем вертолёт, хвост и обломки
function HelicopterCrash.cleanup(spawnData, eventId)
    if not spawnData then return end

    local cx, cy, cz = spawnData.x, spawnData.y, spawnData.z
    local searchRadius = DEBRIS_SPREAD + 2

    -- Удаляем vehicles (фюзеляж + хвост) по PZRC_EventId
    PZRC_EventUtils.removeVehicleByEventId(cx, cy, cz, eventId, searchRadius)

    -- Удаляем WorldItems (металлолом) в радиусе крушения
    local itemsRemoved = 0
    for dx = -searchRadius, searchRadius do
        for dy = -searchRadius, searchRadius do
            local sq = getSquare(cx + dx, cy + dy, 0)
            if sq then
                local items = sq:getWorldObjects()
                if items then
                    for i = items:size() - 1, 0, -1 do
                        local obj = items:get(i)
                        if obj then
                            sq:transmitRemoveItemFromSquare(obj)
                            itemsRemoved = itemsRemoved + 1
                        end
                    end
                end
            end
        end
    end

    -- Удаляем огни (IsoFire)
    for dx = -searchRadius, searchRadius do
        for dy = -searchRadius, searchRadius do
            local sq = getSquare(cx + dx, cy + dy, 0)
            if sq then
                if sq.stopFire then
                    sq:stopFire()
                end
                if sq.transmitStopFire then
                    sq:transmitStopFire()
                end
                local objects = sq:getObjects()
                if objects then
                    for i = objects:size() - 1, 0, -1 do
                        local obj = objects:get(i)
                        if obj and instanceof(obj, "IsoFire") then
                            sq:transmitRemoveItemFromSquare(obj)
                            obj:removeFromWorld()
                        end
                    end
                end
            end
        end
    end
    log("Cleanup: removed " .. itemsRemoved .. " world items + fires for event #" .. eventId)
end

--- Описание
function HelicopterCrash.getDescription(x, y, z)
    return "Helicopter crash site near " .. x .. ", " .. y
end

-- Разбился где угодно кроме плотного города, дорога в разумном радиусе.
-- biome не ограничиваем — может упасть и в поле и в лесу, главное не в здании
-- Открытая местность в окрестностях цивилизации: clearing, ближайший город
-- не дальше cityMaxDist (отсекает совсем глухую чащу), дорога в roadMaxDist
-- клетках.
HelicopterCrash.spawnRequirements = {
    biome       = "clearing",
    cityMaxDist = 800,
    roadMaxDist = 50,
}

-- ---------------------------------------------------------------------------
-- Регистрация
-- ---------------------------------------------------------------------------
PZRC_EventRegistry.register("helicoptercrash", HelicopterCrash)
