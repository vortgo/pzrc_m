require "PZRC_Utils"

PZRC_FridgeClient = PZRC_FridgeClient or {}

local FRIDGE_SPRITES = {
    [0] = "planb_01_10",
    [1] = "planb_01_11",
}
local fridgeRotation = 0

-------------------------------------------------
-- Utils
-------------------------------------------------

local function isFridge(obj)
    if not obj then return false end
    local md = obj:getModData()
    return md and md.PZRC_Fridge == true
end

local function findFridge(worldobjects)
    for _, obj in ipairs(worldobjects) do
        if isFridge(obj) then return obj end
        local sq = obj:getSquare()
        if sq then
            for i = 0, sq:getObjects():size() - 1 do
                local sqObj = sq:getObjects():get(i)
                if isFridge(sqObj) then return sqObj end
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

local function doPlaceFridge(_playerObj, square)
    local cell = getCell()
    if not cell or not square then return end

    local spriteName = FRIDGE_SPRITES[fridgeRotation] or FRIDGE_SPRITES[0]
    local obj = IsoObject.new(cell, square, spriteName)
    obj:getModData().PZRC_Fridge = true
    obj:setName("Fridge")

    square:AddSpecialObject(obj)
    obj:transmitCompleteItemToServer()
end

local function doRotateFridge(playerObj, _square)
    fridgeRotation = (fridgeRotation + 1) % 2
    playerObj:Say(getText("IGUI_PZRC_Fridge_Rotated"))
end

local function doRemoveFridge(_playerObj, fridge)
    local sq = fridge:getSquare()
    if sq then
        sq:transmitRemoveItemFromSquare(fridge)
    end
end

local function doClaimRation(playerObj, _fridge)
    sendClientCommand(playerObj, "PZRC_Fridge", "claimRation", {})
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

    local fridge = findFridge(worldobjects)

    if fridge then
        local claimOpt = context:addOption(
            getText("IGUI_PZRC_Fridge_Claim"),
            playerObj, doClaimRation, fridge
        )

        local md = playerObj:getModData()
        if md.PZRC_Fridge_DaysLeft and md.PZRC_Fridge_DaysLeft > 0 then
            claimOpt.notAvailable = true
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip.description = getText("IGUI_PZRC_Fridge_CooldownDays",
                tostring(md.PZRC_Fridge_DaysLeft))
            claimOpt.toolTip = tip
        end

        if isAdmin(playerObj) then
            local section = PZRC_ContextMenu.getSection(context, "Fridge")
            section:addOption(
                getText("IGUI_PZRC_Fridge_Remove"),
                playerObj, doRemoveFridge, fridge
            )
        end
    elseif isAdmin(playerObj) then
        local section = PZRC_ContextMenu.getSection(context, "Fridge")
        section:addOption(
            getText("IGUI_PZRC_Fridge_Place"),
            playerObj, doPlaceFridge, square
        )
        section:addOption(
            getText("IGUI_PZRC_Fridge_Rotate"),
            playerObj, doRotateFridge, square
        )
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

-------------------------------------------------
-- Server responses
-------------------------------------------------

local function onServerCommand(module, command, args)
    if module ~= "PZRC_Fridge" then return end

    local playerObj = getSpecificPlayer(0)
    if not playerObj then return end

    if command == "rationGranted" then
        playerObj:Say(getText("IGUI_PZRC_Fridge_Received"))

    elseif command == "rationDenied" then
        if args.reason == "Cooldown" then
            if args.extra and args.extra > 0 then
                playerObj:Say(getText("IGUI_PZRC_Fridge_CooldownDays", tostring(args.extra)))
            else
                playerObj:Say(getText("IGUI_PZRC_Fridge_Cooldown"))
            end
        else
            playerObj:Say(getText("IGUI_PZRC_Fridge_Error"))
        end

    elseif command == "state" then
        local md = playerObj:getModData()
        md.PZRC_Fridge_DaysLeft = (args.canClaim and 0) or (args.daysLeft or 0)

    elseif command == "fridgeReset" then
        playerObj:getModData().PZRC_Fridge_DaysLeft = 0
        print("[PZRC_Fridge] Your fridge cooldown has been reset")

    elseif command == "resetDone" then
        print("[PZRC_Fridge] Cooldown reset: " .. tostring(args.target))

    elseif command == "resetFail" then
        print("[PZRC_Fridge] Player not found: " .. tostring(args.target))
    end
end

Events.OnServerCommand.Add(onServerCommand)

-------------------------------------------------
-- Chat command: /resetfridge <name>
-------------------------------------------------

local function hookChat()
    local chat = ISChat.instance
    if not chat or not chat.textEntry then return end

    local origFn = chat.textEntry.onCommandEntered
    local function hookedOnCommandEntered(self)
        local text = chat.textEntry:getText()
        if not text then return origFn(self) end

        local target = text:match("^/resetfridge%s+(%S+)")
        if target then
            local playerObj = getSpecificPlayer(0)
            if playerObj and isAdmin(playerObj) then
                sendClientCommand(playerObj, "PZRC_Fridge", "resetFridge", { target = target })
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
    sendClientCommand(playerObj, "PZRC_Fridge", "syncState", {})
end
Events.OnGameStart.Add(requestSyncState)
