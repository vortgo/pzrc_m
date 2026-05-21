PZRC_EventRegistry = PZRC_EventRegistry or {}
PZRC_EventRegistry.types = {}

local function log(msg)
    print("[PZRC_EventRegistry] " .. tostring(msg))
end

--- Регистрация типа события
--- @param name string     уникальное имя (lowercase)
--- @param handler table   { validate, spawn, cleanup, getDescription }
function PZRC_EventRegistry.register(name, handler)
    local key = name:lower()
    if PZRC_EventRegistry.types[key] then
        log("WARNING: overwriting type '" .. key .. "'")
    end
    PZRC_EventRegistry.types[key] = handler
    log("Registered type: " .. key)
end

--- Получение handler по имени
--- @param name string
--- @return table|nil
function PZRC_EventRegistry.get(name)
    return PZRC_EventRegistry.types[name:lower()]
end

--- Список зарегистрированных типов
--- @return table  массив имён
function PZRC_EventRegistry.list()
    local names = {}
    for k, _ in pairs(PZRC_EventRegistry.types) do
        table.insert(names, k)
    end
    table.sort(names)
    return names
end
