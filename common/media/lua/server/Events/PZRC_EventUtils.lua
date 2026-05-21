PZRC_EventUtils = PZRC_EventUtils or {}

local function log(msg)
    print("[PZRC_EventUtils] " .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- Проверка: в exclude-зоне ли точка (Louisville / восточный край)
-- Координатный guard — первая линия защиты.
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.isInExcludedZone(x, y)
    if y < PZRC_EventConfig.EXCLUDE_MIN_Y then return true end
    if x > PZRC_EventConfig.EXCLUDE_MAX_X then return true end
    return false
end

-- ---------------------------------------------------------------------------
-- Классификатор точки через MetaGrid API
-- Возвращает: { region, city, forest, road, lootRich, intensity, foraging }
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.classifyPoint(x, y)
    local result = {
        region = nil, city = false, forest = false, road = false,
        lootRich = false, intensity = 0, foraging = false,
    }
    local world = getWorld()
    local grid = world and world:getMetaGrid()
    if not grid then return result end

    pcall(function()
        local zones = grid:getZonesAt(x, y, 0)
        if zones then
            for i = 0, zones:size() - 1 do
                local z = zones:get(i)
                if z then
                    local t = z:getType()
                    if t == "Region" then
                        result.region = z:getName()
                    elseif t == "TownZone" then
                        result.city = true
                    elseif t == "Nav" then
                        result.road = true
                    elseif t == "LootZone" and tostring(z:getName()) == "Rich" then
                        result.lootRich = true
                    elseif t and t:find("Forest") then
                        result.forest = true
                    end
                end
            end
        end
    end)

    pcall(function()
        local chunk = grid:getChunkDataFromTile(x, y)
        if chunk then
            result.intensity = chunk:getUnadjustedZombieIntensity() or 0
            result.foraging = chunk:doesHaveForaging() or false
        end
    end)

    return result
end

-- ---------------------------------------------------------------------------
-- Exclude point полный: координатный guard + Louisville region
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.isExcludedPoint(x, y)
    if PZRC_EventUtils.isInExcludedZone(x, y) then return true, "coord" end
    local class = PZRC_EventUtils.classifyPoint(x, y)
    if class.region == "Louisville" then return true, "region=Louisville" end
    return false, nil
end

-- ---------------------------------------------------------------------------
-- Поиск Nav (дороги) в радиусе maxDist через сэмплинг getZonesAt
-- Кольца радиусом 0, 10, 20, 30, ... по 8 точек на кольце.
-- Возвращает { zone, dist } или nil.
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.findNavInRadius(x, y, maxDist)
    maxDist = maxDist or 50
    local grid = getWorld() and getWorld():getMetaGrid()
    if not grid then return nil end

    -- Шаг кольца 10 тайлов, но не больше maxDist
    local step = math.min(10, math.max(1, maxDist))
    local samples = { { 0, 0, 0 } }
    for r = step, maxDist, step do
        local points = 8
        if r <= 10 then points = 4 end
        for i = 0, points - 1 do
            local a = i * 2 * math.pi / points
            local dx = math.floor(r * math.cos(a) + 0.5)
            local dy = math.floor(r * math.sin(a) + 0.5)
            table.insert(samples, { dx, dy, r })
        end
    end

    for _, s in ipairs(samples) do
        local sx, sy = x + s[1], y + s[2]
        local found = nil
        pcall(function()
            local zones = grid:getZonesAt(sx, sy, 0)
            if zones then
                for i = 0, zones:size() - 1 do
                    local z = zones:get(i)
                    if z and z:getType() == "Nav" then
                        found = z
                        return
                    end
                end
            end
        end)
        if found then return { zone = found, dist = s[3] } end
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Поиск ближайшего TownZone в радиусе (аналогично findNavInRadius)
-- Возвращает { zone, dist } или nil
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.findCityInRadius(x, y, maxDist)
    maxDist = maxDist or 30
    local grid = getWorld() and getWorld():getMetaGrid()
    if not grid then return nil end

    local step = math.min(10, math.max(1, maxDist))
    local samples = { { 0, 0, 0 } }
    for r = step, maxDist, step do
        local points = 8
        if r <= 10 then points = 4 end
        for i = 0, points - 1 do
            local a = i * 2 * math.pi / points
            local dx = math.floor(r * math.cos(a) + 0.5)
            local dy = math.floor(r * math.sin(a) + 0.5)
            table.insert(samples, { dx, dy, r })
        end
    end

    for _, s in ipairs(samples) do
        local sx, sy = x + s[1], y + s[2]
        local found = nil
        pcall(function()
            local zones = grid:getZonesAt(sx, sy, 0)
            if zones then
                for i = 0, zones:size() - 1 do
                    local z = zones:get(i)
                    if z and z:getType() == "TownZone" then
                        found = z
                        return
                    end
                end
            end
        end)
        if found then return { zone = found, dist = s[3] } end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Проверка: подходит ли точка под требования события
-- req fields:
--   biome           "forest" | "city" | "clearing" | "any" | nil
--   roadMinDist     minimum distance to nearest road (tiles) — optional
--   roadMaxDist     maximum distance — optional
--   needsBuilding   true — должна быть в пределах ~20 тайлов от здания
--   excludeCity     true — точка НЕ должна быть в городе (TownZone)
--   minDistFromCity N — в радиусе N тайлов не должно быть TownZone (глубина леса)
--   snapToRoad      true — сдвинуть точку на найденную Nav
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.matchesReq(x, y, req)
    local class = PZRC_EventUtils.classifyPoint(x, y)

    -- Biome
    if req.biome == "forest" then
        if not class.forest then return false, "not forest", class end
    elseif req.biome == "city" then
        if not class.city then return false, "not city", class end
    elseif req.biome == "clearing" then
        -- Clearing = открытая местность: не лес, не город, и нет ForagingNav рядом
        if class.forest then return false, "in forest (need clearing)", class end
        if class.city then return false, "in city (need clearing)", class end
    end

    if req.excludeCity and class.city then
        return false, "in city", class
    end

    -- Глубина леса: никаких TownZone в радиусе minDistFromCity
    if req.minDistFromCity then
        local city = PZRC_EventUtils.findCityInRadius(x, y, req.minDistFromCity)
        if city then
            return false, "city within " .. city.dist .. " (need >" .. req.minDistFromCity .. ")", class
        end
    end

    -- Близость к цивилизации: в радиусе cityMaxDist должна найтись TownZone
    -- (heli/airdrop падают у города или окраин, не в дикой чаще)
    if req.cityMaxDist then
        local city = PZRC_EventUtils.findCityInRadius(x, y, req.cityMaxDist)
        if not city then
            return false, "no city within " .. req.cityMaxDist, class
        end
    end

    -- Building
    if req.needsBuilding then
        local grid = getWorld():getMetaGrid()
        local b = nil
        pcall(function()
            b = grid:getBuildingAt(x, y)
            if not b then
                -- радиус-поиск в 20 тайлов
                for r = 5, 20, 5 do
                    for _, off in ipairs({ { r, 0 }, { 0, r }, { -r, 0 }, { 0, -r } }) do
                        local b2 = grid:getBuildingAt(x + off[1], y + off[2])
                        if b2 then b = b2; return end
                    end
                end
            end
        end)
        if not b then return false, "no building nearby", class end
    end

    -- Road proximity
    if req.roadMaxDist then
        local nav = PZRC_EventUtils.findNavInRadius(x, y, req.roadMaxDist)
        if not nav then
            return false, "no road within " .. req.roadMaxDist, class
        end
        if req.roadMinDist and nav.dist < req.roadMinDist then
            return false, "road too close (" .. nav.dist .. "<" .. req.roadMinDist .. ")", class
        end
        class._nav = nav
    end

    return true, "match", class
end

-- ---------------------------------------------------------------------------
-- Главный алгоритм выбора точки спавна
-- 1. Случайный онлайн-игрок (не в сейфзоне) как якорь-игрок
-- 2. Точка-якорь на ANCHOR_DISTANCE тайлов в случайном направлении
-- 3. Рандомная точка в радиусе SEARCH_RADIUS от якоря
-- 4. Exclude-check + matchesReq
-- 5. PICK_ATTEMPTS попыток; каждый раз свежие якорь и точка
-- Возвращает { x, y, class, info } или nil, err
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.pickSpawnLocation(req)
    local anchorDist = PZRC_EventConfig.ANCHOR_DISTANCE or 700
    local searchRadius = PZRC_EventConfig.SEARCH_RADIUS or 250
    local attempts = PZRC_EventConfig.PICK_ATTEMPTS or 10

    local players = getOnlinePlayers()
    if not players or players:size() == 0 then
        return nil, "no online players"
    end

    -- Фильтр: не в сейфзоне
    local valid = {}
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then
            local px, py = p:getX(), p:getY()
            if not PZRC_EventUtils.isInSafehouse(px, py, 0) then
                table.insert(valid, p)
            end
        end
    end
    if #valid == 0 then
        return nil, "no players outside safehouse"
    end

    -- -------------------------------------------------------------------
    -- Специальный путь для BuildingStash: выбираем случайное ЗДАНИЕ
    -- из grid:getBuildings() в диапазоне [minDist, maxDist] от игрока.
    -- -------------------------------------------------------------------
    if req.pickFromBuildings then
        local player = valid[ZombRand(#valid) + 1]
        local px, py = player:getX(), player:getY()
        local minDist = anchorDist - searchRadius  -- 450 по умолчанию
        local maxDist = anchorDist + searchRadius  -- 950 по умолчанию

        local grid = getWorld():getMetaGrid()
        local buildings = grid:getBuildings()
        if not buildings or buildings:size() == 0 then
            return nil, "no buildings in metaGrid"
        end

        local candidates = {}
        local total = buildings:size()
        for i = 0, total - 1 do
            local b = buildings:get(i)
            if b then
                local ok, bx, by, bw, bh = pcall(function()
                    return b:getX(), b:getY(), b:getW(), b:getH()
                end)
                if ok and bx then
                    local cx = bx + math.floor((bw or 4) / 2)
                    local cy = by + math.floor((bh or 4) / 2)
                    local dist = PZRC_EventUtils.distance(cx, cy, px, py)
                    if dist >= minDist and dist <= maxDist
                        and not PZRC_EventUtils.isInExcludedZone(cx, cy) then
                        -- дополнительно проверим регион
                        local class = PZRC_EventUtils.classifyPoint(cx, cy)
                        if class.region ~= "Louisville" then
                            table.insert(candidates, { x = cx, y = cy, b = b, class = class })
                        end
                    end
                end
            end
        end

        log(string.format("pickFromBuildings: %d candidates (from %d total)", #candidates, total))
        if #candidates == 0 then
            return nil, "no buildings in range " .. minDist .. ".." .. maxDist
        end

        local picked = candidates[ZombRand(#candidates) + 1]
        log(string.format("pickFromBuildings: MATCH building at (%d,%d) region=%s player='%s'",
            picked.x, picked.y, tostring(picked.class.region), player:getUsername()))
        return { x = picked.x, y = picked.y, class = picked.class, player = player:getUsername() }
    end

    for attempt = 1, attempts do
        local player = valid[ZombRand(#valid) + 1]
        local px = math.floor(player:getX())
        local py = math.floor(player:getY())

        -- Якорь-точка на ANCHOR_DISTANCE тайлов в случайном направлении
        local a1 = ZombRand(360) * math.pi / 180
        local anchorX = math.floor(px + math.cos(a1) * anchorDist)
        local anchorY = math.floor(py + math.sin(a1) * anchorDist)

        -- Точка-кандидат: смещение на random(0..SEARCH_RADIUS) от якоря
        local a2 = ZombRand(360) * math.pi / 180
        local r = ZombRand(searchRadius + 1)
        local candX = math.floor(anchorX + math.cos(a2) * r)
        local candY = math.floor(anchorY + math.sin(a2) * r)

        -- Exclude
        local excluded, reason = PZRC_EventUtils.isExcludedPoint(candX, candY)
        if excluded then
            log(string.format("pick att%d: (%d,%d) excluded [%s]", attempt, candX, candY, reason))
        else
            local ok, info, class = PZRC_EventUtils.matchesReq(candX, candY, req)
            if ok then
                -- Snap-to-road: перенести точку на найденную Nav (для машин)
                local finalX, finalY = candX, candY
                local snapExcluded = false
                if req.snapToRoad and class._nav then
                    local z = class._nav.zone
                    pcall(function()
                        local zx, zy = z:getX(), z:getY()
                        local zw, zh = z:getWidth(), z:getHeight()
                        finalX = zx + ZombRand(math.max(zw, 1))
                        finalY = zy + ZombRand(math.max(zh, 1))
                    end)
                    if PZRC_EventUtils.isInExcludedZone(finalX, finalY) then
                        snapExcluded = true
                        log(string.format("pick att%d: snapped point (%d,%d) excluded, retrying",
                            attempt, finalX, finalY))
                    elseif req.snapForbidForest then
                        -- Snapped Nav may sit inside a Forest zone (dirt path) — reject.
                        -- Only kicks in when the event explicitly forbids forest roads.
                        local snapClass = PZRC_EventUtils.classifyPoint(finalX, finalY)
                        if snapClass.forest then
                            snapExcluded = true
                            log(string.format("pick att%d: snapped point (%d,%d) is forest road, retrying",
                                attempt, finalX, finalY))
                        end
                    end
                end
                if not snapExcluded then
                    log(string.format("pick att%d: (%d,%d) MATCH player='%s' region=%s forest=%s city=%s road=%s%s",
                        attempt, finalX, finalY,
                        player:getUsername(),
                        tostring(class.region),
                        tostring(class.forest),
                        tostring(class.city),
                        tostring(class.road),
                        req.snapToRoad and " [snapped]" or ""))
                    return { x = finalX, y = finalY, class = class, player = player:getUsername() }
                end
            else
                log(string.format("pick att%d: (%d,%d) fail [%s] region=%s",
                    attempt, candX, candY, info, tostring(class.region)))
            end
        end
    end

    return nil, "no valid location after " .. attempts .. " attempts"
end

-- ---------------------------------------------------------------------------
-- Проверка: попадает ли точка в чей-то сейфхаус
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.isInSafehouse(x, y, radius)
    radius = radius or 0
    local safehouses = SafeHouse.getSafehouseList()
    if not safehouses then return false end

    for i = 0, safehouses:size() - 1 do
        local sh = safehouses:get(i)
        local sx1 = sh:getX()
        local sy1 = sh:getY()
        local sx2 = sh:getX2()
        local sy2 = sh:getY2()
        -- Проверяем пересечение с радиусом поиска
        if x + radius >= sx1 and x - radius <= sx2
            and y + radius >= sy1 and y - radius <= sy2 then
            return true
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Расстояние
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.distance(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

-- ---------------------------------------------------------------------------
-- Проверка безопасности клетки
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.isSquareSafe(square)
    if not square then return false end

    -- isFree() проверяет коллизии, стены, объекты — всё в одном вызове
    if not square:isFree(false) then return false end
    if square:TreatAsSolidFloor() == false then return false end

    -- Встроенные методы IsoGridSquare для деревьев и кустов
    if square:HasTree() then return false end
    if square:hasBush() then return false end

    return true
end

--- Проверка: есть ли машина на клетке или в радиусе вокруг
function PZRC_EventUtils.hasVehicleNearby(x, y, z, radius)
    radius = radius or 3
    local cell = getCell()
    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = cell:getGridSquare(x + dx, y + dy, z or 0)
            if sq then
                local vehicle = sq:getVehicleContainer()
                if vehicle then return true end
                -- Также проверяем движущиеся объекты (машины в процессе загрузки)
                local movingObjects = sq:getMovingObjects()
                if movingObjects then
                    for i = 0, movingObjects:size() - 1 do
                        local obj = movingObjects:get(i)
                        if instanceof(obj, "BaseVehicle") then return true end
                    end
                end
            end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Спавн зомби вокруг точки
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.spawnZombies(x, y, z, eventTypeName, radius)
    local cfg = PZRC_EventConfig.Zombies[eventTypeName]
    if not cfg then return 0 end

    local count = ZombRand(cfg.min, cfg.max + 1)
    if count <= 0 then return 0 end

    radius = radius or 10

    -- Спавним каждого зомби отдельно со смещением от точки (минимум 3 клетки)
    -- чтобы не застревали в объекте события
    local spawned = 0
    for _ = 1, count do
        local angle = ZombRand(360) * math.pi / 180
        local dist = 3 + ZombRand(radius - 2)
        local zx = x + math.floor(dist * math.cos(angle))
        local zy = y + math.floor(dist * math.sin(angle))
        addZombiesInOutfit(zx, zy, z or 0, 1, nil, 0)
        spawned = spawned + 1
    end

    log("Spawned " .. spawned .. " zombies for " .. eventTypeName .. " at " .. x .. "," .. y)
    return spawned
end

-- ---------------------------------------------------------------------------
-- Поиск свободной клетки в радиусе
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.findSafeSquare(x, y, z, maxRadius)
    maxRadius = maxRadius or PZRC_EventConfig.SAFE_SQUARE_RADIUS
    local cell = getCell()
    local zz = z or 0

    -- Сначала проверяем саму точку
    local sq0 = cell:getGridSquare(x, y, zz)
    if PZRC_EventUtils.isSquareSafe(sq0) then
        return sq0
    end

    -- Расширяем радиус постепенно: 2 → 5 → 10 → maxRadius
    local steps = { 2, 5, 10, maxRadius }
    for _, r in ipairs(steps) do
        if r > maxRadius then r = maxRadius end
        for _ = 1, 8 do
            local rx = x + ZombRand(-r, r + 1)
            local ry = y + ZombRand(-r, r + 1)
            local sq = cell:getGridSquare(rx, ry, zz)
            if PZRC_EventUtils.isSquareSafe(sq) then
                return sq
            end
        end
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Поиск случайного контейнера в здании
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.findRandomContainerInBuilding(x, y, z, radius)
    radius = radius or PZRC_EventConfig.BUILDING_SEARCH_RADIUS

    -- Собираем здания в радиусе
    local buildings = {}
    local cell = getCell()

    -- Сканируем сетку с шагом 3 по всем этажам (0-3)
    for dz = 0, 3 do
        for dx = -radius, radius, 3 do
            for dy = -radius, radius, 3 do
                local sq = cell:getGridSquare(x + dx, y + dy, dz)
                if sq then
                    local building = sq:getBuilding()
                    if building then
                        local found = false
                        for _, b in ipairs(buildings) do
                            if b == building then found = true; break end
                        end
                        if not found then
                            table.insert(buildings, building)
                        end
                    end
                end
            end
        end
    end

    if #buildings == 0 then
        log("No buildings found near " .. x .. "," .. y)
        return nil, nil, nil
    end

    -- Случайное здание
    local building = buildings[ZombRand(#buildings) + 1]
    local def = building:getDef()
    if not def then return nil, nil, nil end

    -- Собираем все комнаты
    local rooms = {}
    for i = 0, def:getRooms():size() - 1 do
        table.insert(rooms, def:getRooms():get(i))
    end

    if #rooms == 0 then
        log("Building has no rooms")
        return nil, nil, nil
    end

    -- Перемешиваем комнаты и ищем контейнер
    for attempt = 1, math.min(#rooms, 5) do
        local idx = ZombRand(#rooms) + 1
        local room = rooms[idx]
        local roomDef = room

        -- Получаем IsoRoom → сканируем клетки
        local isoRoom = roomDef:getIsoRoom()
        if isoRoom then
            local containers = {}
            for si = 0, isoRoom:getSquares():size() - 1 do
                local sq = isoRoom:getSquares():get(si)
                if sq then
                    for oi = 0, sq:getObjects():size() - 1 do
                        local obj = sq:getObjects():get(oi)
                        if obj:getContainer() then
                            table.insert(containers, obj)
                        end
                    end
                end
            end

            if #containers > 0 then
                local chosen = containers[ZombRand(#containers) + 1]
                local csq = chosen:getSquare()
                return chosen, chosen:getContainer(), csq
            end
        end
    end

    log("No containers found in building rooms")
    return nil, nil, nil
end

-- ---------------------------------------------------------------------------
-- Proximity check: есть ли игрок рядом
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.isPlayerNearby(x, y, radius)
    radius = radius or PZRC_EventConfig.VISIT_RADIUS
    local players = getOnlinePlayers()
    if not players then return false end

    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then
            local dist = PZRC_EventUtils.distance(x, y, p:getX(), p:getY())
            if dist <= radius then
                return true
            end
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Синхронизация визуала контейнера (спрайт пустой/полный)
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.syncContainerVisual(obj)
    if not obj or not obj:getContainer() then return end
    pcall(obj.sendObjectChange, obj, "containers")
end

-- ---------------------------------------------------------------------------
-- Кэш предметов по категориям (для category-based лута)
-- ---------------------------------------------------------------------------

PZRC_EventUtils.categoryCache = nil

function PZRC_EventUtils.buildCategoryCache()
    if PZRC_EventUtils.categoryCache then return PZRC_EventUtils.categoryCache end

    local cache = {}
    local itemList = getScriptManager():getAllItems()
    for i = 0, itemList:size() - 1 do
        local script = itemList:get(i)
        if not script:getObsolete() and not script:isHidden() then
            local cat = script:getTypeString() or ""
            if cat ~= "" then
                if not cache[cat] then cache[cat] = {} end
                table.insert(cache[cat], script:getFullName())
            end
        end
    end

    -- Логируем доступные категории
    local catNames = {}
    for cat, items in pairs(cache) do
        table.insert(catNames, cat .. "(" .. #items .. ")")
    end
    table.sort(catNames)
    log("Category cache built: " .. table.concat(catNames, ", "))

    PZRC_EventUtils.categoryCache = cache
    return cache
end

function PZRC_EventUtils.getRandomItemFromCategory(categoryName)
    local cache = PZRC_EventUtils.buildCategoryCache()
    local items = cache[categoryName]
    if not items or #items == 0 then
        log("No items in category: " .. tostring(categoryName))
        return nil
    end
    return items[ZombRand(#items) + 1]
end

-- ---------------------------------------------------------------------------
-- Генерация лута из таблицы
-- Поддерживает:
--   { item = "Base.Axe", chance = 0.5, min = 1, max = 2 }       — конкретный предмет
--   { category = "Weapon", chance = 0.5, min = 1, max = 2 }     — случайный из категории
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.generateLoot(container, lootTableName, eventId, skipSync)
    local lootTable = PZRC_EventConfig.Loot[lootTableName]
    if not lootTable then
        log("Unknown loot table: " .. tostring(lootTableName))
        return 0
    end

    local count = 0
    for _, entry in ipairs(lootTable) do
        if ZombRand(1000) < entry.chance * 1000 then
            local qty = ZombRand(entry.min, entry.max + 1)
            for _ = 1, qty do
                local itemId = entry.item
                if not itemId and entry.category then
                    itemId = PZRC_EventUtils.getRandomItemFromCategory(entry.category)
                end
                if itemId then
                    -- container:AddItem can throw a Kahlua NPE on invalid item IDs
                    -- in B42, which would otherwise abort the whole spawn() call
                    -- and leave an empty crate without zombies. Catch per-item.
                    local ok, added = pcall(function() return container:AddItem(itemId) end)
                    if not ok then
                        log("AddItem EXCEPTION on '" .. tostring(itemId) .. "': " .. tostring(added))
                        added = nil
                    end
                    if added then
                        if eventId then
                            added:getModData().PZRC_EventId = eventId
                        end
                        if not skipSync then
                            sendAddItemToContainer(container, added)
                        end
                        count = count + 1
                    end
                end
            end
        end
    end

    return count
end

-- ---------------------------------------------------------------------------
-- Генерация лута с распределением по нескольким контейнерам (round-robin)
-- containers: массив {container, obj} — контейнер и его IsoObject (для syncVisual)
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.generateLootDistributed(containers, lootTableName, eventId)
    local lootTable = PZRC_EventConfig.Loot[lootTableName]
    if not lootTable then
        log("Unknown loot table: " .. tostring(lootTableName))
        return 0
    end

    if #containers == 0 then return 0 end

    local count = 0
    local idx = 1
    for _, entry in ipairs(lootTable) do
        if ZombRand(1000) < entry.chance * 1000 then
            local qty = ZombRand(entry.min, entry.max + 1)
            for _ = 1, qty do
                local itemId = entry.item
                if not itemId and entry.category then
                    itemId = PZRC_EventUtils.getRandomItemFromCategory(entry.category)
                end
                if itemId then
                    local target = containers[idx]
                    local added = target.container:AddItem(itemId)
                    if added then
                        if eventId then
                            added:getModData().PZRC_EventId = eventId
                        end
                        sendAddItemToContainer(target.container, added)
                        count = count + 1
                    end
                    idx = (idx % #containers) + 1
                end
            end
        end
    end

    -- Обновляем визуал всех контейнеров
    for _, target in ipairs(containers) do
        if target.obj then
            PZRC_EventUtils.syncContainerVisual(target.obj)
        end
    end

    return count
end

-- ---------------------------------------------------------------------------
-- Универсальный cleanup по eventId в радиусе
-- Сканирует клетки вокруг точки, удаляет объекты и предметы с PZRC_EventId == eventId
-- opts.radius       — радиус сканирования (default 5)
-- opts.removeItems  — удалять предметы из контейнеров (default true)
-- opts.removeObjects — удалять сами объекты с клетки (default true)
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.cleanupByEventId(x, y, z, eventId, opts)
    opts = opts or {}
    local radius = opts.radius or 5
    local removeItems = opts.removeItems ~= false
    local removeObjects = opts.removeObjects ~= false

    local cell = getCell()
    local removedObjects = 0
    local removedItems = 0

    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = cell:getGridSquare(x + dx, y + dy, z or 0)
            if sq then
                local objsToRemove = {}
                for i = 0, sq:getObjects():size() - 1 do
                    local obj = sq:getObjects():get(i)
                    local objEventId = obj:getModData().PZRC_EventId

                    -- Удаляем помеченные предметы из ЛЮБОГО контейнера на клетке
                    if removeItems then
                        local container = obj:getContainer()
                        if container then
                            local itemsToRemove = {}
                            for j = 0, container:getItems():size() - 1 do
                                local item = container:getItems():get(j)
                                if item:getModData().PZRC_EventId == eventId then
                                    table.insert(itemsToRemove, item)
                                end
                            end
                            for _, item in ipairs(itemsToRemove) do
                                sendRemoveItemFromContainer(container, item)
                                container:Remove(item)
                                removedItems = removedItems + 1
                            end
                            if #itemsToRemove > 0 then
                                PZRC_EventUtils.syncContainerVisual(obj)
                            end
                        end
                    end

                    -- Объект создан событием — помечаем на удаление
                    if removeObjects and objEventId == eventId then
                        table.insert(objsToRemove, obj)
                    end
                end

                -- Удаляем объекты с клетки
                for _, obj in ipairs(objsToRemove) do
                    sq:transmitRemoveItemFromSquare(obj)
                    removedObjects = removedObjects + 1
                end

                -- Предметы на земле (WorldItems)
                if removeItems then
                    local groundItems = {}
                    for i = 0, sq:getWorldObjects():size() - 1 do
                        local wo = sq:getWorldObjects():get(i)
                        local item = wo:getItem()
                        if item and item:getModData().PZRC_EventId == eventId then
                            table.insert(groundItems, wo)
                        end
                    end
                    for _, wo in ipairs(groundItems) do
                        sq:removeWorldObject(wo)
                        removedItems = removedItems + 1
                    end
                end
            end
        end
    end

    log("Cleanup eventId=" .. eventId .. ": removed " .. removedObjects .. " objects, " .. removedItems .. " items")
    return removedObjects, removedItems
end

-- ---------------------------------------------------------------------------
-- Coverage scan — берёт N случайных точек в валидной зоне и считает сколько
-- из них прошло бы фильтр данного spawnReq. Помогает оценить плотность
-- доступных клеток для типа события (helicoptercrash / airdrop / etc).
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.scanCoverage(samples)
    samples = samples or 500
    local world = getWorld()
    local grid = world and world:getMetaGrid()
    if not grid then
        log("ScanCoverage: MetaGrid unavailable")
        return "MetaGrid unavailable"
    end

    -- valid zone (Muldraugh / Rosewood / West Point — не Louisville)
    local minX, maxX = 6000, 14999
    local minY, maxY = 5500, 13000

    local n = 0
    local cForest, cCity, cRoad, cClearing = 0, 0, 0, 0
    local passByType = {}
    local typesToCheck = { "buildingstash", "foreststash", "airdrop", "abandonedvehicle", "camp", "helicoptercrash" }

    for _, tn in ipairs(typesToCheck) do passByType[tn] = 0 end

    log(string.format("=== Coverage scan: %d samples in x=[%d..%d] y=[%d..%d] ===",
        samples, minX, maxX, minY, maxY))

    for i = 1, samples do
        local x = minX + ZombRand(maxX - minX + 1)
        local y = minY + ZombRand(maxY - minY + 1)

        local class = PZRC_EventUtils.classifyPoint(x, y)
        n = n + 1
        if class.forest then cForest = cForest + 1 end
        if class.city   then cCity   = cCity   + 1 end
        if class.road   then cRoad   = cRoad   + 1 end
        if not class.forest and not class.city then cClearing = cClearing + 1 end

        for _, tn in ipairs(typesToCheck) do
            local handler = PZRC_EventRegistry and PZRC_EventRegistry.get and PZRC_EventRegistry.get(tn) or nil
            local req = handler and handler.spawnRequirements or nil
            if req then
                local ok = PZRC_EventUtils.matchesReq(x, y, req)
                if ok then passByType[tn] = passByType[tn] + 1 end
            end
        end
    end

    log(string.format("Classification: clearing=%d (%.1f%%)  forest=%d (%.1f%%)  city=%d (%.1f%%)  road=%d (%.1f%%)",
        cClearing, 100*cClearing/n, cForest, 100*cForest/n, cCity, 100*cCity/n, cRoad, 100*cRoad/n))

    for _, tn in ipairs(typesToCheck) do
        local k = passByType[tn]
        log(string.format("  passes %-18s spawnReq: %d / %d (%.1f%%)", tn, k, n, 100*k/n))
    end

    log("=== Coverage scan finished ===")

    return string.format("Coverage: clearing=%.1f%%, forest=%.1f%%, city=%.1f%%, road=%.1f%% (see log for per-type passes)",
        100*cClearing/n, 100*cForest/n, 100*cCity/n, 100*cRoad/n)
end

-- ---------------------------------------------------------------------------
-- Разведка метакарты (IsoMetaGrid) — используется для /event scanmap
-- Возвращает короткое summary строкой, детали пишет в серверный лог
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.scanMap()
    local world = getWorld()
    local grid = world and world:getMetaGrid()
    if not grid then
        log("ScanMap: MetaGrid unavailable")
        return "MetaGrid unavailable"
    end

    log("=== SCAN MAP START ===")

    -- MetaGrid info
    local minX, minY, gridW, gridH = 0, 0, 0, 0
    pcall(function()
        minX = grid:getMinX(); minY = grid:getMinY()
        gridW = grid:getWidth(); gridH = grid:getHeight()
    end)
    log(string.format("MetaGrid: size=%dx%d origin=(%d,%d)", gridW, gridH, minX, minY))

    -- Global buildings (already confirmed working)
    local buildingCount = 0
    pcall(function()
        local buildings = grid:getBuildings()
        if buildings then buildingCount = buildings:size() end
    end)
    log("Buildings (global): " .. buildingCount)

    -- -------------------------------------------------------------------
    -- Point probes: getZonesAt() + getChunkDataFromTile()
    -- Точки взяты из PZRC_EventConfig.Locations (Muldraugh / Rosewood / WestPoint)
    -- — это валидная зона (y >= 5500, x <= 15000), НЕ Louisville
    -- -------------------------------------------------------------------
    local probes = {
        { x = 11417, y = 6874, expect = "BuildingStash (Muldraugh town)" },
        { x = 11566, y = 6880, expect = "BuildingStash (Muldraugh town)" },
        { x = 11807, y = 7103, expect = "ForestStash (forest)" },
        { x = 11935, y = 7126, expect = "ForestStash (forest)" },
        { x = 11708, y = 7180, expect = "AbandonedVehicle (road)" },
        { x = 11834, y = 7181, expect = "AbandonedVehicle (road)" },
        { x = 11197, y = 6983, expect = "Airdrop (open area)" },
        { x = 11541, y = 7899, expect = "Camp (forest/clearing)" },
        { x = 10194, y = 7948, expect = "Camp (forest/clearing)" },
        { x = 9750,  y = 9825, expect = "Camp (far south)" },
    }

    log("--- Point probes ---")
    for _, p in ipairs(probes) do
        log(string.format("PROBE (%d, %d) expect: %s", p.x, p.y, p.expect))

        -- getZonesAt
        local okZ, errZ = pcall(function()
            local zones = grid:getZonesAt(p.x, p.y, 0)
            if not zones then
                log("  getZonesAt -> nil")
                return
            end
            local n = zones:size()
            log("  getZonesAt -> " .. n .. " zones")
            for i = 0, n - 1 do
                local z = zones:get(i)
                if z then
                    local t = tostring(z:getType() or "?")
                    local zx, zy = z:getX(), z:getY()
                    local zw, zh = z:getWidth(), z:getHeight()
                    log(string.format("    [%s] at %d,%d %dx%d", t, zx, zy, zw, zh))
                end
            end
        end)
        if not okZ then log("  getZonesAt ERR: " .. tostring(errZ)) end

        -- getChunkDataFromTile → zombie intensity + ALL zones via getZone(i)
        local okC, errC = pcall(function()
            local chunk = grid:getChunkDataFromTile(p.x, p.y)
            if not chunk then
                log("  getChunkDataFromTile -> nil")
                return
            end
            log(string.format("  chunk.zombieIntensity = %s | foraging=%s",
                tostring(chunk:getUnadjustedZombieIntensity()),
                tostring(chunk:doesHaveForaging())))

            -- Перечисляем ВСЕ зоны чанка (без фильтра) — через геттеры
            local n = chunk:getZonesSize()
            log("  chunk.zonesSize = " .. n)
            for i = 0, n - 1 do
                local z = chunk:getZone(i)
                if z then
                    local t = tostring(z:getType() or "?")
                    local nm = tostring(z:getName() or "")
                    log(string.format("    [%s] name='%s' at %d,%d %dx%d",
                        t, nm, z:getX(), z:getY(), z:getWidth(), z:getHeight()))
                end
            end
        end)
        if not okC then log("  chunkData ERR: " .. tostring(errC)) end
    end

    log("=== SCAN MAP END ===")
    return string.format("probed %d points, buildings=%d (see server log)",
        #probes, buildingCount)
end

-- ---------------------------------------------------------------------------
-- Удаление транспорта по eventId
-- BaseVehicle — отдельная сущность, не IsoObject на клетке
-- Ищем через getMovingObjects() или getVehicleContainer()
-- ---------------------------------------------------------------------------

function PZRC_EventUtils.removeVehicleByEventId(x, y, z, eventId, radius)
    radius = radius or 5
    local cell = getCell()
    local removed = 0

    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = cell:getGridSquare(x + dx, y + dy, z or 0)
            if sq then
                local vehicle = sq:getVehicleContainer()
                if vehicle and vehicle:getModData().PZRC_EventId == eventId then
                    vehicle:permanentlyRemove()
                    removed = removed + 1
                    log("Removed vehicle #" .. removed .. " for eventId=" .. eventId)
                end
            end
        end
    end

    if removed == 0 then
        log("Vehicle not found for eventId=" .. eventId)
    end
    return removed > 0
end

-- Remove orphan event-vehicles in a square radius — vehicles tagged with PZRC_EventId
-- whose event no longer exists in storage. Lets a new event reclaim a tile that
-- a previous TTL'd event couldn't clean (cleanup ran while chunk was unloaded).
function PZRC_EventUtils.removeOrphanEventVehicles(x, y, z, radius)
    radius = radius or 3
    local cell = getCell()
    if not cell then return 0 end
    local removed = 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = cell:getGridSquare(x + dx, y + dy, z or 0)
            if sq then
                local vehicle = sq:getVehicleContainer()
                if vehicle and vehicle.getModData then
                    local oid = vehicle:getModData().PZRC_EventId
                    if oid and PZRC_EventManager and not PZRC_EventManager.exists(oid) then
                        vehicle:permanentlyRemove()
                        removed = removed + 1
                        log("Removed orphan event-vehicle (stale eventId=" .. tostring(oid) .. ")")
                    end
                end
            end
        end
    end
    return removed
end
