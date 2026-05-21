if not isServer() then return end

-- =========================================================================
-- Library — periodic book respawn on admin-marked shelves with dedup.
-- Shelves persistence lives in getGameTime():getModData() (no external .txt).
-- =========================================================================

local function restockIntervalMs()
    return PZRC_Config.sbox("LibraryRestockIntervalMinutes", 5) * 60 * 1000
end
local lastRestockTime = 0

local shelves = {}        -- {{x=, y=, z=}, ...}
local shelvesIndex = {}   -- "x,y,z" -> true

local LIBRARY_BOOKS = {
    "Base.BookCarpentry1",
    "Base.BookCarving1",
    "Base.BookCooking1",
    "Base.BookElectrician1",
    "Base.BookFarming1",
    "Base.BookFirstAid1",
    "Base.BookFishing1",
    "Base.BookFlintKnapping1",
    "Base.BookForaging1",
    "Base.BookGlassmaking1",
    "Base.BookMasonry1",
    "Base.BookMechanic1",
    "Base.BookMetalWelding1",
    "Base.BookBlacksmith1",
    "Base.BookPottery1",
    "Base.BookTailoring1",
    "Base.BookTrapping1",
    "Base.BookAiming1",
    "Base.BookReloading1",
    "Base.BookHusbandry1",
    "Base.BookButchering1",
    "Base.BookTracking1",
    "Base.BookLongBlade1",
    "Base.BookMaintenance1",
}

local function log(msg)
    print("[PZRC_Library] " .. tostring(msg))
end

-- ----- Persistence (getGameTime ModData) ----------------------------------

local function shelfKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function getStorage()
    local md = getGameTime():getModData()
    if not md.PZRC_Library then
        md.PZRC_Library = { shelves = {} }
    end
    md.PZRC_Library.shelves = md.PZRC_Library.shelves or {}
    return md.PZRC_Library
end

local function loadShelves()
    local store = getStorage()
    shelves = {}
    for _, s in ipairs(store.shelves) do
        if type(s) == "table" and s.x and s.y and s.z then
            table.insert(shelves, { x = s.x, y = s.y, z = s.z })
        end
    end
    log("Loaded " .. #shelves .. " shelves from ModData")
end

local function saveShelves()
    local store = getStorage()
    local out = {}
    for _, s in ipairs(shelves) do
        table.insert(out, { x = s.x, y = s.y, z = s.z })
    end
    store.shelves = out
    log("Saved " .. #shelves .. " shelves to ModData")
end

-- ----- Helpers -----------------------------------------------------------

local function findContainerAt(x, y, z)
    local square = getSquare(x, y, z)
    if not square then return nil, nil end
    for i = 0, square:getObjects():size() - 1 do
        local obj = square:getObjects():get(i)
        if obj:getContainer() then
            return obj, obj:getContainer()
        end
    end
    return nil, nil
end

-- ----- Command handler ---------------------------------------------------

local function onClientCommand(module, command, player, args)
    if module ~= "PZRC_Library" then return end

    local username = player:getUsername()

    -- destroyBook — any player can return a library book
    if command == "destroyBook" then
        local itemId = tonumber(args.itemId)
        if not itemId then return end
        local inv = player:getInventory()
        local items = inv:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item:getID() == itemId and item:getModData().PZRC_LibraryBook then
                local fullType = item:getFullType()
                sendRemoveItemFromContainer(inv, item)
                inv:Remove(item)
                log(username .. " returned library book: " .. fullType)
                return
            end
        end
        return
    end

    -- Admin-only below
    if not PZRC_Utils.isAdminAccess(player) then
        log("WARN: non-admin " .. username .. " attempted library command: " .. command)
        return
    end

    local x = tonumber(args.x)
    local y = tonumber(args.y)
    local z = tonumber(args.z)
    if not x or not y or not z then return end

    if command == "mark" then
        local obj, _ = findContainerAt(x, y, z)
        if not obj then
            log("mark: No container at " .. x .. "," .. y .. "," .. z)
            return
        end
        obj:getModData().PZRC_LibraryShelf = true
        obj:transmitModData()

        local key = shelfKey(x, y, z)
        if shelvesIndex[key] then
            log(username .. " shelf already marked at " .. key)
            return
        end
        table.insert(shelves, { x = x, y = y, z = z })
        shelvesIndex[key] = true
        saveShelves()
        log(username .. " marked shelf at " .. key)

    elseif command == "unmark" then
        local obj, container = findContainerAt(x, y, z)
        if obj then
            obj:getModData().PZRC_LibraryShelf = nil
            obj:transmitModData()

            if container then
                local toRemove = {}
                local items = container:getItems()
                for i = 0, items:size() - 1 do
                    local item = items:get(i)
                    if item:getModData().PZRC_LibraryBook then
                        table.insert(toRemove, item)
                    end
                end
                for _, item in ipairs(toRemove) do
                    sendRemoveItemFromContainer(container, item)
                    container:Remove(item)
                end
                if #toRemove > 0 then
                    pcall(obj.sendObjectChange, obj, "containers")
                    if ItemPicker and ItemPicker.updateOverlaySprite then
                        ItemPicker.updateOverlaySprite(obj)
                    end
                end
            end
        end

        local key = shelfKey(x, y, z)
        for i = #shelves, 1, -1 do
            if shelfKey(shelves[i].x, shelves[i].y, shelves[i].z) == key then
                table.remove(shelves, i)
            end
        end
        shelvesIndex[key] = nil
        saveShelves()
        log(username .. " unmarked shelf at " .. key)
    end
end

-- ----- Restock -----------------------------------------------------------

local function restockLibrary()
    if #shelves == 0 then return end

    local shelfContainers = {}
    for _, s in ipairs(shelves) do
        local obj, container = findContainerAt(s.x, s.y, s.z)
        if obj and container then
            table.insert(shelfContainers, { container = container, obj = obj })
        end
    end

    if #shelfContainers == 0 then return end

    -- 1) Purge any non-library items from marked shelves (these shelves are
    --    library-exclusive: nothing but PZRC_LibraryBook-flagged items lives here).
    local purged = 0
    local purgeSyncNeeded = {}
    for _, sc in ipairs(shelfContainers) do
        local toRemove = {}
        local items = sc.container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if not item:getModData().PZRC_LibraryBook then
                table.insert(toRemove, item)
            end
        end
        for _, item in ipairs(toRemove) do
            sendRemoveItemFromContainer(sc.container, item)
            sc.container:Remove(item)
        end
        if #toRemove > 0 then
            purgeSyncNeeded[sc.obj] = true
            purged = purged + #toRemove
        end
    end

    -- 2) Map existing library books across all shelves (post-purge state).
    local bookFound = {}
    for _, sc in ipairs(shelfContainers) do
        local items = sc.container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item:getModData().PZRC_LibraryBook then
                local ft = item:getFullType()
                if not bookFound[ft] then bookFound[ft] = {} end
                table.insert(bookFound[ft], { container = sc.container, item = item, obj = sc.obj })
            end
        end
    end

    -- 3) Dedup library books — keep one copy across all shelves.
    local dupsRemoved = 0
    local dedupSyncNeeded = {}
    for _, entries in pairs(bookFound) do
        if #entries > 1 then
            for i = 2, #entries do
                sendRemoveItemFromContainer(entries[i].container, entries[i].item)
                entries[i].container:Remove(entries[i].item)
                dedupSyncNeeded[entries[i].obj] = true
                dupsRemoved = dupsRemoved + 1
            end
        end
    end

    -- 4) Spawn missing books on a random marked shelf.
    local spawned = 0
    local syncNeeded = {}
    for _, bookType in ipairs(LIBRARY_BOOKS) do
        if not bookFound[bookType] or #bookFound[bookType] == 0 then
            local sc = shelfContainers[ZombRand(#shelfContainers) + 1]
            local added = sc.container:AddItem(bookType)
            if added then
                added:getModData().PZRC_LibraryBook = true
                sendAddItemToContainer(sc.container, added)
                syncNeeded[sc.obj] = true
                spawned = spawned + 1
            end
        end
    end

    -- 5) Sync visuals for any shelf that lost or gained items.
    for _, sc in ipairs(shelfContainers) do
        if purgeSyncNeeded[sc.obj] or dedupSyncNeeded[sc.obj] or syncNeeded[sc.obj] then
            pcall(sc.obj.sendObjectChange, sc.obj, "containers")
            if ItemPicker and ItemPicker.updateOverlaySprite then
                ItemPicker.updateOverlaySprite(sc.obj)
            end
        end
    end

    if spawned > 0 or dupsRemoved > 0 or purged > 0 then
        log("Restock: spawned " .. spawned
            .. ", removed " .. dupsRemoved .. " duplicates"
            .. ", purged " .. purged .. " non-library items")
    end
end

local function tickRestock()
    local now = getTimestampMs()
    if now - lastRestockTime < restockIntervalMs() then return end
    lastRestockTime = now
    restockLibrary()
end

-- ----- Chunk load: dedup on loaded shelf ----------------------------------

local function buildShelvesIndex()
    shelvesIndex = {}
    for _, s in ipairs(shelves) do
        shelvesIndex[shelfKey(s.x, s.y, s.z)] = true
    end
end

local function restockShelf(obj, container)
    -- Purge non-library items + dedup library duplicates on this single shelf.
    -- Cross-shelf restock happens on the periodic tick.
    local existing = {}
    local changed = false
    local items = container:getItems()
    local toRemove = {}
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getModData().PZRC_LibraryBook then
            local ft = item:getFullType()
            if existing[ft] then
                table.insert(toRemove, item)
            else
                existing[ft] = true
            end
        else
            -- Non-library item on a library shelf — remove
            table.insert(toRemove, item)
        end
    end
    for _, item in ipairs(toRemove) do
        sendRemoveItemFromContainer(container, item)
        container:Remove(item)
        changed = true
    end

    if changed then
        pcall(obj.sendObjectChange, obj, "containers")
        if ItemPicker and ItemPicker.updateOverlaySprite then
            ItemPicker.updateOverlaySprite(obj)
        end
    end

    if not obj:getModData().PZRC_LibraryShelf then
        obj:getModData().PZRC_LibraryShelf = true
        obj:transmitModData()
    end
end

local function onLoadGridsquare(square)
    if not square then return end
    if #shelves == 0 then return end

    for i = 0, square:getObjects():size() - 1 do
        local obj = square:getObjects():get(i)
        if obj:getContainer() then
            local sq = obj:getSquare()
            local objKey = shelfKey(sq:getX(), sq:getY(), sq:getZ())
            if shelvesIndex[objKey] then
                restockShelf(obj, obj:getContainer())
            end
        end
    end
end

-- ----- Init --------------------------------------------------------------

local function onServerStarted()
    loadShelves()
    buildShelvesIndex()
    Events.OnClientCommand.Add(onClientCommand)
    Events.LoadGridsquare.Add(onLoadGridsquare)
    log("Library initialized (" .. #shelves .. " shelves, " .. #LIBRARY_BOOKS .. " books)")
end

Events.OnServerStarted.Add(onServerStarted)
Events.OnTickEvenPaused.Add(tickRestock)
log("PZRC_Library module ready")
