
PZRC_EventConfig = PZRC_EventConfig or {}

-- ---------------------------------------------------------------------------
-- Sandbox-backed поля. Читаются через metatable из SandboxVars.pzrc_m,
-- чтобы админ мог менять значения без редеплоя (и перечитываются runtime).
-- Дефолты указаны в PZRC_EventConfig._defaults.
-- ---------------------------------------------------------------------------

PZRC_EventConfig._defaults = {
    TTL_HOURS                   = 0.05,  -- реальные часы до очистки непосещённого события
    VISIT_RADIUS                = 30,    -- клетки, proximity-check
    BUILDING_SEARCH_RADIUS      = 7,     -- клетки, поиск здания для BuildingStash
    SAFE_SQUARE_RADIUS          = 20,    -- клетки, поиск свободной клетки
    EVENT_OVERLAP_RADIUS        = 30,    -- клетки, минимальная дистанция между событиями
    AUTO_SPAWN_INTERVAL_MINUTES = 5,     -- реальные минуты между автоспавнами
    EXCLUDE_MIN_Y               = 5500,  -- y < этого — Louisville, не спавним
    EXCLUDE_MAX_X               = 15000, -- x > этого — Louisville/восток, не спавним
    ANCHOR_DISTANCE             = 700,   -- якорь на 700 тайлов от случайного игрока
    SEARCH_RADIUS               = 250,   -- радиус поиска места вокруг якоря
    PICK_ATTEMPTS               = 50,    -- число попыток подобрать подходящую точку
}

PZRC_EventConfig._sboxKeys = {
    TTL_HOURS                   = "EventTTLHours",
    VISIT_RADIUS                = "EventVisitRadiusCells",
    BUILDING_SEARCH_RADIUS      = "EventBuildingSearchRadius",
    SAFE_SQUARE_RADIUS          = "EventSafeSquareRadius",
    EVENT_OVERLAP_RADIUS        = "EventOverlapRadiusCells",
    AUTO_SPAWN_INTERVAL_MINUTES = "EventAutoSpawnIntervalMinutes",
    EXCLUDE_MIN_Y               = "EventExcludeMinY",
    EXCLUDE_MAX_X               = "EventExcludeMaxX",
    ANCHOR_DISTANCE             = "EventAnchorDistance",
    SEARCH_RADIUS               = "EventSearchRadius",
    PICK_ATTEMPTS               = "EventPickAttempts",
}

setmetatable(PZRC_EventConfig, {
    __index = function(_, key)
        local sboxKey = PZRC_EventConfig._sboxKeys[key]
        if sboxKey then
            return PZRC_Config.sbox(sboxKey, PZRC_EventConfig._defaults[key])
        end
        return nil
    end,
})

-- ---------------------------------------------------------------------------
-- Лут-таблицы
-- chance = вероятность (0..1), min/max = количество
-- ---------------------------------------------------------------------------

PZRC_EventConfig.Loot = {
    buildingstash = {
        { item = "Base.BlowTorch",            chance = 0.10, min = 1, max = 1 },
        { item = "Base.WeldingMask",          chance = 0.10, min = 1, max = 1 },
        { item = "Base.Antibiotics",          chance = 0.10, min = 1, max = 2 },
        { item = "Base.Pills",                chance = 0.20, min = 1, max = 3 },
        { item = "Base.SutureNeedle",         chance = 0.20, min = 1, max = 3 },
        { item = "Base.Tweezers",             chance = 0.10, min = 1, max = 2 },
        { item = "Base.Disinfectant",         chance = 0.20, min = 1, max = 2 },
        { item = "Base.Bag_BigHikingBag",     chance = 0.15, min = 1, max = 1 },
        { item = "Base.Bag_ShotgunDblBag",    chance = 0.15, min = 1, max = 1 },
        { item = "Base.Bag_ALICEpack",        chance = 0.10, min = 1, max = 1 },
        { item = "Base.Crowbar",              chance = 0.10, min = 1, max = 1 },
        { item = "Base.CannedCornedBeef",     chance = 0.20, min = 1, max = 3 },
        { item = "Base.Lighter",              chance = 0.20, min = 1, max = 1 },
        { item = "Base.Twine",                chance = 0.15, min = 1, max = 2 },
        { item = "Base.Thread",               chance = 0.20, min = 1, max = 3 },
        { item = "Base.GunPowder",            chance = 0.05, min = 1, max = 1 },
        { item = "Base.Wire",                 chance = 0.15, min = 1, max = 3 },
        { item = "Base.Glue",                 chance = 0.15, min = 1, max = 3 },
        { item = "Base.Woodglue",             chance = 0.15, min = 1, max = 3 },
        { item = "Base.BallPeenHammerForged", chance = 0.10, min = 1, max = 1 },
        { item = "Base.Needle",               chance = 0.15, min = 1, max = 2 },
        { item = "Base.GardenFork",           chance = 0.15, min = 1, max = 1 },
        { item = "Base.Axe",                  chance = 0.08, min = 1, max = 1 },
        { item = "Base.Saw",                  chance = 0.15, min = 1, max = 1 },
        { item = "Base.BookFarming1",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookFarming2",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookHusbandry1",       chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookHusbandry2",       chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookBlacksmith1",      chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookBlacksmith2",      chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookCarpentry1",       chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookCarpentry2",       chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookElectrician1",     chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookElectrician2",     chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookFirstAid1",        chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookFirstAid2",        chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookFishing1",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookFishing2",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookForaging1",        chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookForaging2",        chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookMaintenance1",     chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookMaintenance2",     chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookMetalWelding1",    chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookMetalWelding2",    chance = 0.10, min = 1, max = 1 },
        { item = "Base.SmithingMag8",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.TailoringMag1",        chance = 0.10, min = 1, max = 1 },
        { item = "Base.TailoringMag5",        chance = 0.10, min = 1, max = 1 },
        { item = "Base.FarmingMag7",          chance = 0.10, min = 1, max = 1 },
        { item = "Base.TailoringMag10",       chance = 0.10, min = 1, max = 1 },
        { item = "Base.MechanicMag3",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.MechanicMag2",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.MechanicMag1",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.CannedChili",          chance = 0.20, min = 1, max = 2 },
        { item = "Base.CannedPeas",           chance = 0.20, min = 1, max = 2 },
        { item = "Base.CannedPotato2",        chance = 0.20, min = 1, max = 2 },
        { item = "Base.TunaTin",              chance = 0.20, min = 1, max = 2 },
        { item = "Base.TinnedSoup",           chance = 0.20, min = 1, max = 2 },
        { item = "Base.CannedEggplant",       chance = 0.20, min = 1, max = 2 },
        { item = "Base.CannedRoe",            chance = 0.20, min = 1, max = 2 },
        { item = "Base.CannedBroccoli",       chance = 0.20, min = 1, max = 2 },
        { item = "Base.SugarBrown",           chance = 0.20, min = 1, max = 2 },
        { item = "Base.Marinara",             chance = 0.20, min = 1, max = 2 },
        { item = "Base.Crisps",               chance = 0.20, min = 1, max = 2 },
        { item = "Base.Aerosolbomb",          chance = 0.05, min = 1, max = 1 },
        { item = "Base.FlameTrap",            chance = 0.05, min = 1, max = 1 },
        { item = "Base.Vest_BulletCivilian",  chance = 0.05, min = 1, max = 1 },
        { item = "Base.Tshirt_HuntingCamo",   chance = 0.15, min = 1, max = 1 },
        { item = "Base.Hoodie_HuntingCamo_UP", chance = 0.10, min = 1, max = 1 },
        { item = "Base.Bullets357Box",        chance = 0.20, min = 1, max = 1 },
        { item = "Base.Bullets38Box",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.Bullets44Box",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.Bullets45Box",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.Bullets9mmBox",        chance = 0.25, min = 1, max = 1 },
    },

    foreststash = {
        { item = "Base.Machete",              chance = 0.10, min = 1, max = 1 },
        { item = "Base.BaseballBat_RailSpike", chance = 0.10, min = 1, max = 1 },
        { item = "Base.HandAxe_Old",          chance = 0.10, min = 1, max = 1 },
        { item = "Base.PickAxe",              chance = 0.20, min = 1, max = 1 },
        { item = "Base.WoodAxe",              chance = 0.10, min = 1, max = 1 },
        { item = "Base.Shovel2",              chance = 0.10, min = 1, max = 1 },
        { item = "Base.PipeWrench",           chance = 0.10, min = 1, max = 1 },
        { item = "Base.Sword",                chance = 0.05, min = 1, max = 1 },
        { item = "Base.Screwdriver",          chance = 0.15, min = 1, max = 1 },
        { item = "Base.SpearScrapKnife",      chance = 0.15, min = 1, max = 1 },
        { item = "Base.Pistol3",              chance = 0.08, min = 1, max = 1 },
        { item = "Base.Pistol2",              chance = 0.08, min = 1, max = 1 },
        { item = "Base.Pistol",               chance = 0.20, min = 1, max = 1 },
        { item = "Base.JS14_Rifle",           chance = 0.05, min = 1, max = 1 },
        { item = "Base.L94_Rifle",            chance = 0.05, min = 1, max = 1 },
        { item = "Base.HuntingRifle",         chance = 0.05, min = 1, max = 1 },
        { item = "Base.AmmoStraps",           chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookAiming1",          chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookAiming2",          chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookReloading1",       chance = 0.10, min = 1, max = 1 },
        { item = "Base.BookReloading2",       chance = 0.10, min = 1, max = 1 },
        { item = "Base.ElectronicsMag4",      chance = 0.10, min = 1, max = 1 },
        { item = "Base.FarmingMag1",          chance = 0.15, min = 1, max = 1 },
        { item = "Base.FarmingMag2",          chance = 0.15, min = 1, max = 1 },
        { item = "Base.TailoringMag2",        chance = 0.10, min = 1, max = 1 },
        { item = "Base.HuntingMag2",          chance = 0.10, min = 1, max = 1 },
        { item = "Base.WeaponMag1",           chance = 0.10, min = 1, max = 1 },
        { item = "Base.MetalworkMag3",        chance = 0.10, min = 1, max = 1 },
        { item = "Base.HuntingMag3",          chance = 0.10, min = 1, max = 1 },
        { item = "Base.Magazine_Rich",        chance = 0.10, min = 1, max = 1 },
        { item = "Base.Aluminum",             chance = 0.10, min = 1, max = 1 },
        { item = "Base.FishingLine",          chance = 0.10, min = 1, max = 1 },
        { item = "Base.Thread",               chance = 0.10, min = 1, max = 1 },
        { item = "Base.NailsBox",             chance = 0.25, min = 1, max = 1 },
        { item = "Base.Hat_HockeyMask_Silver", chance = 0.10, min = 1, max = 1 },
        { item = "Base.BatteryBox",           chance = 0.10, min = 1, max = 1 },
        { item = "Base.Bag_Sheriff",          chance = 0.10, min = 1, max = 1 },
        { item = "Base.Bag_MedicalBag",       chance = 0.10, min = 1, max = 1 },
        { item = "Base.Bag_ALICE_BeltSus",    chance = 0.10, min = 1, max = 1 },
        { item = "Base.TrapCage",             chance = 0.10, min = 1, max = 1 },
        { item = "Base.TrapStick",            chance = 0.10, min = 1, max = 1 },
        { item = "Base.Bullets357Box",        chance = 0.25, min = 1, max = 1 },
        { item = "Base.Bullets38Box",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.Bullets44Box",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.Bullets45Box",         chance = 0.25, min = 1, max = 1 },
        { item = "Base.TinnedSoup",           chance = 0.20, min = 1, max = 2 },
        { item = "Base.CannedEggplant",       chance = 0.20, min = 1, max = 2 },
        { item = "Base.CannedRoe",            chance = 0.20, min = 1, max = 2 },
        { item = "Base.CannedBroccoli",       chance = 0.20, min = 1, max = 2 },
    },

    airdrop = {
        { item = "Base.Pistol3",              chance = 0.15, min = 1, max = 1 },
        { item = "Base.Pistol2",              chance = 0.15, min = 1, max = 1 },
        { item = "Base.Pistol",               chance = 0.20, min = 1, max = 1 },
        { item = "Base.Revolver_CapGun",      chance = 0.50, min = 1, max = 1 },
        { item = "Base.DoubleBarrelShotgun",  chance = 0.20, min = 1, max = 1 },
        { item = "Base.Shotgun",              chance = 0.20, min = 1, max = 1 },
        { item = "Base.JS3T_Shotgun",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.ShotgunSawnoff",       chance = 0.15, min = 1, max = 1 },
        { item = "Base.JS14_Rifle",           chance = 0.10, min = 1, max = 1 },
        { item = "Base.L92_Carbine",          chance = 0.10, min = 1, max = 1 },
        { item = "Base.L94_Rifle",            chance = 0.10, min = 1, max = 1 },
        { item = "Base.AssaultRifle",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.AssaultRifle2",        chance = 0.10, min = 1, max = 1 },
        { item = "Base.VarmintRifle",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.HuntingRifle",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.MSR7T_Rifle",          chance = 0.10, min = 1, max = 1 },
        { item = "Base.TrapperCarbine",       chance = 0.10, min = 1, max = 1 },
        { item = "Base.Rifle_CapGun",         chance = 0.30, min = 1, max = 1 },
        { item = "Base.44Clip",               chance = 0.10, min = 1, max = 1 },
        { item = "Base.JS14_Clip",            chance = 0.15, min = 1, max = 1 },
        { item = "Base.556Clip",              chance = 0.15, min = 1, max = 1 },
        { item = "Base.M14Clip",              chance = 0.15, min = 1, max = 1 },
        { item = "Base.9mmClip",              chance = 0.15, min = 1, max = 1 },
        { item = "Base.Bullets357Box",        chance = 0.20, min = 1, max = 2 },
        { item = "Base.Bullets45Box",         chance = 0.20, min = 1, max = 2 },
        { item = "Base.ShotgunShellsBox",     chance = 0.25, min = 1, max = 1 },
        { item = "Base.556Box",               chance = 0.25, min = 1, max = 1 },
        { item = "Base.308Box",               chance = 0.10, min = 1, max = 2 },
        { item = "Base.Bullets9mmBox",        chance = 0.20, min = 1, max = 2 },
        { item = "Base.AmmoStraps",           chance = 0.20, min = 1, max = 1 },
        { item = "Base.ChokeTubeFull",        chance = 0.20, min = 1, max = 1 },
        { item = "Base.ChokeTubeImproved",    chance = 0.20, min = 1, max = 1 },
        { item = "Base.GunLight",             chance = 0.20, min = 1, max = 1 },
        { item = "Base.Laser",                chance = 0.20, min = 1, max = 1 },
        { item = "Base.RecoilPad",            chance = 0.20, min = 1, max = 1 },
        { item = "Base.RedDot",               chance = 0.20, min = 1, max = 1 },
        { item = "Base.TritiumSights",        chance = 0.20, min = 1, max = 1 },
        { item = "Base.x2Scope",              chance = 0.20, min = 1, max = 1 },
        { item = "Base.x4Scope",              chance = 0.15, min = 1, max = 1 },
        { item = "Base.x8Scope",              chance = 0.10, min = 1, max = 1 },
        { item = "Base.Bag_ALICEpack",        chance = 0.10, min = 1, max = 1 },
        { item = "Base.Bag_ALICEpack_DesertCamo", chance = 0.10, min = 1, max = 1 },
        { item = "Base.Bag_SurvivorBag",      chance = 0.20, min = 1, max = 1 },
        { item = "Base.Bag_ALICE_BeltSus_Camo", chance = 0.15, min = 1, max = 1 },
        { item = "Base.CarBatteryCharger", chance = 0.15, min = 1, max = 1 }, 
    },

    abandonedvehicle = {
        { item = "Base.EngineParts",          chance = 0.20, min = 1, max = 8 },
        { item = "Base.BookMechanic1",        chance = 0.20, min = 1, max = 1 },
        { item = "Base.BookMechanic2",        chance = 0.20, min = 1, max = 1 },
        { item = "Base.PetrolCan",            chance = 0.20, min = 1, max = 2 },
        { item = "Base.CarBattery1",          chance = 0.10, min = 1, max = 1 },
        { item = "Base.CarBattery2",          chance = 0.10, min = 1, max = 1 },
        { item = "Base.CarBattery3",          chance = 0.15, min = 1, max = 1 },
        { item = "Base.Wrench",               chance = 0.40, min = 1, max = 1 },
        { item = "Base.Screwdriver",          chance = 0.40, min = 1, max = 1 },
        { item = "Base.TinnedBeans",          chance = 0.30, min = 1, max = 2 },
        { item = "Base.WaterBottle",          chance = 0.30, min = 1, max = 1 },
        { item = "Base.MechanicMag3",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.MechanicMag2",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.MechanicMag1",         chance = 0.10, min = 1, max = 1 },
        { item = "Base.CannedChili",          chance = 0.20, min = 1, max = 1 },
        { item = "Base.CannedPeas",           chance = 0.20, min = 1, max = 1 },
        { item = "Base.CannedPotato2",        chance = 0.20, min = 1, max = 1 },
        { item = "Base.TunaTin",              chance = 0.20, min = 1, max = 1 },
        { item = "Base.TinnedSoup",           chance = 0.20, min = 1, max = 2 },
        { item = "Base.CannedEggplant",       chance = 0.20, min = 1, max = 2 },
        { item = "Base.CannedRoe",            chance = 0.20, min = 1, max = 2 },
        { item = "Base.CannedBroccoli",       chance = 0.20, min = 1, max = 2 },
        { item = "Base.SugarBrown",           chance = 0.20, min = 1, max = 2 },
        { item = "Base.Marinara",             chance = 0.20, min = 1, max = 2 },
        { item = "Base.Bag_FannyPackFront",   chance = 0.20, min = 1, max = 1 },
        { item = "Base.Cooler_Beer",          chance = 0.20, min = 1, max = 1 },
        { item = "Base.BeerBottle",           chance = 0.80, min = 1, max = 2 },
        { item = "Base.WalkieTalkie4",        chance = 0.50, min = 1, max = 1 },
        { item = "Base.Lighter",              chance = 0.60, min = 1, max = 1 },
        { item = "Base.WaterPurificationTablets", chance = 0.10, min = 1, max = 1 },
        { item = "Base.Scissors",             chance = 0.10, min = 1, max = 1 },
    },

    camp = {
        -- Еда и вода
        { item = "Base.TinnedBeans",          chance = 0.50, min = 1, max = 1 },
        { item = "Base.CannedCornedBeef",     chance = 0.40, min = 1, max = 1 },
        { item = "Base.CannedChili",          chance = 0.40, min = 1, max = 1 },
        { item = "Base.TunaTin",              chance = 0.30, min = 1, max = 1 },
        { item = "Base.TinnedSoup",           chance = 0.40, min = 1, max = 1 },
        { item = "Base.CannedPeas",           chance = 0.30, min = 1, max = 1 },
        { item = "Base.Crisps",               chance = 0.30, min = 1, max = 1 },
        { item = "Base.Cereal",               chance = 0.20, min = 1, max = 1 },
        { item = "Base.WaterBottle",          chance = 0.50, min = 1, max = 1 },
        { item = "Base.BeerBottle",           chance = 0.40, min = 1, max = 1 },
        { item = "Base.Whiskey",          chance = 0.15, min = 1, max = 1 },
        -- Готовка
        { item = "Base.GridlePan",            chance = 0.25, min = 1, max = 1 },
        { item = "Base.Lighter",              chance = 0.50, min = 1, max = 1 },
        { item = "Base.Matches",              chance = 0.40, min = 1, max = 1 },
        -- Медикаменты
        { item = "Base.Bandage",              chance = 0.40, min = 1, max = 2 },
        { item = "Base.AlcoholBandage",       chance = 0.25, min = 1, max = 2 },
        { item = "Base.Disinfectant",         chance = 0.20, min = 1, max = 1 },
        { item = "Base.Pills",                chance = 0.20, min = 1, max = 1 },
        { item = "Base.SutureNeedle",         chance = 0.15, min = 1, max = 2 },
        -- Инструменты
        { item = "Base.HuntingKnife",         chance = 0.30, min = 1, max = 1 },
        { item = "Base.HandAxe_Old",          chance = 0.20, min = 1, max = 1 },
        { item = "Base.Torch",                chance = 0.40, min = 1, max = 1 },
        { item = "Base.Rope",                 chance = 0.30, min = 1, max = 1 },
        { item = "Base.Twine",                chance = 0.30, min = 1, max = 2 },
        { item = "Base.Tarp",                 chance = 0.20, min = 1, max = 1 },
        { item = "Base.TrapCage",             chance = 0.15, min = 1, max = 1 },
        { item = "Base.TrapStick",            chance = 0.15, min = 1, max = 1 },
        { item = "Base.FishingRod",           chance = 0.15, min = 1, max = 1 },
        { item = "Base.FishingLine",          chance = 0.20, min = 1, max = 1 },
        -- Одежда
        { item = "Base.PonchoYellow",        chance = 0.20, min = 1, max = 1 },
        { item = "Base.Gloves_LeatherGloves", chance = 0.20, min = 1, max = 1 },
        -- Рюкзак
        { item = "Base.Bag_DuffelBag",        chance = 0.20, min = 1, max = 1 },
        { item = "Base.Bag_BigHikingBag",     chance = 0.20, min = 1, max = 1 },
        -- Разное
        { item = "Base.Notebook",             chance = 0.30, min = 1, max = 1 },
        { item = "Base.Pen",                  chance = 0.30, min = 1, max = 1 },
        { item = "Base.WalkieTalkie4",        chance = 0.15, min = 1, max = 1 },
        { item = "Base.Battery",              chance = 0.25, min = 1, max = 2 },
    },

    helicoptercrash = {
        -- Оружие
        { item = "Base.AssaultRifle",         chance = 0.25, min = 1, max = 1 },
        { item = "Base.AssaultRifle2",        chance = 0.15, min = 1, max = 1 },
        { item = "Base.MSR7T_Rifle",          chance = 0.20, min = 1, max = 1 },
        { item = "Base.L92_Carbine",          chance = 0.15, min = 1, max = 1 },
        { item = "Base.Shotgun",              chance = 0.25, min = 1, max = 1 },
        { item = "Base.JS3T_Shotgun",         chance = 0.15, min = 1, max = 1 },
        { item = "Base.Pistol",               chance = 0.15, min = 1, max = 2 },
        { item = "Base.Pistol2",              chance = 0.15, min = 1, max = 2 },
        { item = "Base.Pistol3",              chance = 0.25, min = 1, max = 2 },
        -- Обоймы
        { item = "Base.556Clip",              chance = 0.50, min = 1, max = 2 },
        { item = "Base.M14Clip",              chance = 0.50, min = 1, max = 2 },
        { item = "Base.9mmClip",              chance = 0.50, min = 1, max = 2 },
        { item = "Base.JS14_Clip",            chance = 0.40, min = 1, max = 2 },
        -- Патроны
        { item = "Base.ShotgunShellsBox",     chance = 0.25, min = 1, max = 1 },
        { item = "Base.556Box",               chance = 0.25, min = 1, max = 1 },
        { item = "Base.308Box",               chance = 0.25, min = 1, max = 1 },
        { item = "Base.Bullets9mmBox",        chance = 0.20, min = 1, max = 2 },
        -- Обвесы
        { item = "Base.x4Scope",              chance = 0.35, min = 1, max = 1 },
        { item = "Base.x8Scope",              chance = 0.25, min = 1, max = 1 },
        { item = "Base.RedDot",               chance = 0.35, min = 1, max = 1 },
        { item = "Base.Laser",                chance = 0.30, min = 1, max = 1 },
        { item = "Base.GunLight",             chance = 0.30, min = 1, max = 1 },
        { item = "Base.TritiumSights",        chance = 0.25, min = 1, max = 1 },
        { item = "Base.RecoilPad",            chance = 0.30, min = 1, max = 1 },
        { item = "Base.AmmoStraps",           chance = 0.30, min = 1, max = 1 },
        { item = "Base.ChokeTubeFull",        chance = 0.25, min = 1, max = 1 },
        -- Медицина
        { item = "Base.Antibiotics",          chance = 0.40, min = 1, max = 2 },
        { item = "Base.SutureNeedle",         chance = 0.50, min = 1, max = 2 },
        { item = "Base.SutureNeedleHolder",   chance = 0.30, min = 1, max = 1 },
        { item = "Base.Disinfectant",         chance = 0.40, min = 1, max = 2 },
        { item = "Base.Splint",               chance = 0.30, min = 1, max = 2 },
        { item = "Base.Pills",                chance = 0.40, min = 1, max = 2 },
        { item = "Base.Tweezers",             chance = 0.25, min = 1, max = 1 },
        { item = "Base.Scalpel",              chance = 0.20, min = 1, max = 1 },
        -- Еда
        { item = "Base.WaterRationCan",       chance = 0.50, min = 1, max = 2 },
        { item = "Base.WaterBottle",          chance = 0.50, min = 1, max = 2 },
        { item = "Base.WaterPurificationTablets", chance = 0.30, min = 1, max = 2 },
        { item = "Base.CannedCornedBeef",     chance = 0.40, min = 1, max = 2 },
        { item = "Base.TinnedBeans",          chance = 0.40, min = 1, max = 2 },
        -- Военное снаряжение
        { item = "Base.Vest_BulletArmy",      chance = 0.30, min = 1, max = 1 },
        { item = "Base.Vest_BulletPolice",    chance = 0.15, min = 1, max = 1 },
        { item = "Base.Hat_Army",             chance = 0.35, min = 1, max = 1 },
        { item = "Base.Hat_RiotHelmet",       chance = 0.15, min = 1, max = 1 },
        { item = "Base.Bag_ALICEpack_Army",   chance = 0.35, min = 1, max = 1 },
        { item = "Base.Bag_ALICEpack_DesertCamo", chance = 0.25, min = 1, max = 1 },
        { item = "Base.Bag_ALICE_BeltSus",    chance = 0.30, min = 1, max = 1 },
        { item = "Base.Bag_Military",         chance = 0.25, min = 1, max = 1 },
        { item = "Base.CanteenMilitary",      chance = 0.40, min = 1, max = 2 },
        -- Взрывчатка
        { item = "Base.Aerosolbomb",          chance = 0.15, min = 1, max = 1 },
        { item = "Base.Molotov",              chance = 0.15, min = 1, max = 1 },
        { item = "Base.FlameTrap",            chance = 0.15, min = 1, max = 1 },
        { item = "Base.SmokeBomb",            chance = 0.20, min = 1, max = 1 },
        { item = "Base.NoiseTrap",            chance = 0.20, min = 1, max = 1 },
        -- Электроника
        { item = "Base.WalkieTalkie4",        chance = 0.50, min = 1, max = 2 },
        { item = "Base.Battery",              chance = 0.50, min = 1, max = 2 },
        { item = "Base.ElectronicsScrap",     chance = 0.40, min = 1, max = 2 },
        { item = "Base.Wire",                 chance = 0.30, min = 1, max = 2 },
        { item = "Base.Lighter",              chance = 0.40, min = 1, max = 1 },
        -- Редкие
        { item = "Base.Katana",               chance = 0.05, min = 1, max = 1 },
        { item = "Base.Sledgehammer",         chance = 0.05, min = 1, max = 1 },
        { item = "Base.CarBatteryCharger",    chance = 0.25, min = 1, max = 1 }, 
    },
}

-- ---------------------------------------------------------------------------
-- Настройки зомби для типов событий
-- ---------------------------------------------------------------------------

PZRC_EventConfig.Zombies = {
    buildingstash    = { min = 20,  max = 30  },
    foreststash      = { min = 15,  max = 20  },
    airdrop          = { min = 20, max = 30  },
    abandonedvehicle = { min = 15,  max = 25  },
    camp             = { min = 15, max = 20  },
    helicoptercrash  = { min = 50, max = 80 },
}

-- ---------------------------------------------------------------------------
-- Настройки транспорта (AbandonedVehicle)
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Радио-сообщения при спавне события
-- Лежат внутри мода (media/event_messages.txt), читаются getModFileReader.
-- Формат: секции [typename], сообщения по одной строке, {x}/{y} — плейсхолдеры
-- Опциональный override: ~/Zomboid/Lua/PZRC_event_messages.txt
-- ---------------------------------------------------------------------------

PZRC_EventConfig.EVENT_MESSAGES_FILE_REL      = "media/event_messages.txt"
PZRC_EventConfig.EVENT_MESSAGES_FILE_OVERRIDE = "PZRC_event_messages.txt"

-- ---------------------------------------------------------------------------
-- Интервал автоспавна (в реальных минутах)
-- ---------------------------------------------------------------------------

-- AUTO_SPAWN_INTERVAL_MINUTES теперь читается через sandbox option
-- (EventAutoSpawnIntervalMinutes, default 5). См. metatable PZRC_EventConfig выше.

-- Типы для автоспавна с весами (чем больше weight, тем чаще спавнится)
PZRC_EventConfig.AUTO_SPAWN_TYPES = {
    { type = "buildingstash",    weight = 30 },
    { type = "foreststash",      weight = 20 },
    { type = "camp",             weight = 15 },
    { type = "abandonedvehicle", weight = 10 },
    { type = "airdrop",          weight = 10 },
    { type = "helicoptercrash",  weight = 5 },
}

-- ---------------------------------------------------------------------------
-- Координаты спавна событий (центры поиска)
-- ---------------------------------------------------------------------------

PZRC_EventConfig.FOREST_CRATE_SPRITE = "carpentry_01_16"

PZRC_EventConfig.Locations = {
    buildingstash = {
        {x=10878, y=7138},
        {x=10901, y=7140},
        {x=10732, y=6998},
        {x=10657, y=7188},
        {x=11241, y=6766},
        {x=11243, y=6789},
        {x=11243, y=6807},
        {x=11245, y=6835},
        {x=11242, y=6863},
        {x=11417, y=6874},
        {x=11440, y=6876},
        {x=11499, y=6873},
        {x=11566, y=6880},
        {x=11619, y=6880},
        {x=11673, y=6879},
        {x=11789, y=6860},
        {x=11865, y=6756},
    },
    foreststash = {
        {x=11807, y=7103},
        {x=11840, y=7105},
        {x=11935, y=7126},
        {x=12008, y=7140},
    },
    abandonedvehicle = {
        {x=11708, y=7180},
        {x=11834, y=7181},
        {x=11912, y=7181},
        {x=12019, y=7180},
        {x=12236, y=7139},
        {x=12238, y=7014},
        {x=12253, y=6865},
        {x=12370, y=6639},
    },
    airdrop = {
        {x=11197, y=6983},
        {x=11062, y=6976},
        {x=10956, y=7000},
        {x=10820, y=6844},
        {x=10820, y=6681},
        {x=10656, y=6763},
    },
    camp = {
        {x=11541, y=7899},
        {x=11988, y=7905},
        {x=10194, y=7948},
        {x=9750, y=9825},
        {x=9170, y=9826},
    },
    helicoptercrash = {
        {x=11197, y=6983},
        {x=11062, y=6976},
        {x=10956, y=7000},
        {x=10820, y=6844},
        {x=10820, y=6681},
        {x=10656, y=6763},
        {x=11541, y=7899},
        {x=11988, y=7905},
    },
}

-- ---------------------------------------------------------------------------
-- Настройки транспорта (AbandonedVehicle)
-- ---------------------------------------------------------------------------

PZRC_EventConfig.Vehicle = {
    -- ВНИМАНИЕ: типы должны отсутствовать в ProfessionVehicles из мода
    -- "10YrsVehicles" (3417263423). Тот мод хукает Events.OnSpawnVehicleStart
    -- и подменяет указанные типы на сгоревшие каркасы без частей
    -- (см. ProfessionVehicles.CarLightsPolice — выпадает NormalCarBurntState
    -- и подобные shell-only машины без багажника, сидений и движка).
    -- Если будешь добавлять новые типы — проверь, что их нет в
    -- ProfessionVehicles.* в файле 10YrsVehicles/ProfessionVehicles.lua.
    types = {
        "Base.CarNormal",
        "Base.PickUpTruck",
        "Base.OffRoad",
        "Base.Van",
    },
    -- Состояние: engine 0..100, fuel 0..1, missingTire chance
    condition = {
        engineMin = 0,
        engineMax = 11,
        fuelMin = 0.0,
        fuelMax = 0.5,
        missingTireChance = 0.6,
    },
}

-- ---------------------------------------------------------------------------
-- Загрузка внешнего конфига поверх дефолтов
-- ---------------------------------------------------------------------------
if isServer() then
end
