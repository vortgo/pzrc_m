require "PZRC_Config"

PZRC_Note = {}

PZRC_Note.onCreatePlayer = function(playerIndex, playerObj)
    local modData = playerObj:getModData()
    if modData.PZRC_NoteGiven then return end
    modData.PZRC_NoteGiven = true

    local noteName = getText("IGUI_PZRC_NoteName")
    local freqMHz  = string.format("%.1f", PZRC_Config.RADIO_FREQUENCY / 1000)
    local noteText = getText("IGUI_PZRC_NoteText",
        tostring(PZRC_Config.BASE_X), tostring(PZRC_Config.BASE_Y), freqMHz)

    -- Wait a few ticks — the network isn't ready on first connect.
    local ticksLeft = 10
    local function waitAndSend()
        ticksLeft = ticksLeft - 1
        if ticksLeft > 0 then return end
        Events.OnTick.Remove(waitAndSend)
        sendClientCommand(playerObj, "PZRC_Note", "giveNote", {
            name = noteName,
            text = noteText,
        })
    end
    Events.OnTick.Add(waitAndSend)
end

Events.OnCreatePlayer.Add(PZRC_Note.onCreatePlayer)
