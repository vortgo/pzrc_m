PZRC_Config = PZRC_Config or {}

PZRC_Config._defaults = {
    BASE_X                     = 9492,
    BASE_Y                     = 11190,
    RADIO_FREQUENCY            = 95200,
    VEHICLE_CLAIM_RADIUS       = 90,
    VEHICLE_CLAIM_DURATION_MIN = 240,   -- minutes a claim stays active (4h)
}

PZRC_Config._sboxKeys = {
    BASE_X                     = "BaseX",
    BASE_Y                     = "BaseY",
    RADIO_FREQUENCY            = "RadioFrequencyKHz",
    VEHICLE_CLAIM_RADIUS       = "VehicleClaimRadius",
    VEHICLE_CLAIM_DURATION_MIN = "VehicleClaimDurationMin",
}

setmetatable(PZRC_Config, {
    __index = function(_, key)
        local sboxKey = PZRC_Config._sboxKeys[key]
        if sboxKey then
            local vars = SandboxVars and SandboxVars.pzrc_m
            if vars and vars[sboxKey] ~= nil then
                return vars[sboxKey]
            end
            return PZRC_Config._defaults[key]
        end
        return nil
    end,
})

---@generic T
---@param key string
---@param default T
---@return T
function PZRC_Config.sbox(key, default)
    local vars = SandboxVars and SandboxVars.pzrc_m
    if vars and vars[key] ~= nil then
        return vars[key]
    end
    return default
end
