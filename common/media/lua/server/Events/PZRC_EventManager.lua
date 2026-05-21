PZRC_EventManager = PZRC_EventManager or {}

-- Состояния события
PZRC_EventManager.STATE_PENDING         = "pending"          -- запланировано, чанк не загружен, в мире ничего нет
PZRC_EventManager.STATE_SPAWNED         = "spawned"          -- объекты созданы в мире, игрок не подходил
PZRC_EventManager.STATE_VISITED         = "visited"          -- игрок подошёл, ждём TTL для cleanup
PZRC_EventManager.STATE_PENDING_CLEANUP = "pending_cleanup"  -- TTL истёк, но чанк выгружен — ждём загрузки

local function log(msg)
    print("[PZRC_EventManager] " .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- Хранилище: getGameTime():getModData()["PZRC_Events"]
-- ---------------------------------------------------------------------------

local function getStorage()
    local modData = getGameTime():getModData()
    if not modData["PZRC_Events"] then
        modData["PZRC_Events"] = { events = {}, nextId = 1 }
    end
    return modData["PZRC_Events"]
end

-- ---------------------------------------------------------------------------
-- Проверка: загружен ли чанк с координатами события
-- ---------------------------------------------------------------------------

local function isChunkLoaded(x, y, z)
    return getCell():getGridSquare(x, y, z or 0) ~= nil
end

-- ---------------------------------------------------------------------------
-- Радио-сообщения при спавне события — формат: [typename], одно сообщение/строку
-- Плейсхолдеры: {x}, {y}
-- Источник: shipped в моде, опционально override в ~/Zomboid/Lua/
-- ---------------------------------------------------------------------------

PZRC_EventManager.eventMessages = {}

local function loadEventMessages()
    local lines = PZRC_Utils.readModTextLines(
        PZRC_EventConfig.EVENT_MESSAGES_FILE_REL,
        PZRC_EventConfig.EVENT_MESSAGES_FILE_OVERRIDE)
    if not lines then
        log("Event messages not found (" .. PZRC_EventConfig.EVENT_MESSAGES_FILE_REL .. ")")
        return
    end

    PZRC_EventManager.eventMessages = {}
    local currentType = nil
    for _, raw in ipairs(lines) do
        local line = raw:match("^%s*(.-)%s*$")
        if line ~= "" then
            local section = line:match("^%[(.+)%]$")
            if section then
                currentType = section:lower()
                PZRC_EventManager.eventMessages[currentType] = PZRC_EventManager.eventMessages[currentType] or {}
            elseif currentType then
                table.insert(PZRC_EventManager.eventMessages[currentType], line)
            end
        end
    end

    local total = 0
    for typeName, msgs in pairs(PZRC_EventManager.eventMessages) do
        total = total + #msgs
        log("Loaded " .. #msgs .. " radio messages for [" .. typeName .. "]")
    end
    log("Total event radio messages: " .. total)
end

-- ---------------------------------------------------------------------------
-- Broadcast: отправка серверной команды всем клиентам
-- ---------------------------------------------------------------------------

local function broadcastToClients(module, command, args)
    local players = getOnlinePlayers()
    if players then
        for i = 0, players:size() - 1 do
            sendServerCommand(players:get(i), module, command, args)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Уведомления: лог + радио
-- ---------------------------------------------------------------------------

function PZRC_EventManager.notify(message, eventData)
    log(message)

    if not eventData or not eventData.type then return end

    local msgs = PZRC_EventManager.eventMessages[eventData.type]
    if not msgs or #msgs == 0 then return end

    if not PZRC_Radio then
        log("PZRC_Radio not loaded yet, skipping broadcast")
        return
    end
    local channel = DynamicRadio and DynamicRadio.cache
        and DynamicRadio.cache[PZRC_Radio.channelUUID]
    if not channel then
        log("Radio channel not available, skipping broadcast")
        return
    end

    local msg = msgs[ZombRand(#msgs) + 1]
    msg = msg:gsub("{x}", tostring(eventData.x or "???"))
    msg = msg:gsub("{y}", tostring(eventData.y or "???"))

    local bc = RadioBroadCast.new("SZ-EVT-" .. tostring(ZombRand(100000, 999999)), -1, -1)
    bc:AddRadioLine(RadioLine.new("<bzzt>", 0.5, 0.5, 0.5))
    bc:AddRadioLine(RadioLine.new(msg, 1.0, 0.8, 0.2))
    bc:AddRadioLine(RadioLine.new("<fzzt>", 0.5, 0.5, 0.5))
    channel:setAiringBroadcast(bc)

    log("Radio broadcast sent for event #" .. (eventData.id or "?"))
end

-- ---------------------------------------------------------------------------
-- Попытка инициализации pending-события (спавн объектов в мире)
-- ---------------------------------------------------------------------------

local function tryInitialize(event)
    local handler = PZRC_EventRegistry.get(event.type)
    if not handler then return false end

    if not isChunkLoaded(event.x, event.y, event.z) then return false end

    -- Валидация
    if handler.validate then
        local valid, err = handler.validate(event.x, event.y, event.z)
        if not valid then
            log("Init validation failed for #" .. event.id .. ": " .. tostring(err))
            return false, err
        end
    end

    -- Спавн (обёрнут в pcall — если хендлер бросит Java-NPE, PZ может пере-
    -- запустить onClientCommand и handler.spawn вызовется второй раз; ловим
    -- здесь, чтобы не получить двух физических объектов в мире).
    local ok, spawnData, spawnErr = pcall(handler.spawn, event.x, event.y, event.z, event.id)
    if not ok then
        log("Init spawn EXCEPTION for #" .. event.id .. ": " .. tostring(spawnData))
        return false, "spawn exception: " .. tostring(spawnData)
    end
    if not spawnData then
        log("Init spawn failed for #" .. event.id .. ": " .. tostring(spawnErr))
        return false, spawnErr
    end

    event.state = PZRC_EventManager.STATE_SPAWNED
    event.spawnData = spawnData

    local origX, origY = event.x, event.y
    event.x = spawnData.x or event.x
    event.y = spawnData.y or event.y
    event.z = spawnData.z or event.z

    local dist = math.floor(PZRC_EventUtils.distance(origX, origY, event.x, event.y))
    log("Event #" .. event.id .. " spawned: origin=" .. origX .. "," .. origY
        .. " loot=" .. event.x .. "," .. event.y .. "," .. event.z
        .. " dist=" .. dist)

    return true
end

-- ---------------------------------------------------------------------------
-- Cleanup: удаляем всё что наспавнили
-- Возвращает true если cleanup выполнен, false если отложен
-- force=true пропускает проверку игроков (для /event remove)
-- ---------------------------------------------------------------------------

local function doCleanup(event, force)
    -- pending — в мире ничего нет, всегда успех
    if event.state == PZRC_EventManager.STATE_PENDING then return true end

    -- Чанк не загружен — cleanup невозможен
    if not isChunkLoaded(event.x, event.y, event.z) then return false end

    -- Игрок рядом — откладываем (не удаляем на глазах)
    local cleanupRadius = PZRC_Config.sbox("EventCleanupRadiusCells", 20)
    if not force and PZRC_EventUtils.isPlayerNearby(event.x, event.y, cleanupRadius) then
        return false
    end

    local handler = PZRC_EventRegistry.get(event.type)
    if not handler then return true end

    if handler.cleanup then
        local ok, err = pcall(handler.cleanup, event.spawnData, event.id)
        if not ok then
            log("Cleanup error for #" .. event.id .. ": " .. tostring(err))
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Spawn: регистрация события в планировщике
-- ---------------------------------------------------------------------------

function PZRC_EventManager.spawn(typeName, x, y, z, source)
    local handler = PZRC_EventRegistry.get(typeName)
    if not handler then
        log("Unknown event type: " .. tostring(typeName))
        return nil, "Unknown event type: " .. tostring(typeName)
    end

    z = z or 0
    source = source or "manual"

    -- Запретная зона (Louisville / восточный край)
    if source ~= "manual" and PZRC_EventUtils.isInExcludedZone(x, y) then
        log("Event blocked: " .. x .. "," .. y .. " is in excluded zone (Louisville)")
        return nil, "Location is in excluded zone (Louisville)"
    end

    -- Проверка сейфхауса
    if PZRC_EventUtils.isInSafehouse(x, y, PZRC_EventConfig.BUILDING_SEARCH_RADIUS) then
        log("Event blocked: location " .. x .. "," .. y .. " is inside a safehouse")
        return nil, "Location is inside a safehouse"
    end

    -- Проверка: нет ли уже события в радиусе 30 клеток
    local overlapRadius = PZRC_EventConfig.EVENT_OVERLAP_RADIUS or 30
    local storage = getStorage()
    for _, existing in ipairs(storage.events) do
        local dist = PZRC_EventUtils.distance(x, y, existing.x, existing.y)
        if dist <= overlapRadius then
            log("Event blocked: too close to event #" .. existing.id
                .. " (" .. existing.type .. ") at " .. existing.x .. "," .. existing.y
                .. " dist=" .. math.floor(dist))
            return nil, "Too close to existing event #" .. existing.id .. " (dist=" .. math.floor(dist) .. ")"
        end
    end

    -- Регистрация в планировщике
    local storage = getStorage()
    local id = storage.nextId
    storage.nextId = id + 1

    local event = {
        id = id,
        type = typeName:lower(),
        x = x,
        y = y,
        z = z,
        spawnTime = os.time(),
        state = PZRC_EventManager.STATE_PENDING,
        source = source,
        spawnData = nil,
    }

    table.insert(storage.events, event)

    log("Event #" .. id .. " (" .. typeName .. ") created at origin=" .. x .. "," .. y)

    -- Радио-уведомление сразу при создании
    PZRC_EventManager.notify("Event #" .. id .. " created", event)

    -- Пробуем сразу инициализировать
    local ok, err = tryInitialize(event)
    if not ok and err then
        -- Валидация или спавн провалились — удаляем из планировщика
        table.remove(storage.events, #storage.events)
        return nil, err
    end

    if event.state == PZRC_EventManager.STATE_PENDING then
        log("Event #" .. id .. " (" .. typeName .. ") scheduled at " .. x .. "," .. y .. " (chunk not loaded)")
    end

    -- Уведомляем всех клиентов о новом событии (для маркеров на карте)
    broadcastToClients("PZRC_Events", "eventNotify", {
        id = event.id,
        type = event.type,
        x = event.x,
        y = event.y,
    })

    return event, nil
end

-- ---------------------------------------------------------------------------
-- Удаление события по ID
-- ---------------------------------------------------------------------------

function PZRC_EventManager.remove(eventId, force)
    local storage = getStorage()
    for i, event in ipairs(storage.events) do
        if event.id == eventId then
            local cleaned = doCleanup(event, force)
            if not cleaned then
                event.state = PZRC_EventManager.STATE_PENDING_CLEANUP
                log("Event #" .. eventId .. ": cleanup deferred (chunk/player)")
                -- Маркеры убираем сразу, даже если cleanup отложен
                broadcastToClients("PZRC_Events", "eventRemoved", { id = eventId })
                return false, "Cleanup deferred"
            end

            table.remove(storage.events, i)
            log("Removed event #" .. eventId .. " (was " .. event.state .. ")")
            broadcastToClients("PZRC_Events", "eventRemoved", { id = eventId })
            return true
        end
    end

    log("Event #" .. eventId .. " not found")
    return false, "Event not found"
end

-- ---------------------------------------------------------------------------
-- Удалить все события
-- ---------------------------------------------------------------------------

function PZRC_EventManager.removeAll(force)
    local storage = getStorage()
    local count = #storage.events
    local deferred = 0

    for i = count, 1, -1 do
        local event = storage.events[i]
        local cleaned = doCleanup(event, force)
        -- Маркеры убираем сразу для всех событий
        broadcastToClients("PZRC_Events", "eventRemoved", { id = event.id })
        if cleaned then
            table.remove(storage.events, i)
        else
            event.state = PZRC_EventManager.STATE_PENDING_CLEANUP
            deferred = deferred + 1
        end
    end

    local removed = count - deferred
    log("Removed " .. removed .. " events" .. (deferred > 0 and (", " .. deferred .. " deferred") or ""))
    return removed, deferred
end

-- ---------------------------------------------------------------------------
-- Список активных событий
-- ---------------------------------------------------------------------------

function PZRC_EventManager.list()
    local storage = getStorage()
    return storage.events
end

-- ---------------------------------------------------------------------------
-- Проверка: существует ли событие с данным ID
-- ---------------------------------------------------------------------------

function PZRC_EventManager.exists(eventId)
    local storage = getStorage()
    for _, event in ipairs(storage.events) do
        if event.id == eventId then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Tick: инициализация pending, retry pending_cleanup, proximity check, TTL
-- ---------------------------------------------------------------------------

local function tick()
    local storage = getStorage()
    local now = os.time()
    local ttlSec = PZRC_EventConfig.TTL_HOURS * 3600
    local toRemove = {}

    for _, event in ipairs(storage.events) do
        -- 1. Pending: пробуем инициализировать если чанк загрузился
        if event.state == PZRC_EventManager.STATE_PENDING then
            tryInitialize(event)
        end

        -- 2. Pending cleanup: повторяем cleanup, но не на глазах у игрока (15 тайлов)
        if event.state == PZRC_EventManager.STATE_PENDING_CLEANUP then
            if isChunkLoaded(event.x, event.y, event.z) then
                if not PZRC_EventUtils.isPlayerNearby(event.x, event.y, 15) then
                    local cleaned = doCleanup(event, true)
                    if cleaned then
                        table.insert(toRemove, event.id)
                    end
                end
            end
        end

        -- 3. Spawned: proximity check → переводим в visited
        if event.state == PZRC_EventManager.STATE_SPAWNED then
            if PZRC_EventUtils.isPlayerNearby(event.x, event.y, PZRC_EventConfig.VISIT_RADIUS) then
                event.state = PZRC_EventManager.STATE_VISITED
                event.visitedTime = now
                log("Event #" .. event.id .. " visited by a player")
            end
        end

        -- 4. TTL для pending и spawned — cleanup
        if event.state == PZRC_EventManager.STATE_PENDING or event.state == PZRC_EventManager.STATE_SPAWNED then
            if (now - event.spawnTime) > ttlSec then
                table.insert(toRemove, event.id)
            end
        end

        -- 5. TTL для visited — cleanup, но только когда рядом нет игроков
        if event.state == PZRC_EventManager.STATE_VISITED then
            if (now - event.spawnTime) > ttlSec then
                if not PZRC_EventUtils.isPlayerNearby(event.x, event.y, PZRC_EventConfig.VISIT_RADIUS) then
                    table.insert(toRemove, event.id)
                end
            end
        end
    end

    for j = #toRemove, 1, -1 do
        PZRC_EventManager.remove(toRemove[j], true)
    end
end

-- Tick каждые ~30 сек (через EveryTenSeconds + счётчик)
local tickCounter = 0
local function tickThrottled()
    tickCounter = tickCounter + 1
    if tickCounter >= 3 then
        tickCounter = 0
        tick()
    end
end
-- ---------------------------------------------------------------------------
-- Сборщик мусора: при загрузке чанка проверяем осиротевшие объекты
-- Если объект/предмет помечен PZRC_EventId, но такого события нет — удаляем
-- ---------------------------------------------------------------------------

local function onLoadGridsquare(square)
    if not square then return end

    local objsToRemove = {}
    for i = 0, square:getObjects():size() - 1 do
        local obj = square:getObjects():get(i)
        local objEventId = obj:getModData().PZRC_EventId

        -- 1. Объект создан событием (ящик, палатка) — удаляем целиком
        if objEventId and not PZRC_EventManager.exists(objEventId) then
            table.insert(objsToRemove, obj)
        end

        -- 2. Предметы в контейнере — удаляем осиротевшие независимо от пометки объекта
        local container = obj:getContainer()
        if container then
            local itemsToRemove = {}
            for j = 0, container:getItems():size() - 1 do
                local item = container:getItems():get(j)
                local itemEventId = item:getModData().PZRC_EventId
                if itemEventId and not PZRC_EventManager.exists(itemEventId) then
                    table.insert(itemsToRemove, item)
                end
            end
            for _, item in ipairs(itemsToRemove) do
                container:Remove(item)
            end
        end
    end

    for _, obj in ipairs(objsToRemove) do
        square:transmitRemoveItemFromSquare(obj)
    end

    -- 3. Предметы на земле (WorldObjects)
    local worldObjsToRemove = {}
    for i = 0, square:getWorldObjects():size() - 1 do
        local wo = square:getWorldObjects():get(i)
        local item = wo:getItem()
        if item then
            local itemEventId = item:getModData().PZRC_EventId
            if itemEventId and not PZRC_EventManager.exists(itemEventId) then
                table.insert(worldObjsToRemove, wo)
            end
        end
    end

    for _, wo in ipairs(worldObjsToRemove) do
        square:removeWorldObject(wo)
    end

    -- 4. Машины (BaseVehicle)
    local vehicle = square:getVehicleContainer()
    if vehicle then
        local eventId = vehicle:getModData().PZRC_EventId
        if eventId and not PZRC_EventManager.exists(eventId) then
            vehicle:permanentlyRemove()
            log("GC: removed orphaned vehicle (eventId=" .. eventId .. ")")
        end
    end

    -- 5. Трупы (IsoDeadBody)
    local bodies = square:getDeadBodys()
    if bodies then
        for i = bodies:size() - 1, 0, -1 do
            local body = bodies:get(i)
            if body then
                local eventId = body:getModData().PZRC_EventId
                if eventId and not PZRC_EventManager.exists(eventId) then
                    square:removeCorpse(body, false)
                    log("GC: removed orphaned corpse (eventId=" .. eventId .. ")")
                end
            end
        end
    end
end

-- Подписки регистрируются в onServerStarted (events недоступны при загрузке файла)

-- ---------------------------------------------------------------------------
-- Автоспавн событий
-- ---------------------------------------------------------------------------

local lastAutoSpawn = 0

function PZRC_EventManager.autoSpawn(force, forceType)
    if not force then
        local now = os.time()
        local intervalSec = PZRC_EventConfig.AUTO_SPAWN_INTERVAL_MINUTES * 60

        if (now - lastAutoSpawn) < intervalSec then return end
        lastAutoSpawn = now
    else
        lastAutoSpawn = os.time()  -- сбросим таймер и при force, чтобы следующий авто не был слишком скоро
        log("AutoSpawn: FORCED" .. (forceType and (" type=" .. forceType) or " (random weighted)"))
    end

    -- Онлайн-гейт: нет игроков — не тратим ресурсы
    local players = getOnlinePlayers()
    if not players or players:size() == 0 then
        log("AutoSpawn: no online players, skipping")
        return
    end

    -- Собираем типы с весами из конфига
    local allowedTypes = PZRC_EventConfig.AUTO_SPAWN_TYPES
    if not allowedTypes or #allowedTypes == 0 then
        log("AutoSpawn: no types configured")
        return
    end

    local availableTypes = {}
    local totalWeight = 0
    for _, entry in ipairs(allowedTypes) do
        local typeName = type(entry) == "table" and entry.type or entry
        local weight = type(entry) == "table" and (entry.weight or 1) or 1
        local handler = PZRC_EventRegistry.get(typeName)
        if handler then
            table.insert(availableTypes, { type = typeName, weight = weight, handler = handler })
            totalWeight = totalWeight + weight
        end
    end

    if totalWeight == 0 then
        log("AutoSpawn: no registered event types")
        return
    end

    local picked
    if forceType then
        -- Форсированный тип: ищем в availableTypes
        local forceLower = forceType:lower()
        for _, entry in ipairs(availableTypes) do
            if entry.type == forceLower then picked = entry; break end
        end
        if not picked then
            -- Тип не в AUTO_SPAWN_TYPES, но может быть зарегистрирован
            local handler = PZRC_EventRegistry.get(forceLower)
            if handler then
                picked = { type = forceLower, weight = 1, handler = handler }
            else
                log("AutoSpawn: unknown forced type '" .. forceType .. "'")
                return
            end
        end
    else
        -- Взвешенный случайный выбор
        local roll = ZombRand(totalWeight)
        local cumulative = 0
        picked = availableTypes[#availableTypes]
        for _, entry in ipairs(availableTypes) do
            cumulative = cumulative + entry.weight
            if roll < cumulative then picked = entry; break end
        end
    end

    local req = picked.handler.spawnRequirements or { biome = "any" }
    log("AutoSpawn: type=" .. picked.type .. " req=" .. tostring(req.biome or "any")
        .. (req.needsBuilding and " needsBuilding" or "")
        .. (req.roadMaxDist and (" road<=" .. req.roadMaxDist) or ""))

    local location, err = PZRC_EventUtils.pickSpawnLocation(req)
    if not location then
        log("AutoSpawn: pickSpawnLocation failed — " .. tostring(err))
        return
    end

    local event, spawnErr = PZRC_EventManager.spawn(picked.type, location.x, location.y, 0, "auto")
    if event then
        log("AutoSpawn: spawned " .. picked.type .. " at " .. location.x .. "," .. location.y
            .. " (region=" .. tostring(location.class and location.class.region) .. ")")
    else
        log("AutoSpawn: spawn failed — " .. tostring(spawnErr))
    end
end

-- ---------------------------------------------------------------------------
-- Инициализация: все подписки на events регистрируются после старта сервера
-- ---------------------------------------------------------------------------

local SZ_VERSION = "0.4.2"

-- Fast proximity-only check: walks SPAWNED events on every OnTick frame, but
-- throttled by getTimestampMs() so the body runs about once every N seconds
-- (sandbox-controlled). Keeps the heavy tick (TTL / cleanup / GC) at 1 minute.
local lastVisitCheckMs = 0
local function fastVisitCheck()
    local interval = PZRC_Config.sbox("EventVisitCheckIntervalSeconds", 5) * 1000
    local now = getTimestampMs()
    if now - lastVisitCheckMs < interval then return end
    lastVisitCheckMs = now

    local storage = getStorage()
    if not storage.events or #storage.events == 0 then return end

    local visitRadius = PZRC_EventConfig.VISIT_RADIUS
    local nowEpoch = os.time()
    for _, event in ipairs(storage.events) do
        if event.state == PZRC_EventManager.STATE_SPAWNED
           and PZRC_EventUtils.isPlayerNearby(event.x, event.y, visitRadius) then
            event.state = PZRC_EventManager.STATE_VISITED
            event.visitedTime = nowEpoch
            log("Event #" .. event.id .. " visited by a player (fast tick)")
        end
    end
end

local function onServerStarted()
    loadEventMessages()

    -- Регистрируем только существующие events
    if Events.EveryTenSeconds then
        Events.EveryTenSeconds.Add(tickThrottled)
        log("Registered tick on EveryTenSeconds")
    elseif Events.EveryOneMinute then
        Events.EveryOneMinute.Add(tick)
        log("Registered tick on EveryOneMinute (EveryTenSeconds unavailable)")
    end

    -- Fast SPAWNED→VISITED proximity check (every ~5s, throttled inside)
    if Events.OnTick then
        Events.OnTick.Add(fastVisitCheck)
        log("Registered fast visit-check on OnTick")
    end

    if Events.LoadGridsquare then
        Events.LoadGridsquare.Add(onLoadGridsquare)
        log("Registered GC on LoadGridsquare")
    end

    if Events.EveryOneMinute then
        Events.EveryOneMinute.Add(function() PZRC_EventManager.autoSpawn(false) end)
        log("Registered autoSpawn on EveryOneMinute")
    end

    log("PZRC_EventManager v" .. SZ_VERSION .. " initialized")
end

Events.OnServerStarted.Add(onServerStarted)
log("PZRC_EventManager v" .. SZ_VERSION .. " loaded")
