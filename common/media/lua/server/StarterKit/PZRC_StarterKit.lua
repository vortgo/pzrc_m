if not isServer() then return end

-- =========================================================================
-- StarterKit — one starter pack per character, with a SteamID cooldown to
-- block alt-character abuse on the same account.
-- =========================================================================

PZRC_StarterKitServer = PZRC_StarterKitServer or {}

local SCOPE = "StarterKit"

local function cooldownHours()
    return PZRC_Config.sbox("StarterKitCooldownHours", 24)
end

local function canClaimKit(player)
    if PZRC_Claimable.wasClaimedByCharacter(player, SCOPE) then
        return false, "AlreadyReceived"
    end
    local ok, hoursLeft = PZRC_Claimable.checkSteamCooldownHours(player, SCOPE, cooldownHours())
    if not ok then
        return false, "Cooldown", hoursLeft
    end
    return true
end

local function giveKit(player)
    local items = (PZRC_StarterKitConfig and PZRC_StarterKitConfig.items) or {}
    local inv = player:getInventory()
    local bag = nil

    for _, entry in ipairs(items) do
        for _ = 1, (entry.count or 1) do
            local targetInv = inv
            if entry.container == "bag" and bag then
                local bagInv = bag:getInventory()
                if bagInv then targetInv = bagInv end
            end
            local item = targetInv:AddItem(entry.item)
            if item then
                sendAddItemToContainer(targetInv, item)
                if not bag and instanceof(item, "InventoryContainer") then
                    bag = item
                end
            end
        end
    end

    PZRC_Claimable.markClaimedByCharacter(player, SCOPE)
    PZRC_Claimable.markSteamCooldown(player, SCOPE)
end

local function sendState(player)
    local claimed = PZRC_Claimable.wasClaimedByCharacter(player, SCOPE)
    local _, hoursLeft = PZRC_Claimable.checkSteamCooldownHours(player, SCOPE, cooldownHours())
    sendServerCommand(player, "PZRC_StarterKit", "state", {
        claimedByCharacter = claimed,
        steamCooldownHours = hoursLeft,
    })
end

function PZRC_StarterKitServer.resetKit(username)
    local ok, p = PZRC_Claimable.resetForUsername(username, SCOPE)
    if ok and p then
        sendServerCommand(p, "PZRC_StarterKit", "kitReset", {})
        sendState(p)
        print("[PZRC_StarterKit] Reset kit for " .. username)
        return true
    end
    print("[PZRC_StarterKit] Player not found: " .. tostring(username))
    return false
end

local function onClientCommand(module, command, player, args)
    if module ~= "PZRC_StarterKit" then return end

    if command == "claimKit" then
        local ok, reason, extra = canClaimKit(player)
        if ok then
            giveKit(player)
            sendServerCommand(player, "PZRC_StarterKit", "kitGranted", {})
            sendState(player)
        else
            sendServerCommand(player, "PZRC_StarterKit", "kitDenied", {
                reason = reason,
                extra  = extra,
            })
        end

    elseif command == "syncState" then
        sendState(player)

    elseif command == "resetKit" then
        if not PZRC_Utils.isAdminAccess(player) then
            print("[PZRC_StarterKit] WARN: non-admin " .. player:getUsername() .. " attempted resetKit")
            return
        end
        local target = args and args.target
        if not target then return end
        local ok = PZRC_StarterKitServer.resetKit(target)
        sendServerCommand(player, "PZRC_StarterKit", ok and "resetDone" or "resetFail",
            { target = target })
    end
end

Events.OnClientCommand.Add(onClientCommand)
