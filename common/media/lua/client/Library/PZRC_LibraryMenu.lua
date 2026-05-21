require "PZRC_Utils"

-- =========================================================================
-- Library — admin marks shelves; library books are non-transferable except
-- between shelf and player inventory, and "drop to floor" destroys the book
-- (the server respawns it on a marked shelf during the next restock tick).
-- =========================================================================

local function findContainerObject(worldobjects)
    for _, obj in ipairs(worldobjects) do
        if obj:getContainer() then
            return obj
        end
        local square = obj:getSquare()
        if square then
            for i = 0, square:getObjects():size() - 1 do
                local sqObj = square:getObjects():get(i)
                if sqObj:getContainer() then
                    return sqObj
                end
            end
        end
    end
    return nil
end

local function onMarkShelf(playerNum, obj)
    local playerObj = getSpecificPlayer(playerNum)
    local sq = obj:getSquare()
    sendClientCommand(playerObj, "PZRC_Library", "mark", {
        x = sq:getX(), y = sq:getY(), z = sq:getZ(),
    })
    playerObj:addLineChatElement("Shelf marked as Library", 0.2, 1, 0.2)
end

local function onUnmarkShelf(playerNum, obj)
    local playerObj = getSpecificPlayer(playerNum)
    local sq = obj:getSquare()
    sendClientCommand(playerObj, "PZRC_Library", "unmark", {
        x = sq:getX(), y = sq:getY(), z = sq:getZ(),
    })
    playerObj:addLineChatElement("Shelf unmarked", 1, 1, 0.2)
end

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    if test then return end
    if not PZRC_Utils.IsAdminPlayer() then return end

    local obj = findContainerObject(worldobjects)
    if not obj then return end

    local data = obj:getModData()
    local section = PZRC_ContextMenu.getSection(context, "Library")
    if data and data.PZRC_LibraryShelf then
        section:addOption("Unmark Library Shelf", player, onUnmarkShelf, obj)
    else
        section:addOption("Mark as Library Shelf", player, onMarkShelf, obj)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

-- ----- Transfer restriction ----------------------------------------------

local function isLibraryShelf(container)
    if not container then return false end
    local parent = container:getParent()
    if not parent then return false end
    if not parent.getModData then return false end
    local data = parent:getModData()
    return data and data.PZRC_LibraryShelf == true
end

local function isPlayerMainInventory(container, character)
    return container == character:getInventory()
end

if ISInventoryTransferAction and ISInventoryTransferAction.isValid then
    local _origIsValid = ISInventoryTransferAction.isValid

    function ISInventoryTransferAction:isValid()
        if self.item and self.item.getModData then
            local md = self.item:getModData()
            if md and md.PZRC_LibraryBook then
                local src = self.srcContainer
                local dst = self.destContainer
                local srcIsShelf = isLibraryShelf(src)
                local dstIsShelf = isLibraryShelf(dst)
                local dstIsPlayer = isPlayerMainInventory(dst, self.character)
                local srcIsPlayer = isPlayerMainInventory(src, self.character)

                if (srcIsShelf and dstIsPlayer) or (srcIsPlayer and dstIsShelf) then
                    return _origIsValid(self)
                end

                -- Drop to floor — destroy the book, it will respawn on shelf
                if srcIsPlayer then
                    if not self._pzrcLibraryDestroySent then
                        self._pzrcLibraryDestroySent = true
                        sendClientCommand(self.character, "PZRC_Library", "destroyBook", {
                            itemId = self.item:getID(),
                        })
                        self.character:addLineChatElement(
                            "The book returned to the library shelf.",
                            0.6, 0.8, 1
                        )
                    end
                    return false
                end

                -- Block everything else (bag, car, other container)
                self.character:addLineChatElement(
                    "This book belongs to the library.",
                    1, 0.3, 0.3
                )
                return false
            end
        end
        return _origIsValid(self)
    end
end

-- ----- "Place Item" cursor restriction ------------------------------------
-- Drop goes through ISInventoryTransferAction (handled above), but the
-- "Place item on ground" context option spawns ISPlace3DItemCursor which
-- queues ISDropWorldItemAction directly — bypassing the transfer hook.
-- Block library books at both layers: the menu entry (so the cursor never
-- starts) and the action itself (safety net for any other code path).

local function isLibraryBook(item)
    if not item or not item.getModData then return false end
    local md = item:getModData()
    return md and md.PZRC_LibraryBook == true
end

if ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.onPlaceItemOnGround then
    local _origOnPlace = ISInventoryPaneContextMenu.onPlaceItemOnGround

    ISInventoryPaneContextMenu.onPlaceItemOnGround = function(items, playerObj)
        local filtered = {}
        local blocked = false
        for _, item in ipairs(items) do
            if isLibraryBook(item) then
                blocked = true
            else
                table.insert(filtered, item)
            end
        end
        if blocked and playerObj then
            playerObj:addLineChatElement(
                "This book belongs to the library.",
                1, 0.3, 0.3
            )
        end
        if #filtered == 0 then return end
        return _origOnPlace(filtered, playerObj)
    end
end

if ISDropWorldItemAction and ISDropWorldItemAction.isValid then
    local _origDropIsValid = ISDropWorldItemAction.isValid

    function ISDropWorldItemAction:isValid()
        if isLibraryBook(self.item) then
            if not self._pzrcLibraryNotified then
                self._pzrcLibraryNotified = true
                self.character:addLineChatElement(
                    "This book belongs to the library.",
                    1, 0.3, 0.3
                )
            end
            return false
        end
        return _origDropIsValid(self)
    end
end
