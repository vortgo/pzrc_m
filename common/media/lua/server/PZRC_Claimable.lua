if not isServer() then return end

-- =========================================================================
-- PZRC_Claimable — shared primitives for "player claims reward from world object".
-- Used by StarterKit (one-shot per character + steamID cooldown) and Fridge
-- (per-character game-day cooldown).
--
-- Three independent check modes:
--   1. Character one-shot     — once per character (resets on death).
--   2. SteamID cooldown (hrs) — anti alt-character abuse on same account.
--   3. Character game-day cd  — per character, every N in-game days.
-- =========================================================================

PZRC_Claimable = PZRC_Claimable or {}

local function getStore(scope)
    local gm = getGameTime():getModData()
    if not gm.PZRC_Claimable then gm.PZRC_Claimable = {} end
    if not gm.PZRC_Claimable[scope] then
        gm.PZRC_Claimable[scope] = { character = {}, characterGameDay = {}, steamID = {} }
    end
    local s = gm.PZRC_Claimable[scope]
    s.character         = s.character         or {}
    s.characterGameDay  = s.characterGameDay  or {}
    s.steamID           = s.steamID           or {}
    return s
end

local function gameDay()
    return math.floor((getGameTime():getWorldAgeHours() or 0) / 24)
end

function PZRC_Claimable.getCharacterID(player)
    if not player then return nil end
    local md = player:getModData()
    if not md.PZRC_CharacterID or md.PZRC_CharacterID == "" then
        md.PZRC_CharacterID = tostring(getTimestampMs()) .. "_" .. tostring(ZombRand(2147483647))
        player:transmitModData()
    end
    return md.PZRC_CharacterID
end

function PZRC_Claimable.wasClaimedByCharacter(player, scope)
    local charID = PZRC_Claimable.getCharacterID(player)
    if not charID then return false end
    return getStore(scope).character[charID] ~= nil
end

function PZRC_Claimable.markClaimedByCharacter(player, scope)
    local charID = PZRC_Claimable.getCharacterID(player)
    if not charID then return end
    getStore(scope).character[charID] = os.time()
end

function PZRC_Claimable.checkSteamCooldownHours(player, scope, hours)
    if not hours or hours <= 0 then return true end
    local steamID = tostring(player:getSteamID())
    local last = getStore(scope).steamID[steamID]
    if not last then return true end
    local cooldownSec = hours * 3600
    local elapsed = os.time() - last
    if elapsed >= cooldownSec then return true end
    return false, math.ceil((cooldownSec - elapsed) / 3600)
end

function PZRC_Claimable.markSteamCooldown(player, scope)
    local steamID = tostring(player:getSteamID())
    getStore(scope).steamID[steamID] = os.time()
end

function PZRC_Claimable.checkCharacterGameDayCooldown(player, scope, intervalDays)
    if not intervalDays or intervalDays <= 0 then return true end
    local charID = PZRC_Claimable.getCharacterID(player)
    if not charID then return true end
    local last = getStore(scope).characterGameDay[charID]
    if not last then return true end
    local today = gameDay()
    local elapsed = today - last
    if elapsed >= intervalDays then return true end
    return false, intervalDays - elapsed
end

function PZRC_Claimable.markCharacterGameDayCooldown(player, scope)
    local charID = PZRC_Claimable.getCharacterID(player)
    if not charID then return end
    getStore(scope).characterGameDay[charID] = gameDay()
end

function PZRC_Claimable.resetForUsername(username, scope)
    if not username or username == "" then return false end
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getUsername():lower() == username:lower() then
            local charID = p:getModData().PZRC_CharacterID
            local steamID = tostring(p:getSteamID())
            local store = getStore(scope)
            if charID then
                store.character[charID] = nil
                store.characterGameDay[charID] = nil
            end
            store.steamID[steamID] = nil
            return true, p
        end
    end
    return false
end

PZRC_Claimable.gameDay = gameDay

print("[PZRC_Claimable] Module loaded")
