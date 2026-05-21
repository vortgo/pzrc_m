local function log(msg)
    print("[EventCmdServer] " .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- Обработка OnClientCommand (module="PZRC_Events")
-- ---------------------------------------------------------------------------

local function onClientCommand(module, command, player, args)
    if module ~= "PZRC_Events" then return end

    local level = player:getAccessLevel()
    if level ~= "Admin" and level ~= "admin" then
        log("WARN: non-admin " .. player:getUsername() .. " attempted event command: " .. command)
        return
    end

    local username = player:getUsername()

    if command == "spawn" then
        local typeName = args.type
        if not typeName then
            sendServerCommand(player, "PZRC_Events", "result", {
                text = "Usage: /event spawn <type> [x y]"
            })
            return
        end

        local x = tonumber(args.x) or math.floor(player:getX())
        local y = tonumber(args.y) or math.floor(player:getY())
        local z = tonumber(args.z) or 0

        log(username .. " spawning event '" .. typeName .. "' at " .. x .. "," .. y .. "," .. z)
        local event, err = PZRC_EventManager.spawn(typeName, x, y, z, "manual")

        if event then
            local msg = "Event #" .. event.id .. " (" .. event.type .. ") spawned at "
                .. event.x .. ", " .. event.y .. ", " .. event.z
            sendServerCommand(player, "PZRC_Events", "result", { text = msg })
        else
            sendServerCommand(player, "PZRC_Events", "result", {
                text = "Spawn failed: " .. tostring(err)
            })
        end

    elseif command == "list" then
        local events = PZRC_EventManager.list()
        if #events == 0 then
            sendServerCommand(player, "PZRC_Events", "result", {
                text = "No active events"
            })
            return
        end

        local lines = { "Active events (" .. #events .. "):" }
        for _, ev in ipairs(events) do
            local status = ev.state or "unknown"
            local age = math.floor((os.time() - ev.spawnTime) / 60)
            table.insert(lines,
                "  #" .. ev.id .. " " .. ev.type
                .. " at " .. ev.x .. "," .. ev.y .. "," .. ev.z
                .. " [" .. status .. ", " .. age .. "m, " .. ev.source .. "]"
            )
        end

        sendServerCommand(player, "PZRC_Events", "result", {
            text = table.concat(lines, " | ")
        })

    elseif command == "remove" then
        local id = tonumber(args.id)
        if not id then
            sendServerCommand(player, "PZRC_Events", "result", {
                text = "Usage: /event remove <id>"
            })
            return
        end

        local ok, err = PZRC_EventManager.remove(id, true)
        local msg
        if ok then
            msg = "Event #" .. id .. " removed"
        elseif err then
            msg = "Event #" .. id .. ": " .. err
        else
            msg = "Event #" .. id .. " not found"
        end
        sendServerCommand(player, "PZRC_Events", "result", { text = msg })

    elseif command == "removeall" then
        local removed, deferred = PZRC_EventManager.removeAll(true)
        local msg = "Removed " .. removed .. " events"
        if deferred > 0 then
            msg = msg .. ", " .. deferred .. " deferred (chunks not loaded)"
        end
        sendServerCommand(player, "PZRC_Events", "result", { text = msg })

    elseif command == "types" then
        local types = PZRC_EventRegistry.list()
        sendServerCommand(player, "PZRC_Events", "result", {
            text = "Available types: " .. table.concat(types, ", ")
        })

    elseif command == "reload" then
        -- All settings live in Sandbox Options; nothing to reload externally.
        sendServerCommand(player, "PZRC_Events", "result", {
            text = "PZRC config is sandbox-backed (no external file). Open Sandbox Options to change values."
        })

    elseif command == "scanmap" then
        local summary = PZRC_EventUtils.scanMap and PZRC_EventUtils.scanMap() or "scanMap() not available"
        sendServerCommand(player, "PZRC_Events", "result", { text = summary })

    elseif command == "coverage" then
        local n = tonumber(args and args.n) or 500
        local summary = PZRC_EventUtils.scanCoverage and PZRC_EventUtils.scanCoverage(n) or "scanCoverage() not available"
        sendServerCommand(player, "PZRC_Events", "result", { text = summary })

    elseif command == "autospawn" then
        local forceType = args and args.type
        if forceType and not PZRC_EventRegistry.get(forceType:lower()) then
            sendServerCommand(player, "PZRC_Events", "result", {
                text = "Unknown event type: '" .. forceType .. "'. Use /event types"
            })
            return
        end
        log(username .. " triggered forced autoSpawn" .. (forceType and (" type=" .. forceType) or ""))
        PZRC_EventManager.autoSpawn(true, forceType)
        sendServerCommand(player, "PZRC_Events", "result", {
            text = "AutoSpawn triggered" .. (forceType and (" (" .. forceType .. ")") or "")
                .. " — see server log for pick/match details"
        })

    else
        sendServerCommand(player, "PZRC_Events", "result", {
            text = "Unknown command: " .. command
        })
    end
end

local function onServerStarted()
    if Events.OnClientCommand then
        Events.OnClientCommand.Add(onClientCommand)
        log("Registered OnClientCommand")
    else
        log("WARN: Events.OnClientCommand unavailable!")
    end
    log("EventCommandsServer initialized")
end

Events.OnServerStarted.Add(onServerStarted)
log("EventCommandsServer loaded")
