require "PZRC_Utils"

PZRC_StarterKitClient = PZRC_StarterKitClient or {}

local CRATE_SPRITES = {
    [0] = "planb_01_8",
    [1] = "planb_01_9",
}
local crateRotation = 0

-------------------------------------------------
-- Utils
-------------------------------------------------

local function isSupplyCrate(obj)
    if not obj then return false end
    local md = obj:getModData()
    return md and md.PZRC_StarterKit_Crate == true
end

local function findSupplyCrate(worldobjects)
    for _, obj in ipairs(worldobjects) do
        if isSupplyCrate(obj) then return obj end
        local sq = obj:getSquare()
        if sq then
            for i = 0, sq:getObjects():size() - 1 do
                local sqObj = sq:getObjects():get(i)
                if isSupplyCrate(sqObj) then return sqObj end
            end
        end
    end
    return nil
end

local function getSquareFromObjects(worldobjects)
    for _, obj in ipairs(worldobjects) do
        local sq = obj:getSquare()
        if sq then return sq end
    end
    return nil
end

local function isAdmin(playerObj)
    local level = playerObj:getAccessLevel()
    return level == "Admin" or level == "admin"
end

-------------------------------------------------
-- Actions
-------------------------------------------------

local function doPlaceCrate(_playerObj, square)
    local cell = getCell()
    if not cell or not square then return end

    local spriteName = CRATE_SPRITES[crateRotation] or CRATE_SPRITES[0]
    local obj = IsoObject.new(cell, square, spriteName)
    obj:getModData().PZRC_StarterKit_Crate = true
    obj:setName("SupplyCrate")

    square:AddSpecialObject(obj)
    obj:transmitCompleteItemToServer()
end

local function doRotateCrate(playerObj, _square)
    crateRotation = (crateRotation + 1) % 2
    playerObj:Say(getText("IGUI_PZRC_StarterKit_Rotated"))
end

local function doRemoveCrate(_playerObj, crate)
    local sq = crate:getSquare()
    if sq then
        sq:transmitRemoveItemFromSquare(crate)
    end
end

local function doClaimKit(playerObj, _crate)
    sendClientCommand(playerObj, "PZRC_StarterKit", "claimKit", {})
end

-------------------------------------------------
-- Context menu
-------------------------------------------------

local function onFillWorldObjectContextMenu(playerIndex, context, worldobjects, test)
    if test then return end

    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj then return end

    local square = getSquareFromObjects(worldobjects)
    if not square then return end

    local crate = findSupplyCrate(worldobjects)

    if crate then
        local claimOpt = context:addOption(
            getText("IGUI_PZRC_StarterKit_Claim"),
            playerObj, doClaimKit, crate
        )

        local md = playerObj:getModData()
        if md.PZRC_StarterKit_Received then
            claimOpt.notAvailable = true
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip.description = getText("IGUI_PZRC_StarterKit_AlreadyReceived")
            claimOpt.toolTip = tip
        elseif md.PZRC_StarterKit_SteamCooldownHours and md.PZRC_StarterKit_SteamCooldownHours > 0 then
            claimOpt.notAvailable = true
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip.description = getText("IGUI_PZRC_StarterKit_Cooldown",
                tostring(md.PZRC_StarterKit_SteamCooldownHours))
            claimOpt.toolTip = tip
        end

        if isAdmin(playerObj) then
            local section = PZRC_ContextMenu.getSection(context, "StarterKit")
            section:addOption(
                getText("IGUI_PZRC_StarterKit_Remove"),
                playerObj, doRemoveCrate, crate
            )
        end
    elseif isAdmin(playerObj) then
        local section = PZRC_ContextMenu.getSection(context, "StarterKit")
        section:addOption(
            getText("IGUI_PZRC_StarterKit_Place"),
            playerObj, doPlaceCrate, square
        )
        section:addOption(
            getText("IGUI_PZRC_StarterKit_Rotate"),
            playerObj, doRotateCrate, square
        )
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

-------------------------------------------------
-- Server responses
-------------------------------------------------

local function onServerCommand(module, command, args)
    if module ~= "PZRC_StarterKit" then return end

    local playerObj = getSpecificPlayer(0)
    if not playerObj then return end

    if command == "kitGranted" then
        playerObj:getModData().PZRC_StarterKit_Received = true
        playerObj:Say(getText("IGUI_PZRC_StarterKit_Received"))

    elseif command == "kitDenied" then
        if args.reason == "Cooldown" then
            playerObj:Say(getText("IGUI_PZRC_StarterKit_Cooldown", tostring(args.extra or "?")))
        else
            playerObj:Say(getText("IGUI_PZRC_StarterKit_AlreadyReceived"))
        end

    elseif command == "state" then
        local md = playerObj:getModData()
        md.PZRC_StarterKit_Received = args.claimedByCharacter and true or nil
        md.PZRC_StarterKit_SteamCooldownHours = args.steamCooldownHours

    elseif command == "kitReset" then
        local md = playerObj:getModData()
        md.PZRC_StarterKit_Received = nil
        md.PZRC_StarterKit_SteamCooldownHours = nil
        print("[PZRC_StarterKit] Your kit has been reset")

    elseif command == "resetDone" then
        print("[PZRC_StarterKit] Kit reset: " .. tostring(args.target))

    elseif command == "resetFail" then
        print("[PZRC_StarterKit] Player not found: " .. tostring(args.target))
    end
end

Events.OnServerCommand.Add(onServerCommand)

-------------------------------------------------
-- Chat commands: /resetkit, /radio
-------------------------------------------------

local function hookChat()
    local chat = ISChat.instance
    if not chat or not chat.textEntry then return end

    local origFn = chat.textEntry.onCommandEntered
    local function hookedOnCommandEntered(self)
        local text = chat.textEntry:getText()
        if not text then return origFn(self) end

        local target = text:match("^/resetkit%s+(%S+)")
        if target then
            local playerObj = getSpecificPlayer(0)
            if playerObj and isAdmin(playerObj) then
                sendClientCommand(playerObj, "PZRC_StarterKit", "resetKit", { target = target })
            end
            chat.textEntry:setText("")
            chat:unfocus()
            return
        end

        local freq, msg = text:match("^/radio%s+([%d%.]+)%s+(.+)")
        if freq and msg then
            local playerObj = getSpecificPlayer(0)
            if playerObj and isAdmin(playerObj) then
                sendClientCommand(playerObj, "PZRC_Radio", "broadcast", {
                    freq = freq,
                    text = msg,
                })
            end
            chat.textEntry:setText("")
            chat:unfocus()
            return
        end

        origFn(self)
    end

    chat.textEntry.onCommandEntered = hookedOnCommandEntered
end

Events.OnGameStart.Add(hookChat)

local function requestSyncState()
    local playerObj = getSpecificPlayer(0)
    if not playerObj then return end
    sendClientCommand(playerObj, "PZRC_StarterKit", "syncState", {})
end
Events.OnGameStart.Add(requestSyncState)
