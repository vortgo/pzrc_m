PZRC_Utils = {}

function PZRC_Utils.IsAdminPlayer()
    if not isClient() then return true end
    if isAdmin() or isDebugEnabled() then return true end
    local player = getPlayer()
    if not player then return false end
    local role = player:getRole()
    if not role then return false end
    if role:hasAdminTool() or role:hasAdminPower() then
        return true
    end
    return false
end

function PZRC_Utils.isAdminAccess(player)
    if not player then return false end
    local level = player:getAccessLevel()
    return level == "Admin" or level == "admin"
end

--- Read a text file shipped inside the mod (media/<relative>).
--- Falls back to getFileReader(~/Zomboid/Lua/<basename>) if the mod reader is
--- unavailable, so the same file can be optionally overridden externally.
---@param relativePath string  e.g. "media/radio_messages.txt"
---@param fallbackName string|nil  basename to try in ~/Zomboid/Lua/ as override
---@return string[]|nil lines
function PZRC_Utils.readModTextLines(relativePath, fallbackName)
    local lines = {}
    if getModFileReader then
        local reader = getModFileReader("pzrc_m", relativePath, false)
        if reader then
            local line = reader:readLine()
            while line ~= nil do
                table.insert(lines, line)
                line = reader:readLine()
            end
            reader:close()
            return lines
        end
    end
    if fallbackName then
        local reader = getFileReader(fallbackName, false)
        if reader then
            local line = reader:readLine()
            while line ~= nil do
                table.insert(lines, line)
                line = reader:readLine()
            end
            reader:close()
            return lines
        end
    end
    return nil
end
