if not isServer() then return end

PZRC_Radio = {}
PZRC_Radio.channelUUID = "PZRC-EVENTS-001"

local RADIO_MESSAGES_REL = "media/radio_messages.txt"
local RADIO_MESSAGES_FALLBACK = "PZRC_radio_messages.txt" -- optional override in ~/Zomboid/Lua/
local radioMessages = {}

local function loadRadioMessages()
    local lines = PZRC_Utils.readModTextLines(RADIO_MESSAGES_REL, RADIO_MESSAGES_FALLBACK)
    if not lines then
        print("[PZRC_Radio] Radio messages not found (" .. RADIO_MESSAGES_REL .. ")")
        return
    end

    radioMessages = {}
    local currentSection = nil
    for _, raw in ipairs(lines) do
        local line = raw:match("^%s*(.-)%s*$")
        if line ~= "" then
            local section = line:match("^%[(.+)%]$")
            if section then
                currentSection = section:lower()
                radioMessages[currentSection] = radioMessages[currentSection] or {}
            elseif currentSection then
                table.insert(radioMessages[currentSection], line)
            end
        end
    end

    for sectionName, msgs in pairs(radioMessages) do
        print("[PZRC_Radio] Loaded " .. #msgs .. " messages for [" .. sectionName .. "]")
    end
end

-------------------------------------------------
-- Radio channel
-------------------------------------------------

function PZRC_Radio.init()
    loadRadioMessages()

    local scriptManager = getZomboidRadio():getScriptManager()
    if not scriptManager then
        print("[PZRC_Radio] ERROR: scriptManager not available")
        return
    end

    local channel = DynamicRadioChannel.new(
        "PZRC Events",
        PZRC_Config.RADIO_FREQUENCY,
        ChannelCategory.Amateur,
        PZRC_Radio.channelUUID
    )
    channel:setAirCounterMultiplier(1.0)
    scriptManager:AddChannel(channel, false)

    DynamicRadio.cache[PZRC_Radio.channelUUID] = channel
    table.insert(DynamicRadio.scripts, PZRC_Radio)

    local bc = PZRC_Radio.CreateBroadcast()
    if bc then
        channel:setAiringBroadcast(bc)
    end

    print("[PZRC_Radio] Radio channel initialized on " .. PZRC_Config.RADIO_FREQUENCY)
end

function PZRC_Radio.OnEveryHour(_channel, _gametime, _radio)
    -- required callback for DynamicRadio.scripts
end

function PZRC_Radio.CreateBroadcast()
    local msgs = radioMessages["broadcast"]
    if not msgs or #msgs == 0 then
        print("[PZRC_Radio] No broadcast messages loaded")
        return nil
    end

    local bc = RadioBroadCast.new("PZRC-" .. tostring(ZombRand(100000, 999999)), -1, -1)

    local idx = ZombRand(#msgs) + 1
    local freq = string.format("%.1f", PZRC_Config.RADIO_FREQUENCY / 1000)
    local msg = msgs[idx]
    msg = msg:gsub("{freq}", freq)
    msg = msg:gsub("{x}", tostring(PZRC_Config.BASE_X))
    msg = msg:gsub("{y}", tostring(PZRC_Config.BASE_Y))

    bc:AddRadioLine(RadioLine.new(msg, 1.0, 0.8, 0.2))

    return bc
end

--- Per-event broadcast (called from EventManager.notify)
function PZRC_Radio.CreateEventBroadcast(eventTypeName, x, y)
    local typeToMsg = {
        buildingstash    = 1,
        foreststash      = 3,
        airdrop          = 4,
        abandonedvehicle = 5,
        camp             = 6,
        helicoptercrash  = 7,
    }

    local msgIdx = typeToMsg[eventTypeName] or 1
    local key = "IGUI_PZRC_Event_" .. msgIdx
    local msg = getText(key, tostring(x), tostring(y))

    local bc = RadioBroadCast.new("PZRC-EVT-" .. tostring(ZombRand(100000, 999999)), -1, -1)
    bc:AddRadioLine(RadioLine.new("<bzzt>", 0.5, 0.5, 0.5))
    bc:AddRadioLine(RadioLine.new(msg, 1.0, 0.5, 0.1))
    bc:AddRadioLine(RadioLine.new("<fzzt>", 0.5, 0.5, 0.5))

    return bc
end

function PZRC_Radio.broadcastEvent(eventTypeName, x, y)
    local channel = DynamicRadio.cache[PZRC_Radio.channelUUID]
    if not channel then return end

    local bc = PZRC_Radio.CreateEventBroadcast(eventTypeName, x, y)
    channel:setAiringBroadcast(bc)
    print("[PZRC_Radio] Event broadcast: " .. eventTypeName .. " at " .. x .. "," .. y)
end

-- Channel is created from Events.OnServerStarted to ensure DynamicRadio is ready
Events.OnServerStarted.Add(PZRC_Radio.init)

-------------------------------------------------
-- Daily auto-broadcast at 8:00 and 20:00 in-game
-------------------------------------------------

local lastBroadcastHour = -1

local function onEveryHour()
    local hour = getGameTime():getHour()
    if hour ~= 8 and hour ~= 20 then return end
    if hour == lastBroadcastHour then return end
    lastBroadcastHour = hour

    local channel = DynamicRadio.cache[PZRC_Radio.channelUUID]
    if not channel then return end

    local bc = PZRC_Radio.CreateBroadcast()
    channel:setAiringBroadcast(bc)
end

Events.EveryHours.Add(onEveryHour)

-------------------------------------------------
-- /radio <freq> <text> — admin command
-------------------------------------------------

local function freqToInt(freqStr)
    local num = tonumber(freqStr)
    if not num then return nil end
    return math.floor(num * 1000 + 0.5)
end

local function findChannelByFreq(freqInt)
    for _, channel in pairs(DynamicRadio.cache) do
        if channel:GetFrequency() == freqInt then
            return channel
        end
    end
    return nil
end

local function onClientCommand(module, command, player, args)
    if module ~= "PZRC_Radio" then return end

    if command == "broadcast" then
        if not PZRC_Utils.isAdminAccess(player) then
            print("[PZRC_Radio] WARN: non-admin " .. player:getUsername() .. " attempted broadcast")
            return
        end

        local freqInt = freqToInt(args.freq)
        if not freqInt then return end

        local channel = findChannelByFreq(freqInt)
        if not channel then
            print("[PZRC_Radio] Channel not found for freq " .. tostring(args.freq))
            return
        end

        local bc = RadioBroadCast.new("PZRC-ADM-" .. tostring(ZombRand(100000, 999999)), -1, -1)
        bc:AddRadioLine(RadioLine.new("<bzzt>", 0.5, 0.5, 0.5))
        bc:AddRadioLine(RadioLine.new(args.text, 1.0, 0.8, 0.2))
        bc:AddRadioLine(RadioLine.new("<fzzt>", 0.5, 0.5, 0.5))

        channel:setAiringBroadcast(bc)
        print("[PZRC_Radio] Admin " .. player:getUsername() .. " broadcast on " .. args.freq .. " MHz: " .. args.text)
    end
end

Events.OnClientCommand.Add(onClientCommand)
