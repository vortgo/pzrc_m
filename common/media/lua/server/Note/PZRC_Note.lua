if not isServer() then return end

local function onClientCommand(module, command, player, args)
    if module ~= "PZRC_Note" then return end

    if command == "giveNote" then
        local modData = player:getModData()
        if modData.PZRC_NoteGivenServer then return end

        local inv = player:getInventory()

        -- Note
        local note = inv:AddItem("Base.SheetPaper2")
        if note then
            note:setName(args.name or "Note")
            note:setCustomName(true)
            note:addPage(1, args.text or "")
            sendAddItemToContainer(inv, note)
        end

        modData.PZRC_NoteGivenServer = true
    end
end

Events.OnClientCommand.Add(onClientCommand)
