if not isServer() then return end

-- =========================================================================
-- Fridge — per-character game-day cooldown on a free ration item.
-- =========================================================================

PZRC_FridgeServer = PZRC_FridgeServer or {}

local SCOPE = "Fridge"

local function respawnIntervalDays()
    return PZRC_Config.sbox("FridgeRespawnIntervalGameDays", 1)
end

local function pickRandomItem()
    local items = PZRC_FridgeConfig and PZRC_FridgeConfig.rationItems or {}
    if #items == 0 then return nil end
    return items[ZombRand(#items) + 1]
end

local function canClaim(player)
    local ok, daysLeft = PZRC_Claimable.checkCharacterGameDayCooldown(
        player, SCOPE, respawnIntervalDays())
    if not ok then
        return false, "Cooldown", daysLeft
    end
    return true
end

local function giveRation(player)
    local itemId = pickRandomItem()
    if not itemId then return false end
    local inv = player:getInventory()
    local item = inv:AddItem(itemId)
    if not item then return false end
    sendAddItemToContainer(inv, item)
    PZRC_Claimable.markCharacterGameDayCooldown(player, SCOPE)
    return true, itemId
end

local function sendState(player)
    local ok, daysLeft = PZRC_Claimable.checkCharacterGameDayCooldown(
        player, SCOPE, respawnIntervalDays())
    sendServerCommand(player, "PZRC_Fridge", "state", {
        canClaim = ok,
        daysLeft = daysLeft,
    })
end

function PZRC_FridgeServer.resetFridge(username)
    local ok, p = PZRC_Claimable.resetForUsername(username, SCOPE)
    if ok and p then
        sendServerCommand(p, "PZRC_Fridge", "fridgeReset", {})
        sendState(p)
        print("[PZRC_Fridge] Reset fridge cooldown for " .. username)
        return true
    end
    print("[PZRC_Fridge] Player not found: " .. tostring(username))
    return false
end

local function onClientCommand(module, command, player, args)
    if module ~= "PZRC_Fridge" then return end

    if command == "claimRation" then
        local ok, reason, extra = canClaim(player)
        if not ok then
            sendServerCommand(player, "PZRC_Fridge", "rationDenied", {
                reason = reason, extra = extra,
            })
            return
        end
        local granted, itemId = giveRation(player)
        if granted then
            sendServerCommand(player, "PZRC_Fridge", "rationGranted", { item = itemId })
            sendState(player)
        else
            sendServerCommand(player, "PZRC_Fridge", "rationDenied", { reason = "Error" })
        end

    elseif command == "syncState" then
        sendState(player)

    elseif command == "resetFridge" then
        if not PZRC_Utils.isAdminAccess(player) then
            print("[PZRC_Fridge] WARN: non-admin " .. player:getUsername() .. " attempted resetFridge")
            return
        end
        local target = args and args.target
        if not target then return end
        local ok = PZRC_FridgeServer.resetFridge(target)
        sendServerCommand(player, "PZRC_Fridge", ok and "resetDone" or "resetFail",
            { target = target })
    end
end

Events.OnClientCommand.Add(onClientCommand)
