local function log(msg)
    print("[EventCmdClient] " .. tostring(msg))
end

local function isAdmin(playerObj)
    local level = playerObj:getAccessLevel()
    return level == "Admin" or level == "admin"
end

-- ---------------------------------------------------------------------------
-- Маркеры на карте (SafeZone events)
-- ---------------------------------------------------------------------------

local PZRC_EventMarkers = {}
PZRC_EventMarkers.pendingEvents = {}   -- {id -> {id, type, x, y}} — события, о которых узнали от сервера
PZRC_EventMarkers.activeMarkers = {}   -- {id -> {icon, zone}} — маркеры на карте (только если игрок слышал радио)
PZRC_EventMarkers.MARKER_RADIUS = 50
PZRC_EventMarkers.MARKER_R = 0.2
PZRC_EventMarkers.MARKER_G = 0.8
PZRC_EventMarkers.MARKER_B = 0.2
PZRC_EventMarkers.MARKER_A = 0.6

--- Запомнить событие от сервера (маркер НЕ ставим, ждём радио)
function PZRC_EventMarkers.addPending(id, typeName, x, y)
    PZRC_EventMarkers.pendingEvents[id] = { id = id, type = typeName, x = x, y = y }
    log("Pending event #" .. id .. " (" .. typeName .. ") at " .. x .. "," .. y)
end

--- Удалить маркер и pending
function PZRC_EventMarkers.removeEvent(id)
    PZRC_EventMarkers.pendingEvents[id] = nil
    local marker = PZRC_EventMarkers.activeMarkers[id]
    if marker then
        -- Удаляем зону через API если карта открыта
        if marker.zone then
            local worldMap = _G.ISWorldMap_instance or (ISWorldMap and ISWorldMap.instance) or nil
            if worldMap and worldMap.mapAPI then
                local markersAPI = worldMap.mapAPI.getMarkersAPI and worldMap.mapAPI:getMarkersAPI() or nil
                if markersAPI then
                    pcall(function() markersAPI:removeMarker(marker.zone) end)
                end
            end
        end
        PZRC_EventMarkers.activeMarkers[id] = nil
        PZRC_EventMarkers.zonesCreated = false  -- пересоздадим при следующем открытии карты
        log("Marker removed for event #" .. id)
    end
end

--- Создать маркер для события (вызывается когда игрок услышал радио)
function PZRC_EventMarkers.activateMarker(id)
    if PZRC_EventMarkers.activeMarkers[id] then return end
    local ev = PZRC_EventMarkers.pendingEvents[id]
    if not ev then return end
    PZRC_EventMarkers.activeMarkers[id] = { x = ev.x, y = ev.y, type = ev.type }
    log("Marker activated for event #" .. id .. " at " .. ev.x .. "," .. ev.y)
end

--- Перерисовать все маркеры на карте
PZRC_EventMarkers.zonesCreated = false

function PZRC_EventMarkers.renderMarkers()
    local worldMap = _G.ISWorldMap_instance or (ISWorldMap and ISWorldMap.instance) or nil
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

    if PZRC_EventMarkers.zonesCreated then return end

    local count = 0
    for id, data in pairs(PZRC_EventMarkers.activeMarkers) do
        if not data.zone then
            local zone = markersAPI:addGridSquareMarker(
                math.floor(data.x), math.floor(data.y),
                PZRC_EventMarkers.MARKER_RADIUS,
                PZRC_EventMarkers.MARKER_R, PZRC_EventMarkers.MARKER_G, PZRC_EventMarkers.MARKER_B, PZRC_EventMarkers.MARKER_A
            )
            if zone then
                data.zone = zone
                count = count + 1
            end
        end
    end

    if count > 0 then
        PZRC_EventMarkers.zonesCreated = true
        log("Created " .. count .. " map zones")
    end
end

--- Очистить все маркеры SafeZone (при входе в игру)
function PZRC_EventMarkers.clearAll()
    PZRC_EventMarkers.pendingEvents = {}
    PZRC_EventMarkers.activeMarkers = {}
    PZRC_EventMarkers.zonesCreated = false
    log("All markers cleared")
end

-- ---------------------------------------------------------------------------
-- Патч ISWorldMap: перерисовка маркеров при открытии карты
-- ---------------------------------------------------------------------------

local function patchWorldMap()
    if PZRC_EventMarkers._showWorldMapPatched then return end
    if not ISWorldMap or not ISWorldMap.ShowWorldMap then return end

    local orig = ISWorldMap.ShowWorldMap
    ISWorldMap.ShowWorldMap = function(playerNum, centerX, centerY, zoom)
        orig(playerNum, centerX, centerY, zoom)
        PZRC_EventMarkers.zonesCreated = false  -- пересоздаём маркеры при каждом открытии
        PZRC_EventMarkers.renderMarkers()
    end
    PZRC_EventMarkers._showWorldMapPatched = true
    log("ISWorldMap patched for markers")
end

-- ---------------------------------------------------------------------------
-- Events.OnDeviceText: игрок слышит радио → ищем координаты → активируем маркер
-- ---------------------------------------------------------------------------

local function onDeviceText(_guid, _interactCodes, _x, _y, _z, _line)
    if not _line or type(_line) ~= "string" then return end

    -- Ищем координаты в тексте радио: "число, число" или "число,число"
    for coordX, coordY in _line:gmatch("(%d+),%s*(%d+)") do
        local cx = tonumber(coordX)
        local cy = tonumber(coordY)
        if cx and cy then
            -- Сопоставляем с pending-событиями
            for id, ev in pairs(PZRC_EventMarkers.pendingEvents) do
                if ev.x == cx and ev.y == cy and not PZRC_EventMarkers.activeMarkers[id] then
                    PZRC_EventMarkers.activateMarker(id)
                    PZRC_EventMarkers.zonesCreated = false
                end
            end
        end
    end
end

-- Подписка перенесена в onGameStart (Events.OnDeviceText может не существовать при загрузке)

-- ---------------------------------------------------------------------------
-- Обработка ответов от сервера
-- ---------------------------------------------------------------------------

local function onServerCommand(module, command, args)
    if module ~= "PZRC_Events" then return end

    if command == "result" then
        log(tostring(args.text))

    elseif command == "eventNotify" then
        -- Сервер сообщает о новом событии
        PZRC_EventMarkers.addPending(args.id, args.type, args.x, args.y)

    elseif command == "eventRemoved" then
        -- Сервер удалил событие — убираем маркер
        PZRC_EventMarkers.removeEvent(args.id)
    end
end

Events.OnServerCommand.Add(onServerCommand)

-- ---------------------------------------------------------------------------
-- Парсинг команды /event
-- ---------------------------------------------------------------------------

local function parseEventCommand(text)
    -- /event spawn <type> [x y]
    -- /event list
    -- /event remove <id>
    -- /event removeall
    -- /event types

    local parts = {}
    for token in text:gmatch("%S+") do
        table.insert(parts, token)
    end

    -- parts[1] = "/event"
    if #parts < 2 then return nil end

    local sub = parts[2]:lower()

    if sub == "spawn" then
        if #parts < 3 then
            return nil, "Usage: /event spawn <type> [x y]"
        end
        local cmd = { command = "spawn", type = parts[3] }
        if parts[4] and parts[5] then
            cmd.x = parts[4]
            cmd.y = parts[5]
        end
        return cmd

    elseif sub == "list" then
        return { command = "list" }

    elseif sub == "remove" then
        if #parts < 3 then
            return nil, "Usage: /event remove <id>"
        end
        return { command = "remove", id = parts[3] }

    elseif sub == "removeall" then
        return { command = "removeall" }

    elseif sub == "types" then
        return { command = "types" }

    elseif sub == "scanmap" then
        return { command = "scanmap" }

    elseif sub == "coverage" then
        local cmd = { command = "coverage" }
        if parts[3] then cmd.n = parts[3] end
        return cmd

    elseif sub == "autospawn" then
        local cmd = { command = "autospawn" }
        if parts[3] then cmd.type = parts[3] end
        return cmd
    end

    return nil, "Unknown subcommand: " .. sub
        .. ". Available: spawn, list, remove, removeall, types, scanmap, coverage, autospawn"
end

-- ---------------------------------------------------------------------------
-- Хук чата: цепочка с существующим хуком
-- ---------------------------------------------------------------------------

local function hookChat()
    local chat = ISChat.instance
    if not chat or not chat.textEntry then return end

    -- Сохраняем предыдущий хук (может быть от StarterKitClient)
    local previousFn = chat.textEntry.onCommandEntered

    local function hookedOnCommandEntered(self)
        local text = chat.textEntry:getText()
        if not text then return previousFn(self) end

        -- Проверяем /event
        if text:match("^/event%s") or text == "/event" then
            local playerObj = getSpecificPlayer(0)

            if not playerObj or not isAdmin(playerObj) then
                log("Admin access required")
                chat.textEntry:setText("")
                chat:unfocus()
                return
            end

            local cmd, err = parseEventCommand(text)
            if cmd then
                sendClientCommand(playerObj, "PZRC_Events", cmd.command, cmd)
            else
                log(err or "Usage: /event <spawn|list|remove|removeall|types>")
            end

            chat.textEntry:setText("")
            chat:unfocus()
            return
        end

        -- Передаём в предыдущий хук
        return previousFn(self)
    end

    chat.textEntry.onCommandEntered = hookedOnCommandEntered
    log("Chat hook installed")
end

-- ---------------------------------------------------------------------------
-- Инициализация при старте игры
-- ---------------------------------------------------------------------------

local function onGameStart()
    -- Очищаем маркеры от прошлой сессии
    PZRC_EventMarkers.clearAll()

    -- Хук чата
    hookChat()

    -- Патч карты
    patchWorldMap()

    -- Подписка на радио-текст (Events.OnDeviceText может не существовать при первичной загрузке lua)
    if Events.OnDeviceText then
        Events.OnDeviceText.Add(onDeviceText)
        log("OnDeviceText hook installed")
    else
        log("WARN: Events.OnDeviceText not available")
    end
end

Events.OnGameStart.Add(onGameStart)
local SZ_VERSION = "0.4.3"
log("EventCommandsClient v" .. SZ_VERSION .. " loaded")
