-- ============================================================================
--  ROOXHUB - BREAK AND STEAL AN EGG  (GAME LOGIC)
-- ============================================================================
--  Arsitektur:
--    * TemplateUi.lua = UI framework generik (WindUI, tab Overview/Misc/
--                        Webhook/Configs/Settings, config save/load, anti-afk,
--                        FPS counter, cleanup). TIDAK di-obfuscate, di-host di
--                        GitHub dan di-load via HttpGet.
--    * File ini        = HANYA logic game Break and Steal an Egg. INI yang
--                        di-obfuscate.
--
--  Alur hidup:
--    1. load TemplateUi  -> dapat tabel `ctx`
--    2. ctx:registerGame({ ...callbacks... })  -> daftarkan logic game
--    3. ctx:start()                             -> bangun UI + jalankan
-- ============================================================================

local ctx = loadstring(game:HttpGet("https://raw.githubusercontent.com/lampumenyala/blablabla/refs/heads/main/TemplateUi.lua"))()({
    Name        = "Break and Steal an Egg",
    Version     = "3.0.2",
    Folder      = "RooxHub",
    GlobalFlag  = "RooxHub_BSv2_Running",
    CleanupFlag = "RooxHub_BSv2_Cleanup",
})

--------------------------------------------------------------------------------
-- SHARED ALIASES (table yang sama dengan ctx; bukan copy)
--------------------------------------------------------------------------------
local GAME_CONFIG       = ctx.GAME_CONFIG
local Config            = ctx.Config
local Stats             = ctx.Stats
local Flags             = ctx.Flags
local Connections       = ctx.Connections
local UIElements        = ctx.UIElements
local Players           = ctx.Players
local ReplicatedStorage = ctx.ReplicatedStorage
local RunService        = ctx.RunService
local LocalPlayer       = ctx.LocalPlayer
local WindUI            = ctx.WindUI
local UserInputService  = ctx.UserInputService
local HttpService       = ctx.HttpService
local CoreGui           = ctx.CoreGui

-- Dipakai footer embed webhook pet (dulu ada di boilerplate UI).
local DISCORD_INVITE    = "https://discord.gg/7rQmEenAdk"

-- Tabel export lintas-callback: diisi onInit, dibaca callback tab/webhook yang
-- berada di scope berbeda.
local G = {}

-- ============================================================================
-- DAFTARKAN GAME
-- ============================================================================
ctx:registerGame({
    -- Semua setting gameplay ditulis ke Config di dalam onInit, jadi
    -- configFields boleh kosong: tiap key sudah non-nil saat config tersimpan
    -- di-apply (syarat applyConfig milik template).
    configFields = {},
    statsFields  = {},
    flagFields   = {},

    --------------------------------------------------------------------------
    -- onInit: seluruh logic game (state, module game, remote, engine, loop).
    --------------------------------------------------------------------------
    onInit = function(ctx)
        -- Helper debug/no-op yang dipanggil feature body.
        local function dbg() end
        local function backpackPetCount()
            local bp = LocalPlayer:FindFirstChild("Backpack")
            local n = 0
            if bp then
                for _, t in ipairs(bp:GetChildren()) do
                    if t:IsA("Tool") then n = n + 1 end
                end
            end
            return n
        end

----------------------------------------------------------------
-- BREAK & STEAL: CONFIG / HELPERS / LOOPS
----------------------------------------------------------------
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

-- netralkan loop lama dari versi sebelumnya (mencegah loop menumpuk)
pcall(function()
    getgenv().RooxHub_BreakAndSteal_Running = false
    local prev = getgenv().__rooxFeatureLoop
    if prev and typeof(prev) == "RBXScriptConnection" then
        prev:Disconnect()
    end
    getgenv().__rooxFeatureLoop = nil
end)

local Config = {
    AutoSteal = false,
    AutoStealPlayer = false,
    EggFilter = "Semua",
    -- Egg Priority: how the next egg is picked when several are in range.
    --   "Fastest Break" = lowest MaxHealth, "Nearest" = closest,
    --   "Best Luck" = highest HatchLuck, "Biggest Size" = largest egg.
    EggPriority = "Nearest",
    -- Egg Type filter: only break eggs whose EggType is in this set. Empty = all.
    EggTypeFilter = {},
    -- Pet collection filter for Auto Break / Auto Steal: by RARITY now
    -- (was by name). Empty = collect every rarity. INDEX_FILTER (Auto Complete
    -- Index) still overrides it.
    PetRarityFilter = {},
    -- Mutation filter for Auto Break / Auto Steal: collect only pets whose
    -- "Mutation" attribute is in this set. Empty = every mutation. The special
    -- "None" entry matches pets with no Mutation attribute.
    MutationFilter = {},
    AutoStealMinIncome = 0,
    -- Final delivery spot (hardcoded, inside the SafeZone): after a successful
    -- force-pickup in the target zone the pet is force-TP'd here and the server
    -- banks it on arrival. No SafeZone-spot computation / bank walk is used.
    SafeDropPos = Vector3.new(-57.46, 3.50, 0.95),
    -- "Help Other Player" (Auto Break only): when ON, the Auto Break delivery takes
    -- the seized/farmed pet to THIS spot and DROPS it (for another player to grab)
    -- instead of banking it in the SafeZone, then starts a new cycle.
    HelpOtherPlayer = false,
    HelpDropPos = Vector3.new(-95.84, 3.50, 13.27),
    FarZoneMeta = true,
    -- Auto Titanic Egg: ON = prioritize the titanic egg wherever it spawns; OFF
    -- (default) = ignore it entirely (never targeted, even if it is the nearest egg).
    AutoTitanicEgg = false,
    -- Auto Complete Index: farm the lowest zone still missing Index pets, collecting
    -- only those missing pets (internal override). Requires Auto Break ON.
    AutoCompleteIndex = false,
    GuardBaitTimeout = 20,
    MetaWalkSpeed = 50,
    -- HUNT delivery: the guard must SEIZE the carried pet this many times before the
    -- SafeZone bank is valid. The new HUNT uses a SINGLE catch: spawn onto the target,
    -- steal the pet, walk to the guard, and that one seize authorises the
    -- force-pickup + force-TP to the SafeZone.
    HuntGuardHits = 1,
    AutoTreadmill = false,
    AutoUpgradePickaxe = false,
    -- Pickaxe upgrade multi-select filter (Upgrade tab). Empty = never upgrade.
    -- Only the NEXT tier is bought, and only when its name is selected here.
    PickaxeUpgradeFilter = {},
    AutoUpgradeTreadmill = false,
    AutoUpgradePlot = false,
    AutoUpgradeTrail = false,
    AutoUnlockTreadmill = false,
    AutoPlaceBest = false,
    AutoSell = false,
    SellRarities = {},
    SellInterval = 5,
    AutoMerge = false,
    MergeRarities = {},
    AutoFuse = false,
    AutoHatch = false,
    AutoPlantEgg = false,
    PlantRarities = {},
    AntiKnockback = false,
    AntiAfk = true,
    -- Auto Tutorial (BigFroot parity): while the game tutorial is active, run its
    -- steps FIRST (break a Zone 1 egg, steal, escape/bank, pen, treadmill, ...)
    -- before the normal farm/TP loop. Off = ignore the tutorial.
    AutoTutorial = true,
    -- Auto Claim Index: fire the game's own Index "Claim All" (IndexRemote
    -- "ClaimAll") whenever the Index panel shows it has unclaimed rewards.
    AutoClaimIndex = false,
    AutoDiamondMounted = false,
    DiamondMountedAmounts = {},
    AutoDiamondPlotSkin = false,
    DiamondPlotSkinFilter = {},
    DiamondShopCooldown = 1.0,
    WebhookEnabled = false,
    WebhookUrl = "",
    WebhookRarityFilter = {},
    WebhookNameFilter = {},
    WebhookIncludePlot = true,
    -- FPS Boost (Settings tab)
    BoostUltra = false,
    BoostNoEffects = false,
    -- Movement (Misc tab)
    NoClip = false,
    -- Movement engine selector (BigFroot logic):
    --   "TP v1" = WALK (genuine Humanoid:Move, like Walk mode) to Zone 1, break an
    --             egg + pick up the pet there, let the guard catch us, then TP (the
    --             catch-window hop) to the target-zone egg. It keeps WALKING between
    --             eggs there, picks a pet up, banks via the guard hitguard window,
    --             then the whole cycle restarts from Zone 1 (walked) - never a direct
    --             TP back to the zone.
    --   "TP v2" = TP v1 plus Hop (instant TP to a close egg within HopRange) and
    --             Decoy (instant TP to a Zone1 egg when the window is closing).
    --   "Walk"  = the dedicated real-walk Auto Break engine (Humanoid:Move at the
    --             character's OWN WalkSpeed, treadmill-grinded).
    -- The engines never run together - the dropdown picks one.
    MovementMode = "Walk",
    -- WALK engine SafeZone anchor point (hardcoded). The return-to-SafeZone leg reuses
    -- this SAME start point, so only one coordinate is needed.
    WalkStartPos = Vector3.new(-57.46, 3.50, 0.95),
}
-- Merge ke tabel ctx.Config bersama, lalu rebind supaya semua kode berikutnya
-- (termasuk tab & template) memutasi TABEL YANG SAMA yang disimpan/di-load.
for k, v in pairs(Config) do ctx.Config[k] = v end
Config = ctx.Config

local ZONES = {
    { Name = "Forest", Id = "Zone1" },
    { Name = "Desert", Id = "Zone2" },
    { Name = "Snowy", Id = "Zone3" },
    { Name = "Candy", Id = "Zone4" },
    { Name = "Swamp", Id = "Zone5" },
    { Name = "Ocean", Id = "Zone6" },
    { Name = "Hell", Id = "Zone7" },
    { Name = "Blossom", Id = "Zone8" },
    { Name = "Galaxy", Id = "Zone9" },
    { Name = "Planet X", Id = "Zone10" },
    { Name = "Haunted Graveyard", Id = "Zone11" },
    { Name = "Fairy Castle", Id = "Zone12" },
    { Name = "Fantasy Expansion", Id = "Zone13" },
}
local ZONE_ID = {}
local ZONE_NAMES = { "Semua" }
for _, z in ipairs(ZONES) do
    ZONE_ID[z.Name] = z.Id
    ZONE_NAMES[#ZONE_NAMES + 1] = z.Name
end

local PET_NAMES = {}
pcall(function()
    local AnimalRenders = require(ReplicatedStorage.Shared.AnimalRenders)
    local normal = AnimalRenders and AnimalRenders.Normal
    if normal then
        for name in pairs(normal) do
            PET_NAMES[#PET_NAMES + 1] = name
        end
    end
end)
table.sort(PET_NAMES)

local PET_FILTER_VALUES = { "All Pet" }
for _, n in ipairs(PET_NAMES) do
    PET_FILTER_VALUES[#PET_FILTER_VALUES + 1] = n
end

-- Egg Type values for the "Egg Type" filter, straight from the game's own
-- EggConfig.Eggs (e.g. "Supernova Egg", "Skull Egg", "PhoenixEgg", ...). These are
-- exactly the strings written into each egg's "EggType" attribute.
local EGG_TYPE_VALUES = {}
pcall(function()
    local EggConfig = require(ReplicatedStorage.Shared.EggConfig)
    if type(EggConfig.Eggs) == "table" then
        for name in pairs(EggConfig.Eggs) do
            EGG_TYPE_VALUES[#EGG_TYPE_VALUES + 1] = tostring(name)
        end
    end
end)
table.sort(EGG_TYPE_VALUES)

-- Rarity filter values (high -> low) for the Auto Farm "Filter by Rarity" dropdown.
-- The full ladder, including Void, Omega & Ethereal (which the old RARITIES list omitted).
local PET_RARITY_VALUES = {
    "Primordial", "Ethereal", "Spectral", "Omega", "Void", "Inferno", "Celestial", "Secret", "Cosmic", "Divine",
    "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common",
}

-- Auto Complete Index (internal filter override; nil = disabled). When set, the
-- Auto Break pipeline farms ZoneId and collects ONLY the Missing pet names.
local INDEX_FILTER = { Missing = nil, ZoneId = nil }

-- rarityOfName is defined further down (needs EggRewards / ZoneAnimalsConfig); it is
-- forward-declared here so petAllowed can call it.
local rarityOfName
-- Pet allowed for collection: Auto Complete Index wins, then the RARITY filter
-- (Config.PetRarityFilter), then the MUTATION filter (Config.MutationFilter).
-- Empty filters = everything allowed. In the mutation filter, "None" matches a
-- pet whose Mutation attribute is nil.
local function petAllowed(name, mut)
    if INDEX_FILTER.Missing then
        return name ~= nil and INDEX_FILTER.Missing[name] == true
    end
    local rf = Config.PetRarityFilter
    if rf and next(rf) ~= nil then
        local r = name ~= nil and rarityOfName and rarityOfName(name) or nil
        if not (r ~= nil and rf[r] == true) then return false end
    end
    local mf = Config.MutationFilter
    if mf and next(mf) ~= nil then
        if mut == nil then return mf["None"] == true end
        return mf[mut] == true
    end
    return true
end

local ZoneHitboxLookup = nil
do
    local okZL, mZL = pcall(function() return require(ReplicatedStorage.Shared.ZoneHitboxLookup) end)
    if okZL then ZoneHitboxLookup = mZL end
end

local function zoneOfPosition(pos)
    -- Authoritative: the game's own zone hitbox containment (Workspace.Build.
    -- ZoneHitboxes/<n>). Returns "ZoneN", or nil inside the SafeZone / outside any
    -- zone hitbox.
    if ZoneHitboxLookup and type(ZoneHitboxLookup.GetZoneAt) == "function" then
        local ok, id = pcall(function() return ZoneHitboxLookup.GetZoneAt(pos) end)
        if ok and type(id) == "string" then
            if id == "SafeZone" then return nil end
            return id
        end
    end
    -- Fallback: nearest zone by its real (tagged) ZoneGuard pivot. Never use the
    -- first Model child: some zones (e.g. Zone7 Hell) have a non-guard model first,
    -- so that old heuristic mis-routed the guard walk to the neighbouring zone.
    local build = Workspace:FindFirstChild("Build")
    local zb = build and build:FindFirstChild("ZoneBuilds")
    if not zb then return nil end
    local best, bd = nil, math.huge
    for _, z in ipairs(zb:GetChildren()) do
        if string.match(z.Name, "^Zone%d+$") then
            local guard = nil
            for _, m in ipairs(z:GetChildren()) do
                if m:IsA("Model") and CollectionService:HasTag(m, "ZoneGuard") then guard = m; break end
            end
            local pivot
            if guard then
                local h = guard:FindFirstChild("HumanoidRootPart", true)
                pivot = (h and h.Position) or guard:GetPivot().Position
            else
                pivot = z:GetPivot().Position
            end
            local d = (pivot - pos).Magnitude
            if d < bd then bd = d; best = z.Name end
        end
    end
    return best
end

--------------------------------------------------------------------------------
-- FAR-ZONE META HELPERS
-- The META pipeline (TRAVEL -> BREAK -> PICKUP -> SECURE) is BigFroot-style TP:
-- it no longer self-kills or respawn-pins. It simply steps to an egg in the
-- target zone, breaks it, grabs the pet, then steps to the SafeZone to bank.
-- FAR_ZONE_FROM = 1 routes EVERY specific zone through this pipeline.
local FAR_ZONE_FROM = 1
local function zoneIndexFromId(id)
    if type(id) ~= "string" then return nil end
    local n = tonumber(id:match("^Zone(%d+)$"))
    return n
end
local function zoneBuild(id)
    local build = Workspace:FindFirstChild("Build")
    local zb = build and build:FindFirstChild("ZoneBuilds")
    return zb and id and zb:FindFirstChild(id) or nil
end
local function zoneGuard(id)
    local z = zoneBuild(id)
    if not z then return nil end
    for _, m in ipairs(z:GetChildren()) do
        if m:IsA("Model") and CollectionService:HasTag(m, "ZoneGuard") then
            return m
        end
    end
    return z:FindFirstChildOfClass("Model")
end
-- Titanic-egg handling. hasTitanicMark identifies a titanic egg (tag/attribute);
-- titanicSkipped is true when the user turned "Auto Titanic Egg" OFF, in which case
-- EVERY egg picker must ignore it entirely (not merely de-prioritise it).
local function hasTitanicMark(e)
    return e ~= nil and (CollectionService:HasTag(e, "TitanicEgg") or e:GetAttribute("Titanic") == true)
end
local function titanicSkipped(e)
    return Config.AutoTitanicEgg == false and hasTitanicMark(e)
end
-- Egg Type filter: when any egg types are selected, only those may be targeted.
local function eggTypeAllowed(e)
    local set = Config.EggTypeFilter
    if not set or next(set) == nil then return true end
    local t = e and e:GetAttribute("EggType")
    return t ~= nil and set[t] == true
end
-- A REAL breakable egg. The game tags live eggs "BreakableEgg", but a zone's Eggs
-- folder ALSO holds untagged decor/placeholder parts (e.g. Zone6 "3: Water Egg") that
-- have no Health and can never be broken. Those must be ignored by the in-zone
-- pickers or the META latches onto one (Health=nil read as "already broken") and stalls.
local function pickableEgg(e)
    return e ~= nil and e:IsA("BasePart")
        and CollectionService:HasTag(e, "BreakableEgg")
        and not e:GetAttribute("Broken") and not e:GetAttribute("Hatching") and not e:GetAttribute("Despawning")
end
-- Forward declarations: defined with the other egg helpers further down, but used
-- by the in-zone pickers below (which are defined before Runtime exists).
local findTitanicEgg, titanicZoneId

-- Egg Priority comparator (Config.EggPriority). Returns (key, lowerIsBetter).
local function eggPriorityKey(e, pos)
    local pr = Config.EggPriority
    if pr == "Fastest Break" then
        local h = e:GetAttribute("MaxHealth")
        if type(h) ~= "number" then h = e:GetAttribute("Health") end
        if type(h) ~= "number" then h = math.huge end
        return h, true
    elseif pr == "Best Luck" then
        local l = e:GetAttribute("HatchLuck")
        if type(l) ~= "number" then l = e:GetAttribute("Luck") end
        if type(l) ~= "number" then l = 0 end
        return l, false
    elseif pr == "Biggest Size" then
        local s = e.Size
        return math.max(s.X, s.Y, s.Z), false
    end
    return (pos and (e.Position - pos).Magnitude) or 0, true
end
local function eggBeats(e, cur, pos)
    if not cur then return true end
    local a, aLow = eggPriorityKey(e, pos)
    local b, bLow = eggPriorityKey(cur, pos)
    if aLow then return a < b end
    return a > b
end

local function firstEggInZone(id, pos)
    -- Titanic egg first (it may have spawned in this zone), regardless of ordering.
    local t = findTitanicEgg(nil)
    if t and titanicZoneId(t) == id then return t end
    local z = zoneBuild(id)
    local eggs = z and z:FindFirstChild("Eggs")
    if not eggs then return nil end
    local best = nil
    for _, m in ipairs(eggs:GetChildren()) do
        local e = m:FindFirstChild("Egg")
        if pickableEgg(e) and not titanicSkipped(e) and eggTypeAllowed(e) and eggBeats(e, best, pos) then best = e end
    end
    return best
end
local function nearestEggInZone(pos, id)
    -- Titanic egg first if it is in this zone.
    local t = findTitanicEgg(pos)
    if t and titanicZoneId(t) == id then return t end
    local z = zoneBuild(id)
    local eggs = z and z:FindFirstChild("Eggs")
    if not eggs then return nil end
    local best = nil
    for _, m in ipairs(eggs:GetChildren()) do
        local e = m:FindFirstChild("Egg")
        if pickableEgg(e) and not titanicSkipped(e) and eggTypeAllowed(e) and eggBeats(e, best, pos) then best = e end
    end
    return best
end

local RARITIES = {
    "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic",
    "Divine", "Cosmic", "Secret", "Celestial", "Inferno", "Void", "Omega", "Spectral", "Ethereal", "Primordial",
}

local RARITIES_DESC = {
    "Primordial", "Ethereal", "Spectral", "Omega", "Void", "Inferno", "Celestial", "Secret", "Cosmic", "Divine", "Mythic",
    "Legendary", "Epic", "Rare", "Uncommon", "Common",
}

local ANIMAL_RARITY = {}
pcall(function()
    local ZoneAnimalsConfig = require(ReplicatedStorage.Shared.ZoneAnimalsConfig)
    if ZoneAnimalsConfig then
        for _, zone in ipairs(ZoneAnimalsConfig.Zones or {}) do
            for _, a in ipairs(zone) do
                if a.Name and a.Rarity then ANIMAL_RARITY[a.Name] = a.Rarity end
            end
        end
        for _, a in ipairs(ZoneAnimalsConfig.Extras or {}) do
            if a.Name and a.Rarity then ANIMAL_RARITY[a.Name] = a.Rarity end
        end
        for name, a in pairs(ZoneAnimalsConfig.Legacy or {}) do
            if a.Rarity then ANIMAL_RARITY[name] = a.Rarity end
        end
    end
end)

local EggRewards = nil
pcall(function() EggRewards = require(ReplicatedStorage.Shared.EggRewards) end)

local AnimalRenders = nil
pcall(function() AnimalRenders = require(ReplicatedStorage.Shared.AnimalRenders) end)

local RagdollPhysics = nil
pcall(function() RagdollPhysics = require(ReplicatedStorage.Shared.RagdollPhysics) end)

local PickaxeConfig = nil
local TreadmillUpgradeConfig = nil
local PlotUpgradeConfig = nil
local TreadmillUnlockConfig = nil
local TrailsConfig = nil
pcall(function()
    PickaxeConfig = require(ReplicatedStorage.Shared.PickaxeConfig)
    TreadmillUpgradeConfig = require(ReplicatedStorage.Shared.TreadmillUpgradeConfig)
    PlotUpgradeConfig = require(ReplicatedStorage.Shared.PlotUpgradeConfig)
    TreadmillUnlockConfig = require(ReplicatedStorage.Shared.TreadmillUnlockConfig)
    TrailsConfig = require(ReplicatedStorage.Shared.TrailsConfig)
end)

local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request) or (krnl and krnl.request)
local RARITY_COLORS = {
    Common = 9807270, Uncommon = 3066993, Rare = 3447003, Epic = 10181046,
    Legendary = 16744448, Mythic = 16711680, Divine = 16766720, Cosmic = 10181046,
    Secret = 16724735, Celestial = 15844367, Inferno = 15158332, Spectral = 5635925,
    Void = 9848575, Omega = 4652920, Ethereal = 16752870, Primordial = 4645280,
}
local petThumbCache = {}

local function rarityOfTool(t)
    local name = t:GetAttribute("AnimalName")
    if EggRewards and EggRewards.RarityOf and name then
        local r = EggRewards.RarityOf(name)
        if r then return r end
    end
    local r2 = t:GetAttribute("Rarity")
    if type(r2) == "string" then return r2 end
    if name then return ANIMAL_RARITY[name] end
    return nil
end

function rarityOfName(name)
    if EggRewards and EggRewards.RarityOf and name then
        local r = EggRewards.RarityOf(name)
        if r then return r end
    end
    if name then return ANIMAL_RARITY[name] end
    return nil
end

local Runtime = {
    Phase = "IDLE",
    PhaseTimer = 0,
    TargetEgg = nil,
    BreakPos = nil,
    LastHit = 0,
    Stolen = 0,
    Secured = 0,
    Hits = 0,
    LastStatus = 0,
    LastTick = 0,
    StealInFlight = false,
    LastEggScan = 0,
    LastPromptScan = 0,
    LastSwingKill = 0,
    LastBuy = 0,
    LastBat = 0,
    HuntTarget = nil,
    HuntPos = nil,
    HuntStage = nil,
    HuntStageAt = 0,
    HuntCarried = nil,
    HuntRecoverPick = nil,
    -- Auto Steal Player webhook: stolen pet info captured at pickup + dedup guard
    HuntPetInfo = nil,
    HuntWebhookName = nil,
    HuntWebhookAt = 0,
    HuntKind = nil,
    HuntDropTarget = nil,
    HuntPetZone = nil,
    HuntCoolUntil = 0,
    HuntForcePos = nil,
    HuntForceUntil = 0,
    HuntForcePin = false,
    -- earliest time the pin may release-on-landing (prevents an instant release
    -- right after a respawn jump, which the server then reconciles away)
    HuntForceMinUntil = 0,
    -- one self-respawn per HUNT phase (set on the first RESPAWN kill)
    HuntRespawned = false,
    -- HUNT respawn relocation verification (mirror of the far-zone META RELOCATE):
    -- the respawn pin is re-issued and only trusted once we SETTLE on the target,
    -- so a server pull-back re-pins instead of stranding us at the game's spawn.
    HuntRelocPos = nil,
    HuntRelocAt = 0,
    HuntRelocTries = 0,
    HuntRelocDone = false,
    HuntRelocStart = 0,
    -- the exact point the last pin was issued to; the verify compares our position
    -- to THIS (not the live target) so a moving carrier cannot defeat the settle
    -- test - only a server pull-back moves us away from it.
    HuntRelocDest = nil,
    BatSwings = 0,
    LastEquipBest = 0,
    LastSell = 0,
    LastMerge = 0,
    -- Auto Fuse (FuseMachineRequest): remote-only, like Auto Merge.
    FuseRecipe = nil,       -- {[slotIndex] = petName} from the server "State"
    FuseDeposits = nil,     -- set of server-confirmed deposited pet names
    FuseSent = nil,         -- {[petName] = os.clock()} deposits fired, not yet confirmed
    FuseLastAction = 0,
    FuseLastSync = 0,
    FuseInFlight = false,
    FuseCount = 0,
    LastHatch = 0,
    LastUpgrade = 0,
    LastTreadUp = 0,
    LastPlotUp = 0,
    LastTreadUnlock = 0,
    LastKnock = 0,
    LastSource = "Auto Break",
    DragonTread = 0,
    OnTreadmill = false,
    TreadmillMode = false,
    TreadmillEndAt = 0,
    HoldCFrame = nil,
    HoldUntil = 0,
    BurstEgg = nil,
    PendingPhase = nil,
    PendingHunt = nil,
    LeaveStarted = 0,
    LastExitPress = 0,
    ConfigLoading = false,
    SecureTpAt = 0,
    LastHuntMove = 0,
    TravelDest = nil,
    TravelStrikes = 0,
    TravelSpeed = 0,

    StrikePauseUntil = 0,
    -- META pipeline (BigFroot-style TP: TRAVEL -> BREAK -> PICKUP -> SECURE).
    MetaStage = nil,
    MetaStageAt = 0,
    MetaZone = nil,
    MetaZoneId = nil,
    -- Guard-fling window (shared with HUNT): set the instant a guard catch lands.
    -- inWindow() reads RagdollUntil; the v2 Hopper/Leap/Decoy use these.
    RagdollUntil = 0,
    FlungAt = 0,
    CatchAt = nil,
    DecoyTried = 0,
    HopRange = 80,
    LeapRange = 120,
    Closing = 0.8,
    -- BigFroot hitguard banking sub-machine (BAIT -> RECOVER -> LEAP).
    BankStage = nil,
    BankAt = 0,
    BankPick = nil,
    BankWant = nil,
    BankLeapt = false,
    BankPulled = false,
    BankHelpDrop = false,
    -- Zone 1 decoy entry for FAR zones (BigFroot): before entering a far zone,
    -- break+pickup in Zone 1 so the guard catches us (hitguard), then hop to the
    -- far zone during that window. Runs once per target zone.
    DecoyStage = nil,     -- nil | GOTO1 | BREAK | PICKUP | BAIT | HOP
    DecoyZone = nil,      -- target far zone to hop to
    DecoyEgg = nil,
    DecoyPick = nil,
    DecoyStageAt = 0,
    DecoyPulled = false,
    DecoyDoneZone = nil,  -- far zone already entered via decoy
    -- When the decoy can't be used (no Zone 1 egg / no guard catch), enter the far
    -- zone by WALKING instead of an instant TP (BigFroot retry behaviour).
    MetaWalkEntry = false,
    GuardHitAt = 0,
    GuardHitState = nil,
    ForceTpArmed = false,
    LastStealAttempt = 0,
    MetaSteals = 0,
    MetaLoop = 0,
    MetaWarnedFull = false,
    MetaPick = nil,
    MetaLeg = "TARGET",
    -- respawn-relocate entry (mirror HUNT): self-kill ONCE, then the CharacterAdded
    -- handler pins us onto an egg in the target zone.
    MetaRespawned = false,
    MetaRespawnPending = false,
    MetaRespawnAt = 0,
    MetaSpawnPos = nil,
    -- respawn-relocate verification (no walk fallback): a pin was issued at
    -- MetaRelocAt; if we are not in the target zone once it settles, re-pin.
    MetaRelocAt = 0,
    MetaRelocTries = 0,
    -- the exact point the last META pin was issued to. The settle test compares our
    -- position to THIS (not a re-derived spawn) so a server pull-back is detected even
    -- if nearestEggInZone returns a different egg while we sit at the game spawn.
    MetaRelocDest = nil,
    -- start of the current META relocate (hard bound so it cannot loop near the plot)
    MetaRelocStart = 0,
    -- "ready after pin" timer: set when the pinned character is settled+ready; BREAK
    -- only starts once it has stayed ready for MOVE.RelocReadyHold.
    MetaReadyAt = 0,
    -- live titanic presence (other features yield to the titanic META).
    TitanicAlive = false,
    TitanicCoolUntil = 0,
    -- Auto Complete Index status (for the UI)
    IndexZone = nil,
    IndexMissingCount = nil,
    IndexWaiting = false,
    BeingChased = false,
    MetaForcePos = nil,
    MetaForceUntil = 0,
    MetaForceStart = 0,
    ForcePin = nil,
    TpAttemptAt = 0,
    MetaCoolUntil = 0,
    DeliveredBankedAt = 0,
    BankSettle = 0.2,
    ReleaseTries = 0,
    ReleaseDroppedAt = nil,
    ApproachDest = nil,
    ReleaseBankAt = nil,
    SnapCount = 0,
    BankBlockCount = 0,
    LastFailReason = nil,
    LastWalkIssue = 0,
    MetaWalkDest = nil,
    -- anti-stuck watchdog (movement pressed against geometry with no progress).
    TravelWatchPos = nil,
    TravelWatchAt = 0,
    TravelStuckCount = 0,
    -- Far-zone streaming state (Workspace.StreamingEnabled): far zones keep an
    -- EMPTY Eggs folder until their content is streamed, so features must go to
    -- the zone entry and wait there instead of standing still. Streaming is
    -- requested ONCE per zone (ZoneStreamedFor); repeating it spawned threads
    -- every couple of seconds and caused lag.
    ZoneStreamedFor = nil,
    ZoneAnchorCache = {},
    WalkZoneWaitAt = nil,
    WalkZoneNotified = false,
    MetaZoneWaitAt = nil,
    MetaZoneNotified = false,
    MetaAnchorTpAt = 0,
    DecoyHOPAt = 0,
}
getgenv().__bst = Runtime
getgenv().__bstcfg = Config

local function indexWaitingNow()
    return Config.AutoCompleteIndex == true and Runtime.IndexWaiting == true
end
local function activeZoneId()
    if Config.AutoCompleteIndex then
        if INDEX_FILTER.ZoneId then return INDEX_FILTER.ZoneId end
        if Runtime.IndexWaiting then return nil end
    end
    return ZONE_ID[Config.EggFilter]
end
local function isFarZoneFilter()
    local id = activeZoneId()
    if not id then return false end
    local n = zoneIndexFromId(id)
    return n ~= nil and n >= FAR_ZONE_FROM
end

-- ============================================================================
-- EGG VISUAL LAG KILL (always on, no setting): silence the per-hit damage popup,
-- the egg hit VFX / shrink / camera shake, and the egg debris chunks. Sounds and
-- the post-break HatchVFX burst are left alone.
-- ============================================================================
do
    pcall(function()
        local EggConfig = require(ReplicatedStorage.Shared.EggConfig)
        -- hit VFX / shrink / camera shake off
        local hit = EggConfig.Hit
        if type(hit) == "table" then
            hit.VFXName = ""
            hit.FlashTime = 0
            hit.ShrinkScale = 1
            hit.ShrinkTime = 0
            hit.RecoverTime = 0
            hit.ShakeAngle = 0
        end
        -- egg debris chunks off
        local deb = EggConfig.Debris
        if type(deb) == "table" then
            deb.MinCount = 0
            deb.MaxCount = 0
        end
        -- damage popup off: never hand out the "EggDamagePopup" template
        local BillboardAssets = require(ReplicatedStorage.Shared.BillboardAssets)
        if type(BillboardAssets.Get) == "function" and not BillboardAssets.__rooxNoPopup then
            local origGet = BillboardAssets.Get
            BillboardAssets.Get = function(...)
                local name = (...)
                if name == BillboardAssets then name = select(2, ...) end
                if name == "EggDamagePopup" then return nil end
                return origGet(...)
            end
            BillboardAssets.__rooxNoPopup = true
        end
        -- egg debris module no-op + clear any leftover chunks
        local ps = LocalPlayer:FindFirstChild("PlayerScripts")
        local cl = ps and ps:FindFirstChild("Client")
        local ctrls = cl and cl:FindFirstChild("Controllers")
        local EggDebris = ctrls and ctrls:FindFirstChild("EggDebris")
        if EggDebris then
            local ok, mod = pcall(function() return require(EggDebris) end)
            if ok and type(mod) == "table" and not mod.__rooxNoErupt then
                mod.Erupt = function() end
                mod.__rooxNoErupt = true
            end
        end
        local dparts = Workspace:FindFirstChild("EggDebrisParts")
        if dparts then dparts:ClearAllChildren() end
        -- remove any existing damage popup gui
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        local dgui = pg and pg:FindFirstChild("EggDamagePopups")
        if dgui then dgui:Destroy() end
    end)
end

local DropCarriedRemote = ReplicatedStorage:FindFirstChild("DropCarriedRemote")
local PickaxeShopRequest = ReplicatedStorage:FindFirstChild("PickaxeShopRequest")
local BatHitRequest = ReplicatedStorage:FindFirstChild("BatHitRequest")
local PetsInventoryRemote = ReplicatedStorage:FindFirstChild("PetsInventoryRemote")
local BackpackSellRemote = ReplicatedStorage:FindFirstChild("BackpackSellRemote")
local MergeMachineRemote = ReplicatedStorage:FindFirstChild("MergeMachineRemote")
local FuseMachineRequest = ReplicatedStorage:FindFirstChild("FuseMachineRequest")
local UpgradeTreadmillRequest = ReplicatedStorage:FindFirstChild("UpgradeTreadmillRequest")
local UpgradePlotRequest = ReplicatedStorage:FindFirstChild("UpgradePlotRequest")
local UnlockTreadmillRequest = ReplicatedStorage:FindFirstChild("UnlockTreadmillRequest")
local TrailShopRequest = ReplicatedStorage:FindFirstChild("TrailShopRequest")

--------------------------------------------------------------------------------
-- FEATURE BODY
-- Scoped in an IIFE so its locals live in their own 200-local budget instead of
-- the main chunk's (required for obfuscation).
--------------------------------------------------------------------------------
;(function()
local function getChar()
    local c = LocalPlayer.Character
    return c, c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
end

local function isAlive()
    local c, _, hum = getChar()
    return c and hum and hum.Health > 0
end

local function isCarrying()
    return LocalPlayer:GetAttribute("Carrying") ~= nil
end

--------------------------------------------------------------------------------
-- EGG BREAK = THE GAME'S OWN AUTO SWING (no manual EggHitRequest)
-- Breaking is done EXACTLY the way BigFroot does it: instead of firing
-- EggHitRequest ourselves, we switch ON the game's own AutoSwingController. Its
-- Heartbeat tick picks the nearest egg in range and calls PickaxeController.Swing,
-- which fires BOTH MasteryPickaxeSwing and EggHitRequest(egg, token) with the
-- game's own damage formula (Pickaxe x Potion x Mastery(Power) x RobuxShop). So
-- we send nothing by hand - the game swings, we only toggle the switch.
-- autoSwing(on) mirrors BigFroot's SwingMine rule: we only switch it OFF again if
-- WE were the one who turned it on (never fight a user/game-enabled auto swing).
-- Kept on Runtime to avoid adding top-level locals (main chunk is at the
-- 200-local ceiling).
--------------------------------------------------------------------------------
Runtime.AutoSwingMod = nil
Runtime.AutoSwingMine = false
Runtime.AutoSwingActive = false
Runtime.AutoSwingWarned = false
Runtime.autoSwing = function(on)
    if not Runtime.AutoSwingMod then
        pcall(function()
            local ctrls = LocalPlayer.PlayerScripts.Client.Controllers
            Runtime.AutoSwingMod = require(ctrls.AutoSwingController)
        end)
    end
    local mod = Runtime.AutoSwingMod
    if not (mod and type(mod.SetOn) == "function" and type(mod.IsOn) == "function") then
        return false
    end
    if on then
        if mod.IsOn() == true then
            Runtime.AutoSwingMine = false
        else
            pcall(function() mod.SetOn(true) end)
            Runtime.AutoSwingMine = true
        end
    elseif Runtime.AutoSwingMine then
        pcall(function() mod.SetOn(false) end)
        Runtime.AutoSwingMine = false
    end
    return true
end

-- Surface distance to an egg (EggConfig.HitRange is measured from the egg's
-- surface, not its centre). Falls back to centre distance if the module is
-- unavailable.
Runtime.eggSurfaceDist = function(egg, pos)
    if not egg or not pos then return math.huge end
    local ET = Runtime.EggTargeting
    if not ET then
        pcall(function() ET = require(ReplicatedStorage.Shared.EggTargeting) end)
        Runtime.EggTargeting = ET
    end
    if ET and ET.SurfaceDistance then
        local ok, d = pcall(function() return ET.SurfaceDistance(egg, pos) end)
        if ok and type(d) == "number" then return d end
    end
    return (egg.Position - pos).Magnitude
end

--------------------------------------------------------------------------------
-- MOVE (MICRO-TELEPORT STEPPER)
-- Movement is a series of very small CFrame hops on the HumanoidRootPart toward
-- Runtime.TravelDest. Each frame the engine advances only (speed x frame time)
-- studs, capped by MOVE.MaxStep and by the distance left, so a single hop is
-- always tiny and can never overshoot. No physics velocity and no interpolator
-- object is involved: every hop is planted on the real floor under the target XZ,
-- the physics velocity is zeroed so the game's own ground grip cannot fight it,
-- and the hop is aborted over void or when the character is stuck.
--------------------------------------------------------------------------------
local MOVE = {
    DefaultSpeed = 50,   -- studs/s used when a caller passes no speed (slider default)
    MaxSpeed = 100,      -- hard cap for the auto mover (studs/s)
    MaxStep = 8,         -- max studs covered by ONE hop (lag-spike guard)
    ArriveDist = 4,
    GroundCheckDrop = 60,
    -- Respawn-relocate verification (far-zone auto break + titanic): after the pin,
    -- wait RelocSettle before trusting arrival; if the server pulled us back, re-pin
    -- with a RelocRetry gap (no walk fallback, no spam). RelocMax bounds attempts.
    RelocSettle = 1.5,
    RelocRetry = 3.0,
    RelocArrive = 20,
    RelocMax = 6,
    -- After the META respawn pin lands, the character must stay genuinely READY
    -- (alive, not ragdolled, on the ground, not physics/freefall) for this long
    -- before Auto Break starts breaking - never break on the first settled frame.
    RelocReadyHold = 2.0,
}
getgenv().__bstmove = MOVE
Runtime.TravelDest = nil
Runtime.TravelStrikes = 0
Runtime.TravelSpeed = 0
Runtime.MoveTickAt = 0

-- The ONE speed source for every auto-move. The slider may sit at 0, but a moving
-- feature must still advance, so the value is clamped to [1, MOVE.MaxSpeed].
local function moveSpeed()
    return math.clamp(tonumber(Config.MetaWalkSpeed) or MOVE.DefaultSpeed, 1, MOVE.MaxSpeed)
end
getgenv().__bstspeed = moveSpeed
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

local function hasGroundAt(pos)
    local _, hrp = getChar()
    if hrp then groundParams.FilterDescendantsInstances = { hrp.Parent } end
    local hit = Workspace:Raycast(pos + Vector3.new(0, 12, 0), Vector3.new(0, -MOVE.GroundCheckDrop, 0), groundParams)
    return hit ~= nil
end

-- GROUND CAST: the real floor Y under an XZ column. Breakable eggs are
-- skipped - if the ray lands on one, it is re-cast from just below it -
-- so the character stands on the ground/nest BENEATH an egg, never on top of it.
-- The game's GroundGripController only keeps the character glued to the floor while
-- Humanoid.FloorMaterial ~= Air; a fixed-Y move lifts it off and it floats
-- ("melayang"). This is what lets the move plant the feet on the terrain instead.
-- RespectCanCollide is on (like the game's own floor cast), so non-collidable trigger
-- volumes (treadmill / SafeZone hitboxes) are ignored and the ray lands on real floor.
Runtime.groundYUnderXZ = function(x, z, fromY)
    local _, hrp = getChar()
    groundParams.FilterDescendantsInstances = (hrp and hrp.Parent) and { hrp.Parent } or {}
    local drop = MOVE.GroundCheckDrop + 400
    local from = Vector3.new(x, (fromY or (hrp and hrp.Position.Y) or 0) + 40, z)
    for _ = 1, 4 do
        local hit = Workspace:Raycast(from, Vector3.new(0, -drop, 0), groundParams)
        if not hit then return nil end
        local inst = hit.Instance
        if not CollectionService:HasTag(inst, "BreakableEgg") then
            return hit.Position.Y
        end
        from = hit.Position - Vector3.new(0, 0.1, 0)
    end
    return nil
end

-- Grounded entry point of a zone, used when its content is not streamed in yet
-- (Workspace.StreamingEnabled = true on this game, so far zones have an EMPTY
-- Eggs folder until the client streams them). Starts at the zone hitbox centre
-- and walks the X axis (the map is linear along -X, so the walkable side of a
-- zone is its +X edge) until it finds a point that has real floor under it AND
-- is INSIDE that zone. The hitbox centre of e.g. Zone12 sits over void, so it
-- must never be used as a stand/TP point directly. Falls back to the other
-- direction, then to the zone pivot. Returns nil when nothing is reachable.
Runtime.zoneAnchorPoint = function(id)
    if not id then return nil end
    -- The hitbox geometry is static, so a computed anchor is cached: this avoids
    -- running the raycast scan every feature tick.
    local cached = Runtime.ZoneAnchorCache and Runtime.ZoneAnchorCache[id]
    if cached then return cached end
    local n = zoneIndexFromId(id)
    if not n then return nil end
    local build = Workspace:FindFirstChild("Build")
    local hb = build and build:FindFirstChild("ZoneHitboxes")
    local h = hb and hb:FindFirstChild(tostring(n))
    local z = zoneBuild(id)
    local center = (h and h:IsA("BasePart") and h.Position) or (z and z:GetPivot().Position)
    if not center then return nil end
    local halfX = (h and h:IsA("BasePart") and h.Size.X * 0.5) or 0
    local step = math.max(8, halfX / 10)
    local cands = { center }
    for i = 1, 10 do
        cands[#cands + 1] = Vector3.new(center.X + step * i, center.Y, center.Z)
    end
    for i = 1, 10 do
        cands[#cands + 1] = Vector3.new(center.X - step * i, center.Y, center.Z)
    end
    if z then cands[#cands + 1] = z:GetPivot().Position end
    for _, c in ipairs(cands) do
        local gy = Runtime.groundYUnderXZ(c.X, c.Z, c.Y or center.Y)
        if gy then
            local p = Vector3.new(c.X, gy, c.Z)
            if zoneOfPosition(p) == id then
                if Runtime.ZoneAnchorCache then Runtime.ZoneAnchorCache[id] = p end
                return p
            end
        end
    end
    return nil
end

-- STREAMING PREFETCH (with retry + verify).
-- Far zones (e.g. Fantasy Expansion / Zone13) sit beyond Workspace.StreamingTargetRadius
-- from the SafeZone, so they stay EMPTY until explicitly requested. A single
-- RequestStreamAroundAsync can time out, so it must be RETRIED until the zone's
-- content actually appears - and never be marked done before that.
-- zoneStreamAnchor: request point that does NOT depend on streamed ground (the
-- static zone hitbox centre / build pivot), because a far zone has no floor/eggs
-- before it streams.
Runtime.zoneStreamAnchor = function(id)
    local n = zoneIndexFromId(id)
    if not n then return nil end
    local build = Workspace:FindFirstChild("Build")
    local hb = build and build:FindFirstChild("ZoneHitboxes")
    local h = hb and hb:FindFirstChild(tostring(n))
    if h and h:IsA("BasePart") then return h.Position end
    local z = zoneBuild(id)
    return z and z:GetPivot().Position or nil
end

-- zoneHasContent: the zone's Eggs folder only gains children after its content
-- streams in (far zones start with an EMPTY Eggs folder under StreamingEnabled).
Runtime.zoneHasContent = function(id)
    local z = zoneBuild(id)
    local eggs = z and z:FindFirstChild("Eggs")
    if eggs and #eggs:GetChildren() > 0 then return true end
    -- Already physically inside the zone (or standing where its hitbox is): its
    -- content is up, even if every egg is momentarily broken/respawning.
    local ch = LocalPlayer.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp and zoneOfPosition(hrp.Position) == id then return true end
    return false
end

Runtime.ZoneStreamState = Runtime.ZoneStreamState or {}
Runtime.requestZoneStream = function(id, timeout)
    if not id then return false end
    local st = Runtime.ZoneStreamState[id]
    if st and st.Done then return false end
    if Runtime.zoneHasContent(id) then
        Runtime.ZoneStreamState[id] = { Done = true, At = os.clock(), Tries = 0 }
        return false
    end
    if not st then
        st = { Done = false, At = 0, Tries = 0, InFlight = false }
        Runtime.ZoneStreamState[id] = st
    end
    if st.InFlight then return false end
    local now = os.clock()
    if now - (st.At or 0) < 2.0 then return false end
    st.At = now
    st.Tries = (st.Tries or 0) + 1
    local anchor = Runtime.zoneStreamAnchor(id)
    if not anchor then return false end
    st.InFlight = true
    task.spawn(function()
        pcall(function() LocalPlayer:RequestStreamAroundAsync(anchor, timeout or 10) end)
        task.wait(0.5)
        st.InFlight = false
        if Runtime.zoneHasContent(id) then st.Done = true end
    end)
    return true
end

local function moveStop()
    Runtime.TravelDest = nil
    Runtime.TravelArrive = nil
    Runtime.MoveTickAt = 0
    pcall(function() RunService:UnbindFromRenderStep("BSTravelStep") end)
end

-- THE STEPPER. One hop per frame: advance at most (speed x frame time) studs toward
-- the shared destination, clamped to MOVE.MaxStep and to the distance left, then
-- re-plant the feet on the floor under the new XZ. Because the hop length is also
-- clamped to the distance left it can never overshoot, so no braking rule is
-- needed. Physics velocity is zeroed on every hop so gravity and the game's own
-- ground grip cannot fight the move.
local function moveStep()
    if not getgenv()[GAME_CONFIG.GlobalFlag] then moveStop() return end
    local dest = Runtime.TravelDest
    local c, hrp, hum = getChar()
    if not dest or not hrp or not hum or hum.Health <= 0 then moveStop() return end
    -- A deliberate pin (guard-window force-TP / catch hold / anti-knock) owns the
    -- character: never fight it with a hop.
    if Runtime.MetaForcePos or Runtime.HuntForcePos or Runtime.CatchHoldPos or Runtime.AntiKnockPos then
        Runtime.MoveTickAt = os.clock()
        return
    end
    local arrive = Runtime.TravelArrive or MOVE.ArriveDist
    local flat = Vector3.new(dest.X - hrp.Position.X, 0, dest.Z - hrp.Position.Z)
    if flat.Magnitude <= arrive then
        local v = hrp.AssemblyLinearVelocity
        pcall(function() hrp.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0) end)
        moveStop()
        return
    end
    -- never hop into a spot with no ground under it (edge of the map -> void death).
    -- Probe at most the distance LEFT, never a full 12 studs past the destination:
    -- when the remaining distance is short the probe lands ON the (already grounded)
    -- target, so an egg sitting at the edge of a small island/plate no longer aborts
    -- the final approach and strands the character out of Auto Swing range.
    local probeAhead = math.min(flat.Magnitude, 12)
    if flat.Magnitude > 2 and not hasGroundAt(hrp.Position + flat.Unit * probeAhead) then
        Runtime.TravelStrikes = Runtime.TravelStrikes + 1
        moveStop()
        return
    end
    local nowM = os.clock()
    local dt = nowM - (Runtime.MoveTickAt or nowM)
    Runtime.MoveTickAt = nowM
    if dt <= 0 then return end
    local speed = math.clamp(Runtime.TravelSpeedCfg or moveSpeed(), 1, MOVE.MaxSpeed)
    Runtime.TravelSpeed = speed
    local len = math.min(speed * dt, MOVE.MaxStep, flat.Magnitude)
    if len <= 0 then return end
    -- ONE hop: land on the floor under the next XZ, face the direction of travel.
    local from = hrp.Position
    local nextXZ = from + flat.Unit * len
    local gy = Runtime.groundYUnderXZ(nextXZ.X, nextXZ.Z, from.Y)
    local off = ((type(hum.HipHeight) == "number") and hum.HipHeight or 2) + hrp.Size.Y * 0.5
    local y = gy and (gy + off) or from.Y
    local target = Vector3.new(nextXZ.X, y, nextXZ.Z)
    pcall(function() hrp.CFrame = CFrame.lookAt(target, target + flat.Unit) end)
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
    -- ANTI-STUCK WATCHDOG: no progress -> hop to break free and drop the move.
    local last = Runtime.TravelWatchPos
    if (not last) or (hrp.Position - last).Magnitude > 1.5 then
        Runtime.TravelWatchPos = hrp.Position
        Runtime.TravelWatchAt = nowM
        Runtime.TravelStuckCount = 0
    elseif nowM - (Runtime.TravelWatchAt or nowM) > 2.0 then
        Runtime.TravelWatchAt = nowM
        Runtime.TravelWatchPos = hrp.Position
        Runtime.TravelStuckCount = (Runtime.TravelStuckCount or 0) + 1
        pcall(function()
            hum.Jump = true
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end)
        if Runtime.TravelStuckCount >= 3 then
            Runtime.TravelStuckCount = 0
            pcall(function() hrp.CFrame = hrp.CFrame + Vector3.new(0, 4, 0) end)
        end
        moveStop()
    end
end

-- Runtime.TravelDest is the SINGLE movement slot shared by every feature. Only the
-- branch that owns the active phase may set it: Auto Steal (BREAK/PICKUP/SECURE),
-- HUNT, far-zone META, and the IDLE helpers (Treadmill / Plant). AutoMerge must NOT
-- call this (it is remote-only), or it hijacks the character mid-delivery.
local function tpTo(pos, yoff, speed, arrive)
    local _, hrp, hum = getChar()
    if not hrp then return end
    -- A move may already be running (every phase re-issues tpTo to keep up with a
    -- moving target). Keep the step clock running in that case: resetting it on
    -- every re-issue would throw away the elapsed frame time and the character
    -- would advance at only a fraction of the configured speed.
    local wasActive = Runtime.TravelDest ~= nil
    Runtime.TravelSpeedCfg = speed or moveSpeed()
    Runtime.TravelArrive = arrive
    -- Ground the destination: stand ON the floor at the target XZ instead of a fixed
    -- height in the air. Falls back to the air offset when there is no floor
    -- (edge of the map / mid-air target).
    local gy = Runtime.groundYUnderXZ(pos.X, pos.Z, pos.Y)
    local dest
    if gy then
        local off = ((hum and type(hum.HipHeight) == "number") and hum.HipHeight or 2) + hrp.Size.Y * 0.5
        dest = Vector3.new(pos.X, gy + off, pos.Z)
    else
        dest = pos + Vector3.new(0, yoff or 2, 0)
    end
    Runtime.TravelDest = dest
    local flat = Vector3.new(dest.X - hrp.Position.X, 0, dest.Z - hrp.Position.Z)
    if flat.Magnitude <= (arrive or MOVE.ArriveDist) then
        return
    end
    if not wasActive then
        Runtime.MoveTickAt = os.clock()
    end
    pcall(function()
        RunService:BindToRenderStep("BSTravelStep", Enum.RenderPriority.Character.Value + 3, moveStep)
    end)
end
local function travelActive()
    return Runtime.TravelDest ~= nil
end

--------------------------------------------------------------------------------
-- TP MODE SELECTOR (BigFroot-style)
-- "TP v1" / "TP v2" both drive the META pipeline through the shared micro-step
-- mover (tpTo). v2 additionally:
--   Hop     = an instant single-frame step to the next egg within HopRange, so
--             the loop does not walk between close eggs.
--   Leap    = an instant step while the guard fling window is open (the server
--             expects a relocation during the ragdoll, so it is not a plain TP).
--   Decoy   = when the fling window is about to close, grab a Zone1 egg to bait
--             the guard into catching us again and reopening the window.
-- "Walk" keeps its own engine and never touches these.
--------------------------------------------------------------------------------
local function isV1()
    return Config.MovementMode == "TP v1"
end
local function isV2()
    return Config.MovementMode == "TP v2" or Config.MovementMode == "TP"
end
local function isTPMode()
    return isV1() or isV2()
end

-- True while the guard fling/ragdoll window is still open (offset shrinks it).
Runtime.inWindow = function(offset)
    return os.clock() < ((Runtime.RagdollUntil or 0) - (offset or 0))
end

-- v2 only: window is still open but about to close, and this fling has not been
-- used for a decoy yet.
Runtime.windowClosing = function()
    return isV2() and Runtime.inWindow(0.05)
        and not Runtime.inWindow(Runtime.Closing or 0.8)
        and Runtime.DecoyTried ~= Runtime.FlungAt
end

-- BigFroot-style Mover: ALL TP is a single direct CFrame set (instant). There is
-- no micro-stepping in TP v1/v2 - BigFroot's Ticket/Hop/Leap/Go are all instant.
-- yoff lifts the point off the floor if a caller needs a little clearance.
Runtime.instantTp = function(pos, yoff)
    if not pos then return false end
    local _, hrp, hum = getChar()
    if not hrp then return false end
    -- a deliberate instant TP always wins over the anti-knock/step holds
    moveStop()
    Runtime.AntiKnockPos = nil
    pcall(function() RunService:UnbindFromRenderStep("BSAntiKnock") end)
    local gy = Runtime.groundYUnderXZ(pos.X, pos.Z, pos.Y)
    local off = ((hum and type(hum.HipHeight) == "number") and hum.HipHeight or 2)
        + hrp.Size.Y * 0.5 + (yoff or 0)
    local dest = gy and Vector3.new(pos.X, gy + off, pos.Z)
        or (pos + Vector3.new(0, (yoff or 0) + 3, 0))
    pcall(function() hrp.CFrame = CFrame.new(dest) end)
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
    pcall(function()
        local c = LocalPlayer.Character
        if c and c:GetAttribute("Ragdolled") == true and RagdollPhysics then
            RagdollPhysics.SnapUpright(c)
        end
    end)
    Runtime.LastInstantTp = os.clock()
    return true
end

-- Go/Ticket/Hop: BigFroot instant teleports (kind/height already on the point).
Runtime.Go = function(pos, yoff)
    return Runtime.instantTp(pos, yoff)
end
Runtime.Ticket = function(pos)
    return Runtime.instantTp(pos, 0)
end
Runtime.Hop = function(pos)
    return Runtime.instantTp(pos, 0)
end
-- Leap: instant TP allowed ONLY inside the guard catch window (hitguard).
Runtime.Leap = function(pos)
    if not Runtime.inWindow(0.2) then return false end
    return Runtime.instantTp(pos, 0)
end

-- Back-compat wrappers (older call sites use these names).
Runtime.hopToEgg = function(egg)
    if not egg or not egg.Parent then return false end
    return Runtime.Hop(egg.Position)
end
Runtime.leapTo = function(pos)
    if not pos then return false end
    return Runtime.Leap(pos)
end

-- v2 only: bait the guard with a Zone1 egg when the window is closing.
Runtime.tryDecoy = function()
    if not Runtime.windowClosing() then return false end
    Runtime.DecoyTried = Runtime.FlungAt
    local egg = firstEggInZone("Zone1")
    if not egg then return false end
    return Runtime.hopToEgg(egg)
end

local function arrivedNear(pos, dist)
    local _, hrp = getChar()
    return hrp ~= nil and (hrp.Position - pos).Magnitude <= (dist or (MOVE.ArriveDist + 2))
end

getgenv().__bsttp = tpTo
getgenv().__bsttravel = function()
    local _, hrp = getChar()
    return Runtime.TravelDest, hrp and hrp.Position, Runtime.TravelStrikes
end

--------------------------------------------------------------------------------
-- GUARD-HIT TRIGGER (for the far-zone guard-bait meta)
-- The guard landing a catch puts the character in Physics state and sends a
-- "fling" on CatchFlingRemote. We watch LocalPlayer."BeingChased",
-- Character."Ragdolled" and the CatchFlingRemote fling payload. When any of
-- them fires, Runtime.GuardHitAt is stamped - that is the window the forced
-- teleport is allowed to run in.
--------------------------------------------------------------------------------
local function stampGuardHit(state)
    Runtime.GuardHitAt = os.clock()
    Runtime.GuardHitState = state or "hit"
    -- BigFroot-style fling window (used by TP v1/v2 Leap on META). The guard catch
    -- opens a ~3s window where the server expects a relocation, so a step here is
    -- legal. A new fling re-opens the window and clears the decoy marker.
    Runtime.FlungAt = os.clock()
    Runtime.RagdollUntil = os.clock() + 3.0
    do
        local _, chrp = getChar()
        if chrp then Runtime.CatchAt = chrp.Position end
    end
    -- HUNT guard-bait: the catch just landed. Jump straight to RECOVER at frame
    -- rate (skip the 6.7Hz loop detect + the BRIEF wait) and release the movement
    -- pins so nothing fights the recovery force-TP. Guarded on WALK_GUARD so the
    -- fling + Ragdolled pair cannot double-count the hit.
    if Runtime.Phase == "HUNT"
        and (Runtime.HuntStage == "WALK_GUARD" or Runtime.HuntStage == "PICKUP") then
        pcall(function() Runtime.huntReleasePins() end)
        Runtime.HuntGuardHits = (Runtime.HuntGuardHits or 0) + 1
        Runtime.HuntRecoverPick = nil
        Runtime.HuntRecoverEntryCarried = isCarrying()
        Runtime.HuntStage = "RECOVER"
        Runtime.HuntStageAt = os.clock()
    end
    -- The fling arrives the frame the guard lands the catch. Hold the character on
    -- the catch point for every HUNT stage: it keeps us in place and the seized pet
    -- at our feet, so the instant re-grab lands and we are carrying when the next
    -- hit arrives.
    local armHold = (Runtime.Phase == "HUNT"
            and (Runtime.HuntStage == "WALK_GUARD"
                or Runtime.HuntStage == "PICKUP"
                or Runtime.HuntStage == "BRIEF"
                or Runtime.HuntStage == "RECOVER"))
    if armHold then
        local _, hrp = getChar()
        if hrp then
            Runtime.CatchHoldPos = hrp.Position
            Runtime.CatchHoldUntil = os.clock() + 3.0
        end
    end
    if Runtime.onGuardHit then pcall(Runtime.onGuardHit, state) end
end
local function armGuardTrigger()
    local lp = LocalPlayer
    -- BeingChased only means the guard picked us as a target; it is NOT the
    -- hit. Keep it informational so we never fire the force-TP early.
    Connections.GuardChased = lp:GetAttributeChangedSignal("BeingChased"):Connect(function()
        Runtime.BeingChased = lp:GetAttribute("BeingChased") ~= nil
    end)
    -- The instant the guard seizes the pet, the Carrying attribute clears. Detect
    -- that at frame rate (NOT the 6.7Hz feature loop) and jump straight to RECOVER,
    -- releasing the pins, so the regrab + force-TP runs inside the catch window.
    Connections.GuardCarry = lp:GetAttributeChangedSignal("Carrying"):Connect(function()
        if lp:GetAttribute("Carrying") ~= nil then return end
        if Runtime.Phase == "HUNT"
            and (Runtime.HuntStage == "WALK_GUARD"
                or Runtime.HuntStage == "PICKUP"
                or Runtime.HuntStage == "BRIEF") then
            -- Stamp the seize so the recovery force-TP is authorised even on frames
            -- where Ragdolled has not flipped yet (the pet is seized ~30ms before it).
            Runtime.GuardHitAt = os.clock()
            Runtime.GuardHitState = "seize"
            pcall(function() Runtime.huntReleasePins() end)
            Runtime.HuntGuardHits = (Runtime.HuntGuardHits or 0) + 1
            Runtime.HuntRecoverPick = nil
            Runtime.HuntRecoverEntryCarried = isCarrying()
            Runtime.HuntStage = "RECOVER"
            Runtime.HuntStageAt = os.clock()
        end
    end)
    local function watchChar(c)
        if not c then return end
        if Connections.GuardRagdoll then
            pcall(function() Connections.GuardRagdoll:Disconnect() end)
            Connections.GuardRagdoll = nil
        end
        Connections.GuardRagdoll = c:GetAttributeChangedSignal("Ragdolled"):Connect(function()
            if c:GetAttribute("Ragdolled") == true then stampGuardHit("Ragdolled") end
        end)
    end
    watchChar(lp.Character)
    Connections.GuardCharAdded = lp.CharacterAdded:Connect(watchChar)
    -- The fling payload is the actual catch landing.
    local CFR = ReplicatedStorage:FindFirstChild("CatchFlingRemote")
    if CFR and CFR:IsA("BaseRemoteEvent") then
        Connections.GuardFling = CFR.OnClientEvent:Connect(function(action, dir)
            if action == "fling" and typeof(dir) == "Vector3" then
                stampGuardHit("fling")
            elseif action == "release" then
                -- BigFroot closes the window early on "release".
                Runtime.RagdollUntil = math.min(Runtime.RagdollUntil or 0, os.clock())
            end
        end)
    end
end
-- True only during the actual hit window (ragdoll / fling), never merely chased.
local function guardCatchNow()
    local c = LocalPlayer.Character
    return c ~= nil and c:GetAttribute("Ragdolled") == true
end
-- The catch window for a SPECIFIC zone's guard: only true while that guard is
-- winding up its lunge on us (the last moment the pet is still held) and it is
-- actually next to us. Deliberately does NOT trust the bare Ragdolled flag -
-- that lingers from the previous decoy catch and would fire the jump before
-- this zone's guard ever hit us.
local function guardWindUpNow(zoneId)
    local _, hrp = getChar()
    if not hrp then return false end
    -- any guard actually winding up a lunge right next to us (the kite can
    -- cross zone borders, so do not restrict to the target zone's guard)
    for _, g in ipairs(CollectionService:GetTagged("ZoneGuard")) do
        if g:IsA("Model") and g.Parent and g:GetAttribute("ChaseState") == "WindUp" then
            local h = g:FindFirstChild("HumanoidRootPart", true)
            if h and (h.Position - hrp.Position).Magnitude <= 40 then return true end
        end
    end
    return false
end
-- A real catch just landed (server pushed us into ragdoll via CatchFlingRemote),
-- scoped by GuardHitAt which is reset on every leg/attempt transition.
local function guardFlingFresh(requireBait)
    if Runtime.GuardHitAt <= 0 or (os.clock() - Runtime.GuardHitAt) > 1.5 then return false end
    local s = Runtime.GuardHitState
    return s == "fling" or s == "Ragdolled" or s == "seize"
end

--------------------------------------------------------------------------------
-- FORCED TELEPORT (guard-hit window only)
-- A bounded single CFrame hop. Refuses unless a guard catch is fresh and the
-- character is actually ragdolled/chased, so it never fires as a plain
-- teleport. Used both to cross into the target zone and to carry the pet to
-- the SafeZone.
--------------------------------------------------------------------------------
local metaForceStep
local function forceTpTo(pos, yoff, gateZone, maxStep)
    local c, hrp = getChar()
    if not hrp then return false end
    local lungeOk = Runtime.MetaLungeAt and (os.clock() - Runtime.MetaLungeAt) <= 1.2
    local ok = lungeOk or guardFlingFresh() or guardCatchNow()
    if not ok and gateZone then ok = guardWindUpNow(gateZone) end
    if not ok then return false end
    -- cancel any in-flight walk so it cannot fight the pinned destination
    moveStop()
    -- drop the anti-knock hold first: it runs at a LATER render priority, so if left
    -- armed it wins the frame and pins us back (the "stuck in Zone1 after the decoy
    -- bait" bug). A deliberate force-TP always overrides the knockback hold.
    Runtime.AntiKnockPos = nil
    pcall(function() RunService:UnbindFromRenderStep("BSAntiKnock") end)
    local dest = pos + Vector3.new(0, yoff or 3, 0)
    if maxStep then
        local flat = Vector3.new(dest.X - hrp.Position.X, 0, dest.Z - hrp.Position.Z)
        if flat.Magnitude > maxStep then
            dest = hrp.Position + flat.Unit * maxStep + Vector3.new(0, yoff or 3, 0)
        end
    end
    pcall(function() hrp.CFrame = CFrame.new(dest) end)
    -- kill the fling impulse so the ragdoll does not carry us back out of the
    -- destination before the move registers.
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
    -- hold the destination for the whole catch window: the fling event arrives
    -- a frame BEFORE the Ragdolled attribute flips, so pinning only while
    -- Ragdolled is true would release on the first frame and the guard's fling
    -- velocity + server reconciliation would throw us back ("terpental"). Pin
    -- position AND zero velocity every frame for ~4s so the jump sticks.
    Runtime.MetaForcePos = dest
    Runtime.MetaForceUntil = os.clock() + 4.0
    Runtime.MetaForceStart = os.clock()
    -- ForcePin keeps the destination pinned for the WHOLE window. The old gate
    -- released the pin unless a catch was already registered, but the SafeZone
    -- delivery hop fires on the guard's WindUp (before the catch), so the pin
    -- dropped on the very next frame and the server reconciliation pulled the
    -- character back out of the SafeZone.
    Runtime.ForcePin = true
    pcall(function()
        RunService:BindToRenderStep("BSMetaForceStep", Enum.RenderPriority.Character.Value - 1, metaForceStep)
    end)
    if c then
        pcall(function()
            if c:GetAttribute("Ragdolled") == true and RagdollPhysics then
                RagdollPhysics.SnapUpright(c)
            end
        end)
    end
    return true
end
getgenv().__bstforcetp = forceTpTo

-- Keeps the character at the forced destination for the catch window.
metaForceStep = function()
    if not Runtime.MetaForcePos then return end
    -- Hold for the full window while ForcePin is armed, regardless of whether a
    -- catch has been registered yet (the delivery hop fires on WindUp). A hard
    -- anti-cheat verdict clears ForcePin, and the window cap ends it anyway.
    if os.clock() > (Runtime.MetaForceUntil or 0) or not Runtime.ForcePin then
        Runtime.MetaForcePos = nil
        Runtime.ForcePin = nil
        pcall(function() RunService:UnbindFromRenderStep("BSMetaForceStep") end)
        return
    end
    local c, hrp, hum = getChar()
    if not hrp or not c or not hum then return end
    -- Release early once we have landed at the destination and are no longer
    -- ragdolled, so the follow-up walk is not fought by the pin. The 4s cap above
    -- still bounds it if the destination has no floor under it.
    if not guardCatchNow() and hum.FloorMaterial ~= Enum.Material.Air
        and (hrp.Position - Runtime.MetaForcePos).Magnitude <= 6 then
        Runtime.MetaForcePos = nil
        Runtime.ForcePin = nil
        pcall(function() RunService:UnbindFromRenderStep("BSMetaForceStep") end)
        return
    end
    -- No catch resolved and the destination has no floor under it (we would float
    -- there for the whole window): stop after ~2s. A real catch still holds via
    -- guardCatchNow() until the ragdoll ends.
    if not guardCatchNow() and (os.clock() - (Runtime.MetaForceStart or 0)) > 2.0 then
        Runtime.MetaForcePos = nil
        Runtime.ForcePin = nil
        pcall(function() RunService:UnbindFromRenderStep("BSMetaForceStep") end)
        return
    end
    -- hold BOTH position and velocity: the client fling controller re-applies
    -- the fling velocity each frame during the ragdoll, so zeroing it too is
    -- what stops the "terpental" and makes the jump stick.
    pcall(function() hrp.CFrame = CFrame.new(Runtime.MetaForcePos) end)
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
end

--------------------------------------------------------------------------------
-- WALK MOVEMENT / META MOVEMENT
-- Humanoid:MoveTo is slow here (~23 studs/s) and is overridden by the game's own
-- movement controller, so walkTo / walkStop / walkActive are thin wrappers over
-- the step mover (tpTo / moveStop) - every meta stage uses the shared move.
--------------------------------------------------------------------------------
local function walkTo(pos, yoff)
    tpTo(pos, yoff, moveSpeed())
end
local function walkStop()
    moveStop()
    -- Also halt the genuine Walk engine (Humanoid:Move). TP v1 drives every
    -- non-TP move through it, so a stage transition / arrival must stop it here
    -- too. For every other mode WalkDest is nil, so this is a harmless no-op.
    pcall(function() Runtime.walkStop() end)
end
local function walkActive()
    return travelActive()
end
getgenv().__bstwalk = walkTo

--------------------------------------------------------------------------------
-- WALK ENGINE LOCOMOTION (mode "Walk" only)
-- Genuine walking: Humanoid:MoveTo at the character's OWN WalkSpeed (the value the
-- game assigns from the treadmill SpeedPower). Nothing here sets WalkSpeed, velocity
-- or CFrame - the game's GroundGripController drives the motion. Kept fully separate
-- from the TP mover (tpTo/moveStep/BSTravelStep) and from the META/HUNT force-TPs, so
-- the existing engines are untouched.
-- All state/handlers live on Runtime to stay under the main chunk's local budget.
--------------------------------------------------------------------------------
Runtime.WalkDest = nil
Runtime.WalkReissueAt = 0

Runtime.walkStop = function()
    Runtime.WalkDest = nil
    Runtime.WalkArrive = nil
    Runtime.WalkReissueAt = 0
    Runtime.WalkWatchPos = nil
    Runtime.WalkWatchAt = 0
    Runtime.WalkStuckCount = 0
    pcall(function()
        local _, _, hum = getChar()
        if hum then hum:Move(Vector3.zero) end
    end)
    if Runtime.WalkConn then
        pcall(function() Runtime.WalkConn:Disconnect() end)
        Runtime.WalkConn = nil
    end
    pcall(function() RunService:UnbindFromRenderStep("BSWalkStep") end)
end

Runtime.walkGo = function(pos, arrive)
    local _, hrp, hum = getChar()
    if not hrp or not pos then return end
    local gy = Runtime.groundYUnderXZ(pos.X, pos.Z, pos.Y)
    local dest
    if gy then
        local off = ((hum and type(hum.HipHeight) == "number") and hum.HipHeight or 2) + hrp.Size.Y * 0.5
        dest = Vector3.new(pos.X, gy + off, pos.Z)
    else
        dest = pos
    end
    Runtime.WalkDest = dest
    Runtime.WalkArrive = arrive or MOVE.ArriveDist
    -- RenderStepped (not BindToRenderStep): it fires AFTER the game's own control
    -- module, so our MoveDirection survives instead of being reset to zero.
    if not Runtime.WalkConn then
        Runtime.WalkConn = RunService.RenderStepped:Connect(Runtime.walkStep)
    end
end

Runtime.walkStep = function()
    if not getgenv()[GAME_CONFIG.GlobalFlag] then Runtime.walkStop() return end
    local dest = Runtime.WalkDest
    local c, hrp, hum = getChar()
    if not dest or not hrp or not hum or hum.Health <= 0 then Runtime.walkStop() return end
    -- yield to any deliberate pin (guard force-TP / catch hold / knock hold)
    if Runtime.MetaForcePos or Runtime.HuntForcePos or Runtime.CatchHoldPos or Runtime.AntiKnockPos then return end
    -- never fight a ragdoll/fling: wait it out (the pipeline waits too)
    if c:GetAttribute("Ragdolled") == true or hum:GetState() == Enum.HumanoidStateType.Physics then return end
    local arrive = Runtime.WalkArrive or MOVE.ArriveDist
    local flat = Vector3.new(dest.X - hrp.Position.X, 0, dest.Z - hrp.Position.Z)
    if flat.Magnitude <= arrive then
        Runtime.walkStop()
        return
    end
    local nowM = os.clock()
    -- Humanoid:Move drives MoveDirection directly; the game's GroundGripController
    -- then lerps our velocity to MoveDirection * WalkSpeed (the treadmill speed).
    -- Humanoid:MoveTo is throttled to ~16 studs/s in this game, so we use Move and
    -- set it every frame so the controller cannot reset MoveDirection to zero.
    pcall(function() hum:Move(flat.Unit) end)
    -- anti-stuck watchdog (no CFrame hop, no TP): jump, then give up and let the
    -- caller re-issue; the main loop timeouts bound the stage.
    local last = Runtime.WalkWatchPos
    if (not last) or (hrp.Position - last).Magnitude > 1.5 then
        Runtime.WalkWatchPos = hrp.Position
        Runtime.WalkWatchAt = nowM
        Runtime.WalkStuckCount = 0
    elseif nowM - (Runtime.WalkWatchAt or nowM) > 3.0 then
        Runtime.WalkWatchAt = nowM
        Runtime.WalkWatchPos = hrp.Position
        Runtime.WalkStuckCount = (Runtime.WalkStuckCount or 0) + 1
        pcall(function()
            hum.Jump = true
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end)
        if Runtime.WalkStuckCount >= 2 then
            Runtime.WalkStuckCount = 0
            Runtime.walkStop()
        end
    end
end

Runtime.walkActive = function()
    return Runtime.WalkDest ~= nil
end

-- NoClip is NO LONGER used by any auto feature (Walk mode included). Behaviour is
-- left entirely to the Misc NoClip toggle. This helper only RELEASES any NoClip a
-- previous build force-enabled for Walk, and never turns it back on.
Runtime.WalkNoClipManaged = false
Runtime.WalkNoClipSynced = false
Runtime.syncWalkNoClip = function()
    if Runtime.WalkNoClipManaged then
        Runtime.WalkNoClipManaged = false
        Runtime.WalkNoClipSynced = false
        local f = getgenv().__bsNoClip
        if f then pcall(f, false) end
    end
end

-- Debug helper: which egg the engine would break next in a zone (per Egg Priority).
getgenv().__bsPickEgg = function(zoneId)
    local _, hrp = getChar()
    if not hrp then return nil end
    return nearestEggInZone(hrp.Position, zoneId)
end

-- The WALK return point: the character walks straight back to the SAME single
-- hardcoded SafeZone point used at the start (WalkStartPos).

--------------------------------------------------------------------------------
-- ANTI-CHEAT STRIKE DETECTOR
-- The server sends verdicts (Forgiven* / Teleport / Speed / Fly* / *Exploded /
-- BankTeleport / StealRush) on the Notify remote. On any hard strike we pause
-- all features so we never stack into "RepeatExploded" (death). Forgiven*
-- strikes only raise a flag we can read, because they are informational.
--------------------------------------------------------------------------------
local function isVerdictText(t)
    if type(t) ~= "string" then return false end
    return t:find("Anti%-cheat") ~= nil or t:find("pulled back") ~= nil
        or t:find("exploded") ~= nil or t:find("sent back") ~= nil
        or t:find("blocked banking") ~= nil
end

local function isHardStrike(t)
    if type(t) ~= "string" then return false end
    if t:find("Forgiven") ~= nil then return false end
    return t:find("Anti%-cheat") ~= nil
end

local function armStrikeDetector()
    local Notify = ReplicatedStorage:FindFirstChild("Notify")
    if not Notify or not Notify:IsA("BaseRemoteEvent") then return end
    Connections.StrikeDetector = Notify.OnClientEvent:Connect(function(text, kind)
        if not isVerdictText(text) then return end
        if isHardStrike(text) then
            Runtime.StrikePauseUntil = os.clock() + 3
            moveStop()
            -- stop fighting the server: drop the force-TP pin immediately
            Runtime.MetaForcePos = nil
            Runtime.ForcePin = nil
            pcall(function() RunService:UnbindFromRenderStep("BSMetaForceStep") end)
            -- classify so the meta can react (and the status panel can show why)
            local low = string.lower(tostring(text))
            if low:find("teleport") then
                Runtime.LastFailReason = "snap (AC teleport)"
                Runtime.SnapCount = (Runtime.SnapCount or 0) + 1
            elseif low:find("bank") or low:find("sent back") then
                Runtime.LastFailReason = "bank diblokir"
                Runtime.BankBlockCount = (Runtime.BankBlockCount or 0) + 1
                -- bank was blocked because the server still saw a teleport: wait
                -- longer before banking next time.
                Runtime.BankSettle = math.min((Runtime.BankSettle or 3.0) + 2.0, 12.0)
            end
        end
    end)
end

local function equipPickaxe()
    local c, _, hum = getChar()
    if not c or not hum or not isAlive() then return end
    local cur = c:FindFirstChildOfClass("Tool")
    if cur and cur.Name == "Pickaxe" then return end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local paxe = bp and bp:FindFirstChild("Pickaxe")
    if paxe and paxe:IsA("Tool") then
        pcall(function() hum:EquipTool(paxe) end)
    end
end

local function liveEggs()
    local list = {}
    for _, e in ipairs(CollectionService:GetTagged("BreakableEgg")) do
        if e:IsA("BasePart") and e.Parent
            and not e:GetAttribute("Broken") and not e:GetAttribute("Hatching") and not e:GetAttribute("Despawning")
            and not titanicSkipped(e) then
            list[#list + 1] = e
        end
    end
    return list
end

-- Exact zone id of an egg (walk up to the "ZoneN" ancestor). Avoids the old
-- GetFullName substring match where "Zone1" also matched "Zone10".
local function eggZoneId(e)
    local a = e
    for _ = 1, 6 do
        a = a and a.Parent
        if not a then return nil end
        if string.match(a.Name, "^Zone%d+$") then return a.Name end
    end
    return nil
end

-- TITANIC EGG PRIORITY. The titanic egg is a normal BreakableEgg (so it is already
-- in liveEggs()) plus tag "TitanicEgg" / attribute "Titanic". It must ALWAYS be the
-- Auto Steal target, in whatever zone it spawned, and it is handled through the
-- existing META pipeline. These helpers only pick the target; they change no method.
local function isTitanicEgg(e)
    return e ~= nil and e.Parent ~= nil
        and (CollectionService:HasTag(e, "TitanicEgg") or e:GetAttribute("Titanic") == true)
        and not e:GetAttribute("Broken") and not e:GetAttribute("Hatching") and not e:GetAttribute("Despawning")
end
findTitanicEgg = function(pos)
    if Config.AutoTitanicEgg == false then return nil end
    local best, bd = nil, math.huge
    for _, e in ipairs(liveEggs()) do
        if isTitanicEgg(e) then
            local m = pos and (e.Position - pos).Magnitude or 0
            if m < bd then bd = m; best = e end
        end
    end
    return best
end
titanicZoneId = function(egg)
    if egg then
        local z = eggZoneId(egg)
        if z then return z end
        local idx = egg:GetAttribute("TitanicZoneIndex")
        if type(idx) == "number" then return "Zone" .. tostring(idx) end
    end
    return nil
end

local function titanicStandPoint(egg, zoneId)
    if not egg then return nil end
    local size = egg.Size
    local radius = math.max(size.X, size.Z) * 0.25
    local dirs = {}
    local _, hrp = getChar()
    if hrp then
        local d = hrp.Position - egg.Position
        d = Vector3.new(d.X, 0, d.Z)
        if d.Magnitude > 0.1 then dirs[#dirs + 1] = d.Unit end
    end
    dirs[#dirs + 1] = Vector3.new(1, 0, 0)
    dirs[#dirs + 1] = Vector3.new(-1, 0, 0)
    dirs[#dirs + 1] = Vector3.new(0, 0, 1)
    dirs[#dirs + 1] = Vector3.new(0, 0, -1)
    for _, dir in ipairs(dirs) do
        local xz = egg.Position + dir * radius
        local gy = Runtime.groundYUnderXZ(xz.X, xz.Z, egg.Position.Y)
        if gy then
            local stand = Vector3.new(xz.X, gy, xz.Z)
            if not zoneId or zoneOfPosition(stand) == zoneId then
                return stand
            end
        end
    end
    local gy = Runtime.groundYUnderXZ(egg.Position.X, egg.Position.Z, egg.Position.Y)
    if gy then return Vector3.new(egg.Position.X, gy, egg.Position.Z) end
    return egg.Position - Vector3.new(0, size.Y * 0.5, 0)
end

local function metaEggPoint(egg, zoneId)
    if egg and isTitanicEgg(egg) then
        return titanicStandPoint(egg, zoneId) or egg.Position
    end
    return egg and egg.Position or nil
end

-- BigFroot reach: instant TP to the egg in TP modes, otherwise the shared walker.
-- Mirrors BigFroot's mover exactly:
--   inside the catch window            -> Leap (instant TP)
--   outside window & not carrying      -> Ticket (instant TP), or v2 Hop if close
--   else                               -> Walk fallback
Runtime.moverReach = function(egg, zoneId)
    if not egg or not egg.Parent then return false end
    local _, hrp = getChar()
    if not hrp then return false end
    local stand = isTitanicEgg(egg) and (metaEggPoint(egg, zoneId) or egg.Position) or egg.Position
    local d = Runtime.eggSurfaceDist(egg, hrp.Position)
    if d <= 4 then return true end
    if isTitanicEgg(egg) then
        if not Runtime.walkActive() then Runtime.walkGo(stand, 2) end
        return false
    end
    if isTPMode() then
        if Runtime.inWindow(0.2) then
            return Runtime.Leap(stand)
        end
        if not isCarrying() then
            if isV2() and (egg.Position - hrp.Position).Magnitude <= Runtime.HopRange then
                return Runtime.Hop(stand)
            end
            return Runtime.Ticket(stand)
        end
    end
    if not walkActive() then walkTo(stand, 2) end
    return false
end

local function nearestEgg(pos)
    local now = os.clock()
    if now < Runtime.LastEggScan then return nil end
    Runtime.LastEggScan = now + 0.4
    -- Titanic egg wins over everything, regardless of the zone filter.
    local titanic = findTitanicEgg(pos)
    if titanic then return titanic end
    local wantId = activeZoneId()
    local best = nil
    for _, e in ipairs(liveEggs()) do
        if (not wantId or eggZoneId(e) == wantId) and eggTypeAllowed(e) then
            if eggBeats(e, best, pos) then best = e end
        end
    end
    return best
end

-- META egg picker: respect the zone filter when a zone is set; otherwise use the
-- global pick (nearestEgg already honours EggPriority + titanic + EggType).
local function metaPickEgg(pos, zoneId)
    if zoneId then
        return nearestEggInZone(pos, zoneId) or firstEggInZone(zoneId)
    end
    return nearestEgg(pos)
end

local function livePickups()
    local list = {}
    for _, p in ipairs(CollectionService:GetTagged("AnimalPickup")) do
        if p:IsA("Model") and p.Parent and not p:GetAttribute("Despawning") then
            list[#list + 1] = p
        end
    end
    return list
end

local function anchorPos(anc)
    if not anc then return nil end
    if anc:IsA("Attachment") then
        local ok, pos = pcall(function() return anc.WorldPosition end)
        if ok then return pos end
    end
    if anc:IsA("BasePart") then return anc.Position end
    local m = anc:FindFirstAncestorOfClass("Model")
    if m then return m:GetPivot().Position end
    return nil
end

local function stealPromptFor(pick)
    local now = os.clock()
    if now < Runtime.LastPromptScan then return nil end
    Runtime.LastPromptScan = now + 0.6
    local best, bd = nil, math.huge
    local pickPos = pick:GetPivot().Position
    for _, v in ipairs(CollectionService:GetTagged("SmartPrompt")) do
        if v:IsA("ProximityPrompt") and v.Name == "StealPrompt" then
            local pos = anchorPos(v.Parent)
            if pos then
                local m = (pos - pickPos).Magnitude
                if m < bd then bd = m; best = { Prompt = v, Pos = pos } end
            end
        end
    end
    return best
end

-- Nearest enabled StealPrompt to an arbitrary position (used by the far-zone
-- meta when waiting on / force-teleporting to a specific guard). The game
-- pools prompts under per-guard anchor parts, so match by world position.
local function nearestStealPrompt(pos)
    local best, bd = nil, math.huge
    for _, v in ipairs(CollectionService:GetTagged("SmartPrompt")) do
        if v:IsA("ProximityPrompt") and v.Name == "StealPrompt" then
            local p = anchorPos(v.Parent)
            if p then
                local m = (p - pos).Magnitude
                if m < bd then bd = m; best = { Prompt = v, Pos = p, Enabled = v.Enabled } end
            end
        end
    end
    return best, bd
end

-- Resolve the pooled StealPrompt that belongs to a dropped pet, plus the
-- distance the player must be within for the SERVER to accept the trigger. The
-- prompt lives on a Workspace.PromptAnchor placed at the pickup position with
-- MaxActivationDistance ~10, so we must be genuinely inside that radius (with a
-- margin, because the server validates our distance to the prompt, not the
-- pickup, and latency shifts it). Returns prompt, promptPos, fireRange, pickPos.
Runtime.pickupFireInfo = function(pick)
    if not pick or not pick.Parent then return nil end
    local pickPos = pick:GetPivot().Position
    local info = nearestStealPrompt(pickPos)
    local prompt = info and info.Prompt or nil
    local promptPos = (info and info.Pos) or pickPos
    local maxDist = 10
    if prompt then
        local md = prompt.MaxActivationDistance
        if type(md) == "number" and md > 0 and md < 1e6 then maxDist = md end
    end
    local fireRange = math.max(4, maxDist - 3)
    return prompt, promptPos, fireRange, pickPos
end

-- FORCE PICKUP: grab the dropped pet. The StealPrompt is POOLED on a separate
-- PromptAnchor (not inside the model) and firing it works ONLY from the current
-- position - a CFrame hop right before firing is rejected by the server. Fire
-- only when actually inside the prompt's activation radius; the caller steps in
-- otherwise. Without the fireRange margin the old code could settle just outside
-- the prompt radius and deadlock (stage stopped gliding at 12, fire needed <=11).
Runtime.forcePickup = function(pick)
    if isCarrying() then return true end
    if not pick or not pick.Parent then return false end
    if pick:GetAttribute("Despawning") then return false end
    local _, hrp = getChar()
    if not hrp then return false end
    local prompt, promptPos, fireRange, pickPos = Runtime.pickupFireInfo(pick)
    if not promptPos then return false end
    if (promptPos - hrp.Position).Magnitude > fireRange then
        -- too far for the server to accept: caller must step in
        return false
    end
    local function tryPrompt(v)
        pcall(function()
            v.Enabled = true
            v.HoldDuration = 0
            v.RequiresLineOfSight = false
            fireproximityprompt(v)
        end)
    end
    -- fire every StealPrompt anchored within reach of this pickup (pooled)
    local fired = false
    for _, v in ipairs(CollectionService:GetTagged("SmartPrompt")) do
        if v:IsA("ProximityPrompt") and v.Name == "StealPrompt" then
            local ap = anchorPos(v.Parent)
            if ap and (ap - pickPos).Magnitude <= fireRange + 2 then
                tryPrompt(v)
                fired = true
            end
        end
    end
    if not fired and prompt then tryPrompt(prompt) end
    return isCarrying()
end

-- INSTANT pickup (post-hit/ragdoll recovery). Fires the pet's StealPrompt from
-- wherever we are, with NO player-distance gate and NO step/teleport. The pet
-- is dropped at our feet the instant the guard catches us, so as soon as the
-- drop exists we hammer the prompt every frame - we should already be picking up
-- while barely floating, instead of wasting the short window gliding in.
Runtime.forcePickupInstant = function(pick)
    if isCarrying() then return true end
    if not pick or not pick.Parent then return false end
    if pick:GetAttribute("Despawning") then return false end
    local prompt, _, _, pickPos = Runtime.pickupFireInfo(pick)
    pickPos = pickPos or pick:GetPivot().Position
    local function tryPrompt(v)
        pcall(function()
            v.Enabled = true
            v.HoldDuration = 0
            v.RequiresLineOfSight = false
            fireproximityprompt(v)
        end)
    end
    local fired = false
    for _, v in ipairs(CollectionService:GetTagged("SmartPrompt")) do
        if v:IsA("ProximityPrompt") and v.Name == "StealPrompt" then
            local ap = anchorPos(v.Parent)
            if ap and (ap - pickPos).Magnitude <= 12 then
                tryPrompt(v)
                fired = true
            end
        end
    end
    if not fired and prompt then tryPrompt(prompt) end
    return isCarrying()
end

local function guards()
    local list = {}
    for _, g in ipairs(CollectionService:GetTagged("ZoneGuard")) do
        if g:IsA("Model") and g.Parent then list[#list + 1] = g end
    end
    return list
end

-- Nearest zone guard to a position. When zoneId is given, ONLY guards belonging
-- to that zone are considered (matched by the ZoneId attribute, or the guard
-- returned by zoneGuard(zoneId)); nil is returned when the zone has no guard, so
-- a kite can never run off to another zone's guard (e.g. Hell's guard when the
-- target zone is Blossom).
Runtime.nearestGuard = function(pos, zoneId)
    local zoneGuardModel = zoneId and zoneGuard(zoneId) or nil
    local best, bd = nil, math.huge
    for _, g in ipairs(guards()) do
        local ok = true
        if zoneId then
            ok = (g:GetAttribute("ZoneId") == zoneId) or (g == zoneGuardModel)
        end
        if ok then
            local h = g:FindFirstChild("HumanoidRootPart", true)
            local gp = (h and h.Position) or g:GetPivot().Position
            local m = (gp - pos).Magnitude
            if m < bd then bd = m; best = g end
        end
    end
    return best, bd
end

-- Release the movement/catch pins HUNT installs, so they cannot keep forcing the
-- CFrame after HUNT stops owning the character (e.g. on a fail to IDLE).
Runtime.huntReleasePins = function()
    Runtime.HuntForcePos = nil
    Runtime.HuntForcePin = false
    Runtime.HuntForceUntil = 0
    Runtime.HuntForceMinUntil = 0
    pcall(function() RunService:UnbindFromRenderStep("BSHuntForce") end)
    Runtime.CatchHoldPos = nil
    Runtime.CatchHoldUntil = 0
end

-- Reset EVERY transient HUNT field so a failed cycle cannot leak state into the
-- next one (force-pins, catch-hold, regrab timers, stale pet references, ...).
-- Call this on HUNT phase entry; the new HUNT starts at ACQUIRE (no decoy).
Runtime.huntResetCycle = function()
    Runtime.HuntStage = "ACQUIRE"
    Runtime.HuntStageAt = os.clock()
    Runtime.HuntCarried = nil
    Runtime.HuntRecoverPick = nil
    Runtime.HuntKind = nil
    Runtime.HuntTarget = nil
    Runtime.HuntDropTarget = nil
    Runtime.HuntPetZone = nil
    Runtime.HuntPos = nil
    Runtime.HuntRegrabAt = 0
    Runtime.WalkGuardAt = 0
    Runtime.LastStealAttempt = 0
    -- respawn relocation (drop-only: kill -> respawn -> pin onto the drop)
    Runtime.HuntRespawnPending = false
    Runtime.HuntRespawnAt = 0
    Runtime.HuntRespawned = false
    Runtime.HuntSpawnPos = nil
    Runtime.HuntRelocPos = nil
    Runtime.HuntRelocAt = 0
    Runtime.HuntRelocTries = 0
    Runtime.HuntRelocDone = false
    Runtime.HuntRelocStart = 0
    Runtime.HuntRelocDest = nil
    Runtime.TargetEgg = nil
    Runtime.BurstEgg = nil
    Runtime.MetaLungeAt = nil
    Runtime.GuardHitAt = 0
    Runtime.GuardHitState = nil
    Runtime.CatchHoldPos = nil
    Runtime.CatchHoldUntil = 0
    -- guard-hit counter for the HUNT delivery
    Runtime.HuntGuardHits = 0
    -- recovery-detection + pin timers (so a new cycle never sees the old one)
    Runtime.HuntRecoverSeen = nil
    Runtime.HuntRecoverEntryCarried = false
    Runtime.HuntRecoverPicked = false
    -- stop the shared mover so nothing drags into the next cycle
    moveStop()
    Runtime.TravelDest = nil
    Runtime.TravelStrikes = 0
    -- release the HUNT staging pin
    Runtime.HuntForcePos = nil
    Runtime.HuntForcePin = false
    Runtime.HuntForceUntil = 0
    Runtime.HuntForceMinUntil = 0
    pcall(function() RunService:UnbindFromRenderStep("BSHuntForce") end)
    -- release any lingering META force-TP pin (forceTpTo used by the META recovery)
    Runtime.MetaForcePos = nil
    Runtime.ForcePin = nil
    pcall(function() RunService:UnbindFromRenderStep("BSMetaForceStep") end)
end

local function threatScan(pos)
    local dist, state, wind = math.huge, "Idle", false
    for _, g in ipairs(guards()) do
        local st = g:GetAttribute("ChaseState") or "Idle"
        if st == "WindUp" then wind = true end
        local m = (g:GetPivot().Position - pos).Magnitude
        if m < dist then dist = m; state = st end
    end
    return dist, state, wind
end

local function myPlot()
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, p in ipairs(plots:GetChildren()) do
        if p:IsA("Model") and p:GetAttribute("OwnerUserId") == LocalPlayer.UserId then return p end
    end
    return nil
end

local function plotSpot()
    local plot = myPlot()
    local hit = plot and plot:FindFirstChild("Hitbox")
    if hit and hit:IsA("BasePart") then return hit.Position, plot end
    return nil, plot
end

local function safeZonePart()
    local build = Workspace:FindFirstChild("Build")
    local bz = build and build:FindFirstChild("ZoneHitboxes")
    local sz = bz and bz:FindFirstChild("SafeZone")
    if sz and sz:IsA("BasePart") then return sz end
    return nil
end

local function safeZoneSpot()
    local sz = safeZonePart()
    if sz then
        return Vector3.new(sz.Position.X, sz.Position.Y - sz.Size.Y / 2 + 4, sz.Position.Z)
    end
    return nil
end

local function inSafeZone(p)
    local sz = safeZonePart()
    if not sz then return false end
    local l = sz.CFrame:PointToObjectSpace(p)
    return math.abs(l.X) <= sz.Size.X / 2
        and math.abs(l.Y) <= sz.Size.Y / 2 + 8
        and math.abs(l.Z) <= sz.Size.Z / 2
end

-- BigFroot-style SafeZone bank / bait points.
-- safePosInside : a grounded point clamped INSIDE the SafeZone (14-stud margin).
-- safeBaitPos   : a grounded point just OUTSIDE the SafeZone edge (guard bait).
Runtime.safePosInside = function(fromPos)
    local sz = safeZonePart()
    local _, hrp = getChar()
    local ref = fromPos or (hrp and hrp.Position)
    if not sz or not ref then return Config.SafeDropPos end
    local q = sz.CFrame:PointToObjectSpace(ref)
    local hx = math.max(sz.Size.X * 0.5 - 14, 1)
    local hz = math.max(sz.Size.Z * 0.5 - 14, 1)
    local w = sz.CFrame:PointToWorldSpace(Vector3.new(
        math.clamp(q.X, -hx, hx), 0, math.clamp(q.Z, -hz, hz)))
    local gy = Runtime.groundYUnderXZ(w.X, w.Z, sz.Position.Y)
    return Vector3.new(w.X, (gy or sz.Position.Y), w.Z)
end

Runtime.safeBaitPos = function(fromPos)
    local sz = safeZonePart()
    local _, hrp = getChar()
    local ref = fromPos or (hrp and hrp.Position)
    if not sz or not ref then return Config.SafeDropPos end
    local q = sz.CFrame:PointToObjectSpace(ref)
    local hx = sz.Size.X * 0.5
    local hz = math.clamp(q.Z, -math.max(sz.Size.Z * 0.5 - 8, 1), math.max(sz.Size.Z * 0.5 - 8, 1))
    for i = 0, 8 do
        local w = sz.CFrame:PointToWorldSpace(Vector3.new(-hx - 5 - i * 3, 0, hz))
        local gy = Runtime.groundYUnderXZ(w.X, w.Z, sz.Position.Y)
        local p = Vector3.new(w.X, (gy or sz.Position.Y), w.Z)
        if not inSafeZone(p) then return p end
    end
    return sz.Position
end
--------------------------------------------------------------------------------
-- FRAME-ACCURATE KITE HOP (far-zone meta delivery)
-- The feature loop ticks at ~6.7Hz while a guard WindUp lasts only 0.6-0.8s, so
-- the delivery hop is done here at frame rate: the instant a guard next to us
-- starts its lunge, hop the pet up to ~120 studs toward the SafeZone. A larger
-- single jump outside the ragdoll is pulled back; this keeps every hop legal.
--------------------------------------------------------------------------------
local function metaKiteStep()
    Runtime.KiteTicks = (Runtime.KiteTicks or 0) + 1
    -- Hold the character on the catch point while we recover. The fling is applied
    -- CLIENT-side (CatchFlingController) each Heartbeat, so pinning here (after it)
    -- stops the fling carrying us off the dropped pet - keeping the pet inside the
    -- prompt radius so the instant pickup can fire. Released once carrying.
    if Runtime.CatchHoldPos then
        if isCarrying() or os.clock() >= (Runtime.CatchHoldUntil or 0) then
            Runtime.CatchHoldPos = nil
        else
            local c, hrp = getChar()
            if hrp then
                if RagdollPhysics then
                    pcall(function() RagdollPhysics.SetCharacterNetworkOwner(c, LocalPlayer) end)
                end
                pcall(function() hrp.CFrame = CFrame.new(Runtime.CatchHoldPos) end)
                pcall(function()
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                end)
            end
        end
    end
    -- frame-accurate delivery/recovery, assigned after the pickup helpers exist
    if Runtime.recoverStep then Runtime.recoverStep() end
    -- META hitguard bank runs at frame rate too: the catch window is short, so the
    -- re-grab + Leap to the SafeZone must not wait for the ~6.7Hz feature loop.
    if Runtime.Phase == "META" and Runtime.BankStage and Runtime.metaBankStep then
        pcall(Runtime.metaBankStep, os.clock())
    end
    -- Zone 1 decoy entry for far zones also needs frame-rate (short catch window)
    -- so the hop to the far zone lands inside the hitguard window.
    if Runtime.Phase == "META" and Runtime.DecoyStage and Runtime.decoyEntryStep then
        pcall(Runtime.decoyEntryStep, os.clock())
    end
end
getgenv().__bstkite = metaKiteStep

--------------------------------------------------------------------------------
-- HIT EVENT HOOK
-- On the actual catch (fling) the pet is already seized, so there is nothing to
-- teleport; we only clear the wind-up arm. Kept so the delivery decision lives
-- in one place and to stamp the bait generation.
--------------------------------------------------------------------------------
local function metaOnGuardHit(state)
    Runtime.MetaLungeAt = nil
end
Runtime.onGuardHit = metaOnGuardHit

local function nearestPickupNear(center, radius)
    local best, bd = nil, radius or math.huge
    for _, p in ipairs(livePickups()) do
        if petAllowed(p:GetAttribute("AnimalName"), p:GetAttribute("Mutation")) then
            local m = (p:GetPivot().Position - center).Magnitude
            if m < bd then bd = m; best = p end
        end
    end
    return best, bd
end

-- ANY dropped AnimalPickup near a point (ignores the name/pet filter). Used so a
-- filtered run does not stall on an UNWANTED hatch: once that pet is on the ground
-- (or a short grace passes) we go break the next egg.
local function anyPickupNear(center, radius)
    local best, bd = nil, radius or math.huge
    for _, p in ipairs(livePickups()) do
        local m = (p:GetPivot().Position - center).Magnitude
        if m < bd then bd = m; best = p end
    end
    return best, bd
end

--------------------------------------------------------------------------------
-- FAR-ZONE META PICKUP / CARRY HELPERS
--------------------------------------------------------------------------------
local function satchelFull()
    local cap = LocalPlayer:GetAttribute("SatchelCapacity")
    local cnt = LocalPlayer:GetAttribute("CarryCount") or 0
    if type(cap) == "number" then return cnt >= cap end
    return false
end

--------------------------------------------------------------------------------
-- EGG BREAK STEP (shared by the meta phases)
-- Fires the burst-3 on a fresh egg then keeps the server rate (~0.35s).
--------------------------------------------------------------------------------
local function breakEggStep(egg, now)
    if not egg or not egg.Parent then return end
    local _, hrp = getChar()
    if not hrp then return end
    equipPickaxe()
    Runtime.BreakPos = egg.Position
    local m = Runtime.eggSurfaceDist(egg, hrp.Position)
    if m > 4 then
        local walkPos = egg.Position
        if isTitanicEgg(egg) then walkPos = metaEggPoint(egg) or egg.Position end
        if isTitanicEgg(egg) then
            if not Runtime.walkActive() then Runtime.walkGo(walkPos, 2) end
        elseif not walkActive() and not travelActive() then
            walkTo(walkPos, 2)
        end
        return
    end
    -- Within 8 studs: the shared per-tick sync (Runtime.autoSwing) switches the game's
    -- AutoSwingController ON once we are within its 6-stud pick range; the game then
    -- swings and fires EggHitRequest itself. Nothing is sent by hand here.
end

local function eggBrokeOrGone(egg)
    if not egg then return false end
    if not egg.Parent or egg:GetAttribute("Broken")
        or egg:GetAttribute("Hatching") or egg:GetAttribute("Despawning") then
        return true
    end
    -- Health can be absent until an egg is first hit: only a REAL 0 counts as broken.
    local h = egg:GetAttribute("Health")
    return type(h) == "number" and h <= 0
end

local function dropCarried()
    if DropCarriedRemote then
        pcall(function() DropCarriedRemote:FireServer() end)
    end
end

local function buyNextPickaxe()
    local tier = LocalPlayer:GetAttribute("PickaxeTier") or 1
    if PickaxeShopRequest then
        pcall(function() PickaxeShopRequest:FireServer("Buy", tier + 1) end)
    end
end

local function cash()
    local c = LocalPlayer:GetAttribute("Cash")
    return type(c) == "number" and c or 0
end

local function tryUpgradePickaxe()
    if not (PickaxeConfig and PickaxeShopRequest) then return end
    -- Multi-select filter: empty = never upgrade. Only buy the NEXT tier when the
    -- user has explicitly selected that pickaxe; anything not selected is skipped.
    -- The game only sells tier+1, so a selected higher tier also needs the tiers
    -- below it selected to be reached.
    local filter = Config.PickaxeUpgradeFilter
    if not filter or next(filter) == nil then return end
    local tier = LocalPlayer:GetAttribute("PickaxeTier") or PickaxeConfig.DefaultTier
    if tier >= #PickaxeConfig.Tiers then return end
    local nextTier = PickaxeConfig.Tiers[tier + 1]
    local nextName = type(nextTier) == "table" and nextTier.Name or nil
    if not nextName or filter[nextName] ~= true then return end
    local price = PickaxeConfig.GetPrice(tier + 1)
    if type(price) == "number" and price > 0 and cash() >= price then
        buyNextPickaxe()
    end
end

local function tryUpgradeTreadmill()
    local plot = myPlot()
    if not plot then return end
    if Config.AutoUnlockTreadmill and TreadmillUnlockConfig and UnlockTreadmillRequest then
        if plot:GetAttribute(TreadmillUnlockConfig.UnlockedAttribute) ~= true then
            pcall(function() UnlockTreadmillRequest:FireServer() end)
            return
        end
    end
    if not (TreadmillUpgradeConfig and UpgradeTreadmillRequest) then return end
    local lvl = plot:GetAttribute("TreadmillLevel") or TreadmillUpgradeConfig.DefaultLevel
    local cost = TreadmillUpgradeConfig.UpgradeCost(lvl)
    if type(cost) == "number" and cash() >= cost then
        pcall(function() UpgradeTreadmillRequest:FireServer() end)
    end
end

local function tryUpgradePlot()
    local plot = myPlot()
    if not plot then return end
    if not (PlotUpgradeConfig and UpgradePlotRequest) then return end
    local lvl = plot:GetAttribute("PlotLevel") or PlotUpgradeConfig.DefaultLevel
    local cost = PlotUpgradeConfig.UpgradeCost(lvl)
    if type(cost) == "number" and cash() >= cost then
        pcall(function() UpgradePlotRequest:FireServer() end)
    end
end

-- Auto Upgrade Trail: buy the next unowned trail we can afford with CASH (the same
-- "Buy" the shop's cash Purchase button fires; never the Robux DevProduct). Owned
-- ids come from LocalPlayer "EquippedTrail" + "OwnedTrails" (comma-separated).
local function tryUpgradeTrail()
    if not (TrailsConfig and TrailShopRequest) then return end
    local owned = {}
    local eq = TrailsConfig.ClampEquipped(LocalPlayer:GetAttribute(TrailsConfig.EquippedAttribute))
    if type(eq) == "number" and eq ~= 0 then owned[eq] = true end
    local ownedStr = LocalPlayer:GetAttribute(TrailsConfig.OwnedAttribute)
    if type(ownedStr) == "string" then
        for s in string.gmatch(ownedStr, "[^,]+") do
            local n = tonumber(s)
            if n then owned[n] = true end
        end
    end
    local c = cash()
    local nextId = nil
    for _, t in ipairs(TrailsConfig.Trails) do
        if type(t.Price) == "number" and t.Price > 0 and t.Price <= c and not owned[t.Id] then
            if not nextId or t.Id < nextId then nextId = t.Id end
        end
    end
    if nextId then
        pcall(function() TrailShopRequest:FireServer("Buy", nextId) end)
    end
end

-- Auto Claim Index: the game's Index panel (MainGUI.Frames.Index) shows a
-- CompletionBar.Claim button whenever there are unclaimed index rewards, and the
-- game's own button fires IndexRemote:FireServer("ClaimAll", nil). We mirror that
-- exactly, only firing while the button is visible so nothing is sent when there is
-- nothing to claim.
local function autoClaimIndex()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local mainGui = pg and pg:FindFirstChild("MainGUI")
    local frames = mainGui and mainGui:FindFirstChild("Frames")
    local index = frames and frames:FindFirstChild("Index")
    local bar = index and index:FindFirstChild("CompletionBar")
    local btn = bar and bar:FindFirstChild("Claim")
    if not (btn and btn:IsA("GuiButton") and btn.Visible) then return end
    local remote = ReplicatedStorage:FindFirstChild("IndexRemote")
    if remote and remote:IsA("RemoteEvent") then
        pcall(function() remote:FireServer("ClaimAll", nil) end)
    end
end

local petNotified = setmetatable({}, { __mode = "k" })

local function formatShort(n)
    n = tonumber(n) or 0
    if n >= 1e12 then return string.format("%.2fT", n / 1e12) end
    if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
    if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
    if n >= 1e3 then return string.format("%.2fK", n / 1e3) end
    return tostring(math.floor(n))
end

local function petImageUrl(name)
    if not name then return nil end
    if petThumbCache[name] ~= nil then return petThumbCache[name] or nil end
    local url = nil
    local render = AnimalRenders and AnimalRenders.Normal and AnimalRenders.Normal[name]
    local assetId = render and tostring(render):match("%d+") or nil
    if assetId and httpRequest then
        pcall(function()
            local res = httpRequest({
                Url = "https://thumbnails.roblox.com/v1/assets?assetIds=" .. assetId
                    .. "&returnPolicy=PlaceHolder&size=420x420&format=Png&isCircular=false",
                Method = "GET",
            })
            if res and type(res) == "table" and res.Body then
                local decoded = HttpService:JSONDecode(res.Body)
                if decoded and decoded.data and decoded.data[1] and decoded.data[1].imageUrl then
                    url = decoded.data[1].imageUrl
                end
            end
        end)
    end
    if not url and assetId then
        url = "https://www.roblox.com/asset-thumbnail/image?assetId=" .. assetId .. "&width=420&height=420&format=png"
    end
    petThumbCache[name] = url or false
    return url
end

local function plotPetsList()
    local plot = myPlot()
    local pa = plot and plot:FindFirstChild("PlacedAnimals")
    if not pa then return "_(kosong)_" end
    local rows = {}
    for _, m in ipairs(pa:GetChildren()) do
        rows[#rows + 1] = {
            name = m:GetAttribute("AnimalName") or m.Name,
            cps = m:GetAttribute("CashPerSecond") or 0,
        }
    end
    table.sort(rows, function(a, b) return a.cps > b.cps end)
    local lines = {}
    for i, r in ipairs(rows) do
        lines[#lines + 1] = ("%d. **%s** — $%s/s"):format(i, r.name, formatShort(r.cps))
    end
    if #lines == 0 then return "_(kosong)_" end
    return table.concat(lines, "\n")
end

local function webhookAllowed(name, rarity)
    local rf = Config.WebhookRarityFilter
    if rf and next(rf) ~= nil and not (rarity and rf[rarity] == true) then return false end
    local nf = Config.WebhookNameFilter
    if nf and next(nf) ~= nil and not (name and nf[name] == true) then return false end
    return true
end

local function sendPetWebhook(pet, isTest)
    if not isTest and not Config.WebhookEnabled then return false, "disabled" end
    local url = Config.WebhookUrl
    if url then url = url:match("^%s*(.-)%s*$") end
    if not url or url == "" then return false, "URL kosong" end
    if not (url:find("discord%.com/api/webhooks") or url:find("discordapp%.com/api/webhooks")) then
        return false, "URL bukan Discord webhook valid"
    end
    if not httpRequest then return false, "Executor tidak mendukung HTTP" end

    local function build()
        local name = pet.Name or "Unknown"
        local rarity = pet.Rarity or "?"
        local inc = 0
        if Runtime.petIncomeFor then
            local ok, v = pcall(Runtime.petIncomeFor, name, pet.Size, pet.Mutation, pet.Weight, pet.Variant)
            if ok and type(v) == "number" then inc = v end
        end
        local fields = {
            { name = "💵 Income", value = "$" .. formatShort(inc) .. "/s", inline = false },
            { name = "⭐ Rarity", value = ("`%s`"):format(rarity), inline = false },
            { name = "📏 Size / ⚖️ Weight", value = ("x%s / %s KG"):format(tostring(pet.Size or 1), tostring(pet.Weight or 0)), inline = false },
            { name = "🧬 Mutation / Variant", value = ("%s / %s"):format(tostring(pet.Mutation or "-"), tostring(pet.Variant or "-")), inline = false },
            { name = "📍 Source", value = tostring(pet.Source or "-"), inline = false },
            { name = "👤 Player", value = LocalPlayer.Name .. " (" .. LocalPlayer.DisplayName .. ")", inline = false },
            { name = "💰 Cash", value = "$" .. formatShort(cash()), inline = false },
        }
        if Config.WebhookIncludePlot then
            fields[#fields + 1] = { name = "🏠 Plot (Income/s)", value = plotPetsList(), inline = false }
        end
        local embed = {
            title = "🎉 Pet Obtained! (" .. name .. ")",
            color = RARITY_COLORS[rarity] or 14423100,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            fields = fields,
            footer = { text = "RooxHub • Break and Steal an Egg | Discord: " .. DISCORD_INVITE },
        }
        local img = petImageUrl(name)
        if img then embed.thumbnail = { url = img } end
        local body = HttpService:JSONEncode({
            username = "RooxHub • Break and Steal an Egg",
            embeds = { embed },
        })
        local ok, res = pcall(function()
            return httpRequest({
                Url = url,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = body,
            })
        end)
        if not ok then return false, tostring(res) end
        if res and type(res) == "table" and res.StatusCode and (res.StatusCode < 200 or res.StatusCode >= 300) then
            return false, "HTTP " .. tostring(res.StatusCode)
        end
        return true
    end

    if isTest then return build() end
    task.spawn(build)
    return true
end

local function processPetTool(tool)
    if not Config.WebhookEnabled then return end
    if not tool or not tool:IsA("Tool") then return end
    if not CollectionService:HasTag(tool, "AnimalTool") then return end
    -- Auto Break and Auto Steal Player send their webhooks explicitly at bank
    -- time (sendAutoBreakWebhook / sendHuntWebhook), so the Backpack.ChildAdded
    -- hook must NOT duplicate them. Skip entirely while either feature is active.
    if Config.AutoSteal or Config.AutoStealPlayer then return end
    if tool:GetAttribute("BackpackRestored") == true then return end
    if petNotified[tool] then return end
    petNotified[tool] = true
    local name = tool:GetAttribute("AnimalName") or tool.Name
    local rarity = rarityOfTool(tool)
    if not webhookAllowed(name, rarity) then return end
    sendPetWebhook({
        Name = name,
        Rarity = rarity,
        Size = tool:GetAttribute("SizeMult"),
        Weight = tool:GetAttribute("WeightKg"),
        Mutation = tool:GetAttribute("Mutation"),
        Variant = tool:GetAttribute("Variant"),
        Source = Runtime.LastSource or "Manual",
    })
end

local function hookPetWebhook(container)
    if not container then return end
    local key = "PetWebhook_" .. container.Name
    if Connections[key] then return end
    Connections[key] = container.ChildAdded:Connect(processPetTool)
end

-- Auto Steal Player (HUNT) webhook. The stolen pet does not fire the Backpack
-- AnimalTool hook, so we send it explicitly when the pet is banked. Details come
-- from the AnimalPickup model attributes (same names as a pet Tool).
local function captureHuntPetInfo(pick, fallbackName)
    if not pick then return end
    Runtime.HuntPetInfo = {
        Name = pick:GetAttribute("AnimalName") or fallbackName,
        Size = pick:GetAttribute("SizeMult"),
        Mutation = pick:GetAttribute("Mutation"),
        Weight = pick:GetAttribute("WeightKg"),
        Variant = pick:GetAttribute("Variant"),
    }
end

local function sendHuntWebhook()
    local info = Runtime.HuntPetInfo
    local name = (info and info.Name) or Runtime.HuntCarried
    Runtime.HuntPetInfo = nil
    if not name then return end
    local rarity = rarityOfName(name)
    if not (Config.WebhookEnabled and webhookAllowed(name, rarity)) then return end
    Runtime.HuntWebhookName = name
    Runtime.HuntWebhookAt = os.clock()
    sendPetWebhook({
        Name = name,
        Rarity = rarity,
        Size = info and info.Size,
        Mutation = info and info.Mutation,
        Weight = info and info.Weight,
        Variant = info and info.Variant,
        Source = "Auto Steal Player",
    })
end

local function captureAutoBreakPetInfo(pick, fallbackName)
    if not pick then return end
    Runtime.AutoBreakPetInfo = {
        Name = pick:GetAttribute("AnimalName") or fallbackName,
        Size = pick:GetAttribute("SizeMult"),
        Mutation = pick:GetAttribute("Mutation"),
        Weight = pick:GetAttribute("WeightKg"),
        Variant = pick:GetAttribute("Variant"),
    }
end

local function sendAutoBreakWebhook()
    local info = Runtime.AutoBreakPetInfo
    Runtime.AutoBreakPetInfo = nil
    if not info or not info.Name then return end
    local name = info.Name
    local rarity = rarityOfName(name)
    if not (Config.WebhookEnabled and webhookAllowed(name, rarity)) then return end
    Runtime.MetaWebhookName = name
    Runtime.MetaWebhookAt = os.clock()
    sendPetWebhook({
        Name = name,
        Rarity = rarity,
        Size = info.Size,
        Mutation = info.Mutation,
        Weight = info.Weight,
        Variant = info.Variant,
        Source = "Auto Break",
    })
end

local function isPlayerCarrying(p)
    return p and p:GetAttribute("Carrying") ~= nil
end

-- UNIFIED HUNT TARGET: a pet whose income >= AutoStealMinIncome, whether it is
-- being CARRIED by another player or lying on the ground as an AnimalPickup. One
-- system, no zone filter, works in every zone. Returns (kind, subject, dist):
--   kind = "PLAYER" -> subject is the Player
--   kind = "DROP"   -> subject is the AnimalPickup Model
local function petIncomeFor(name, size, mut, kg, var)
    if not (EggRewards and EggRewards.PlacedCashPerSecond and type(name) == "string") then return 0 end
    local ok, v = pcall(function() return EggRewards.PlacedCashPerSecond(name, size, mut, kg, var) end)
    if ok and type(v) == "number" then return v end
    return 0
end
Runtime.petIncomeFor = petIncomeFor
-- Tile-break helper: is this candidate strictly better than the current best?
-- Priority is INCOME (highest wins); distance only breaks exact ties. This makes
-- the hunt always go for the single most valuable pet on the server, whatever the
-- minimum-income setting is - it never settles for a nearby low-value pet.
local function huntBetter(inc, dist, bestInc, bestDist)
    if not bestInc then return true end
    if inc > bestInc then return true end
    if inc == bestInc and dist < bestDist then return true end
    return false
end

-- AUTO STEAL (DROP-ONLY): the target is always a dropped AnimalPickup on the
-- ground (never a player-carried pet). Picks the highest-income drop that passes
-- the income minimum + rarity filter + mutation filter.
local function findHuntTarget(pos)
    local need = tonumber(Config.AutoStealMinIncome) or 0
    local best, bd = nil, math.huge
    local bestInc = nil
    if Runtime.pickupIncome then
        for _, pick in ipairs(livePickups()) do
            local pname = pick:GetAttribute("AnimalName")
            if pname and petAllowed(pname, pick:GetAttribute("Mutation")) then
                local inc = Runtime.pickupIncome(pick)
                if inc >= need and inc > 0 then
                    local m = (pick:GetPivot().Position - pos).Magnitude
                    if huntBetter(inc, m, bestInc, bd) then
                        bestInc = inc; bd = m; best = pick
                    end
                end
            end
        end
    end
    return "DROP", best, bd
end

-- HUNT pickup selector: never grabs an arbitrary pet. It matches the INTENDED pet
-- by name first (the one we just stole/dropped); only if the name is unknown does
-- it fall back to the highest-income pickup (>= min). It NEVER returns an
-- income-blind / below-minimum pet the way nearestPickupRaw did.
Runtime.huntPickupFor = function(center, radius, wantName, ignore)
    local need = tonumber(Config.AutoStealMinIncome) or 0
    local r = radius or math.huge
    local function ok(pick)
        return pick and pick:IsA("Model") and pick.Parent
            and not pick:GetAttribute("Despawning") and pick ~= ignore
    end
    if wantName then
        local best, bd = nil, r
        for _, p in ipairs(livePickups()) do
            if ok(p) and p:GetAttribute("AnimalName") == wantName
                and petAllowed(p:GetAttribute("AnimalName"), p:GetAttribute("Mutation")) then
                local m = (p:GetPivot().Position - center).Magnitude
                if m < bd then bd = m; best = p end
            end
        end
        if best then return best end
    end
    -- no name match: highest income at/above the minimum (never below-min), and
    -- still respecting the rarity + mutation filters (never grab an off-filter pet).
    local best, bestInc, bestDist = nil, nil, math.huge
    for _, p in ipairs(livePickups()) do
        if ok(p) and petAllowed(p:GetAttribute("AnimalName"), p:GetAttribute("Mutation")) then
            local inc = Runtime.pickupIncome and Runtime.pickupIncome(p) or 0
            if inc >= need and inc > 0 then
                local m = (p:GetPivot().Position - center).Magnitude
                if m <= r and huntBetter(inc, m, bestInc, bestDist) then
                    bestInc = inc; bestDist = m; best = p
                end
            end
        end
    end
    return best
end

-- Forced-TP pin used by the drop-only HUNT relocation (self-kill -> respawn ->
-- pin onto the dropped pet). Kept SEPARATE from the META pin.
local function huntForceStep()
    if not Runtime.HuntForcePos then return end
    if os.clock() > (Runtime.HuntForceUntil or 0) or not Runtime.HuntForcePin then
        Runtime.HuntForcePos = nil
        Runtime.HuntForcePin = false
        pcall(function() RunService:UnbindFromRenderStep("BSHuntForce") end)
        return
    end
    local c, hrp = getChar()
    if not hrp then return end
    local floorAir = true
    pcall(function()
        local h = c and c:FindFirstChildOfClass("Humanoid")
        floorAir = h and h.FloorMaterial == Enum.Material.Air
    end)
    -- MINIMUM HOLD: never release merely because we touched down. A respawn jump
    -- lands for a single frame and the server reconciliation then pulls us back.
    if os.clock() < (Runtime.HuntForceMinUntil or 0) then
        pcall(function() hrp.CFrame = CFrame.new(Runtime.HuntForcePos) end)
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)
        return
    end
    if not guardCatchNow() and not floorAir
        and (hrp.Position - Runtime.HuntForcePos).Magnitude <= 4 then
        Runtime.HuntForcePos = nil
        Runtime.HuntForcePin = false
        pcall(function() RunService:UnbindFromRenderStep("BSHuntForce") end)
        return
    end
    pcall(function() hrp.CFrame = CFrame.new(Runtime.HuntForcePos) end)
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
end

-- Forced TP onto a target position, pinned (anchor-freeze) for a short window.
Runtime.huntForceTp = function(pos, yoff, hold)
    local c, hrp = getChar()
    if not hrp then return false end
    moveStop()
    Runtime.AntiKnockPos = nil
    pcall(function() RunService:UnbindFromRenderStep("BSAntiKnock") end)
    local dest = pos + Vector3.new(0, yoff or 2, 0)
    Runtime.HuntForcePos = dest
    Runtime.HuntForceUntil = os.clock() + (hold or 2.0)
    Runtime.HuntForceMinUntil = os.clock() + math.min(hold or 2.0, 0.7)
    Runtime.HuntForcePin = true
    pcall(function() RunService:BindToRenderStep("BSHuntForce", Enum.RenderPriority.Character.Value - 1, huntForceStep) end)
    pcall(function() hrp.CFrame = CFrame.new(dest) end)
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
    return true
end

local function backpackTools()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local list = {}
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then list[#list + 1] = t end
        end
    end
    return list
end

local function rarityAllowed(r)
    if not Config.SellRarities or next(Config.SellRarities) == nil then return false end
    return r ~= nil and Config.SellRarities[r] == true
end

local function equipBestPet()
    if PetsInventoryRemote then
        pcall(function() PetsInventoryRemote:FireServer("EquipBest", nil) end)
    end
end

local function sellPets()
    if not BackpackSellRemote then return end
    local list = {}
    for _, t in ipairs(backpackTools()) do
        if CollectionService:HasTag(t, "AnimalTool") and rarityAllowed(t:GetAttribute("Rarity")) then
            list[#list + 1] = t
            if #list >= 200 then break end
        end
    end
    if #list == 0 then return end
    pcall(function() BackpackSellRemote:InvokeServer(list) end)
end

local function mergeRarityAllowed(t)
    if not Config.MergeRarities or next(Config.MergeRarities) == nil then return true end
    local r = rarityOfTool(t)
    return r ~= nil and Config.MergeRarities[r] == true
end

local function mergePetTools()
    local list = {}
    for _, t in ipairs(backpackTools()) do
        if CollectionService:HasTag(t, "AnimalTool") and mergeRarityAllowed(t) then
            list[#list + 1] = t
        end
    end
    return list
end

local function doMerge()
    if not MergeMachineRemote then return end
    local groups, order = {}, {}
    for _, t in ipairs(mergePetTools()) do
        local name = t:GetAttribute("AnimalName") or t.Name
        if not groups[name] then
            groups[name] = {}
            order[#order + 1] = name
        end
        groups[name][#groups[name] + 1] = t
    end
    for _, name in ipairs(order) do
        local g = groups[name]
        if #g >= 3 then
            pcall(function() MergeMachineRemote:FireServer("Merge", { g[1], g[2], g[3] }) end)
            return
        end
    end
end

-- ============================================================================
-- AUTO FUSE (remote-only): the game's Fuse Machine (Zone10 / SciFi UI) is driven
-- by ReplicatedStorage.FuseMachineRequest. We mirror the game's own controller:
--   "Sync"                 -> server replies "State" (deposits, recipe)
--   "Deposit"(petName, tool)
--   "Fuse"
-- Fired from anywhere (no walking), exactly like Auto Merge.
-- ============================================================================
;(function()
    local FuseCfg = nil
    pcall(function() FuseCfg = require(ReplicatedStorage.Shared.FuseMachineConfig) end)
    local SPEED_ATTR = (FuseCfg and FuseCfg.SpeedPowerAttribute) or "SpeedPower"
    local REQ_POWER = (FuseCfg and FuseCfg.RequiredSpeedPower) or 100000000000
    local COOLDOWN = (FuseCfg and FuseCfg.RequestCooldown) or 0.25

    local function hasSpeed()
        local p = LocalPlayer:GetAttribute(SPEED_ATTR)
        return type(p) == "number" and p >= REQ_POWER
    end
    Runtime.fuseHasSpeed = hasSpeed

    -- Find an owned AnimalTool (backpack or equipped) whose AnimalName matches `name`.
    local function findTool(name)
        local bp = LocalPlayer:FindFirstChild("Backpack")
        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") and CollectionService:HasTag(t, "AnimalTool")
                    and t:GetAttribute("AnimalName") == name then
                    return t
                end
            end
        end
        local c = LocalPlayer.Character
        local eq = c and c:FindFirstChildOfClass("Tool")
        if eq and CollectionService:HasTag(eq, "AnimalTool")
            and eq:GetAttribute("AnimalName") == name then
            return eq
        end
        return nil
    end

    local function sync(now)
        if now - (Runtime.FuseLastSync or 0) < 1.5 then return end
        Runtime.FuseLastSync = now
        Runtime.FuseLastAction = now
        pcall(function() FuseMachineRequest:FireServer("Sync") end)
    end

    Runtime.tryAutoFuse = function(now)
        if not Config.AutoFuse or not FuseMachineRequest then return end
        if now - (Runtime.FuseLastAction or 0) < COOLDOWN then return end
        if not hasSpeed() then return end

        if Runtime.FuseInFlight then
            -- safety: never stay stuck if the server never confirms the fuse
            if now - (Runtime.FuseLastAction or 0) > 6 then Runtime.FuseInFlight = false end
            return
        end

        local recipe = Runtime.FuseRecipe
        if not recipe or next(recipe) == nil then
            sync(now)          -- ask the server for the recipe
            return
        end

        local dep = Runtime.FuseDeposits or {}
        -- prune stale "sent but not confirmed" marks so a rejected deposit can retry
        local sent = Runtime.FuseSent
        if not sent then sent = {}; Runtime.FuseSent = sent end
        for nm, at in pairs(sent) do
            if now - at > 2.0 or dep[nm] ~= nil then sent[nm] = nil end
        end

        -- all recipe slots confirmed by the server -> fuse
        local allDone = true
        for _, name in pairs(recipe) do
            if dep[name] == nil then allDone = false break end
        end
        if allDone then
            Runtime.FuseLastAction = now
            Runtime.FuseInFlight = true
            Runtime.FuseSent = {}
            pcall(function() FuseMachineRequest:FireServer("Fuse") end)
            return
        end

        -- deposit the next missing recipe pet we own (one request per cooldown tick)
        for _, name in pairs(recipe) do
            if dep[name] == nil and sent[name] == nil then
                local tool = findTool(name)
                if tool then
                    sent[name] = now
                    Runtime.FuseLastAction = now
                    pcall(function() FuseMachineRequest:FireServer("Deposit", name, tool) end)
                else
                    -- do not own this pet: ask the server to re-roll (it prefers owned pets)
                    sync(now)
                end
                return
            end
        end
    end

    if FuseMachineRequest and FuseMachineRequest:IsA("BaseRemoteEvent") then
        Connections.FuseMachine = FuseMachineRequest.OnClientEvent:Connect(function(action, a2, a3)
            if action == "State" then
                local dep = {}
                if type(a2) == "table" then
                    for i in pairs(a2) do
                        if type(i) == "string" then dep[i] = true end
                    end
                end
                local rec = nil
                if type(a3) == "table" then
                    rec = {}
                    for k, n in pairs(a3) do
                        if type(n) == "string" then rec[k] = n end
                    end
                end
                Runtime.FuseDeposits = dep
                Runtime.FuseRecipe = rec
                Runtime.FuseInFlight = false
            elseif action == "Fused" then
                Runtime.FuseCount = (Runtime.FuseCount or 0) + 1
                Runtime.FuseRecipe = nil
                Runtime.FuseDeposits = nil
                Runtime.FuseSent = {}
                Runtime.FuseInFlight = false
            end
        end)
    end
end)()

-- ============================================================================
-- AUTO COMPLETE INDEX: farm the LOWEST zone that still has Index pets missing,
-- collecting ONLY those missing pets (via the internal INDEX_FILTER override, so
-- the user's own Egg/Pet filter is untouched). Requires Auto Break (AutoSteal) ON;
-- reward claiming is handled by the existing AutoClaimIndex.
-- ============================================================================
;(function()
    local IndexRemote = ReplicatedStorage:FindFirstChild("IndexRemote")
    local StateMap = {}          -- name -> "Ready"/"Claimed" (from the server "State")
    local StateSeen = false
    local byZone = nil           -- { [zoneNumber] = { names } } for the visible Index
    local lastGet = 0
    local lastScan = 0

    local function buildByZone()
        if byZone then return byZone end
        byZone = {}
        if not EggRewards or type(EggRewards.Pool) ~= "table" then return byZone end
        for _, j in ipairs(EggRewards.Pool) do
            local zone = j.Zone
            if type(j.Name) == "string" and type(zone) == "number" and not j.IndexHidden then
                local t = byZone[zone]
                if not t then t = {}; byZone[zone] = t end
                t[#t + 1] = j.Name
            end
        end
        return byZone
    end

    if IndexRemote and IndexRemote:IsA("BaseRemoteEvent") then
        Connections.IndexState = IndexRemote.OnClientEvent:Connect(function(action, a2)
            if action == "State" and type(a2) == "table" then
                local m = {}
                for k, v in pairs(a2) do
                    if type(k) == "string" then m[k] = v end
                end
                StateMap = m
                StateSeen = true
            end
        end)
    end

    Runtime.updateAutoCompleteIndex = function(now)
        if not Config.AutoCompleteIndex or not Config.AutoSteal then
            INDEX_FILTER.Missing = nil
            INDEX_FILTER.ZoneId = nil
            Runtime.IndexZone = nil
            Runtime.IndexMissingCount = nil
            Runtime.IndexWaiting = false
            return
        end
        -- refresh the server-side Index state periodically
        if IndexRemote and now - lastGet > 3 then
            lastGet = now
            pcall(function() IndexRemote:FireServer("Get", nil) end)
        end
        if not StateSeen then
            INDEX_FILTER.Missing = nil
            INDEX_FILTER.ZoneId = nil
            Runtime.IndexZone = nil
            Runtime.IndexMissingCount = nil
            Runtime.IndexWaiting = true
            return
        end
        Runtime.IndexWaiting = false
        if now - lastScan < 1 then return end
        lastScan = now
        local zones = buildByZone()
        local bestZone, bestMissing = nil, nil
        -- highest zone present in the pool (Zone12+ included automatically),
        -- so a newly added map zone never has to be hardcoded here again.
        local maxZone = 0
        for zn in pairs(zones) do
            if type(zn) == "number" and zn > maxZone then maxZone = zn end
        end
        for zn = 1, maxZone do
            local names = zones[zn]
            if names then
                local miss = nil
                for _, name in ipairs(names) do
                    if StateMap[name] == nil then
                        if not miss then miss = {} end
                        miss[name] = true
                    end
                end
                if miss then bestZone, bestMissing = zn, miss break end
            end
        end
        if bestZone then
            INDEX_FILTER.ZoneId = "Zone" .. tostring(bestZone)
            INDEX_FILTER.Missing = bestMissing
            local cnt = 0
            for _ in pairs(bestMissing) do cnt = cnt + 1 end
            Runtime.IndexZone = bestZone
            Runtime.IndexMissingCount = cnt
        else
            -- nothing missing anywhere: release the override; Auto Break resumes normal
            INDEX_FILTER.Missing = nil
            INDEX_FILTER.ZoneId = nil
            Runtime.IndexZone = nil
            Runtime.IndexMissingCount = 0
        end
    end
end)()

local function doHatchReady()
    for _, m in ipairs(CollectionService:GetTagged("MergeEggPlaced")) do
        if m.Parent and m:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
            local id = m:GetAttribute("EggId")
            local ready = m:GetAttribute("Ready")
            local readyAt = m:GetAttribute("ReadyAtServerTime") or 0
            if id ~= nil and (ready == true or readyAt <= Workspace:GetServerTimeNow()) then
                if MergeMachineRemote then
                    pcall(function() MergeMachineRemote:FireServer("HatchEgg", id) end)
                end
            end
        end
    end
end

-- ============================================================================
-- AUTO PLANT EGG: place egg tools (tag MergeEggTool) from the backpack onto the
-- plot. The game plants via MergeMachineRemote:FireServer("PlaceEgg", tool, pos)
-- where pos is a world point on the plot (the click-ray hit). Kept on Runtime to
-- avoid new top-level locals (main chunk is at the 200-local ceiling).
-- ============================================================================
Runtime.PLANT_OFFSETS = {
    { 0, 0 }, { 9, 0 }, { -9, 0 }, { 0, 9 }, { 0, -9 },
    { 9, 9 }, { -9, -9 }, { 9, -9 }, { -9, 9 },
    { 18, 0 }, { -18, 0 }, { 0, 18 }, { 0, -18 },
}
Runtime.plantRarityAllowed = function(tool)
    if not Config.PlantRarities or next(Config.PlantRarities) == nil then return true end
    local r = rarityOfName(tool:GetAttribute("AnimalName"))
    return r ~= nil and Config.PlantRarities[r] == true
end
Runtime.nextPlantEgg = function()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and CollectionService:HasTag(t, "MergeEggTool") and Runtime.plantRarityAllowed(t) then
                return t
            end
        end
    end
    local c = LocalPlayer.Character
    local eq = c and c:FindFirstChildOfClass("Tool")
    if eq and CollectionService:HasTag(eq, "MergeEggTool") and Runtime.plantRarityAllowed(eq) then
        return eq
    end
    return nil
end
Runtime.tryPlantEgg = function()
    if not MergeMachineRemote then return end
    local _, hrp, hum = getChar()
    if not hrp or not hum then return end
    local tool = Runtime.nextPlantEgg()
    if not tool then return end
    pcall(function() hum:EquipTool(tool) end)
    local offs = Runtime.PLANT_OFFSETS
    local idx = ((Runtime.PlantSpot or 0) % #offs) + 1
    Runtime.PlantSpot = (Runtime.PlantSpot or 0) + 1
    local off = offs[idx]
    local pos = Vector3.new(hrp.Position.X + off[1], hrp.Position.Y - 2.6, hrp.Position.Z + off[2])
    pcall(function() MergeMachineRemote:FireServer("PlaceEgg", tool, pos) end)
    Runtime.PlantFires = (Runtime.PlantFires or 0) + 1
end

-- The character's OWN plot home point (the pen area). Resolved EVERY call so it
-- stays correct after a rejoin / plot change (the plot model and its position can
-- differ per session). Falls back to the plot Hitbox spot.
Runtime.plotHome = function()
    local plot = myPlot()
    if not plot then return nil end
    local ok, pivot = pcall(function() return plot:GetPivot().Position end)
    if ok and pivot then return pivot end
    return plotSpot()
end
-- Auto Plant Egg step: walk (never a big TP) to our OWN plot first when we are off it,
-- then plant. Only runs while idle and not carrying.
Runtime.plantStep = function(now)
    if not MergeMachineRemote then return end
    if not Runtime.nextPlantEgg() then Runtime.PlantMode = false return end
    local _, hrp = getChar()
    if not hrp then return end
    local home = Runtime.plotHome()
    if not home then Runtime.PlantMode = false return end
    if (hrp.Position - home).Magnitude > 14 then
        -- off the plot: step to it (re-issued so the idle walk-stop cannot cancel)
        Runtime.PlantMode = true
        if now - (Runtime.PlantGoAt or 0) > 0.25 then
            Runtime.PlantGoAt = now
            tpTo(home, 3, moveSpeed())
        end
        return
    end
    Runtime.PlantMode = false
    if now - (Runtime.LastPlant or 0) > 0.7 then
        Runtime.LastPlant = now
        Runtime.tryPlantEgg()
    end
end

local function pickupIncome(pick)
    if not (EggRewards and EggRewards.PlacedCashPerSecond) then return 0 end
    local name = pick:GetAttribute("AnimalName")
    if type(name) ~= "string" then return 0 end
    local size = pick:GetAttribute("SizeMult") or 1
    local mut = pick:GetAttribute("Mutation")
    local kg = pick:GetAttribute("WeightKg")
    local var = pick:GetAttribute("Variant")
    local ok, v = pcall(function() return EggRewards.PlacedCashPerSecond(name, size, mut, kg, var) end)
    if ok and type(v) == "number" then return v end
    return 0
end
Runtime.pickupIncome = pickupIncome

-- Highest-income dropped AnimalPickup at or above the configured absolute
-- minimum ($/s). nil if none qualifies. Used by the far-zone meta.
local function bestMinIncomePickup(center, radius)
    local r = radius or math.huge
    if INDEX_FILTER.Missing then
        -- Auto Complete Index mode: take the NEAREST wanted pet, ignoring income
        -- (the income minimum must not block collecting an Index pet).
        local best, bd = nil, math.huge
        for _, p in ipairs(livePickups()) do
            if petAllowed(p:GetAttribute("AnimalName"), p:GetAttribute("Mutation")) then
                local m = (p:GetPivot().Position - center).Magnitude
                if m <= r and m < bd then bd = m; best = p end
            end
        end
        return best, best and pickupIncome(best) or 0
    end
    local need = tonumber(Config.AutoStealMinIncome) or 0
    local best, bestInc = nil, need
    for _, p in ipairs(livePickups()) do
        local m = (p:GetPivot().Position - center).Magnitude
        if m <= r and petAllowed(p:GetAttribute("AnimalName"), p:GetAttribute("Mutation")) then
            local inc = pickupIncome(p)
            if inc >= bestInc and inc > 0 then
                bestInc = inc; best = p
            end
        end
    end
    return best, bestInc
end

-- Find the pet the guard dropped when it seized us: an AnimalPickup matching
-- the pet we were carrying, within 40 studs of the player or of a nearby guard
-- (we may have been flung away from our feet).
local function findRecoverPickup(pos, want)
    want = want or Runtime.MetaCarried
    local centers = { pos }
    for _, g in ipairs(CollectionService:GetTagged("ZoneGuard")) do
        if g:IsA("Model") and g.Parent then
            local h = g:FindFirstChild("HumanoidRootPart", true)
            if h and (h.Position - pos).Magnitude <= 250 then centers[#centers + 1] = h.Position end
        end
    end
    local best, bd = nil, 60
    -- last-resort global match (bounded): still locate the pet after a big fling
    local globalBest, globalBd = nil, 300
    for _, p in ipairs(livePickups()) do
        if p:IsA("Model") and p.Parent then
            local name = p:GetAttribute("AnimalName")
            if not want or name == want then
                local pp = p:GetPivot().Position
                for _, c in ipairs(centers) do
                    local m = (pp - c).Magnitude
                    if m < bd then bd = m; best = p end
                end
                local dm = (pp - pos).Magnitude
                if dm < globalBd then globalBd = dm; globalBest = p end
            end
        end
    end
    return best or globalBest
end

-- BigFroot catch pickup: during the ~3s after a guard catch, look for the dropped
-- pet within 60 studs of the CATCH point (CatchAt); otherwise within 15 of us.
Runtime.findCatchPickup = function(want, radius)
    local _, hrp = getChar()
    local now = os.clock()
    local inWin = Runtime.CatchAt ~= nil and (now - (Runtime.FlungAt or 0)) < 3
    local center = (inWin and Runtime.CatchAt) or (hrp and hrp.Position)
    if not center then return nil end
    local r = radius or (inWin and 60 or 15)
    local best, bd = nil, r
    for _, p in ipairs(livePickups()) do
        if p:IsA("Model") and p.Parent and not p:GetAttribute("Despawning") then
            local nm = p:GetAttribute("AnimalName")
            if (not want) or nm == want then
                local m = (p:GetPivot().Position - center).Magnitude
                if m < bd then bd = m; best = p end
            end
        end
    end
    return best
end

-- After a successful bank, BigFroot does NOT stand still: it instantly re-enters
-- the farm loop and TPs straight back to the target zone for the next egg.
Runtime.metaBankResume = function(now)
    Runtime.BankStage = nil
    Runtime.BankLeapt = false
    Runtime.BankPick = nil
    Runtime.BankWant = nil
    Runtime.BankHelpDrop = false
    Runtime.BankPulled = false
    Runtime.MetaStage = "TRAVEL"
    Runtime.MetaStageAt = now
    Runtime.TargetEgg = nil
    Runtime.BurstEgg = nil
    Runtime.MetaCoolUntil = 0
    Runtime.Phase = "META"
    if isV1() then
        -- TP v1 hallmark: after a bank the cycle restarts from Zone 1 via the
        -- decoy (walk to a Zone 1 egg -> break -> pickup -> guard catch -> TP to
        -- the target zone). This is NOT a "retry": it is how TP v1 enters a zone
        -- safely. It is only skipped while we are ALREADY inside the target zone
        -- (see the decoy arming guard below), so it no longer loops back to the
        -- start when we are standing in Zone 11/12.
        Runtime.DecoyStage = nil
        Runtime.DecoyEgg = nil
        Runtime.DecoyPick = nil
        Runtime.DecoyPulled = false
        Runtime.MetaWalkEntry = false
        Runtime.MetaStage = "TRAVEL"
        Runtime.MetaStageAt = now
        walkStop()
        return
    end
    local _, hrp = getChar()
    if not hrp then return end
    local zoneId = Runtime.MetaZoneId or activeZoneId()
    local egg = metaPickEgg(hrp.Position, zoneId)
    if egg then
        Runtime.TargetEgg = egg
        Runtime.moverReach(egg, zoneId)   -- instant TP back to the zone right now
    end
end

--------------------------------------------------------------------------------
-- BIGFROOT HITGUARD BANKING (all moves are INSTANT TP)
--   BAIT    : instant TP to this zone's guard / SafeZone edge; wait to be caught.
--   RECOVER : the guard seized the pet -> instant TP onto the drop near CatchAt
--             (60 studs) and grab it back.
--   LEAP    : carrying again -> instant TP (Leap) into the SafeZone during the
--             catch window; the server banks it on arrival.
-- v2 re-baits with a Zone1 decoy when the window is about to close.
--------------------------------------------------------------------------------
Runtime.metaBankStep = function(now)
    local _, hrp = getChar()
    if not hrp then return true end
    local pos = hrp.Position
    local stage = Runtime.BankStage

    -- Help Other Player: the pet was dropped for someone else -> resume instantly.
    if Runtime.BankHelpDrop and not isCarrying() then
        Runtime.BankHelpDrop = false
        Runtime.MetaSteals = (Runtime.MetaSteals or 0) + 1
        Runtime.LastSource = "Auto Break"
        sendAutoBreakWebhook()
        Runtime.metaBankResume(now)
        return true
    end

    if stage == "LEAP" then
        if isCarrying() then
            if inSafeZone(pos) then
                Runtime.BankLeapt = true
                -- inside the SafeZone carrying: the server banks on arrival. If it
                -- does not within a few seconds, drop and restart so we never hang.
                if now - (Runtime.BankAt or now) > 6 then
                    dropCarried()
                    Runtime.BankStage = nil
                    Runtime.BankLeapt = false
                    Runtime.MetaStage = nil
                    Runtime.Phase = "IDLE"
                    Runtime.LastFailReason = "bank safe timeout"
                    Runtime.MetaCoolUntil = now + 1.5
                end
                return true
            end
            if Runtime.inWindow(0.2) then
                Runtime.Leap(Runtime.safePosInside(pos))
                Runtime.BankLeapt = true
            elseif now - (Runtime.BankAt or now) > 2 then
                Runtime.BankStage = "BAIT"
                Runtime.BankAt = now
                Runtime.BankPulled = false
            end
        else
            if Runtime.BankLeapt then
                if inSafeZone(pos) then Runtime.Secured = (Runtime.Secured or 0) + 1 end
                Runtime.MetaSteals = (Runtime.MetaSteals or 0) + 1
                Runtime.LastSource = "Auto Break"
                sendAutoBreakWebhook()
                Runtime.metaBankResume(now)
            else
                Runtime.LastFailReason = "bank lost pet"
                Runtime.BankStage = nil
                Runtime.BankLeapt = false
                Runtime.BankPick = nil
                Runtime.MetaStage = nil
                Runtime.Phase = "IDLE"
                Runtime.TargetEgg = nil
                Runtime.BurstEgg = nil
                Runtime.MetaCoolUntil = now + 1.5
            end
        end
        return true
    end

    if stage == "RECOVER" then
        if isCarrying() then
            Runtime.BankStage = "LEAP"
            Runtime.BankAt = now
            return true
        end
        local pick = Runtime.BankPick
        if not pick or not pick.Parent or pick:GetAttribute("Despawning") then
            pick = Runtime.findCatchPickup(Runtime.BankWant)
            -- name mismatch guard: fall back to whatever pet lies at the catch point
            if not pick then pick = Runtime.findCatchPickup(nil) end
            Runtime.BankPick = pick
        end
        if pick then
            local _, promptPos, fireRange = Runtime.pickupFireInfo(pick)
            local target = promptPos or pick:GetPivot().Position
            if (target - pos).Magnitude > (fireRange or 7) then
                if Runtime.inWindow(0.2) then Runtime.Leap(target) else Runtime.instantTp(target) end
            end
            if now - (Runtime.LastStealAttempt or 0) > 0.03 then
                Runtime.LastStealAttempt = now
                Runtime.forcePickupInstant(pick)
            end
        elseif now - (Runtime.BankAt or now) > 3.0 then
            Runtime.BankStage = nil
            Runtime.BankPick = nil
            Runtime.MetaStage = nil
            Runtime.Phase = "IDLE"
            Runtime.LastFailReason = "bank pet lost"
            Runtime.MetaCoolUntil = now + 1.0
        end
        return true
    end

    -- BAIT
    if not isCarrying() then
        Runtime.BankStage = "RECOVER"
        Runtime.BankAt = now
        Runtime.BankPick = nil
        return true
    end
    if Runtime.inWindow(0.2) then
        Runtime.BankStage = "LEAP"
        Runtime.BankAt = now
        return true
    end
    if Config.HelpOtherPlayer then
        local dest = Config.HelpDropPos
        local flat = Vector3.new(dest.X - pos.X, 0, dest.Z - pos.Z)
        if flat.Magnitude > 8 then
            if now - (Runtime.SecureTpAt or 0) > 0.2 then
                Runtime.SecureTpAt = now
                Runtime.instantTp(dest)
            end
        else
            walkStop(); dropCarried()
            Runtime.BankHelpDrop = true
        end
        return true
    end
    -- BAIT: get the zone guard to catch us (that opens the hitguard window).
    -- If it is already chasing and close, stand still and let it hit; otherwise
    -- pull it onto us with an instant TP; if there is no guard, bait at the
    -- SafeZone edge.
    if now - (Runtime.SecureTpAt or 0) > 0.25 then
        Runtime.SecureTpAt = now
        local zg, gd = nil, math.huge
        if Runtime.nearestGuard then zg, gd = Runtime.nearestGuard(pos, Runtime.MetaZoneId) end
        local gp = nil
        if zg then
            local gh = zg:FindFirstChild("HumanoidRootPart", true)
            gp = (gh and gh.Position) or zg:GetPivot().Position
        end
        local zstate = zg and (zg:GetAttribute("ChaseState") or "Idle") or "Idle"
        local chasing = Runtime.BeingChased or zstate == "Chasing" or zstate == "WindUp"
        if gp and chasing then
            walkStop()                        -- it is chasing: hold still, get caught
        elseif gp and (gd or 0) > 60 and not Runtime.BankPulled then
            Runtime.BankPulled = true         -- aggro it ONCE, then let it chase
            Runtime.instantTp(gp)
        else
            walkStop()
        end
    end
    if isV2() then Runtime.tryDecoy() end
    if now - (Runtime.BankAt or now) > 25 then
        if isCarrying() then dropCarried() end
        Runtime.BankStage = nil
        Runtime.BankPick = nil
        Runtime.MetaStage = nil
        Runtime.Phase = "IDLE"
        Runtime.LastFailReason = "bank bait timeout"
        Runtime.MetaCoolUntil = now + 1.5
    end
    return true
end

--------------------------------------------------------------------------------
-- ZONE 1 DECOY ENTRY (BigFroot far-zone access)
-- Before entering a FAR zone (Zone 3+), BigFroot does not TP straight there:
-- it drops into Zone 1, breaks an egg, grabs the pet so the Zone 1 guard chases,
-- gets CAUGHT (this opens the hitguard window), and only inside that window does
-- it instant-TP (hop) to the far zone. Runs ONCE per target zone.
--------------------------------------------------------------------------------
-- Any pickable Zone 1 egg, IGNORING the user's EggType/titanic filter (the decoy
-- only needs SOME egg so the Zone 1 guard starts chasing us).
local function decoyEggZone1(pos)
    local z = zoneBuild("Zone1")
    local eggs = z and z:FindFirstChild("Eggs")
    if not eggs then return nil end
    local best, bd = nil, math.huge
    for _, m in ipairs(eggs:GetChildren()) do
        local e = m:FindFirstChild("Egg")
        if pickableEgg(e) then
            local d = (e.Position - pos).Magnitude
            if d < bd then bd = d; best = e end
        end
    end
    return best
end

Runtime.decoyEntryStep = function(now)
    local _, hrp = getChar()
    if not hrp then return end
    local pos = hrp.Position
    local stage = Runtime.DecoyStage
    local targetZone = Runtime.DecoyZone

    if stage == "GOTO1" then
        local egg = Runtime.DecoyEgg
        if egg and not egg.Parent then egg = nil; Runtime.DecoyEgg = nil end
        if not egg then
            egg = decoyEggZone1(pos)
            Runtime.DecoyEgg = egg
        end
        if not egg then
            -- no Zone 1 egg available: retry by WALKING to the far zone (no TP)
            Runtime.DecoyStage = nil
            Runtime.DecoyDoneZone = targetZone
            Runtime.MetaWalkEntry = true
            Runtime.MetaStage = "TRAVEL"; Runtime.MetaStageAt = now
            return
        end
        if Runtime.eggSurfaceDist(egg, pos) > 4 then
            if isV1() then
                -- TP v1: WALK (genuine Humanoid:Move, like Walk mode) to the Zone 1 egg.
                if not Runtime.walkActive() then Runtime.walkGo(egg.Position, 5) end
            else
                Runtime.moverReach(egg, "Zone1")
            end
        else
            walkStop()
            Runtime.DecoyStage = "BREAK"; Runtime.DecoyStageAt = now
        end

    elseif stage == "BREAK" then
        local egg = Runtime.DecoyEgg
        if not egg or not egg.Parent or eggBrokeOrGone(egg) then
            Runtime.DecoyStage = "PICKUP"; Runtime.DecoyStageAt = now
            return
        end
        if Runtime.eggSurfaceDist(egg, pos) > 4 then
            if isV1() then
                -- TP v1: WALK (genuine Humanoid:Move, like Walk mode) to the Zone 1 egg.
                if not Runtime.walkActive() then Runtime.walkGo(egg.Position, 5) end
            else
                Runtime.moverReach(egg, "Zone1")
            end
        else
            walkStop()
            breakEggStep(egg, now)
        end

    elseif stage == "PICKUP" then
        if isCarrying() then
            Runtime.DecoyStage = "BAIT"; Runtime.DecoyStageAt = now
            return
        end
        local pick = Runtime.DecoyPick
        if not pick or not pick.Parent or pick:GetAttribute("Despawning") then
            pick = bestMinIncomePickup(pos, 120)
            if not pick then
                local best, bd = nil, 200
                for _, p in ipairs(livePickups()) do
                    local m = (p:GetPivot().Position - pos).Magnitude
                    if m < bd then bd = m; best = p end
                end
                pick = best
            end
            Runtime.DecoyPick = pick
        end
        if pick then
            local _, promptPos, fireRange = Runtime.pickupFireInfo(pick)
            local target = promptPos or pick:GetPivot().Position
            if (target - pos).Magnitude > (fireRange or 7) then
                if isV1() then
                    -- TP v1: WALK (genuine Humanoid:Move) to the drop.
                    if not Runtime.walkActive() then Runtime.walkGo(target, 3) end
                else
                    Runtime.instantTp(target)
                end
            elseif now - (Runtime.LastStealAttempt or 0) > 0.08 then
                Runtime.LastStealAttempt = now
                Runtime.forcePickupInstant(pick)
            end
        elseif now - (Runtime.DecoyStageAt or now) > 8 then
            -- no pet appeared; still try to bait the guard with whatever we have
            Runtime.DecoyStage = "BAIT"; Runtime.DecoyStageAt = now
        end

    elseif stage == "BAIT" then
        if Runtime.inWindow(0.2) then
            Runtime.DecoyHOPAt = nil
            Runtime.DecoyStage = "HOP"; Runtime.DecoyStageAt = now
            return
        end
        -- The guard seizing the carried pet means we were caught (hitguard), even
        -- if the fling event was not observed -> hop now.
        if not isCarrying() and (now - (Runtime.DecoyStageAt or now)) > 0.15 then
            Runtime.DecoyHOPAt = nil
            Runtime.DecoyStage = "HOP"; Runtime.DecoyStageAt = now
            return
        end
        local zg, gd = nil, math.huge
        if isV1() then
            -- TP v1: stand still and let the carried Zone 1 pet draw the guard in.
            -- Never TP to the guard (the user asked for no movement here).
            walkStop()
        else
            if Runtime.nearestGuard then zg, gd = Runtime.nearestGuard(pos, "Zone1") end
            local gp = nil
            if zg then
                local gh = zg:FindFirstChild("HumanoidRootPart", true)
                gp = (gh and gh.Position) or zg:GetPivot().Position
            end
            local zstate = zg and (zg:GetAttribute("ChaseState") or "Idle") or "Idle"
            local chasing = Runtime.BeingChased or zstate == "Chasing" or zstate == "WindUp"
            if gp and chasing then
                walkStop()                        -- being chased: get caught
            elseif gp and (gd or 0) > 60 and not Runtime.DecoyPulled then
                Runtime.DecoyPulled = true
                Runtime.instantTp(gp)             -- aggro the Zone 1 guard once
            else
                walkStop()
            end
        end
        if now - (Runtime.DecoyStageAt or now) > 15 then
            -- never caught: retry by WALKING to the far zone (no TP)
            Runtime.DecoyStage = nil
            Runtime.DecoyDoneZone = targetZone
            Runtime.MetaWalkEntry = true
            Runtime.MetaStage = "TRAVEL"; Runtime.MetaStageAt = now
        end

    elseif stage == "HOP" then
        walkStop()   -- halt the genuine walk engine before the instant hop
        -- Keep the streaming prefetch alive: it retries until the zone's content
        -- actually appears (Fantasy Expansion / Zone13 starts empty until streamed).
        if targetZone and Runtime.requestZoneStream then Runtime.requestZoneStream(targetZone) end
        local egg = nearestEggInZone(pos, targetZone) or firstEggInZone(targetZone)
        -- TP v1 with filter "Semua" (no target zone): hop to the nearest egg anywhere.
        if not egg and isV1() then egg = nearestEgg(pos) end
        local dest = egg and egg.Position
        if not dest and targetZone then dest = Runtime.zoneAnchorPoint(targetZone) end
        -- Never hop into a far zone whose content has NOT streamed: the server pulls
        -- the relocation back and the zone never loads (the Zone13 dead-lock).
        local streamed = (not targetZone) or (egg ~= nil)
            or (Runtime.zoneHasContent and Runtime.zoneHasContent(targetZone))
        if dest and streamed then
            -- inside the hitguard window: instant TP to the far zone
            if Runtime.inWindow(0.2) then
                Runtime.Leap(dest)
            else
                Runtime.instantTp(dest)
            end
            Runtime.DecoyStreamStart = nil
            Runtime.TargetEgg = egg
            Runtime.DecoyStage = nil
            Runtime.DecoyDoneZone = targetZone
            Runtime.DecoyPulled = false
            Runtime.DecoyEgg = nil
            Runtime.DecoyPick = nil
            Runtime.MetaWalkEntry = false
            Runtime.MetaStage = "BREAK"
            Runtime.MetaStageAt = now
        elseif targetZone and now - (Runtime.DecoyStreamStart or now) < 90 then
            -- Not streamed yet: restart the Zone 1 decoy so the NEXT hop has a FRESH
            -- catch window, while streaming keeps retrying in the background.
            Runtime.DecoyStreamStart = Runtime.DecoyStreamStart or now
            Runtime.DecoyStage = "GOTO1"
            Runtime.DecoyStageAt = now
            Runtime.DecoyEgg = nil
            Runtime.DecoyPick = nil
            Runtime.DecoyPulled = false
            Runtime.DecoyHOPAt = nil
        else
            -- No destination / streaming stalled: walk-entry fallback.
            Runtime.DecoyStreamStart = nil
            Runtime.DecoyStage = nil
            Runtime.DecoyDoneZone = targetZone
            Runtime.DecoyPulled = false
            Runtime.DecoyEgg = nil
            Runtime.DecoyPick = nil
            Runtime.MetaWalkEntry = true
            Runtime.MetaStage = "TRAVEL"
            Runtime.MetaStageAt = now
        end
    end
end

--------------------------------------------------------------------------------
-- FRAME-ACCURATE RECOVERY (far-zone meta + auto-steal-player)
-- The guard seizes the pet and drops it back, but the catch window (ragdoll)
-- lasts well under a second, so the pickup + full-TP must run at frame rate,
-- not on the ~7Hz feature loop. Shared by:
--   META: MetaStage RECOVER/CARRY_BAIT, pet name MetaCarried
--   HUNT: HuntStage RECOVER/BAIT, pet name HuntCarried
--------------------------------------------------------------------------------


-- ANTI-KNOCKBACK HARD PIN: while the guard's ragdoll/fling is active, hold the HRP
-- at the position the knockback started so the character stays EXACTLY where it was
-- ("diam di tempat") - zeroing velocity alone still let the fling carry us off.
Runtime.AntiKnockPos = nil
Runtime.AntiKnockUntil = 0
Runtime.antiKnockStep = function()
    local pos = Runtime.AntiKnockPos
    if not pos then return end
    -- yield to an active force-TP (META delivery/recovery hop / HUNT pin): the
    -- hold must never fight a deliberate teleport
    if Runtime.MetaForcePos or Runtime.HuntForcePos then
        Runtime.AntiKnockPos = nil
        pcall(function() RunService:UnbindFromRenderStep("BSAntiKnock") end)
        return
    end
    if os.clock() > (Runtime.AntiKnockUntil or 0) then
        Runtime.AntiKnockPos = nil
        pcall(function() RunService:UnbindFromRenderStep("BSAntiKnock") end)
        return
    end
    local c, hrp = getChar()
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    local rag = c and c:GetAttribute("Ragdolled")
    local phys = hum and hum:GetState() == Enum.HumanoidStateType.Physics
    if not hrp or (not rag and not phys) then
        -- knockback ended: release and hand movement back
        Runtime.AntiKnockPos = nil
        pcall(function() RunService:UnbindFromRenderStep("BSAntiKnock") end)
        return
    end
    pcall(function()
        hrp.CFrame = CFrame.new(pos)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
end
getgenv().__bsHuntSelfCheck = function()
    -- Verify the new HUNT (Auto Steal Player) state-machine wiring. No game action.
    -- Run while NOT mid-META (it resets the HUNT transient state via huntResetCycle).
    assert(Runtime.Phase ~= "META", "do not run this during a META cycle")
    local keep = Runtime.HuntStage
    Runtime.huntResetCycle()
    assert(Runtime.HuntStage == "ACQUIRE", "huntResetCycle must start at ACQUIRE")
    local c = Connections.HuntCharAdded
    assert(c ~= nil and typeof(c) == "RBXScriptConnection", "HuntCharAdded not connected")
    Runtime.HuntStage = keep
    return { ok = true, startStage = "ACQUIRE" }
end

-- Hide the LOCAL body for a short window so the ragdoll "getar" during the banking
-- force-TP is not visible. Client-only (LocalTransparencyModifier) and auto-restores
-- so the body can never stay invisible.
Runtime.hideBody = function(on)
    if on then
        local c = LocalPlayer.Character
        if Runtime.BodyHidden or not c then return end
        Runtime.BodyHidden = true
        Runtime.BodySaved = setmetatable({}, { __mode = "k" })
        for _, d in ipairs(c:GetDescendants()) do
            if d:IsA("BasePart") then
                Runtime.BodySaved[d] = d.LocalTransparencyModifier
                d.LocalTransparencyModifier = 1
            end
        end
        local token = (Runtime.BodyHideToken or 0) + 1
        Runtime.BodyHideToken = token
        task.delay(3.5, function()
            if Runtime.BodyHideToken == token then Runtime.hideBody(false) end
        end)
    else
        if not Runtime.BodyHidden then return end
        Runtime.BodyHidden = false
        if Runtime.BodySaved then
            for p, v in pairs(Runtime.BodySaved) do
                if p.Parent then pcall(function() p.LocalTransparencyModifier = v end) end
            end
        end
        Runtime.BodySaved = nil
    end
end

local function recoverStep()
    if not getgenv()[GAME_CONFIG.GlobalFlag] then return end
    -- Only HUNT uses the frame-rate recovery now. The META pipeline banks by
    -- stepping into the SafeZone (SECURE), so it never needs a guard catch.
    if Runtime.Phase ~= "HUNT" then return end
    local c, hrp = getChar()
    if not hrp or not c then return end
    local pos = hrp.Position

    -- HUNT recovery (steal-from-player). Once the guard-hit quota is met this is the
    -- SAME delivery the META uses (100% reliable): pick the seized pet back up at
    -- frame rate from our feet (the catch-hold keeps us on it), then force-TP it to
    -- the SafeZone inside the SAME catch window - no artificial window flag, because
    -- the server only honours the TP inside the real fling/ragdoll window.
    local st = Runtime.HuntStage
    if st ~= "RECOVER" then return end

    -- Fresh RECOVER: remember whether we entered it still carrying (the catch fires a
    -- frame before the seize) so we never force-TP a pet the guard is about to take.
    if Runtime.HuntRecoverSeen ~= Runtime.HuntStageAt then
        Runtime.HuntRecoverSeen = Runtime.HuntStageAt
        Runtime.HuntRecoverEntryCarried = isCarrying()
        Runtime.HuntRecoverPicked = false
    end

    if isCarrying() then
        -- Below the quota: hand the re-grabbed pet back to the bait so we are carrying
        -- it when the guard hits again.
        if (Runtime.HuntGuardHits or 0) < (Config.HuntGuardHits or 3) then
            Runtime.HuntRecoverPick = nil
            Runtime.HuntStage = "WALK_GUARD"; Runtime.HuntStageAt = os.clock()
            return
        end
        if Runtime.HuntRecoverEntryCarried and not Runtime.HuntRecoverPicked then return end
        -- Quota met -> bank EXACTLY like the META (no MetaLungeAt trick).
        Runtime.HuntRecoverPick = nil
        if forceTpTo(Config.SafeDropPos, 3) then
            Runtime.hideBody(true)
            Runtime.HuntStage = "TP_SAFE"
            Runtime.HuntStageAt = os.clock()
        end
        return
    end
    Runtime.HuntRecoverPicked = true
    -- Not carrying: grab the seized pet back up (mirror the META recovery exactly).
    local pick = Runtime.HuntRecoverPick
    if not pick or not pick.Parent or pick:GetAttribute("Despawning") then
        pick = findRecoverPickup(pos, Runtime.HuntCarried)
        Runtime.HuntRecoverPick = pick
    end
    if pick then
        captureHuntPetInfo(pick, Runtime.HuntCarried)
        local _, promptPos, fireRange = Runtime.pickupFireInfo(pick)
        local target = promptPos or pick:GetPivot().Position
        if (target - pos).Magnitude > (fireRange or 7) then
            -- The pet is NOT at our feet (it dropped at the guard): fall back to a
            -- pinned force-TP onto it inside the hit window, then fire.
            Runtime.CatchHoldPos = nil
            if forceTpTo(target, 2) then
                if (os.clock() - (Runtime.LastStealAttempt or 0)) > 0.03 then
                    Runtime.LastStealAttempt = os.clock()
                    Runtime.forcePickupInstant(pick)
                end
            elseif (os.clock() - (Runtime.LastStealAttempt or 0)) > 0.03 then
                Runtime.LastStealAttempt = os.clock()
                Runtime.forcePickupInstant(pick)
            end
        else
            -- Pet at our feet (the catch-hold kept us on it): fire THIS frame.
            if (os.clock() - (Runtime.LastStealAttempt or 0)) > 0.03 then
                Runtime.LastStealAttempt = os.clock()
                Runtime.forcePickupInstant(pick)
            end
        end
    end
end
Runtime.recoverStep = recoverStep

local function doSteal(info)
    Runtime.StealInFlight = true
    task.spawn(function()
        tpTo(info.Pos, 1)
        local timeout = os.clock() + 6
        while travelActive() and not arrivedNear(info.Pos, 6) and os.clock() < timeout do
            if not getgenv()[GAME_CONFIG.GlobalFlag] then break end
            task.wait(0.05)
        end
        if not getgenv()[GAME_CONFIG.GlobalFlag] then Runtime.StealInFlight = false return end
        if not arrivedNear(info.Pos, 7) then Runtime.StealInFlight = false return end
        -- force pickup: step onto the prompt and hammer it until Carrying is set
        -- (a single fire missed when the pet was a few studs away or not ready).
        local deadline = os.clock() + 2
        repeat
            if not getgenv()[GAME_CONFIG.GlobalFlag] then break end
            local _, hrp = getChar()
            if hrp then
                pcall(function() hrp.CFrame = CFrame.new(info.Pos + Vector3.new(0, 3, 0)) end)
                pcall(function()
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                end)
            end
            pcall(function() fireproximityprompt(info.Prompt) end)
            if isCarrying() then break end
            task.wait(0.05)
        until os.clock() > deadline
        if isCarrying() then Runtime.Stolen = Runtime.Stolen + 1 end
        Runtime.StealInFlight = false
    end)
end

local function ourTreadmill()
    local plot = myPlot()
    if not plot then return nil end
    for _, m in ipairs(plot:GetChildren()) do
        if m:IsA("Model") and m.Name ~= "TreadmillBoard" and m:GetAttribute("TreadmillLevel") then
            return m
        end
    end
    return nil
end

local function treadmillSpot()
    local m = ourTreadmill()
    if not m then return nil end
    local hit = m:FindFirstChild("Hitbox") or m.PrimaryPart
    if hit and hit:IsA("BasePart") then return hit.Position end
    return m:GetPivot().Position
end

local function onTreadmillNow()
    if Runtime.OnTreadmill then return true end
    local c, _, hum = getChar()
    if hum and hum.AutoRotate == false and c and not c:GetAttribute("Ragdolled") then
        return true
    end
    return false
end

local function unbindTreadmillLock()
    pcall(function() RunService:UnbindFromRenderStep("TreadmillFaceLock") end)
    local _, _, hum = getChar()
    if hum then pcall(function() hum.AutoRotate = true end) end
end

local function pressExitTreadmill()
    unbindTreadmillLock()
    local _, _, hum = getChar()
    if hum then
        pcall(function() hum.Jump = true end)
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
    end
    pcall(function()
        local VIM = game:GetService("VirtualInputManager")
        VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
    end)
end

local function leaveTreadmill()
    pressExitTreadmill()
    Runtime.TreadmillEndAt = os.clock()
end

-- ============================================================================
-- TUTORIAL (BigFroot parity)
-- While the game tutorial is active, do its steps FIRST: equip pickaxe, break a
-- Zone 1 egg, steal the animal, escape/bank, go to the pen, place, upgrade, ...
-- The normal farm/TP loop is suppressed until the tutorial finishes.
-- ============================================================================
Runtime.tutorialActive = function()
    return Config.AutoTutorial ~= false
        and LocalPlayer:GetAttribute("TutorialActive") == true
end

Runtime.tutorialStep = function(now)
    local stage = tostring(LocalPlayer:GetAttribute("TutorialStage") or "")
    local _, hrp = getChar()
    if not hrp then return end
    local pos = hrp.Position
    -- default: auto swing off outside the break step
    if Runtime.autoSwing then Runtime.autoSwing(false) end

    if stage == "EquipPickaxe" or stage == "EquipNewPickaxe" then
        equipPickaxe()
    elseif stage == "BreakEgg" or stage == "BreakStrongerEgg" then
        -- BigFroot: break a ZONE 1 egg for the tutorial first (never the target).
        local egg = nearestEggInZone(pos, "Zone1") or firstEggInZone("Zone1")
        if egg then
            Runtime.TargetEgg = egg
            if Runtime.eggSurfaceDist(egg, pos) > 4 then
                Runtime.moverReach(egg, "Zone1")
            else
                walkStop()
                if Runtime.autoSwing then Runtime.autoSwing(true) end
                breakEggStep(egg, now)
            end
        end
    elseif stage == "StealAnimal" or stage == "CollectStrongerAnimal" then
        if LocalPlayer:GetAttribute("TutorialAwaitReveal") then return end
        local pick = bestMinIncomePickup(pos, 250)
        if not pick then
            local best, bd = nil, 250
            for _, p in ipairs(livePickups()) do
                local m = (p:GetPivot().Position - pos).Magnitude
                if m < bd then bd = m; best = p end
            end
            pick = best
        end
        if pick then
            local _, promptPos, fireRange = Runtime.pickupFireInfo(pick)
            local target = promptPos or pick:GetPivot().Position
            if (target - pos).Magnitude > (fireRange or 7) then
                Runtime.instantTp(target)
            elseif now - (Runtime.LastStealAttempt or 0) > 0.08 then
                Runtime.LastStealAttempt = now
                Runtime.forcePickupInstant(pick)
            end
        end
    elseif stage == "Escape" or stage == "EscapeStronger" then
        if isCarrying() then
            Runtime.instantTp(Runtime.safePosInside(pos))
        end
    elseif stage == "GoToPen" or stage == "GoToPenStronger" then
        local home = Runtime.plotHome and Runtime.plotHome()
        if home then Runtime.instantTp(home) end
    elseif stage == "PlaceAnimal" or stage == "PlaceAnimalStronger" then
        equipBestPet()
    elseif stage == "UpgradePen" then
        if UnlockTreadmillRequest then pcall(function() UnlockTreadmillRequest:FireServer() end) end
    elseif stage == "UseTreadmill" then
        local spot = treadmillSpot()
        if spot then Runtime.instantTp(spot) end
    elseif stage == "BuyPickaxe" then
        if PickaxeShopRequest then pcall(function() PickaxeShopRequest:FireServer("Buy", 2) end) end
    elseif stage == "BuyTrail" then
        tryUpgradeTrail()
    end
end

local statusPar = nil
local lastThreatDist, lastThreatState = math.huge, "Idle"

----------------------------------------------------------------
-- MAIN LOOP (Heartbeat)
----------------------------------------------------------------
Connections.FeatureLoop = RunService.Heartbeat:Connect(function()
    if not getgenv()[GAME_CONFIG.GlobalFlag] then return end
    if Runtime.ConfigLoading then return end

    -- Walk mode drives NoClip: ON while Auto Break is ON, OFF when it is OFF
    if Runtime.syncWalkNoClip then Runtime.syncWalkNoClip() end

    local c, hrp, hum = getChar()
    if not hrp or not hum or hum.Health <= 0 then
        -- keep the drop-only HUNT cycle alive across a death: the fresh character
        -- resumes the pickup/bank stage machine (no self-respawn any more).
        local keepHunt = Runtime.Phase == "HUNT"
        -- keep the META (TP) cycle alive across a death/respawn: the stage machine
        -- resumes from TRAVEL on the fresh character (no self-kill any more).
        local keepMeta = Runtime.Phase == "META"
        -- keep a WALK cycle alive across a death/respawn: the stage machine resumes
        -- (GOTO_START walks the fresh character back into the SafeZone).
        local keepWalk = Runtime.Phase == "WALK"
        if keepHunt or keepMeta or keepWalk then return end
        Runtime.Phase = "IDLE"
        Runtime.StealInFlight = false
        moveStop()
        pcall(function() Runtime.walkStop() end)
        return
    end

    -- anti-cheat strike pause: stop fighting the server, drop back to IDLE
    if Runtime.StrikePauseUntil and os.clock() < Runtime.StrikePauseUntil then
        moveStop()
        pcall(function() Runtime.walkStop() end)
        Runtime.Phase = "IDLE"
        Runtime.StealInFlight = false
        return
    end

    if Config.AntiKnockback and RagdollPhysics then
        local root = hrp
        local ragdolled = c:GetAttribute("Ragdolled")
        local phys = hum:GetState() == Enum.HumanoidStateType.Physics
        -- React ONLY to a REAL knockback (ragdoll / physics). The old `vel > 60` check
        -- also fired during our OWN fast auto-move: it zeroed the move velocity AND ran
        -- 5 physics helper calls EVERY frame, which made the character crawl ("lambat")
        -- and tanked the FPS during any retry/reposition.
        -- Also YIELD to an active force-TP pin, or the hold fights a deliberate
        -- relocation hop and leaves the character stuck in the wrong zone.
        if (ragdolled or phys) and not Runtime.BankStage
            and not Runtime.MetaForcePos and not Runtime.HuntForcePos then
            -- throttle the (heavy) helper calls to ~20Hz
            local nowAK = os.clock()
            if nowAK - (Runtime.LastAntiKnock or 0) >= 0.05 then
                Runtime.LastAntiKnock = nowAK
                pcall(function() RagdollPhysics.SnapUpright(c) end)
                pcall(function() RagdollPhysics.SetCharacterVelocity(c, Vector3.zero, Vector3.zero) end)
                pcall(function() RagdollPhysics.StopCharacterDescent(c) end)
                pcall(function() RagdollPhysics.SetCharacterNetworkOwner(c, LocalPlayer) end)
                pcall(function()
                    hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
                    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                    hum.PlatformStand = false
                end)
            end
            -- hard position pin while actually knocked: hold the HRP at the spot the
            -- knockback started so the fling cannot carry us off ("diam di tempat")
            if not Runtime.AntiKnockPos then
                Runtime.AntiKnockPos = root.Position
                Runtime.AntiKnockUntil = os.clock() + 2.5
            end
            pcall(function()
                RunService:BindToRenderStep("BSAntiKnock", Enum.RenderPriority.Character.Value + 4, Runtime.antiKnockStep)
            end)
        end
    end

    -- Drop-only Auto Steal has no chase/bat combat; the stage machine below just
    -- picks up matching drops and banks them.

    local tick = os.clock()
    if tick - Runtime.LastTick < 0.15 then return end
    Runtime.LastTick = tick

    local pos = hrp.Position
    local carrying = isCarrying()
    local now = os.clock()

    -- ===== BigFroot parity: the tutorial runs FIRST (break a Zone 1 egg, steal,
    -- bank, pen, treadmill, ...). While it is active the farm/TP loop is paused,
    -- so TP v1/v2 never rushes to the target zone before the Zone 1 egg is broken.
    if Runtime.tutorialActive and Runtime.tutorialActive() then
        local firstTut = not Runtime.TutorialWasActive
        Runtime.TutorialWasActive = true
        Runtime.Phase = "IDLE"
        Runtime.MetaStage = nil
        Runtime.BankStage = nil
        Runtime.BankPick = nil
        if firstTut then
            -- stop any leftover farm travel once on tutorial entry
            pcall(function() Runtime.walkStop() end)
            moveStop()
        end
        pcall(Runtime.tutorialStep, now)
        return
    end
    -- Tutorial just finished: clear the tutorial target so META picks a fresh egg
    -- in the real target zone instead of the Zone 1 tutorial egg.
    if Runtime.TutorialWasActive then
        Runtime.TutorialWasActive = false
        Runtime.TargetEgg = nil
        Runtime.MetaStage = nil
        Runtime.Phase = "IDLE"
        pcall(function() Runtime.autoSwing(false) end)
    end

    -- AutoCompleteIndex: resolve the index zone BEFORE any phase/zone decision.
    if Runtime.updateAutoCompleteIndex then
        Runtime.updateAutoCompleteIndex(now)
    end
    -- Live titanic presence: other features yield to the titanic META.
    Runtime.TitanicAlive = Config.AutoSteal == true and findTitanicEgg(pos) ~= nil
    if indexWaitingNow() and not carrying and (Runtime.Phase == "BREAK" or Runtime.Phase == "META") then
        Runtime.Phase = "IDLE"
        Runtime.MetaStage = nil
        Runtime.StealInFlight = false
        moveStop()
    end

    -- TRAVEL ARRIVAL (safe-travel engine drives movement via RenderStep)
    if Runtime.TravelDest and (hrp.Position - Runtime.TravelDest).Magnitude <= (Runtime.TravelArrive or MOVE.ArriveDist) then
        moveStop()
    end


    local active = Config.AutoSteal or Config.AutoStealPlayer
    if not active then
        Runtime.Phase = "IDLE"
    end
    -- TreadmillMode only matters while idling toward / standing on the treadmill;
    -- drop it if another phase took over so it cannot exempt stray moves forever.
    if Runtime.TreadmillMode and Runtime.Phase ~= "IDLE" and Runtime.Phase ~= "TMEXIT" and not Runtime.OnTreadmill then
        Runtime.TreadmillMode = false
    end
    -- leaving the WALK phase: stop the real-walk mover.
    -- TP v1 (Phase META) also drives the genuine Walk engine, so it must be allowed
    -- to keep walking there instead of being stopped every tick.
    local walkEngineOwner = (Runtime.Phase == "WALK")
        or (Config.MovementMode == "TP v1" and Runtime.Phase == "META")
    if not walkEngineOwner and Runtime.WalkDest then
        Runtime.walkStop()
    end
    if Runtime.Phase ~= "META" and Runtime.Phase ~= "HUNT" and Runtime.Phase ~= "WALK" and not Runtime.TreadmillMode and not Runtime.PlantMode and walkActive() then walkStop() end

    if Runtime.Phase == "BREAK" and not Config.AutoSteal then
        Runtime.Phase = "IDLE"
    end

    if Runtime.OnTreadmill and not Config.AutoTreadmill then
        leaveTreadmill()
        Runtime.TreadmillMode = false
    end

    -- META: carried-state stage transitions. The pickup can succeed a tick BEFORE
    -- the Carrying attribute replicates locally, so PICKUP may see its pick already
    -- despawned and switch to BREAK; the next tick Carrying is true while the stage
    -- is BREAK -> it would keep breaking eggs WITH a pet in hand. This catches it
    -- from any pre-delivery stage and hands straight to SECURE (bank it).
    if Runtime.Phase == "META" then
        if carrying and (Runtime.MetaStage == "PICKUP"
                or Runtime.MetaStage == "BREAK"
                or Runtime.MetaStage == "TRAVEL") then
            Runtime.MetaStage = "SECURE"
            Runtime.MetaStageAt = now
            Runtime.MetaPick = nil
            Runtime.TargetEgg = nil
            Runtime.BurstEgg = nil
            dbg("META", ("carry->SECURE carried=%s bp=%d"):format(
                tostring(LocalPlayer:GetAttribute("Carrying")), backpackPetCount()))
            walkStop()
        end
    end

    if not carrying and not Runtime.StealInFlight then
        local phaseNow = Runtime.Phase
        -- Movement engine selector. Walk is a fully separate engine, so the TP
        -- Auto Break / META / HUNT paths below are never mixed with it.
        local walkMode = Config.AutoSteal and Config.MovementMode == "Walk"
        -- Titanic egg has absolute priority over everything except HUNT: while one
        -- is alive, Auto Steal runs the META pipeline (targeting the titanic egg's
        -- zone, wherever it is).
        local titanicEgg = Config.AutoSteal and (Runtime.TitanicCoolUntil or 0) <= now and findTitanicEgg(pos)
        -- TP v1/v2 always use the BigFroot META loop (instant TP across all zones,
        -- incl. "Semua"). Non-TP modes keep the old far-zone-only gate.
        local metaActive = Config.AutoSteal and Config.FarZoneMeta
            and (isTPMode() or isFarZoneFilter() or titanicEgg ~= nil)
        local wantPhase, wantHunt, wantHuntKind = nil, nil, nil
        -- AUTO STEAL (drop-only): a dropped AnimalPickup whose income, rarity and
        -- mutation pass the filters. Never chases a player. Never in Walk mode.
        if not walkMode and Config.AutoStealPlayer and now >= (Runtime.HuntCoolUntil or 0)
            and (phaseNow == "IDLE" or phaseNow == "BREAK" or phaseNow == "PICKUP") then
            local k, subj = findHuntTarget(pos)
            if k and subj then
                wantPhase = "HUNT"
                wantHunt = subj
                wantHuntKind = k
                Runtime.HuntKind = k
                Runtime.HuntTarget = nil
                Runtime.HuntDropTarget = subj
            end
        end
        if not wantPhase then
            if walkMode then
                -- Walk engine owns Auto Break entirely (all zones incl. titanic /
                -- complete index). Starts when idle and re-arms after each delivery.
                if phaseNow == "IDLE" or phaseNow == "BREAK" or phaseNow == "PICKUP" then
                    wantPhase = "WALK"
                end
            elseif indexWaitingNow() then
                wantPhase = nil
            elseif metaActive then
                -- far-zone guard-bait meta owns Auto Steal (when no HUNT target).
                if phaseNow == "IDLE" or phaseNow == "BREAK" or phaseNow == "PICKUP" then
                    if (Runtime.MetaCoolUntil or 0) <= now then
                        wantPhase = "META"
                    end
                end
            elseif phaseNow == "IDLE" and Config.AutoSteal then
                wantPhase = "BREAK"
            end
        end
        if wantPhase then
            if Runtime.TreadmillMode and onTreadmillNow() then
                Runtime.PendingPhase = wantPhase
                Runtime.PendingHunt = wantHunt
                Runtime.PendingHuntKind = wantHuntKind
                Runtime.LeaveStarted = now
                Runtime.Phase = "TMEXIT"
                leaveTreadmill()
            else
                if wantPhase == "HUNT" then
                    if phaseNow ~= "HUNT" then
                        -- New HUNT opening (drop-only): latch the dropped pet and go
                        -- ACQUIRE -> PICKUP. huntResetCycle clears everything
                        -- (including the target picked above), so re-apply it after.
                        local k, subj = wantHuntKind, wantHunt
                        Runtime.huntResetCycle()
                        Runtime.HuntKind = k
                        Runtime.HuntTarget = (k == "PLAYER") and subj or nil
                        Runtime.HuntDropTarget = (k == "DROP") and subj or nil
                    end
                end
                if wantPhase == "META" and phaseNow ~= "META" then
                    Runtime.MetaLeg = "TARGET"
                    Runtime.MetaStage = "TRAVEL"
                    Runtime.MetaStageAt = now
                    Runtime.MetaZoneWaitAt = nil
                    Runtime.MetaZoneNotified = false
                    Runtime.MetaAnchorTpAt = 0
                    Runtime.DecoyHOPAt = nil
                    -- Target zone: the titanic egg's zone if one is alive, else the filter.
                    local metaZoneId = (titanicEgg and titanicZoneId(titanicEgg))
                        or activeZoneId()
                    Runtime.MetaZone = Config.EggFilter
                    Runtime.MetaZoneId = metaZoneId
                    Runtime.TargetEgg = nil
                    Runtime.BurstEgg = nil
                    Runtime.MetaLoop = (Runtime.MetaLoop or 0) + 1
                    -- fresh cycle: clear any stale bank sub-machine state
                    Runtime.BankStage = nil
                    Runtime.BankPick = nil
                    Runtime.BankWant = nil
                    Runtime.BankLeapt = false
                    Runtime.BankHelpDrop = false
                    -- clear any stale decoy stage (TP v1 re-arms it from TRAVEL)
                    Runtime.DecoyStage = nil
                end
                if wantPhase == "WALK" and phaseNow ~= "WALK" then
                    -- Fresh walk cycle: park at WalkStartPos, then walk to the zone.
                    Runtime.WalkStage = "GOTO_START"
                    Runtime.WalkStageAt = now
                    Runtime.WalkEgg = nil
                    Runtime.WalkPick = nil
                    Runtime.WalkHadPet = false
                    Runtime.WalkCarried = nil
                    Runtime.WalkRecoverPick = nil
                    Runtime.LastStealAttempt = 0
                    Runtime.WalkZoneWaitAt = nil
                    Runtime.WalkZoneNotified = false
                    Runtime.walkStop()
                end
                Runtime.Phase = wantPhase
            end
        end
    end

    local dist, state, wind = threatScan(pos)
    lastThreatDist, lastThreatState = dist, state
    Runtime.LastThreatDist, Runtime.LastThreatState = dist, state


    -- Auto Treadmill: walk (never a big TP) onto our OWN treadmill and stand in
    -- its detection Hitbox so the server starts the session. The move is
    -- re-issued while approaching and is NOT cancelled by the idle walk-stop above.
    -- Never while in Hell (InHell attribute): gliding to a world treadmill that is
    -- not present in the Hell map is pointless/harmful.
    if Runtime.Phase == "IDLE" and Config.AutoTreadmill and not Runtime.OnTreadmill
        and LocalPlayer:GetAttribute("InHell") ~= true
        and os.clock() - Runtime.TreadmillEndAt > 0.5 and now - Runtime.DragonTread > 6 then
        Runtime.DragonTread = now
        Runtime.TreadmillMode = true
        Runtime.TreadStartAt = now
    end
    if Runtime.TreadmillMode and Runtime.Phase == "IDLE" and not Runtime.OnTreadmill then
        local spot = treadmillSpot()
        local _, hrp = getChar()
        if spot and hrp then
            local flat = Vector3.new(spot.X - hrp.Position.X, 0, spot.Z - hrp.Position.Z)
            if flat.Magnitude > 5 then
                -- still approaching: re-issue the move (server-accepted step)
                if now - (Runtime.TreadMoveAt or 0) > 0.25 then
                    Runtime.TreadMoveAt = now
                    tpTo(spot, 2, moveSpeed())
                end
            else
                -- arrived: stop, then nudge the last few studs into the Hitbox so
                -- the server registers us inside the detection volume
                moveStop()
                if now - (Runtime.TreadNudgeAt or 0) > 0.3 then
                    Runtime.TreadNudgeAt = now
                    pcall(function() hrp.CFrame = CFrame.new(spot.X, hrp.Position.Y, spot.Z) end)
                    pcall(function()
                        hrp.AssemblyLinearVelocity = Vector3.zero
                        hrp.AssemblyAngularVelocity = Vector3.zero
                    end)
                end
            end
        end
        if now - (Runtime.TreadStartAt or now) > 25 then
            Runtime.TreadmillMode = false
            Runtime.TreadmillEndAt = now
            moveStop()
        end
    end

    -- AUTO SWING SYNC (every tick): Auto Break no longer fires EggHitRequest by hand -
    -- it drives the game's own AutoSwingController. We only switch it ON while we are
    -- actually at the chosen egg (<=6 studs, the game's own pick range) and OFF the
    -- moment we leave that spot (walking, carrying, idle, hunt). This keeps the Egg
    -- Type / titanic / priority targeting: we walk to OUR egg first, then let the game
    -- swing. If the module is missing we stop and warn once, like BigFroot.
    do
        local swEgg = (Runtime.Phase == "BREAK" and Runtime.TargetEgg)
            or (Runtime.Phase == "META" and Runtime.MetaStage == "BREAK" and Runtime.TargetEgg)
            or (Runtime.Phase == "META" and Runtime.DecoyStage == "BREAK" and Runtime.DecoyEgg)
            or (Runtime.Phase == "WALK" and Runtime.WalkStage == "BREAK" and Runtime.WalkEgg)
            or nil
        local swNear = swEgg and swEgg.Parent ~= nil and not carrying
            and Runtime.eggSurfaceDist(swEgg, pos) <= 6
        local swOk = Runtime.autoSwing(swNear == true)
        Runtime.AutoSwingActive = (swOk and swNear) == true
        if swNear and not swOk and not Runtime.AutoSwingWarned then
            Runtime.AutoSwingWarned = true
            pcall(function()
                WindUI:Notify({ Title = "Auto Swing", Content = "the game's Auto Swing is missing", Duration = 4 })
            end)
        end
    end

    if Config.AutoUpgradePickaxe and now - Runtime.LastBuy > 8 then
        Runtime.LastBuy = now
        tryUpgradePickaxe()
    end

    if (Config.AutoUpgradeTreadmill or Config.AutoUnlockTreadmill) and now - Runtime.LastTreadUp > 8 then
        Runtime.LastTreadUp = now
        tryUpgradeTreadmill()
    end

    if Config.AutoUpgradePlot and now - Runtime.LastPlotUp > 8 then
        Runtime.LastPlotUp = now
        tryUpgradePlot()
    end

    if Config.AutoUpgradeTrail and now - (Runtime.LastTrailUp or 0) > 8 then
        Runtime.LastTrailUp = now
        tryUpgradeTrail()
    end

    if Config.AutoClaimIndex and now - (Runtime.LastIndexClaim or 0) > 2 then
        Runtime.LastIndexClaim = now
        pcall(autoClaimIndex)
    end

    if Config.AutoPlaceBest and now - Runtime.LastEquipBest > 3 then
        Runtime.LastEquipBest = now
        task.spawn(equipBestPet)
    end

    -- AutoMerge: remote-only. The server accepts "Merge" from anywhere (the game's
    -- own MergeMachineController fires it from the UI button with NO distance check),
    -- so we must NOT walk to the machine: the old tpTo(eggMachineSpot()) hijacked
    -- Runtime.TravelDest from Auto Steal / hunt / meta / treadmill / banking.
    -- Evaluated BEFORE AutoSell so pets queued for a merge are not sold in the same
    -- tick, and gated on not-carrying (during a delivery the travel engine owns the
    -- character). Never moves the character, so it cannot interfere with any phase.
    if Config.AutoMerge and not carrying and now - Runtime.LastMerge > 2.5 then
        Runtime.LastMerge = now
        task.spawn(doMerge)
    end

    -- AutoFuse: also remote-only (fires FuseMachineRequest from anywhere). No walk.
    if Config.AutoFuse and not carrying and Runtime.tryAutoFuse then
        Runtime.tryAutoFuse(now)
    end

    if Config.AutoSell and now - Runtime.LastSell > Config.SellInterval then
        Runtime.LastSell = now
        task.spawn(sellPets)
    end

    if Config.AutoHatch and now - Runtime.LastHatch > 2.5 then
        Runtime.LastHatch = now
        task.spawn(doHatchReady)
    end

    -- Auto Plant Egg: never while in Hell (Phase is forced to IDLE there, which
    -- would otherwise move us to the overworld plot from inside the Hell map).
    if Config.AutoPlantEgg and Runtime.Phase == "IDLE" and not carrying and not Runtime.TreadmillMode
        and LocalPlayer:GetAttribute("InHell") ~= true then
        Runtime.plantStep(now)
    else
        Runtime.PlantMode = false
    end

    if Runtime.Phase == "TMEXIT" then
        if (not onTreadmillNow()) or (now - Runtime.LeaveStarted > 2.5) then
            Runtime.OnTreadmill = false
            Runtime.TreadmillMode = false
            local p = Runtime.PendingPhase or "IDLE"
            local ph = Runtime.PendingHunt
            local pk = Runtime.PendingHuntKind
            Runtime.PendingPhase = nil
            Runtime.PendingHunt = nil
            Runtime.PendingHuntKind = nil
            if p == "HUNT" and ph then
                -- Full drop-only HUNT re-init (mirror the direct entry): reset every
                -- transient field, then re-latch the queued drop target.
                Runtime.huntResetCycle()
                Runtime.HuntKind = pk
                Runtime.HuntTarget = (pk == "PLAYER") and ph or nil
                Runtime.HuntDropTarget = (pk == "DROP") and ph or nil
            elseif p == "HUNT" then
                -- Target vanished while leaving the treadmill: do not enter HUNT.
                p = "IDLE"
            end
            Runtime.Phase = p
        elseif now - Runtime.LastExitPress > 0.6 then
            Runtime.LastExitPress = now
            leaveTreadmill()
        end
    elseif Runtime.Phase == "SECURE" then
        -- Run the pet to the SafeZone with the step move. Entering the zone
        -- carrying makes the SERVER bank it automatically (BankEffectsController
        -- plays the bank cue); no drop is needed, and this is fully legal (no
        -- instant teleport -> no anti-cheat strike/ban).
        if carrying then
            if Config.HelpOtherPlayer then
                -- Help Other Player: carry the pet to the help spot and DROP it there
                -- (for another player) instead of banking it in the SafeZone.
                local dest = Config.HelpDropPos
                local flat = Vector3.new(dest.X - pos.X, 0, dest.Z - pos.Z)
                if flat.Magnitude > 8 then
                    if now - (Runtime.SecureTpAt or 0) > 0.25 then
                        Runtime.SecureTpAt = now
                        tpTo(dest, 3, moveSpeed())
                    end
                else
                    moveStop()
                    dropCarried()
                end
            elseif not inSafeZone(pos) then
                local sz = safeZoneSpot()
                if sz then
                    if now - (Runtime.SecureTpAt or 0) > 0.25 then
                        Runtime.SecureTpAt = now
                        tpTo(sz, 3, moveSpeed())
                    end
                else
                    local spot = plotSpot()
                    if spot and now - (Runtime.SecureTpAt or 0) > 0.35 then
                        Runtime.SecureTpAt = now
                        tpTo(spot, 3)
                    end
                end
            end
        else
            if inSafeZone(pos) then
                Runtime.Secured = Runtime.Secured + 1
                sendAutoBreakWebhook()
            end
            -- Help Other Player: wait 3s before the next cycle (avoid an immediate
            -- respawn/kill by the far-zone relocate).
            if Config.HelpOtherPlayer then Runtime.MetaCoolUntil = now + 3.0 end
            Runtime.Phase = "IDLE"
            Runtime.TargetEgg = nil
        end
    elseif Runtime.Phase == "PICKUP" then
        if carrying then
            Runtime.Phase = "SECURE"
        elseif now - Runtime.PhaseTimer > 25 then
            Runtime.Phase = "IDLE"
            Runtime.TargetEgg = nil
        elseif not Runtime.StealInFlight then
            local center = Runtime.BreakPos or pos
            local pick = nearestPickupNear(center, 80)
            if pick then
                captureAutoBreakPetInfo(pick, pick:GetAttribute("AnimalName"))
                local info = stealPromptFor(pick)
                if info then
                    Runtime.PhaseTimer = now
                    doSteal(info)
                end
            else
                -- No WANTED pet on the ground. The hatched pet is either an unwanted
                -- one (skip it and keep breaking) or has not appeared yet. Go back to
                -- BREAK as soon as an (unwanted) pet is on the ground, or after a
                -- short grace, instead of standing here for the full 25s.
                if anyPickupNear(center, 80) or (now - Runtime.PhaseTimer > 2.5) then
                    Runtime.Phase = "BREAK"
                    Runtime.TargetEgg = nil
                end
            end
        end
    elseif Runtime.Phase == "HUNT" then
        local stage = Runtime.HuntStage or "ACQUIRE"

        if stage == "ACQUIRE" then
            -- Drop-only: latch the dropped AnimalPickup we are going to collect.
            local subj = Runtime.HuntDropTarget
            local cname = subj and subj:GetAttribute("AnimalName") or nil
            if subj then captureHuntPetInfo(subj, cname) end
            if not (subj and subj.Parent and not subj:GetAttribute("Despawning")) then
                Runtime.HuntStage = "RESET"; Runtime.HuntStageAt = now
            else
                local tpos = subj:GetPivot().Position
                Runtime.HuntCarried = cname
                Runtime.HuntPos = tpos
                Runtime.HuntSpawnPos = tpos
                -- Prefer the drop's own replicated zone; fall back to the position.
                Runtime.HuntPetZone = subj:GetAttribute("ZoneId") or zoneOfPosition(tpos)
                Runtime.HuntRecoverPick = nil
                Runtime.HuntRecoverSeen = nil
                Runtime.HuntRecoverEntryCarried = false
                Runtime.HuntRecoverPicked = false
                Runtime.LastStealAttempt = 0
                Runtime.HuntGuardHits = 0
                Runtime.GuardHitAt = 0; Runtime.GuardHitState = nil
                -- Relocate by self-respawn + pin onto the drop (no walking across
                -- the map, no player locking).
                Runtime.HuntRespawned = false
                Runtime.HuntRespawnPending = false
                Runtime.HuntRespawnAt = 0
                Runtime.HuntRelocPos = tpos
                Runtime.HuntRelocAt = 0
                Runtime.HuntRelocTries = 0
                Runtime.HuntRelocDone = false
                Runtime.HuntRelocStart = 0
                Runtime.HuntRelocDest = nil
                Runtime.HuntStage = "RESPAWN"; Runtime.HuntStageAt = now
                dbg("HUNT", ("ACQUIRE drop pet=%s zone=%s"):format(
                    tostring(cname), tostring(Runtime.HuntPetZone)))
            end
        elseif stage == "RESPAWN" then
            -- Drop-only relocation: self-kill ONCE, then pin onto the dropped pet
            -- and VERIFY the move (re-pin if the server pulls us back). No player
            -- locking - the destination is always the ground drop.
            local _, hrp0, hum0 = getChar()
            if not Runtime.HuntRespawned then
                if hum0 and hum0.Health > 0 then
                    Runtime.HuntRespawned = true
                    Runtime.HuntRespawnAt = now
                    Runtime.HuntRespawnPending = true
                    Runtime.HuntRelocPos = Runtime.HuntSpawnPos or Runtime.HuntPos
                    Runtime.HuntRelocAt = 0
                    Runtime.HuntRelocTries = 0
                    Runtime.HuntRelocDone = false
                    Runtime.HuntRelocStart = now
                    pcall(function()
                        moveStop()
                        Runtime.huntReleasePins()
                        hum0.Health = 0
                    end)
                elseif now - Runtime.HuntStageAt > 8 then
                    Runtime.HuntStage = "RESET"; Runtime.HuntStageAt = now
                end
                return
            end
            if not hrp0 then
                if now - (Runtime.HuntRelocStart or now) > 8 then
                    Runtime.HuntStage = "RESET"; Runtime.HuntStageAt = now
                end
                return
            end
            if Runtime.HuntRelocStart == 0 then Runtime.HuntRelocStart = now end
            -- keep the destination fresh (the drop may still be on the ground)
            local spawn = Runtime.HuntRelocPos
            local drop = Runtime.HuntDropTarget
            if drop and drop.Parent and not drop:GetAttribute("Despawning") then
                spawn = drop:GetPivot().Position
                Runtime.HuntRelocPos = spawn
            end
            spawn = spawn or Runtime.HuntSpawnPos or Runtime.HuntPos
            if not spawn then
                Runtime.HuntStage = "RESET"; Runtime.HuntStageAt = now
                return
            end
            if Runtime.HuntRelocAt == 0 then
                Runtime.HuntRespawnPending = false
                Runtime.huntForceTp(spawn, 4, 1.5)
                Runtime.HuntRelocDest = spawn
                Runtime.HuntRelocAt = now
                Runtime.HuntRelocTries = (Runtime.HuntRelocTries or 0) + 1
            end
            -- The pin put us ON the drop: grab it at once (no distance gate).
            if not isCarrying() then
                local pick = Runtime.HuntDropTarget
                if pick and pick.Parent and not pick:GetAttribute("Despawning") then
                    if now - (Runtime.LastStealAttempt or 0) > 0.05 then
                        Runtime.LastStealAttempt = now
                        if Runtime.forcePickupInstant(pick) then
                            Runtime.huntReleasePins()
                            Runtime.HuntRelocDone = true
                            Runtime.HuntStage = "PICKUP"
                            Runtime.HuntStageAt = now
                            return
                        end
                    end
                end
            end
            -- Verify the pin actually held (a server pull-back moves us away).
            local dest0 = Runtime.HuntRelocDest or spawn
            local settled = (now - (Runtime.HuntRelocAt or 0)) >= MOVE.RelocSettle
            if settled and (hrp0.Position - dest0).Magnitude <= MOVE.RelocArrive then
                Runtime.HuntRelocDone = true
                Runtime.HuntStage = "PICKUP"
                Runtime.HuntStageAt = now
            elseif now - (Runtime.HuntRelocAt or 0) >= MOVE.RelocRetry then
                if (Runtime.HuntRelocTries or 0) >= MOVE.RelocMax then
                    Runtime.HuntStage = "RESET"; Runtime.HuntStageAt = now
                else
                    Runtime.huntForceTp(spawn, 4, 1.5)
                    Runtime.HuntRelocDest = spawn
                    Runtime.HuntRelocAt = now
                    Runtime.HuntRelocTries = (Runtime.HuntRelocTries or 0) + 1
                end
            end
            if now - (Runtime.HuntRelocStart or now) > (MOVE.RelocRetry * (MOVE.RelocMax + 1) + 6) then
                Runtime.HuntStage = "RESET"; Runtime.HuntStageAt = now
            end
        elseif stage == "PICKUP" then
            if isCarrying() then
                -- recompute the zone from where the pet actually is now (the carrier
                -- may have moved since ACQUIRE), so we walk to THIS zone's own guard.
                Runtime.HuntPetZone = zoneOfPosition(pos) or Runtime.HuntPetZone
                Runtime.LastSource = "Auto Steal Player"
                Runtime.HuntStage = "WALK_GUARD"; Runtime.HuntStageAt = now
                Runtime.WalkGuardAt = 0
                Runtime.HuntGuardHits = 0
                Runtime.GuardHitAt = 0; Runtime.GuardHitState = nil
            else
                local pick = Runtime.HuntRecoverPick
                if not pick or not pick.Parent or pick:GetAttribute("Despawning") then
                    pick = Runtime.huntPickupFor(pos, 120, Runtime.HuntCarried)
                    -- Far acquired drop: fall back to the exact target we latched in
                    -- ACQUIRE, then walk toward it.
                    if not pick then
                        local d = Runtime.HuntDropTarget
                        if d and d.Parent and not d:GetAttribute("Despawning") then pick = d end
                    end
                    Runtime.HuntRecoverPick = pick
                end
                if pick then
                    captureHuntPetInfo(pick, Runtime.HuntCarried)
                    local _, promptPos = Runtime.pickupFireInfo(pick)
                    local target = promptPos or pick:GetPivot().Position
                    if (target - pos).Magnitude > 10 then
                        -- pet not at our feet: step in (server-accepted move) -
                        -- but NEVER while a guard catch is landing: the fling/ragdoll is
                        -- active, and gliding back to the pet then is read by the server
                        -- as a speed/teleport violation and gets us kicked. Hand straight
                        -- to RECOVER, whose frame-rate recoverStep re-grabs + force-TPs.
                        if guardFlingFresh() or guardCatchNow() or Runtime.CatchHoldPos then
                            pcall(function() Runtime.huntReleasePins() end)
                            Runtime.HuntGuardHits = math.max(Runtime.HuntGuardHits or 0, 1)
                            Runtime.HuntRecoverPick = nil
                            Runtime.HuntRecoverEntryCarried = isCarrying()
                            Runtime.HuntStage = "RECOVER"; Runtime.HuntStageAt = now
                        elseif now - (Runtime.HuntRegrabAt or 0) > 0.15 then
                            Runtime.HuntRegrabAt = now
                            walkTo(target, 2)
                        end
                    else
                        moveStop()
                        if now - (Runtime.LastStealAttempt or 0) > 0.05 then
                            Runtime.LastStealAttempt = now
                            Runtime.forcePickupInstant(pick)
                        end
                    end
                elseif now - Runtime.HuntStageAt > 2 then
                    -- Drop vanished (picked up by someone else / despawned): reset and
                    -- let the outer selector acquire a fresh matching drop.
                    Runtime.HuntStage = "RESET"; Runtime.HuntStageAt = now
                end
            end
        elseif stage == "WALK_GUARD" then
            -- Carrying the stolen pet: walk to THIS zone's guard and let it SEIZE
            -- the pet (that single catch authorises the delivery). On the seize we
            -- go BRIEF -> RECOVER, which grabs it back + force-TPs it in the window.
            if not isCarrying() then
                Runtime.HuntGuardHits = (Runtime.HuntGuardHits or 0) + 1
                Runtime.HuntRecoverPick = nil
                Runtime.HuntStage = "BRIEF"; Runtime.HuntStageAt = now
            elseif now - Runtime.HuntStageAt > (Config.GuardBaitTimeout or 20) then
                if isCarrying() then dropCarried() end
                Runtime.HuntStage = "RESET"; Runtime.HuntStageAt = now
            else
                local zg = Runtime.nearestGuard(pos, Runtime.HuntPetZone) or Runtime.nearestGuard(pos)
                if zg then
                    local gh = zg:FindFirstChild("HumanoidRootPart", true)
                    local gp = (gh and gh.Position) or zg:GetPivot().Position
                    if (gp - pos).Magnitude > 8 then
                        if now - (Runtime.WalkGuardAt or 0) > 0.2 then
                            Runtime.WalkGuardAt = now
                            walkTo(gp, 2)
                        end
                    else
                        walkStop()
                    end
                end
            end
        elseif stage == "BRIEF" then
            -- The guard seized the pet: give the server a beat so the drop exists,
            -- then RECOVER (same as the META BRIEF stage). Only a fallback now -
            -- the frame-rate Carrying/fling hooks normally jump straight to RECOVER.
            if now - Runtime.HuntStageAt > 0.15 then
                Runtime.HuntStage = "RECOVER"; Runtime.HuntStageAt = now
                Runtime.HuntRecoverPick = nil
            end
        elseif stage == "RECOVER" then
            -- recoverStep (frame rate) does the single-pet delivery: re-grab the
            -- seized pet and force-TP it to SafeDropPos inside the catch window.
            if not isCarrying() and now - Runtime.HuntStageAt > 8 then
                Runtime.HuntStage = "RESET"; Runtime.HuntStageAt = now
                Runtime.HuntRecoverPick = nil
            end
        elseif stage == "TP_SAFE" then
            -- force-TP'd the pet to SafeDropPos while carrying; the server banks it
            -- on arrival and Carrying clears.
            if not isCarrying() then
                Runtime.hideBody(false)
                Runtime.Secured = Runtime.Secured + 1
                sendHuntWebhook()   -- report the stolen pet (Auto Steal Player)
                Runtime.huntReleasePins()
                Runtime.HuntTarget = nil; Runtime.HuntDropTarget = nil; Runtime.HuntKind = nil
                Runtime.HuntStage = nil; Runtime.Phase = "IDLE"; Runtime.HuntCoolUntil = now + 4.0
            elseif now - Runtime.HuntStageAt > 8 then
                if isCarrying() then dropCarried() end
                Runtime.LastFailReason = "bank diblokir (hunt deliver timeout)"
                Runtime.HuntStage = "RESET"; Runtime.HuntStageAt = now
            end
        elseif stage == "RESET" then
            -- Full clean restart: drop the cycle and go IDLE; the outer selector
            -- re-acquires a fresh target on the next tick.
            Runtime.hideBody(false)
            Runtime.huntReleasePins()
            Runtime.HuntRespawnPending = false
            Runtime.HuntRespawnAt = 0
            Runtime.HuntPetInfo = nil
            Runtime.LastSource = "Auto Break"
            Runtime.HuntTarget = nil; Runtime.HuntDropTarget = nil; Runtime.HuntKind = nil
            -- longer post-fail cooldown: a failed attempt must not instantly re-acquire
            -- (and self-respawn) again on the very next tick.
            Runtime.HuntStage = nil; Runtime.Phase = "IDLE"; Runtime.HuntCoolUntil = now + 4.0
        else
            -- Unknown / corrupt stage: full clean restart.
            Runtime.huntResetCycle()
        end
    elseif Runtime.Phase == "BREAK" and Config.AutoSteal then
        -- Never break while carrying (a pet was grabbed a tick before this branch):
        -- bank it via SECURE instead of breaking eggs with a pet in hand.
        if isCarrying() then
            Runtime.Phase = "SECURE"
            Runtime.TargetEgg = nil
            return
        end
        equipPickaxe()
        local egg = Runtime.TargetEgg
        local eggHealth = egg and egg:GetAttribute("Health")
        local brokeOrGone = egg and (not egg.Parent or egg:GetAttribute("Broken")
            or egg:GetAttribute("Hatching") or egg:GetAttribute("Despawning")
            or (type(eggHealth) == "number" and eggHealth <= 0))
        if brokeOrGone then
            Runtime.LastSource = "Auto Break"
            Runtime.Phase = "PICKUP"
            Runtime.PhaseTimer = now
            Runtime.TargetEgg = nil
        else
            if not egg then
                egg = nearestEgg(pos)
                Runtime.TargetEgg = egg
            end
            if egg then
                Runtime.BreakPos = egg.Position
                local m = Runtime.eggSurfaceDist(egg, pos)
                if m > 4 then
                    tpTo(egg.Position, 2, moveSpeed(), 3)
                end
                -- Within 8 studs: the shared per-tick sync (Runtime.autoSwing) switches the
                -- game's AutoSwingController ON at <=6 studs; the game breaks the egg
                -- itself (MasteryPickaxeSwing + EggHitRequest). No manual fire here.
            end
        end
    elseif Runtime.Phase == "META" and Config.AutoSteal then
        -- Target zone: titanic egg's zone while one is alive; latch it for the whole
        -- run (so the zone survives the egg breaking mid-delivery).
        local tEgg = ((Runtime.TitanicCoolUntil or 0) <= now) and findTitanicEgg(pos) or nil
        if tEgg then
            Runtime.MetaZoneId = titanicZoneId(tEgg)
            Runtime.MetaTitanic = true
        elseif Runtime.MetaTitanic then
            Runtime.MetaTitanic = false
            Runtime.MetaZoneId = activeZoneId()
            Runtime.MetaStage = "TRAVEL"
            Runtime.MetaStageAt = now
            Runtime.TargetEgg = nil
            Runtime.BurstEgg = nil
        elseif Config.AutoCompleteIndex and not isCarrying() then
            local idxZone = INDEX_FILTER.ZoneId or activeZoneId()
            if idxZone and Runtime.MetaZoneId ~= idxZone then
                Runtime.MetaZoneId = idxZone
                Runtime.MetaStage = "TRAVEL"
                Runtime.MetaStageAt = now
                Runtime.TargetEgg = nil
                Runtime.BurstEgg = nil
            end
        end
        local zoneId = Runtime.MetaZoneId or activeZoneId()
        local stage = Runtime.MetaStage or "TRAVEL"

        -- BigFroot far-zone entry: for a FAR zone (Zone 3+) enter via a Zone 1
        -- decoy ONCE per target: break+pickup in Zone 1 so the guard catches us
        -- (hitguard), then hop to the far zone inside that window. Until then we
        -- never TP straight to the far zone.
        do
            local tzIdx = zoneIndexFromId(zoneId)
            if isV1() then
                -- TP v1 entry (hallmark): walk to a Zone 1 egg, break it, pick the
                -- pet up, let the guard catch us, then TP to the target zone inside
                -- that catch window. Re-armed from TRAVEL (e.g. after every bank),
                -- BUT never while we are already inside the target zone - that was
                -- the "goes back and repeats from the start" loop. MetaWalkEntry is
                -- the no-catch walk fallback and deliberately skips the decoy.
                if not Runtime.DecoyStage and stage == "TRAVEL"
                    and not Runtime.MetaWalkEntry
                    and not isCarrying()
                    and not Runtime.BankStage
                    and zoneOfPosition(pos) ~= zoneId then
                    if Runtime.requestZoneStream then Runtime.requestZoneStream(zoneId) end
                    Runtime.DecoyStage = "GOTO1"
                    Runtime.DecoyZone = zoneId
                    Runtime.DecoyEgg = nil
                    Runtime.DecoyPick = nil
                    Runtime.DecoyPulled = false
                    Runtime.DecoyStageAt = now
                    Runtime.TargetEgg = nil
                    Runtime.BurstEgg = nil
                    walkStop()
                end
            elseif not Runtime.DecoyStage and isTPMode() and tzIdx and tzIdx >= 3
                and Runtime.DecoyDoneZone ~= zoneId
                and not isCarrying()
                and zoneOfPosition(pos) ~= zoneId then
                if Runtime.requestZoneStream then Runtime.requestZoneStream(zoneId) end
                Runtime.DecoyStage = "GOTO1"
                Runtime.DecoyZone = zoneId
                Runtime.DecoyEgg = nil
                Runtime.DecoyPick = nil
                Runtime.DecoyPulled = false
                Runtime.DecoyStageAt = now
                walkStop()
            end
        end

        -- BigFroot hitguard bank takes priority: while carrying (or a bank is in
        -- progress) run the instant-TP bank sub-machine instead of breaking.
        if Runtime.DecoyStage then
            -- The decoy entry runs FRAME-RATE in metaKiteStep (short catch window).
        elseif Runtime.BankStage or isCarrying() or stage == "SECURE" then
            if not Runtime.BankStage then
                Runtime.BankStage = "BAIT"
                Runtime.BankAt = now
                Runtime.BankWant = LocalPlayer:GetAttribute("Carrying")
                Runtime.BankLeapt = false
                Runtime.BankPulled = false
                Runtime.MetaStage = "SECURE"
                Runtime.MetaStageAt = now
                Runtime.TargetEgg = nil
                Runtime.BurstEgg = nil
                walkStop()
            end
            -- The actual bank runs FRAME-RATE in metaKiteStep (short catch window).
        elseif stage == "TRAVEL" then
            -- Once inside the target zone, stop the walk-retry and resume instant
            -- TP for the eggs inside the zone.
            if Runtime.MetaWalkEntry and zoneOfPosition(pos) == zoneId then
                Runtime.MetaWalkEntry = false
            end
            -- BigFroot Ticket/Hop/Leap: instant TP straight onto a target-zone egg.
            local egg = Runtime.TargetEgg
            if egg and (not egg.Parent or eggBrokeOrGone(egg)) then
                egg = nil
                Runtime.TargetEgg = nil
            end
            if not egg then
                egg = metaPickEgg(pos, zoneId)
                Runtime.TargetEgg = egg
            end
            if egg then
                if Runtime.eggSurfaceDist(egg, pos) <= 4 then
                    walkStop()
                    Runtime.MetaWalkEntry = false
                    Runtime.MetaStage = "BREAK"
                    Runtime.MetaStageAt = now
                elseif isTitanicEgg(egg) then
                    local stand = metaEggPoint(egg, zoneId) or egg.Position
                    if not Runtime.walkActive() then Runtime.walkGo(stand, 2) end
                elseif Runtime.MetaWalkEntry then
                    local stand = egg.Position
                    if isV1() then
                        if not Runtime.walkActive() then Runtime.walkGo(stand, 5) end
                    elseif not travelActive() then
                        walkTo(stand, 2)
                    end
                elseif isV1() then
                    local stand = egg.Position
                    if not Runtime.walkActive() then Runtime.walkGo(stand, 5) end
                else
                    Runtime.moverReach(egg, zoneId)
                end
            else
                -- No egg in the target zone yet (its content is not streamed in).
                -- Prefetch streaming and move to the zone's grounded entry point,
                -- then keep waiting: the picker rescans every tick.
                if zoneId then
                    if Runtime.requestZoneStream then Runtime.requestZoneStream(zoneId) end
                    local anchor = Runtime.zoneAnchorPoint(zoneId)
                    if anchor then
                        local inZone = zoneOfPosition(pos) == zoneId
                        local flat = Vector3.new(anchor.X - pos.X, 0, anchor.Z - pos.Z)
                        if (not inZone) and flat.Magnitude > 8 then
                            if isV1() then
                                if not Runtime.walkActive() then Runtime.walkGo(anchor, 8) end
                            elseif Runtime.MetaWalkEntry then
                                if not travelActive() then walkTo(anchor, 3) end
                            elseif now - (Runtime.MetaAnchorTpAt or 0) > 0.5 then
                                Runtime.MetaAnchorTpAt = now
                                -- Never raw-TP into a zone whose content is not
                                -- streamed yet (server pulls it back -> never loads).
                                -- Wait for the stream; fall back to walking if it
                                -- stalls, so the bot cannot dead-lock.
                                if Runtime.zoneHasContent and Runtime.zoneHasContent(zoneId) then
                                    Runtime.MetaStreamWaitAt = nil
                                    Runtime.instantTp(anchor)
                                else
                                    Runtime.MetaStreamWaitAt = Runtime.MetaStreamWaitAt or now
                                    if now - Runtime.MetaStreamWaitAt > 20 then
                                        Runtime.MetaWalkEntry = true
                                    end
                                end
                            end
                        end
                    end
                end
                Runtime.MetaStageAt = now
            end
        elseif stage == "BREAK" then
            -- NEVER break while carrying a pet (defence in depth; the carried-state
            -- block above already handles it). Hand straight to SECURE.
            if isCarrying() then
                Runtime.MetaStage = "SECURE"
                Runtime.MetaStageAt = now
                Runtime.MetaPick = nil
                Runtime.TargetEgg = nil
                Runtime.BurstEgg = nil
                walkStop()
                return
            end
            -- Cycle eggs in the target zone: break one, and the moment it
            -- breaks/hatches leave it and break the next; only pick up a
            -- qualifying pet.
            local egg = Runtime.TargetEgg
            if egg and (not egg.Parent or eggBrokeOrGone(egg)) then
                -- leave the hatching egg, move to the next one
                Runtime.LastSource = "Auto Break"
                Runtime.TargetEgg = nil
                Runtime.BurstEgg = nil
                Runtime.MetaStageAt = now
                egg = nil
            end
            if not egg then
                egg = metaPickEgg(pos, zoneId)
                Runtime.TargetEgg = egg
            end
            if egg then
                if Runtime.eggSurfaceDist(egg, pos) > 4 then
                    if isTitanicEgg(egg) then
                        local stand = metaEggPoint(egg, zoneId) or egg.Position
                        if not Runtime.walkActive() then Runtime.walkGo(stand, 2) end
                    elseif isV1() then
                        local stand = egg.Position
                        if not Runtime.walkActive() then Runtime.walkGo(stand, 5) end
                    else
                        Runtime.moverReach(egg, zoneId)
                    end
                else
                    walkStop()
                    breakEggStep(egg, now)
                end
            else
                -- No egg in the target zone yet (not streamed in). Move to the
                -- zone's grounded entry point and wait; the picker rescans every
                -- tick and BREAK resumes as soon as eggs replicate.
                if zoneId then
                    if Runtime.requestZoneStream then Runtime.requestZoneStream(zoneId) end
                    local anchor = Runtime.zoneAnchorPoint(zoneId)
                    if anchor then
                        local inZone = zoneOfPosition(pos) == zoneId
                        local flat = Vector3.new(anchor.X - pos.X, 0, anchor.Z - pos.Z)
                        if (not inZone) and flat.Magnitude > 8 then
                            if isV1() then
                                if not Runtime.walkActive() then Runtime.walkGo(anchor, 8) end
                            elseif Runtime.MetaWalkEntry then
                                if not travelActive() then walkTo(anchor, 3) end
                            elseif now - (Runtime.MetaAnchorTpAt or 0) > 0.5 then
                                Runtime.MetaAnchorTpAt = now
                                -- Never raw-TP into a zone whose content is not
                                -- streamed yet (server pulls it back -> never loads).
                                -- Wait for the stream; fall back to walking if it
                                -- stalls, so the bot cannot dead-lock.
                                if Runtime.zoneHasContent and Runtime.zoneHasContent(zoneId) then
                                    Runtime.MetaStreamWaitAt = nil
                                    Runtime.instantTp(anchor)
                                else
                                    Runtime.MetaStreamWaitAt = Runtime.MetaStreamWaitAt or now
                                    if now - Runtime.MetaStreamWaitAt > 20 then
                                        Runtime.MetaWalkEntry = true
                                    end
                                end
                            end
                            Runtime.MetaZoneWaitAt = nil
                        else
                            walkStop()
                            Runtime.MetaZoneWaitAt = Runtime.MetaZoneWaitAt or now
                            if now - Runtime.MetaZoneWaitAt > 15 and not Runtime.MetaZoneNotified then
                                Runtime.MetaZoneNotified = true
                                pcall(function()
                                    WindUI:Notify({
                                        Title = "Auto Farm",
                                        Content = "Zone " .. tostring(zoneId) .. ": egg belum ter-load, menunggu...",
                                        Duration = 4,
                                    })
                                end)
                            end
                        end
                    end
                end
                Runtime.MetaStageAt = now
            end
            -- v2 Decoy: when the fling window is about to close, bait Zone1.
            if isV2() then Runtime.tryDecoy() end
            -- while cycling eggs, grab a qualifying pet as soon as it appears
            if not isCarrying() then
                local pick, inc = bestMinIncomePickup(pos, 120)
                if pick then
                    Runtime.MetaPick = pick
                    Runtime.LastSource = "Auto Break"
                    Runtime.MetaStage = "PICKUP"
                    Runtime.MetaStageAt = now
                    captureAutoBreakPetInfo(pick, pick:GetAttribute("AnimalName"))
                elseif Runtime.MetaTitanic and not tEgg then
                    Runtime.MetaTitanic = false
                    Runtime.MetaZoneId = activeZoneId()
                    Runtime.MetaStage = "TRAVEL"
                    Runtime.MetaStageAt = now
                    Runtime.TargetEgg = nil
                    Runtime.BurstEgg = nil
                end
            end
        elseif stage == "PICKUP" then
            local pick = Runtime.MetaPick
            if not pick or not pick.Parent or pick:GetAttribute("Despawning") then
                -- the chosen pet despawned. If we already grabbed it (Carrying a
                -- tick behind), bank it instead of going back to break with a pet.
                Runtime.MetaPick = nil
                if isCarrying() then
                    Runtime.MetaStage = "SECURE"
                    Runtime.MetaStageAt = now
                else
                    Runtime.MetaStage = "BREAK"
                    Runtime.MetaStageAt = now
                end
            else
                local _, promptPos, fireRange = Runtime.pickupFireInfo(pick)
                local target = promptPos or pick:GetPivot().Position
                local d = (target - pos).Magnitude
                if not isCarrying() and d > (fireRange or 7) then
                    if isV1() then
                        -- TP v1: WALK (genuine Humanoid:Move) to the drop.
                        if now - (Runtime.PickMoveAt or 0) > 0.08 then
                            Runtime.PickMoveAt = now
                            if not Runtime.walkActive() then Runtime.walkGo(target, 3) end
                        end
                    elseif now - (Runtime.PickMoveAt or 0) > 0.08 then
                        -- BigFroot instant TP onto the drop (Leap inside the window).
                        Runtime.PickMoveAt = now
                        if isTPMode() and Runtime.inWindow(0.2) then
                            Runtime.Leap(target)
                        else
                            Runtime.instantTp(target)
                        end
                    end
                else
                    walkStop()
                    if satchelFull() then
                        if not Runtime.MetaWarnedFull then
                            Runtime.MetaWarnedFull = true
                            pcall(function() WindUI:Notify({ Title = "Notice", Content = "Satchel full - sell/bank first.", Duration = 4 }) end)
                        end
                        Runtime.Phase = "IDLE"
                        Runtime.MetaStage = nil
                    elseif now - (Runtime.LastStealAttempt or 0) > 0.08 then
                        Runtime.LastStealAttempt = now
                        Runtime.forcePickup(pick)
                    end
                end
                if now - Runtime.MetaStageAt > 15 then
                    Runtime.MetaPick = nil
                    Runtime.MetaStage = "BREAK"
                    Runtime.MetaStageAt = now
                end
            end
        elseif stage == "SECURE" then
            -- Handled by the hitguard bank sub-machine at the top of this block.
            -- (Kept as a safe fallback in case the stage is reached directly.)
            Runtime.metaBankStep(now)
        end
    elseif Runtime.Phase == "WALK" and Config.AutoSteal then
        -- WALK ENGINE (mode "Walk" only): genuine walking via Humanoid:MoveTo at the
        -- character's own treadmill WalkSpeed. Loop: GOTO_START -> TO_ZONE -> BREAK ->
        -- PICKUP -> RETURN (walk back to WalkStartPos) -> bank -> repeat.
        -- No TP/CFrame here at all; the TP/META/HUNT engines are untouched.
        if c:GetAttribute("Ragdolled") == true
            or (hum and hum:GetState() == Enum.HumanoidStateType.Physics) then
            -- guard flung us: wait the ragdoll out, then resume the same stage
            Runtime.walkStop()
        else
            local stage = Runtime.WalkStage or "GOTO_START"
            if isCarrying() and stage ~= "RETURN" then
                stage = "RETURN"
                Runtime.WalkStage = "RETURN"
                Runtime.WalkStageAt = now
            end
            -- Remember that we are (or were) carrying, so RETURN can tell a guard
            -- SEIZE (Carrying cleared mid-way) from a successful SafeZone bank.
            if isCarrying() then
                Runtime.WalkHadPet = true
                Runtime.WalkCarried = LocalPlayer:GetAttribute("Carrying")
            end
            -- resolve the target zone for this tick (titanic > complete index > filter)
            local zoneId = nil
            local tEgg = findTitanicEgg(pos)
            if tEgg then
                zoneId = titanicZoneId(tEgg)
            elseif Config.AutoCompleteIndex and INDEX_FILTER.ZoneId then
                zoneId = INDEX_FILTER.ZoneId
            else
                zoneId = activeZoneId()
            end

            if stage == "GOTO_START" then
                -- park at the WalkStartPos hardcoded SafeZone point, then head out
                local start = Config.WalkStartPos or Config.SafeDropPos
                if arrivedNear(start, 8) then
                    Runtime.WalkStage = "TO_ZONE"
                    Runtime.WalkStageAt = now
                elseif not Runtime.walkActive() then
                    Runtime.walkGo(start, 6)
                end

            elseif stage == "TO_ZONE" then
                -- walk from the SafeZone point into the filter zone (all zones when
                -- filter = "Semua")
                local egg = nil
                if zoneId then
                    egg = nearestEggInZone(pos, zoneId) or firstEggInZone(zoneId)
                else
                    egg = nearestEgg(pos)
                end
                if egg then
                    Runtime.WalkEgg = egg
                    local inZone = (zoneId == nil) or (zoneOfPosition(pos) == zoneId)
                    if not Runtime.walkActive() then
                        local walkDest = metaEggPoint(egg, zoneId) or egg.Position
                        local arrive = isTitanicEgg(egg) and 2 or 6
                        Runtime.walkGo(walkDest, arrive)
                    end
                    if inZone and Runtime.eggSurfaceDist(egg, pos) <= 12 then
                        Runtime.WalkStage = "BREAK"
                        Runtime.WalkStageAt = now
                    end
                else
                    -- The zone's eggs are not visible yet: Workspace.StreamingEnabled
                    -- keeps far zones out of the client until they are approached, so
                    -- their Eggs folder is EMPTY while we are at the SafeZone. Walk to
                    -- the zone's GROUNDED entry point (never the hitbox centre, which
                    -- sits over void for some zones) and wait there - the picker
                    -- rescans every tick and switches to BREAK once eggs replicate.
                    local anchor = zoneId and Runtime.zoneAnchorPoint(zoneId)
                    if anchor then
                        if Runtime.requestZoneStream then Runtime.requestZoneStream(zoneId) end
                        local inZone = zoneOfPosition(pos) == zoneId
                        local flat = Vector3.new(anchor.X - pos.X, 0, anchor.Z - pos.Z)
                        if (not inZone) and flat.Magnitude > 8 then
                            if not Runtime.walkActive() then Runtime.walkGo(anchor, 8) end
                            Runtime.WalkZoneWaitAt = nil
                        else
                            Runtime.walkStop()
                            Runtime.WalkZoneWaitAt = Runtime.WalkZoneWaitAt or now
                            if now - Runtime.WalkZoneWaitAt > 15 and not Runtime.WalkZoneNotified then
                                Runtime.WalkZoneNotified = true
                                pcall(function()
                                    WindUI:Notify({
                                        Title = "Auto Farm",
                                        Content = "Zone " .. tostring(zoneId) .. ": egg belum ter-load, menunggu...",
                                        Duration = 4,
                                    })
                                end)
                            end
                        end
                        Runtime.WalkStageAt = now
                    else
                        Runtime.walkStop()
                        if now - Runtime.WalkStageAt > 8 then
                            Runtime.WalkStage = "GOTO_START"
                            Runtime.WalkStageAt = now
                        end
                    end
                end

            elseif stage == "BREAK" then
                -- Cycle eggs in the zone exactly like the far-zone META does: break
                -- one, and the moment it breaks/hatches move on to the next. We do
                -- NOT stop and wait on a single egg.
                local egg = Runtime.WalkEgg
                if egg and (not egg.Parent or eggBrokeOrGone(egg)) then
                    -- leave the hatching egg, move to the next one
                    Runtime.LastSource = "Auto Break"
                    Runtime.WalkEgg = nil
                    Runtime.BurstEgg = nil
                    Runtime.WalkStageAt = now
                    egg = nil
                end
                if not egg then
                    if zoneId then
                        egg = nearestEggInZone(pos, zoneId) or firstEggInZone(zoneId)
                    else
                        egg = nearestEgg(pos)
                    end
                    Runtime.WalkEgg = egg
                end
                if egg then
                    local d = Runtime.eggSurfaceDist(egg, pos)
                    if d > 4 then
                        local walkPos = egg.Position
                        local arrive = 3
                        if isTitanicEgg(egg) then
                            walkPos = metaEggPoint(egg, zoneId) or egg.Position
                            arrive = 2
                        end
                        if not Runtime.walkActive() then Runtime.walkGo(walkPos, arrive) end
                    else
                        Runtime.walkStop()
                        Runtime.BreakPos = egg.Position
                        breakEggStep(egg, now)
                    end
                end
                -- while cycling eggs, grab a qualifying pet (income minimum + rarity
                -- filter, same as the META bestMinIncomePickup) as soon as it appears
                if not isCarrying() then
                    local pick = bestMinIncomePickup(pos, 120)
                    if pick then
                        Runtime.WalkPick = pick
                        Runtime.LastSource = "Auto Break"
                        Runtime.WalkStage = "PICKUP"
                        Runtime.WalkStageAt = now
                        captureAutoBreakPetInfo(pick, pick:GetAttribute("AnimalName"))
                    end
                end

            elseif stage == "PICKUP" then
                -- Grab the qualifying pet (income minimum + rarity filter). If it
                -- vanishes we do NOT sit and wait - we look for another qualifying
                -- pickup, or go back to breaking other eggs (META behaviour).
                local pick = Runtime.WalkPick
                if pick and (not pick.Parent or pick:GetAttribute("Despawning")) then
                    pick = nil
                    Runtime.WalkPick = nil
                end
                if isCarrying() then
                    Runtime.WalkStage = "RETURN"
                    Runtime.WalkStageAt = now
                elseif not pick then
                    pick = bestMinIncomePickup(pos, 120)
                    Runtime.WalkPick = pick
                    if not pick then
                        Runtime.WalkStage = "BREAK"
                        Runtime.WalkStageAt = now
                        Runtime.WalkEgg = nil
                    end
                end
                if not isCarrying() and pick then
                    local _, promptPos, fireRange = Runtime.pickupFireInfo(pick)
                    local target = promptPos or pick:GetPivot().Position
                    local d = (target - pos).Magnitude
                    if d > (fireRange or 7) then
                        if not Runtime.walkActive() then Runtime.walkGo(target, 2) end
                    else
                        Runtime.walkStop()
                        if now - (Runtime.LastStealAttempt or 0) > 0.08 then
                            Runtime.LastStealAttempt = now
                            Runtime.forcePickup(pick)
                        end
                        if isCarrying() then
                            Runtime.WalkStage = "RETURN"
                            Runtime.WalkStageAt = now
                        end
                    end
                    if now - Runtime.WalkStageAt > 20 then
                        Runtime.WalkPick = nil
                        Runtime.WalkStage = "BREAK"
                        Runtime.WalkStageAt = now
                    end
                end

            elseif stage == "RECOVER" then
                -- A guard seized the carried pet during the return (ragdoll/hit).
                -- Walk back to the dropped AnimalPickup and grab it again; once we
                -- are carrying, the auto-transition above resumes RETURN. If the pet
                -- is gone, farm again instead of walking to the SafeZone empty-handed.
                if now - Runtime.WalkStageAt > 15 then
                    -- hard bound: never loop in recovery forever
                    Runtime.LastFailReason = "walk recover timeout"
                    Runtime.WalkHadPet = false
                    Runtime.WalkCarried = nil
                    Runtime.WalkRecoverPick = nil
                    Runtime.WalkStage = "BREAK"
                    Runtime.WalkStageAt = now
                    Runtime.WalkEgg = nil
                    Runtime.WalkPick = nil
                else
                local pick = Runtime.WalkRecoverPick
                if not pick or not pick.Parent or pick:GetAttribute("Despawning") then
                    pick = Runtime.findCatchPickup(Runtime.WalkCarried)
                    if not pick then pick = findRecoverPickup(pos, Runtime.WalkCarried) end
                    if not pick then pick = Runtime.findCatchPickup(nil) end
                    Runtime.WalkRecoverPick = pick
                end
                if pick then
                    local _, promptPos, fireRange = Runtime.pickupFireInfo(pick)
                    local target = promptPos or pick:GetPivot().Position
                    local d = (target - pos).Magnitude
                    if d > (fireRange or 7) then
                        if not Runtime.walkActive() then Runtime.walkGo(target, 3) end
                    else
                        Runtime.walkStop()
                        if now - (Runtime.LastStealAttempt or 0) > 0.08 then
                            Runtime.LastStealAttempt = now
                            Runtime.forcePickupInstant(pick)
                        end
                    end
                elseif now - Runtime.WalkStageAt > 6 then
                    -- pet is gone: give up this delivery and farm again
                    Runtime.LastFailReason = "walk recover failed"
                    Runtime.WalkHadPet = false
                    Runtime.WalkCarried = nil
                    Runtime.WalkRecoverPick = nil
                    Runtime.WalkStage = "BREAK"
                    Runtime.WalkStageAt = now
                    Runtime.WalkEgg = nil
                    Runtime.WalkPick = nil
                end
                end

            elseif stage == "RETURN" then
                -- Guard hit mid-return: the pet was SEIZED (Carrying cleared while not
                -- in the SafeZone) -> recover it instead of banking empty-handed.
                if Runtime.WalkHadPet and not isCarrying() and not inSafeZone(hrp.Position) then
                    Runtime.WalkStage = "RECOVER"
                    Runtime.WalkStageAt = now
                    Runtime.WalkRecoverPick = nil
                    Runtime.walkStop()
                else
                    -- Single-point return: walk back to the SAME hardcoded start point
                    -- (WalkStartPos). NoClip is not used here.
                    local dest = Config.WalkStartPos or Config.SafeDropPos
                    if not Runtime.walkActive() then Runtime.walkGo(dest, 6) end
                    if (not isCarrying()) and (inSafeZone(hrp.Position) or arrivedNear(dest, 8)) then
                        Runtime.walkStop()
                        Runtime.WalkStage = "GOTO_START"
                        Runtime.WalkStageAt = now
                        Runtime.WalkEgg = nil
                        Runtime.WalkPick = nil
                        Runtime.WalkHadPet = false
                        Runtime.WalkCarried = nil
                        Runtime.WalkRecoverPick = nil
                        Runtime.LastSource = "Auto Break"
                        Runtime.Secured = (Runtime.Secured or 0) + 1
                        Runtime.MetaSteals = (Runtime.MetaSteals or 0) + 1
                        Runtime.MetaCoolUntil = now + 1.0
                        sendAutoBreakWebhook()
                    elseif now - Runtime.WalkStageAt > 90 then
                        Runtime.walkStop()
                        if isCarrying() then dropCarried() end
                        Runtime.WalkHadPet = false
                        Runtime.WalkCarried = nil
                        Runtime.LastFailReason = "walk return timeout"
                        Runtime.WalkStage = "GOTO_START"
                        Runtime.WalkStageAt = now
                    end
                end

            else
                Runtime.WalkStage = "GOTO_START"
                Runtime.WalkStageAt = now
            end
        end
    end

    if statusPar and now - Runtime.LastStatus > 0.8 then
        Runtime.LastStatus = now
        local _, plot = plotSpot()
        local placed = plot and (plot:GetAttribute("AnimalsPlaced") or 0) or "-"
        local max = plot and (plot:GetAttribute("MaxAnimals") or 8) or "-"
        statusPar:SetDesc(("Phase: %s | Zone: %s | Carry: %s\nStolen: %s | Secured: %s | Hits: %s\nHunt: %s | Bat: %s\nGuard: %s (%.0fm) | Plot: %s/%s\nMeta: %s | Loop: %s | MinInc: %s\nSnap: %s | BankBlock: %s | Settle: %.1fs | Fail: %s\nMove: %s | WS: %s | WalkStage: %s"):format(
            tostring(Runtime.Phase),
            tostring(Config.EggFilter),
            carrying and tostring(LocalPlayer:GetAttribute("Carrying")) or "-",
            tostring(Runtime.Stolen), tostring(Runtime.Secured), tostring(Runtime.Hits),
            Runtime.HuntTarget and Runtime.HuntTarget.Name or "-", tostring(Runtime.BatSwings or 0),
            lastThreatState, lastThreatDist, tostring(placed), tostring(max),
            tostring(Runtime.MetaStage or "-"), tostring(Runtime.MetaSteals or 0), tostring(Config.AutoStealMinIncome or 0),
            tostring(Runtime.SnapCount or 0), tostring(Runtime.BankBlockCount or 0),
            tonumber(Runtime.BankSettle) or 3.0, tostring(Runtime.LastFailReason or "-"),
            tostring(Config.MovementMode or "TP v2"),
            tostring(hum and math.floor((hum.WalkSpeed or 0) + 0.5) or "-"),
            tostring(Runtime.WalkStage or "-")
        ))
    end
end)

getgenv().__rooxFeatureLoop = Connections.FeatureLoop

do
local DS = {
    MountedBought = 0,
    LastAction = "-",
    LastAt = 0,
    LastStep = 0,
    LastEquipAt = 0,
    InFlight = false,
    PendingSkin = nil,
    PendingAt = 0,
    FailCooldownUntil = 0,
    LastError = nil,
}

local function diamonds()
    local v = LocalPlayer:GetAttribute("Diamonds")
    return type(v) == "number" and v or 0
end

local function ownedSkins()
    local set = {}
    local raw = LocalPlayer:GetAttribute("OwnedPlotSkins")
    if type(raw) == "string" then
        for id in string.gmatch(raw, "[^,]+") do set[id] = true end
    end
    return set
end

local RideEggCfg = nil
pcall(function() RideEggCfg = require(ReplicatedStorage.Shared.RideEggConfig) end)
local PlotSkinCfg = nil
pcall(function() PlotSkinCfg = require(ReplicatedStorage.Shared.PlotSkinConfig) end)

local FALLBACK_MOUNTED_PRICES = { [1] = 1000, [3] = 3000, [8] = 8000 }

local function mountedPrice(n)
    local p = FALLBACK_MOUNTED_PRICES[n]
    if RideEggCfg and type(RideEggCfg.Prices) == "table" and type(RideEggCfg.Prices.Mounted) == "table" then
        local v = RideEggCfg.Prices.Mounted[n]
        if type(v) == "number" then p = v end
    end
    return p
end

local function selectedAmounts()
    local out = {}
    local f = Config.DiamondMountedAmounts
    if type(f) == "table" then
        for _, n in ipairs({ 1, 3, 8 }) do
            if f[tostring(n)] == true or f["x" .. n] == true or f[n] == true then
                out[#out + 1] = n
            end
        end
    end
    return out
end

local function skinSelected(name)
    local f = Config.DiamondPlotSkinFilter
    return type(f) == "table" and name ~= nil and f[name] == true
end

local function buyMounted(now)
    local amounts = selectedAmounts()
    if #amounts == 0 then return false end
    local bal = diamonds()
    local amount = nil
    for _, n in ipairs(amounts) do
        if bal >= mountedPrice(n) then amount = n break end
    end
    if not amount then return false end
    local remote = ReplicatedStorage:FindFirstChild("RideEggRemote")
    if not (remote and remote:IsA("RemoteFunction")) then return false end
    DS.InFlight = true
    DS.LastAt = now
    task.spawn(function()
        local ok, res = pcall(function() return remote:InvokeServer("Hatch", "Mounted", amount) end)
        if ok and type(res) == "table" then
            DS.MountedBought = DS.MountedBought + 1
            DS.LastAction = ("Mounted x%d (+%d)"):format(amount, #res)
            DS.LastError = nil
        else
            DS.LastError = ok and "hatch request failed" or tostring(res)
            DS.FailCooldownUntil = os.clock() + 5
        end
        DS.InFlight = false
    end)
    return true
end

local function skinCandidates()
    local list = {}
    local owned = ownedSkins()
    if PlotSkinCfg and type(PlotSkinCfg.Skins) == "table" then
        for id, s in pairs(PlotSkinCfg.Skins) do
            if skinSelected(s.Name) and not owned[id] and DS.PendingSkin ~= id then
                list[#list + 1] = { Id = id, Name = s.Name, Price = tonumber(s.Price) or 0 }
            end
        end
    end
    table.sort(list, function(a, b) return a.Price < b.Price end)
    return list
end

local function buySkin(now)
    local list = skinCandidates()
    if #list == 0 then return false end
    local bal = diamonds()
    local pick = nil
    for _, c in ipairs(list) do
        if bal >= c.Price then pick = c break end
    end
    if not pick then return false end
    local remote = ReplicatedStorage:FindFirstChild("PlotSkinRequest")
    if not (remote and remote:IsA("RemoteEvent")) then return false end
    pcall(function() remote:FireServer("Buy", pick.Id) end)
    DS.PendingSkin = pick.Id
    DS.PendingAt = now
    DS.LastAt = now
    DS.LastAction = "Buy " .. pick.Name
    return true
end

local function equipOwnedSkins(now)
    if not PlotSkinCfg or type(PlotSkinCfg.Skins) ~= "table" then return false end
    local remote = ReplicatedStorage:FindFirstChild("PlotSkinRequest")
    if not (remote and remote:IsA("RemoteEvent")) then return false end
    local owned = ownedSkins()
    local equipped = LocalPlayer:GetAttribute("PlotSkin")
    if now - (DS.LastEquipAt or 0) < 1 then return false end
    for id, s in pairs(PlotSkinCfg.Skins) do
        if skinSelected(s.Name) and owned[id] and equipped ~= id then
            DS.LastEquipAt = now
            pcall(function() remote:FireServer("Equip", id) end)
            DS.LastAction = "Equip " .. s.Name
            return true
        end
    end
    return false
end

local function diamondStep(now)
    if now < (DS.FailCooldownUntil or 0) then return end
    if DS.InFlight then return end
    local cd = tonumber(Config.DiamondShopCooldown) or 1
    if cd < 0.3 then cd = 0.3 end
    if now - (DS.LastAt or 0) < cd then return end
    if DS.PendingSkin then
        if ownedSkins()[DS.PendingSkin] then
            DS.PendingSkin = nil
        elseif now - (DS.PendingAt or now) > 6 then
            DS.PendingSkin = nil
        end
    end
    if Config.AutoDiamondPlotSkin and type(Config.DiamondPlotSkinFilter) == "table"
        and next(Config.DiamondPlotSkinFilter) ~= nil then
        if equipOwnedSkins(now) then return end
        if not DS.PendingSkin and buySkin(now) then return end
    end
    if Config.AutoDiamondMounted then
        buyMounted(now)
    end
end

Connections.DiamondShopLoop = RunService.Heartbeat:Connect(function()
    if not getgenv()[GAME_CONFIG.GlobalFlag] then return end
    local now = os.clock()
    if now - (DS.LastStep or 0) < 0.3 then return end
    DS.LastStep = now
    diamondStep(now)
end)

getgenv().__bsDiamondShop = function()
    local owned = ownedSkins()
    local count = 0
    for _ in pairs(owned) do count = count + 1 end
    return {
        Diamonds = diamonds(),
        MountedBought = DS.MountedBought,
        LastAction = DS.LastAction,
        LastError = DS.LastError,
        PendingSkin = DS.PendingSkin,
        OwnedSkins = count,
        Equipped = LocalPlayer:GetAttribute("PlotSkin"),
        InFlight = DS.InFlight,
    }
end
end


----------------------------------------------------------------
-- TREADMILL FORCE-OFF GUARD (binds above TreadmillFaceLock priority)
----------------------------------------------------------------
local function tmGuardStep()
    if not getgenv()[GAME_CONFIG.GlobalFlag] then return end
    if Runtime.Phase == "IDLE" then return end
    local exiting = Runtime.Phase == "TMEXIT"
    if not exiting and not onTreadmillNow() then return end
    pcall(function() RunService:UnbindFromRenderStep("TreadmillFaceLock") end)
    local c, hrp, hum = getChar()
    if hum and hum.AutoRotate == false then
        pcall(function() hum.AutoRotate = true end)
    end
    if not exiting and hrp and Runtime.HoldCFrame and os.clock() < (Runtime.HoldUntil or 0) then
        hrp.CFrame = Runtime.HoldCFrame
    end
end
pcall(function()
    RunService:BindToRenderStep("BSTmGuard", Enum.RenderPriority.Character.Value + 2, tmGuardStep)
end)
Connections.UnbindTmGuard = { Disconnect = function()
    pcall(function() RunService:UnbindFromRenderStep("BSTmGuard") end)
end }

----------------------------------------------------------------
-- FAR-ZONE META KITE (frame-accurate delivery hop)
----------------------------------------------------------------
pcall(function()
    RunService:BindToRenderStep("BSMetaKite", Enum.RenderPriority.Character.Value + 1, metaKiteStep)
end)
Connections.UnbindMetaKite = { Disconnect = function()
    pcall(function() RunService:UnbindFromRenderStep("BSMetaKite") end)
end }

--------------------------------------------------------------
-- ANTI-CHEAT STRIKE DETECTOR (arm)
---------------------------------------------------------------
armStrikeDetector()

----------------------------------------------------------------
-- GUARD-HIT TRIGGER (far-zone meta)
----------------------------------------------------------------
armGuardTrigger()

---------------------------------------------------------------
-- DROP-ONLY HUNT SPAWN-PIN (self-kill ONCE -> respawn -> pin onto the DROP).
---------------------------------------------------------------
Connections.HuntCharAdded = LocalPlayer.CharacterAdded:Connect(function(ch)
    if Runtime.Phase ~= "HUNT" then return end
    local st = Runtime.HuntStage
    local early = (st == "ACQUIRE" or st == "RESPAWN" or st == "PICKUP")
    if not (Runtime.HuntRespawnPending or early) then return end
    Runtime.HuntRespawnPending = false
    -- A death already produced a fresh character, so never self-kill again this cycle.
    Runtime.HuntRespawned = true
    -- Latch the DROP destination (never a player).
    local p = nil
    local drop = Runtime.HuntDropTarget
    if drop and drop.Parent then p = drop:GetPivot().Position end
    Runtime.HuntRelocPos = p or Runtime.HuntSpawnPos or Runtime.HuntPos
    Runtime.HuntRelocAt = 0
    Runtime.HuntRelocDone = false
    Runtime.HuntRelocStart = os.clock()
    Runtime.HuntStage = "RESPAWN"
    Runtime.HuntStageAt = os.clock()
    -- immediate best-effort pin; RESPAWN re-pins if the server pulls back
    task.spawn(function()
        local hrp = ch:FindFirstChild("HumanoidRootPart") or ch:WaitForChild("HumanoidRootPart", 3)
        if not hrp then return end
        if Runtime.Phase ~= "HUNT" or not Runtime.HuntRelocPos then return end
        if not Runtime.huntForceTp(Runtime.HuntRelocPos, 4, 1.5) then return end
        Runtime.HuntRelocDest = Runtime.HuntRelocPos
        Runtime.HuntRelocAt = os.clock()
        if (Runtime.HuntRelocTries or 0) == 0 then Runtime.HuntRelocTries = 1 end
    end)
end)

----------------------------------------------------------------
-- TREADMILL SESSION TRACKER
----------------------------------------------------------------
do
    local tr = ReplicatedStorage:FindFirstChild("TreadmillSessionRemote")
    if tr and tr:IsA("RemoteEvent") then
        Connections.TreadmillSession = tr.OnClientEvent:Connect(function(a1, a2)
            if type(a1) == "number" and typeof(a2) == "CFrame" then
                Runtime.OnTreadmill = true
            else
                Runtime.OnTreadmill = false
                Runtime.TreadmillEndAt = os.clock()
            end
        end)
    end
end

----------------------------------------------------------------
-- PET WEBHOOK HOOK
----------------------------------------------------------------
do
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then hookPetWebhook(bp) end
    Connections.PetWebhookBackpackWatch = LocalPlayer.ChildAdded:Connect(function(ch)
        if ch.Name == "Backpack" then hookPetWebhook(ch) end
    end)
end

----------------------------------------------------------------
-- ANTI-AFK (toggle: Config.AntiAfk)
-- Resets Roblox's idle timer AND the game's own AntiAfkController timer (its
-- tracker is reset only by Keyboard / MouseButton / Touch / Gamepad input seen on
-- UserInputService.InputBegan). Primary method = engine VirtualUser (a Roblox
-- service, executor-agnostic) which fires InputBegan as MouseButton2; fallback =
-- VirtualInputManager key event. NO native OS input (keyclick/mousemoverel) - that
-- crashed some executors (Delta force-close). Never moves the character.
----------------------------------------------------------------
do
    local AFK_KEY = Enum.KeyCode.LeftAlt
    local VIM = nil
    pcall(function() VIM = game:GetService("VirtualInputManager") end)
    local VUser = nil
    pcall(function() VUser = game:GetService("VirtualUser") end)

    local function poke()
        if not getgenv()[GAME_CONFIG.GlobalFlag] or not Config.AntiAfk then return end
        -- never disturb the player while they are typing
        if UserInputService:GetFocusedTextBox() then return end
        -- 1) engine VirtualUser click -> InputBegan (MouseButton2), resets the game timer
        if VUser then
            pcall(function()
                VUser:CaptureController()
                VUser:ClickButton2(Vector2.new(0, 0))
            end)
        end
        -- 2) engine key event fallback (safe on every executor; works on Real)
        if VIM then
            pcall(function()
                VIM:SendKeyEvent(true, AFK_KEY, false, game)
                VIM:SendKeyEvent(false, AFK_KEY, false, game)
            end)
        end
    end
    getgenv().__bsAntiAfkPoke = poke
    -- safe capability report (never invokes input) - run on Delta to see what exists
    getgenv().__bsAntiAfkCapabilities = function()
        local ex = "?"
        if identifyexecutor then
            local ok, n = pcall(identifyexecutor)
            if ok and n then ex = tostring(n) end
        end
        return {
            VirtualUser = VUser ~= nil,
            VirtualInputManager = VIM ~= nil,
            executor = ex,
        }
    end

    -- safety net: poke the instant Roblox flags us idle
    Connections.AntiAfkIdled = LocalPlayer.Idled:Connect(poke)

    task.spawn(function()
        while getgenv()[GAME_CONFIG.GlobalFlag] do
            task.wait(60 + math.random() * 30)   -- 60-90s, well under the 1080s cap
            if not getgenv()[GAME_CONFIG.GlobalFlag] then break end
            poke()
        end
    end)
end

----------------------------------------------------------------
-- FPS BOOST (Settings tab)
-- Two toggles, ported from the BigFroot "Ultra FPS Boost" + "No Effects":
--   Ultra FPS Boost : drop Rendering quality, kill shadows/atmosphere/terrain and
--                     strip textures/particles/shadows off every part. One batched
--                     initial pass + a DescendantAdded hook (NOT a 6s full sweep,
--                     which is what lagged before).
--   No Effects      : stop the game's visual-only client loops (particle / VFX /
--                     burst / flash / music controllers) so those per-frame jobs
--                     never run, plus clear particles/beams/trails.
-- Pure client-side, fully reversible. Only affects visuals - never movement or
-- server logic.
----------------------------------------------------------------
local BoostFns = (function()
    local Lighting = game:GetService("Lighting")
    local BATCH = 250

    local B = {
        Ultra = false, NoEffects = false,
        Rendering = nil, Lighting = nil, PostFx = nil, Terrain = nil,
        Conn = nil, LoopConns = {},
        Eff = setmetatable({}, { __mode = "k" }),     -- particle/beam/trail/...
        Deco = setmetatable({}, { __mode = "k" }),    -- decal/texture
        Hl = setmetatable({}, { __mode = "k" }),      -- highlight
        Lt = setmetatable({}, { __mode = "k" }),      -- light
        Part = setmetatable({}, { __mode = "k" }),    -- basepart
    }

    local function alive()
        return getgenv()[GAME_CONFIG.GlobalFlag] == true
    end

    local function wantEffects()
        return (B.Ultra or B.NoEffects) and alive()
    end

    -- ---------- core visual strip ----------
    local function stripOne(d)
        if not alive() then return end
        local cls = d.ClassName
        if cls == "ParticleEmitter" or cls == "Beam" or cls == "Trail"
            or cls == "Smoke" or cls == "Fire" or cls == "Sparkles" then
            if wantEffects() then
                if not B.Eff[d] then B.Eff[d] = { Enabled = d.Enabled } end
                pcall(function() d.Enabled = false end)
                if cls == "ParticleEmitter" then
                    pcall(function() d.Lifetime = NumberRange.new(0) end)
                end
            end
            return
        end
        if not (B.Ultra and alive()) then return end
        if cls == "Decal" or cls == "Texture" then
            if not B.Deco[d] then B.Deco[d] = { Transparency = d.Transparency } end
            pcall(function() d.Transparency = 1 end)
        elseif cls == "Explosion" then
            pcall(function() d.Visible = false end)
        elseif cls == "Highlight" then
            if d.Name ~= "EspHighlight" and d.Name ~= "BigFrootEsp" then
                if not B.Hl[d] then B.Hl[d] = { Enabled = d.Enabled } end
                pcall(function() d.Enabled = false end)
            end
        elseif cls == "Light" then
            if not B.Lt[d] then B.Lt[d] = { Enabled = d.Enabled } end
            pcall(function() d.Enabled = false end)
        elseif d:IsA("BasePart") then
            if not B.Part[d] then
                local okT, tid = pcall(function() return d.TextureID end)
                B.Part[d] = {
                    Color = d.Color, Material = d.Material, Reflectance = d.Reflectance,
                    CastShadow = d.CastShadow, TextureID = okT and tid or nil,
                }
            end
            pcall(function() d.CastShadow = false end)
            if cls == "MeshPart" then pcall(function() d.TextureID = "" end) end
            if d.Anchored then
                pcall(function() d.Material = Enum.Material.SmoothPlastic end)
                pcall(function() d.Reflectance = 0 end)
            end
        end
    end

    local function stripPass()
        local n = 0
        for _, d in ipairs(Workspace:GetDescendants()) do
            if not (B.Ultra or B.NoEffects) or not alive() then return end
            stripOne(d)
            n = n + 1
            if n % BATCH == 0 then task.wait() end
        end
    end

    local function ensureConn()
        if B.Conn then return end
        B.Conn = Workspace.DescendantAdded:Connect(function(d)
            pcall(stripOne, d)
        end)
    end

    local function dropConnIfIdle()
        if not (B.Ultra or B.NoEffects) and B.Conn then
            pcall(function() B.Conn:Disconnect() end)
            B.Conn = nil
        end
    end

    local function restoreEff()
        if B.Ultra or B.NoEffects then return end
        for inst, o in pairs(B.Eff) do
            pcall(function() if inst.Parent then inst.Enabled = o.Enabled end end)
        end
        table.clear(B.Eff)
    end

    local function restoreUltra()
        for inst, o in pairs(B.Deco) do
            pcall(function() if inst.Parent then inst.Transparency = o.Transparency end end)
        end
        table.clear(B.Deco)
        for inst, o in pairs(B.Hl) do
            pcall(function() if inst.Parent then inst.Enabled = o.Enabled end end)
        end
        table.clear(B.Hl)
        for inst, o in pairs(B.Lt) do
            pcall(function() if inst.Parent then inst.Enabled = o.Enabled end end)
        end
        table.clear(B.Lt)
        for inst, o in pairs(B.Part) do
            pcall(function()
                if inst.Parent then
                    inst.Color = o.Color; inst.Material = o.Material
                    inst.Reflectance = o.Reflectance; inst.CastShadow = o.CastShadow
                    if o.TextureID ~= nil then inst.TextureID = o.TextureID end
                end
            end)
        end
        table.clear(B.Part)
    end

    -- ---------- Ultra FPS Boost ----------
    local function applyRendering()
        if B.Rendering then return end
        local ok, s = pcall(settings)
        if not ok or s == nil then return end
        local okR, r = pcall(function() return s.Rendering end)
        if not okR or not r then return end
        local saved = { Render = r }
        pcall(function() saved.Quality = r.QualityLevel end)
        pcall(function() saved.Mesh = r.MeshPartDetailLevel end)
        B.Rendering = saved
        pcall(function() r.QualityLevel = Enum.QualityLevel.Level01 end)
        pcall(function() r.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level04 end)
    end

    local function unapplyRendering()
        if not B.Rendering then return end
        local s = B.Rendering
        if s.Quality then pcall(function() s.Render.QualityLevel = s.Quality end) end
        if s.Mesh then pcall(function() s.Render.MeshPartDetailLevel = s.Mesh end) end
        B.Rendering = nil
    end

    local function applyLighting()
        if not B.Lighting then
            B.Lighting = { GlobalShadows = Lighting.GlobalShadows, FogEnd = Lighting.FogEnd }
        end
        pcall(function() Lighting.GlobalShadows = false end)
        pcall(function() Lighting.FogEnd = 9e9 end)
        if not B.PostFx then
            B.PostFx = {}
            for _, e in ipairs(Lighting:GetChildren()) do
                if e:IsA("PostEffect") or e:IsA("Clouds") then
                    B.PostFx[e] = { prop = "Enabled", val = e.Enabled }
                elseif e:IsA("Atmosphere") then
                    B.PostFx[e] = { prop = "Density", val = e.Density }
                end
            end
        end
        for e in pairs(B.PostFx) do
            pcall(function()
                if e:IsA("Atmosphere") then e.Density = 0 else e.Enabled = false end
            end)
        end
    end

    local function unapplyLighting()
        if B.Lighting then
            pcall(function()
                Lighting.GlobalShadows = B.Lighting.GlobalShadows
                Lighting.FogEnd = B.Lighting.FogEnd
            end)
            B.Lighting = nil
        end
        if B.PostFx then
            for e, o in pairs(B.PostFx) do
                pcall(function() if e.Parent then e[o.prop] = o.val end end)
            end
            B.PostFx = nil
        end
    end

    local function applyTerrain()
        local t = Workspace:FindFirstChildOfClass("Terrain")
        if not t then return end
        if not B.Terrain then
            local saved = { Inst = t }
            pcall(function() saved.Decoration = t.Decoration end)
            pcall(function() saved.WaveSize = t.WaterWaveSize end)
            pcall(function() saved.WaveSpeed = t.WaterWaveSpeed end)
            pcall(function() saved.Reflect = t.WaterReflectance end)
            B.Terrain = saved
        end
        pcall(function() t.Decoration = false end)
        pcall(function() t.WaterWaveSize = 0 end)
        pcall(function() t.WaterWaveSpeed = 0 end)
        pcall(function() t.WaterReflectance = 0 end)
    end

    local function unapplyTerrain()
        if not B.Terrain then return end
        local o = B.Terrain; B.Terrain = nil
        if not (o.Inst and o.Inst.Parent) then return end
        if o.Decoration ~= nil then pcall(function() o.Inst.Decoration = o.Decoration end) end
        if o.WaveSize ~= nil then pcall(function() o.Inst.WaterWaveSize = o.WaveSize end) end
        if o.WaveSpeed ~= nil then pcall(function() o.Inst.WaterWaveSpeed = o.WaveSpeed end) end
        if o.Reflect ~= nil then pcall(function() o.Inst.WaterReflectance = o.Reflect end) end
    end

    local function ultraOn()
        B.Ultra = true
        applyRendering(); applyLighting(); applyTerrain()
        ensureConn()
        task.spawn(stripPass)
    end

    local function ultraOff()
        B.Ultra = false
        restoreUltra(); restoreEff()
        unapplyLighting(); unapplyTerrain(); unapplyRendering()
        dropConnIfIdle()
    end

    -- ---------- No Effects (aggressive) ----------
    local VISUAL = {
        -- Client.Controllers
        EggEffects = true, MergeEggVFX = true, MergeRevealFX = true, MergeSfx = true,
        MergeEggHatch = true, MergeOutcomeDisplay = true, RewardFlashController = true,
        GuardChaseVisualsController = true, EggLocalHits = true,
        EggDamagePopupController = true, EggDebris = true, EggGemDropController = true,
        EggTypeAnimController = true, AnimalAnimationController = true,
        AnimalPlaceVFXController = true, AnimalCashPopupController = true,
        ConfettiController = true, FloatingIconController = true,
        ChaseAlertController = true, MusicController = true, GuardFootstepController = true,
        GuardIdleSfxController = true, GuardRoarController = true, AffordabilityFX = true,
        FrameFocusFXController = true, RarityGradientAnimationController = true,
        ShineTextController = true, SpinIconController = true, StatusAuraController = true,
        WeatherSkyController = true, WitchAnimController = true, TitanicEventController = true,
        HeldToolVisualsController = true, BatTargetHighlight = true, PurchaseOverlay = true,
        AdminAbuseFXController = true, NewItemController = true,
        ShopFeaturedAnimController = true, ShopBadgeController = true, ShopRendersController = true,
        -- Client.Modules
        VFXBurst = true, EggRarityBurst = true, FloatingIconFX = true, ShopCloseFx = true,
        EggPlaceBurst = true, EggLandImpact = true, BackpackSlotVisuals = true,
        NewItemTweens = true, GuiFade = true, StrokePulse = true, SpriteSheet = true,
        MasteryLevelUpFX = true, CameraShaker = true, EventLighting = true,
        LightningBolt = true, CinematicMode = true, BazookaMuzzle = true,
        BinaryTransition = true,
    }

    local function connModule(c)
        local f = c.Function
        if type(f) ~= "function" then return nil end
        local ok, src = pcall(debug.info, f, "s")
        if not ok or type(src) ~= "string" or src == "" then return nil end
        return src:match("%.([%w_]+)$")
    end

    local function loopsOn()
        if #B.LoopConns > 0 then return end
        if type(getconnections) ~= "function" then return end
        for _, sig in ipairs({ RunService.Heartbeat, RunService.RenderStepped, RunService.Stepped }) do
            local ok, conns = pcall(getconnections, sig)
            if ok and type(conns) == "table" then
                for _, c in ipairs(conns) do
                    local name = connModule(c)
                    if name and VISUAL[name] then
                        local done = false
                        if type(c.Disable) == "function" then
                            done = pcall(c.Disable, c)
                        elseif c.Enabled ~= nil then
                            c.Enabled = false; done = true
                        end
                        if done then table.insert(B.LoopConns, c) end
                    end
                end
            end
        end
    end

    local function loopsOff()
        for _, c in ipairs(B.LoopConns) do
            pcall(function()
                if type(c.Enable) == "function" then c.Enable(c)
                elseif c.Enabled ~= nil then c.Enabled = true end
            end)
        end
        table.clear(B.LoopConns)
    end

    local function effectsOn()
        B.NoEffects = true
        ensureConn()
        loopsOn()
        task.spawn(stripPass)
    end

    local function effectsOff()
        B.NoEffects = false
        loopsOff()
        restoreEff()
        dropConnIfIdle()
    end

    return {
        Ultra = function(enable)
            Config.BoostUltra = enable
            if enable then ultraOn() else ultraOff() end
        end,
        NoEffects = function(enable)
            Config.BoostNoEffects = enable
            if enable then effectsOn() else effectsOff() end
        end,
    }
end)()

getgenv().__bsBoostCleanup = function()
    pcall(function() BoostFns.Ultra(false) end)
    pcall(function() BoostFns.NoEffects(false) end)
end

----------------------------------------------------------------
-- NO CLIP (Misc tab)
-- Passive CanCollide loop. No CFrame/teleport, no speed change -> it never
-- fires an anti-cheat verdict (the server only warns on speed/teleport/fly).
-- It only wins the per-frame race against ragdoll systems (CatchFlingController
-- / RagdollPhysics.StartAntiTunnelGuard) that re-enable CanCollide while
-- ragdolled. Character parts only.
----------------------------------------------------------------
do
    local NoClipConn = nil
    local NoClipCharConn = nil
    local savedCollide = setmetatable({}, { __mode = "k" })

    local function noclipChar()
        local c = LocalPlayer.Character
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then
                if savedCollide[p] == nil then savedCollide[p] = p.CanCollide end
                if p.CanCollide then p.CanCollide = false end
            end
        end
    end

    local function noclipApply()
        if not getgenv()[GAME_CONFIG.GlobalFlag] then return end
        noclipChar()
    end

    local function setNoClip(on)
        Config.NoClip = on and true or false
        if on then
            noclipChar()
            if not NoClipConn then
                NoClipConn = RunService.Stepped:Connect(noclipApply)
            end
            if not NoClipCharConn then
                NoClipCharConn = LocalPlayer.CharacterAdded:Connect(function()
                    task.defer(noclipChar)
                end)
            end
        else
            if NoClipConn then
                pcall(function() NoClipConn:Disconnect() end)
                NoClipConn = nil
            end
            if NoClipCharConn then
                pcall(function() NoClipCharConn:Disconnect() end)
                NoClipCharConn = nil
            end
            for p, v in pairs(savedCollide) do
                pcall(function() if p.Parent then p.CanCollide = v end end)
            end
            table.clear(savedCollide)
        end
    end

    getgenv().__bsNoClip = setNoClip
    if Config.NoClip then setNoClip(true) end
end


        ------------------------------------------------------------------
        -- SERAHKAN LOGIC FPS BOOST KE TEMPLATE (toggle di tab Settings)
        ------------------------------------------------------------------
        ctx.boost.Ultra     = BoostFns.Ultra
        ctx.boost.NoEffects = BoostFns.NoEffects

        -- Export yang dipakai onCreateTabs / onUpdateStats / onWebhookFilters.
        G.Runtime          = Runtime
        G.formatShort      = formatShort
        G.sendPetWebhook   = sendPetWebhook
        G.plotSpot         = plotSpot
        G.backpackPetCount = backpackPetCount
    end)()

    --------------------------------------------------------------------------
    -- Export di scope onInit (didefinisikan di luar IIFE body).
    --------------------------------------------------------------------------
    G.ZONE_NAMES        = ZONE_NAMES
    G.EGG_TYPE_VALUES   = EGG_TYPE_VALUES
    G.PET_RARITY_VALUES = PET_RARITY_VALUES
    G.PET_FILTER_VALUES = PET_FILTER_VALUES
    G.RARITIES          = RARITIES
    G.RARITIES_DESC     = RARITIES_DESC
    G.Config            = Config

    -- Parser income (dipakai input "Minimum Income" dan saat config di-apply).
    -- Dipindahkan dari config manager lama yang sekarang ditangani template.
    Runtime.parseIncome = function(txt)
        if type(txt) == "number" then return math.max(0, txt) end
        local s = tostring(txt or ""):lower():gsub("[%s,]", "")
        if s == "" then return 0 end
        local num, suf = s:match("^(%d*%.?%d+)([kmbt]?)$")
        local n
        if num then n = tonumber(num) else n = tonumber((s:gsub("[^%d%.]", ""))) end
        if not n then return 0 end
        local mult = 1
        if suf == "k" then mult = 1e3
        elseif suf == "m" then mult = 1e6
        elseif suf == "b" then mult = 1e9
        elseif suf == "t" then mult = 1e12 end
        return math.max(0, n * mult)
    end
    end,  -- end onInit

    --------------------------------------------------------------------------
    -- onCreateTabs: tab khusus game. Template menambahkan Overview sebelum ini,
    -- lalu Misc/Webhook/Configs/Settings setelah ini.
    --------------------------------------------------------------------------
    onCreateTabs = function(ctx)
        local Window            = ctx.Window
        local UIElements        = ctx.UIElements
        local Config            = ctx.Config
        local WindUI            = ctx.WindUI
        local HttpService       = ctx.HttpService
        local LocalPlayer       = ctx.LocalPlayer
        local ReplicatedStorage = ctx.ReplicatedStorage
        local GAME_CONFIG       = ctx.GAME_CONFIG

        -- Re-export dari G (callback tab beda scope dengan onInit).
        local Runtime           = G.Runtime
        local ZONE_NAMES        = G.ZONE_NAMES
        local EGG_TYPE_VALUES   = G.EGG_TYPE_VALUES
        local PET_RARITY_VALUES = G.PET_RARITY_VALUES
        local PET_FILTER_VALUES = G.PET_FILTER_VALUES
        local RARITIES          = G.RARITIES
        local RARITIES_DESC     = G.RARITIES_DESC
        local formatShort       = G.formatShort

        local function setUIElementValue(el, val)
            ctx.setUIElementVisual(el, val)
        end

----------------------------------------------------------------
-- TAB: AUTO BREAK (pipeline: TP egg -> break -> pickup -> base)
----------------------------------------------------------------
local TabAutoSteal = Window:Tab({ Title = "Auto Farm", Icon = "zap" })
TabAutoSteal:Section({ Title = "Auto Break", Icon = "zap" })
UIElements.AutoSteal = TabAutoSteal:Toggle({
    Title = "Auto Break",
    Desc = "Auto break eggs and collect pets.",
    Value = Config.AutoSteal,
    Callback = function(v)
        Config.AutoSteal = v
        if not v then Runtime.autoSwing(false) end
        -- Reset the far-zone decoy so toggling Auto Break off/on starts over from
        -- the Zone 1 entry (break+pickup+hitguard) instead of a direct TP.
        Runtime.DecoyStage = nil
        Runtime.DecoyDoneZone = nil
        Runtime.DecoyEgg = nil
        Runtime.DecoyPick = nil
        Runtime.DecoyPulled = false
        Runtime.MetaWalkEntry = false
        Runtime.BankStage = nil
        Runtime.BankPick = nil
        Runtime.BankWant = nil
        Runtime.MetaStage = nil
        Runtime.Phase = "IDLE"
        if Runtime.syncWalkNoClip then Runtime.syncWalkNoClip() end
    end,
})
UIElements.AutoStealMinIncome = TabAutoSteal:Input({
    Title = "Minimum Income",
    Desc = "Minimum income ($/s) to collect. Accepts 900m, 1.5B, 200k, 10k or a plain number.",
    Value = tostring(Config.AutoStealMinIncome or 0),
    Placeholder = "contoh: 900m",
    ClearTextOnFocus = false,
    Callback = function(txt)
        local v = Runtime.parseIncome(txt)
        Config.AutoStealMinIncome = v
        pcall(function()
            WindUI:Notify({ Title = "Minimum Income", Content = "= $" .. formatShort(v) .. "/s", Duration = 2 })
        end)
    end,
})
UIElements.EggFilter = TabAutoSteal:Dropdown({
    Title = "Filter Zone",
    Desc = "Pick a target zone.",
    Values = ZONE_NAMES,
    Value = Config.EggFilter,
    Default = Config.EggFilter,
    Callback = function(v) Config.EggFilter = v end,
})
UIElements.PetRarityFilter = TabAutoSteal:Dropdown({
    Title = "Filter by Rarity",
    Desc = "Only collect these rarities. Empty = all.",
    Values = PET_RARITY_VALUES,
    Value = {},
    Default = {},
    Multi = true,
    AllowNone = true,
    SearchBarEnabled = true,
    Callback = function(selected)
        local set = {}
        if type(selected) == "table" then
            for k, v in pairs(selected) do
                local r = (type(v) == "string" and v) or (type(k) == "string" and k) or nil
                if r then set[r] = true end
            end
        elseif type(selected) == "string" then
            set[selected] = true
        end
        Config.PetRarityFilter = set
    end,
})
UIElements.EggPriority = TabAutoSteal:Dropdown({
    Title = "Egg Priority",
    Desc = "Which egg to target when several are in range.",
    Values = { "Fastest Break", "Nearest", "Best Luck", "Biggest Size" },
    Value = Config.EggPriority,
    Default = Config.EggPriority,
    Callback = function(v) Config.EggPriority = v end,
})
UIElements.EggType = TabAutoSteal:Dropdown({
    Title = "Egg Type",
    Desc = "Only break these egg types. None selected = all types.",
    Values = EGG_TYPE_VALUES,
    Value = {},
    Default = {},
    Multi = true,
    AllowNone = true,
    SearchBarEnabled = true,
    Callback = function(selected)
        local set = {}
        if type(selected) == "table" then
            for k, v in pairs(selected) do
                local name = (type(v) == "string" and v) or (type(k) == "string" and k) or nil
                if name then set[name] = true end
            end
        elseif type(selected) == "string" then
            set[selected] = true
        end
        Config.EggTypeFilter = set
    end,
})
do
    -- Mutation values straight from the game's own MutationConfig: the fixed
    -- mutations plus the weather-driven ones. "None" = pets with no Mutation.
    local MUTATION_VALUES = { "None" }
    pcall(function()
        local MC = require(ReplicatedStorage.Shared.MutationConfig)
        local seen = { None = true }
        local function add(list)
            if type(list) ~= "table" then return end
            for _, m in ipairs(list) do
                local n = type(m) == "table" and m.Name or nil
                if type(n) == "string" and n ~= "" and not seen[n] then
                    seen[n] = true
                    MUTATION_VALUES[#MUTATION_VALUES + 1] = n
                end
            end
        end
        add(MC.Mutations)
        add(MC.WeatherMutations)
    end)
    UIElements.MutationFilter = TabAutoSteal:Dropdown({
        Title = "Filter by Mutation",
        Desc = "Only collect these mutations. Empty = all.",
        Values = MUTATION_VALUES,
        Value = {},
        Default = {},
        Multi = true,
        AllowNone = true,
        SearchBarEnabled = true,
        Callback = function(selected)
            local set = {}
            if type(selected) == "table" then
                for k, v in pairs(selected) do
                    local name = (type(v) == "string" and v) or (type(k) == "string" and k) or nil
                    if name then set[name] = true end
                end
            elseif type(selected) == "string" then
                set[selected] = true
            end
            Config.MutationFilter = set
        end,
    })
end
-- Normalize any legacy saved "TP" to "TP v2" so the dropdown always shows a valid item.
if Config.MovementMode == "TP" then Config.MovementMode = "TP v2" end
UIElements.MovementMode = TabAutoSteal:Dropdown({
    Title = "Movement Mode",
    Desc = "Use Walk if your fps low, Use TP v1 if u want fast but safe, Use TP V2 if u want instant",
    Values = { "TP v1", "TP v2", "Walk" },
    Value = Config.MovementMode,
    Default = Config.MovementMode,
    Callback = function(v)
        Config.MovementMode = v
        if v == "Walk" then
            -- Walk is the Auto Break engine; Auto Steal (Drop) belongs to TP.
            if Config.AutoStealPlayer then
                Config.AutoStealPlayer = false
                setUIElementValue(UIElements.AutoStealPlayer, false)
            end
        end
        if Runtime.syncWalkNoClip then Runtime.syncWalkNoClip() end
    end,
})
UIElements.AutoTitanicEgg = TabAutoSteal:Toggle({
    Title = "Auto Titanic Egg",
    Desc = "On = prioritize the Titanic Egg wherever it spawns. Off = fully ignore it.",
    Value = Config.AutoTitanicEgg,
    Callback = function(v) Config.AutoTitanicEgg = v end,
})
UIElements.AutoStealPlayer = TabAutoSteal:Toggle({
    Title = "Auto Steal (Drop)",
    Desc = "Auto steal pets dropped on the ground (no player chasing).",
    Value = Config.AutoStealPlayer,
    Callback = function(v)
        Config.AutoStealPlayer = v
        if not v then Runtime.autoSwing(false) end
    end,
})
TabAutoSteal:Section({ Title = "Help Other Player", Icon = "hand-heart" })
UIElements.HelpOtherPlayer = TabAutoSteal:Toggle({
    Title = "Help Other Player",
    Desc = "Auto Break drops the pet at the help spot (for another player) instead of banking it in the SafeZone.",
    Value = Config.HelpOtherPlayer,
    Callback = function(v) Config.HelpOtherPlayer = v end,
})
TabAutoSteal:Section({ Title = "Index", Icon = "clipboard-list" })
UIElements.AutoCompleteIndex = TabAutoSteal:Toggle({
    Title = "Auto Complete Index",
    Desc = "Farm the lowest zone still missing Index pets, collecting only those pets. Needs Auto Break ON.",
    Value = Config.AutoCompleteIndex,
    Callback = function(v) Config.AutoCompleteIndex = v end,
})
local indexStatusPar = TabAutoSteal:Paragraph({
    Title = "Index Status",
    Desc = "Idle.",
})
task.spawn(function()
    while getgenv()[GAME_CONFIG.GlobalFlag] do
        task.wait(0.5)
        if indexStatusPar then
            local z = Runtime.IndexZone
            local c = Runtime.IndexMissingCount
            pcall(function()
                if Config.AutoCompleteIndex and Runtime.IndexWaiting then
                    indexStatusPar:SetDesc("Waiting for Index state (zone filter ignored)...")
                elseif Config.AutoCompleteIndex and z then
                    indexStatusPar:SetDesc(("Target: Zone%d | Missing: %s pet"):format(z, tostring(c)))
                else
                    indexStatusPar:SetDesc("Idle (all Index complete, or feature off).")
                end
            end)
        end
    end
end)
----------------------------------------------------------------
-- TAB: UPGRADE
----------------------------------------------------------------
local TabUpgrade = Window:Tab({ Title = "Upgrade", Icon = "trending-up" })
TabUpgrade:Section({ Title = "Auto Upgrade", Icon = "trending-up" })
UIElements.AutoUpgradePickaxe = TabUpgrade:Toggle({
    Title = "Auto Upgrade Pickaxe",
    Desc = "Auto buy the next pickaxe tier with cash.",
    Value = Config.AutoUpgradePickaxe,
    Callback = function(v) Config.AutoUpgradePickaxe = v end,
})
do
    -- Values come from the game's own PickaxeConfig.Tiers (ascending tier order).
    local PICKAXE_VALUES = {}
    pcall(function()
        local PC = require(ReplicatedStorage.Shared.PickaxeConfig)
        for _, t in ipairs((PC and PC.Tiers) or {}) do
            local n = (type(t) == "table" and t.Name) or nil
            if type(n) == "string" and n ~= "" then
                PICKAXE_VALUES[#PICKAXE_VALUES + 1] = n
            end
        end
    end)
    UIElements.PickaxeUpgradeFilter = TabUpgrade:Dropdown({
        Title = "Filter Pickaxe Upgrade",
        Desc = "Only buy the pickaxes you select here. Empty = do not upgrade.",
        Values = PICKAXE_VALUES,
        Value = {},
        Default = {},
        Multi = true,
        AllowNone = true,
        SearchBarEnabled = true,
        Callback = function(selected)
            local set = {}
            if type(selected) == "table" then
                for k, v in pairs(selected) do
                    local name = (type(v) == "string" and v) or (type(k) == "string" and k) or nil
                    if name then set[name] = true end
                end
            elseif type(selected) == "string" then
                set[selected] = true
            end
            Config.PickaxeUpgradeFilter = set
        end,
    })
end
UIElements.AutoUpgradeTreadmill = TabUpgrade:Toggle({
    Title = "Auto Upgrade Treadmill",
    Desc = "Auto upgrade the treadmill with cash.",
    Value = Config.AutoUpgradeTreadmill,
    Callback = function(v) Config.AutoUpgradeTreadmill = v end,
})
UIElements.AutoUnlockTreadmill = TabUpgrade:Toggle({
    Title = "Auto Unlock Treadmill",
    Desc = "Unlock the treadmill first if locked.",
    Value = Config.AutoUnlockTreadmill,
    Callback = function(v) Config.AutoUnlockTreadmill = v end,
})
UIElements.AutoUpgradePlot = TabUpgrade:Toggle({
    Title = "Auto Upgrade Plot",
    Desc = "Auto upgrade the plot with cash.",
    Value = Config.AutoUpgradePlot,
    Callback = function(v) Config.AutoUpgradePlot = v end,
})
UIElements.AutoUpgradeTrail = TabUpgrade:Toggle({
    Title = "Auto Upgrade Trail",
    Desc = "Auto buy the next trail you can afford with cash.",
    Value = Config.AutoUpgradeTrail,
    Callback = function(v) Config.AutoUpgradeTrail = v end,
})

----------------------------------------------------------------
-- TAB: EGG
----------------------------------------------------------------
local TabEgg = Window:Tab({ Title = "Egg", Icon = "egg" })

TabEgg:Section({ Title = "Pet", Icon = "paw-print" })
UIElements.AutoPlaceBest = TabEgg:Toggle({
    Title = "Auto Place Best Pet",
    Desc = "Auto place your best pets on the plot.",
    Value = Config.AutoPlaceBest,
    Callback = function(v) Config.AutoPlaceBest = v end,
})

TabEgg:Section({ Title = "Sell", Icon = "coins" })
UIElements.AutoSell = TabEgg:Toggle({
    Title = "Auto Sell",
    Desc = "Auto sell backpack pets of the selected rarities.",
    Value = Config.AutoSell,
    Callback = function(v) Config.AutoSell = v end,
})
UIElements.SellRarities = TabEgg:Dropdown({
    Title = "Filter Sell Rarities",
    Desc = "Rarities to sell. Empty = sell nothing.",
    Values = RARITIES,
    Value = {},
    Default = {},
    Multi = true,
    AllowNone = true,
    Callback = function(selected)
        local set = {}
        if type(selected) == "table" then
            for k, v in pairs(selected) do
                local name = (type(v) == "string" and v) or (type(k) == "string" and k) or nil
                if name then set[name] = true end
            end
        elseif type(selected) == "string" then
            set[selected] = true
        end
        Config.SellRarities = set
    end,
})
UIElements.SellInterval = TabEgg:Slider({
    Title = "Sell Interval",
    Desc = "Seconds per sell.",
    Value = { Min = 2, Max = 30, Default = Config.SellInterval },
    Step = 1,
    Callback = function(v) Config.SellInterval = v end,
})

TabEgg:Section({ Title = "Merge", Icon = "git-merge" })
UIElements.AutoMerge = TabEgg:Toggle({
    Title = "Auto Merge",
    Desc = "Auto merge 3 identical pets from the backpack.",
    Value = Config.AutoMerge,
    Callback = function(v) Config.AutoMerge = v end,
})
UIElements.MergeRarities = TabEgg:Dropdown({
    Title = "Filter Merge Rarities",
    Desc = "Rarities to merge. Empty = all.",
    Values = RARITIES,
    Value = {},
    Default = {},
    Multi = true,
    AllowNone = true,
    Callback = function(selected)
        local set = {}
        if type(selected) == "table" then
            for k, v in pairs(selected) do
                local name = (type(v) == "string" and v) or (type(k) == "string" and k) or nil
                if name then set[name] = true end
            end
        elseif type(selected) == "string" then
            set[selected] = true
        end
        Config.MergeRarities = set
    end,
})
UIElements.AutoHatch = TabEgg:Toggle({
    Title = "Auto Hatch Ready",
    Desc = "Auto collect eggs that are ready.",
    Value = Config.AutoHatch,
    Callback = function(v) Config.AutoHatch = v end,
})
TabEgg:Section({ Title = "Fuse", Icon = "atom" })
UIElements.AutoFuse = TabEgg:Toggle({
    Title = "Auto Fuse",
    Desc = "Auto deposit the recipe pets and fire the Fuse Machine remotely (Zone 10). No walking.",
    Value = Config.AutoFuse,
    Callback = function(v) Config.AutoFuse = v end,
})
local fuseStatusPar = TabEgg:Paragraph({
    Title = "Fuse Status",
    Desc = "Idle.",
})
task.spawn(function()
    while getgenv()[GAME_CONFIG.GlobalFlag] do
        task.wait(0.5)
        if fuseStatusPar then
            local rec = Runtime.FuseRecipe
            local dep = Runtime.FuseDeposits
            local recStr = "-"
            local depCount = 0
            if rec then
                local rl = {}
                for _, n in pairs(rec) do rl[#rl + 1] = n end
                table.sort(rl)
                recStr = (#rl > 0) and table.concat(rl, ", ") or "-"
            end
            if dep then for _ in pairs(dep) do depCount = depCount + 1 end end
            local lock = (Runtime.fuseHasSpeed and Runtime.fuseHasSpeed()) and "Unlocked" or "Locked (need 1e11 Speed)"
            pcall(function()
                fuseStatusPar:SetDesc(("Recipe: %s\nDeposited: %s | Fused: %s\nStatus: %s"):format(
                    recStr, tostring(depCount), tostring(Runtime.FuseCount or 0), lock))
            end)
        end
    end
end)
TabEgg:Section({ Title = "Plant Egg", Icon = "sprout" })
UIElements.AutoPlantEgg = TabEgg:Toggle({
    Title = "Auto Plant Egg",
    Desc = "Auto plant eggs from the backpack onto your plot.",
    Value = Config.AutoPlantEgg,
    Callback = function(v) Config.AutoPlantEgg = v end,
})
UIElements.PlantRarities = TabEgg:Dropdown({
    Title = "Filter Rarity (Egg)",
    Desc = "Rarities of eggs to plant. Empty = all.",
    Values = RARITIES_DESC,
    Value = {},
    Default = {},
    Multi = true,
    AllowNone = true,
    Callback = function(selected)
        local set = {}
        if type(selected) == "table" then
            for k, v in pairs(selected) do
                local name = (type(v) == "string" and v) or (type(k) == "string" and k) or nil
                if name then set[name] = true end
            end
        elseif type(selected) == "string" then
            set[selected] = true
        end
        Config.PlantRarities = set
    end,
})

----------------------------------------------------------------
-- TAB: EVENT
----------------------------------------------------------------
do
local TabEvent = Window:Tab({ Title = "Event", Icon = "ghost" })
TabEvent:Section({ Title = "Diamond Shop", Icon = "gem" })

local skinIds = {}
local skinLabels = {}
pcall(function()
    local PC = require(ReplicatedStorage.Shared.PlotSkinConfig)
    for id, s in pairs(PC.Skins or {}) do
        if type(s.Name) == "string" then
            skinIds[s.Name] = id
            skinLabels[#skinLabels + 1] = s.Name
        end
    end
end)
table.sort(skinLabels)

UIElements.AutoDiamondMounted = TabEvent:Toggle({
    Title = "Auto Buy Mounted Egg",
    Desc = "Buy Mounted Eggs with Diamonds using the selected bundle sizes.",
    Value = Config.AutoDiamondMounted,
    Callback = function(v) Config.AutoDiamondMounted = v end,
})
UIElements.DiamondMountedAmounts = TabEvent:Dropdown({
    Title = "Mounted Amount",
    Desc = "Bundle size to buy. Empty = buy nothing.",
    Values = { "x1", "x3", "x8" },
    Value = {},
    Default = {},
    Multi = true,
    AllowNone = true,
    Callback = function(selected)
        local set = {}
        if type(selected) == "table" then
            for k, v in pairs(selected) do
                local label = (type(v) == "string" and v) or (type(k) == "string" and k) or nil
                local n = label and label:match("^x?(%d+)$")
                if n then set["x" .. n] = true end
            end
        elseif type(selected) == "string" then
            local n = selected:match("^x?(%d+)$")
            if n then set["x" .. n] = true end
        end
        Config.DiamondMountedAmounts = set
    end,
})
UIElements.AutoDiamondPlotSkin = TabEvent:Toggle({
    Title = "Auto Buy Plot Skin",
    Desc = "Buy the selected Plot Skins with Diamonds, then equip them automatically.",
    Value = Config.AutoDiamondPlotSkin,
    Callback = function(v) Config.AutoDiamondPlotSkin = v end,
})
UIElements.DiamondPlotSkinFilter = TabEvent:Dropdown({
    Title = "Plot Skin",
    Desc = "Choose which Plot Skins to buy. Empty = buy nothing.",
    Values = skinLabels,
    Value = {},
    Default = {},
    Multi = true,
    AllowNone = true,
    SearchBarEnabled = true,
    Callback = function(selected)
        local set = {}
        if type(selected) == "table" then
            for k, v in pairs(selected) do
                local label = (type(v) == "string" and v) or (type(k) == "string" and k) or nil
                if label and skinIds[label] then set[label] = true end
            end
        elseif type(selected) == "string" then
            if skinIds[selected] then set[selected] = true end
        end
        Config.DiamondPlotSkinFilter = set
    end,
})
local diamondStatusPar = TabEvent:Paragraph({
    Title = "Diamond Shop Status",
    Desc = "Idle.",
})
task.spawn(function()
    while getgenv()[GAME_CONFIG.GlobalFlag] do
        task.wait(0.5)
        if diamondStatusPar then
            local s = getgenv().__bsDiamondShop and getgenv().__bsDiamondShop() or {}
            pcall(function()
                diamondStatusPar:SetDesc(("Diamonds: %s | Mounted bought: %s\nOwned skins: %s | Equipped: %s\nLast: %s%s"):format(
                    tostring(s.Diamonds or 0),
                    tostring(s.MountedBought or 0),
                    tostring(s.OwnedSkins or 0),
                    tostring(s.Equipped or "-"),
                    tostring(s.LastAction or "-"),
                    s.LastError and ("\nError: " .. tostring(s.LastError)) or ""
                ))
            end)
        end
    end
end)
end

----------------------------------------------------------------
-- TAB: MISC
----------------------------------------------------------------
local TabMisc = Window:Tab({ Title = "Utility", Icon = "wrench" })
TabMisc:Section({ Title = "Treadmill", Icon = "gauge" })
UIElements.AutoTreadmill = TabMisc:Toggle({
    Title = "Auto Treadmill",
    Desc = "Auto use your treadmill to gain Speed while idle.",
    Value = Config.AutoTreadmill,
    Callback = function(v) Config.AutoTreadmill = v end,
})
TabMisc:Section({ Title = "Combat", Icon = "shield" })
UIElements.AntiKnockback = TabMisc:Toggle({
    Title = "Anti Knockback",
    Desc = "Reduce knockback/ragdoll from bats and guards.",
    Value = Config.AntiKnockback,
    Callback = function(v) Config.AntiKnockback = v end,
})
UIElements.AntiAfk = TabMisc:Toggle({
    Title = "Anti AFK",
    Desc = "Stop you being flagged idle (VirtualUser click). Turn OFF to test if it is the crash cause.",
    Value = Config.AntiAfk,
    Callback = function(v) Config.AntiAfk = v end,
})
TabMisc:Section({ Title = "Movement", Icon = "move" })
UIElements.NoClip = TabMisc:Toggle({
    Title = "No Clip",
    Desc = "Walk through walls. Turn OFF when standing still (you may fall through the floor).",
    Value = Config.NoClip,
    Callback = function(v)
        Config.NoClip = v
        local f = getgenv().__bsNoClip
        if f then f(v) end
    end,
})
TabMisc:Section({ Title = "Index", Icon = "list" })
UIElements.AutoClaimIndex = TabMisc:Toggle({
    Title = "Auto Claim Index",
    Desc = "Auto claim all available Index rewards (fires the game's Claim All when ready).",
    Value = Config.AutoClaimIndex,
    Callback = function(v) Config.AutoClaimIndex = v end,
})


    end,  -- end onCreateTabs

    --------------------------------------------------------------------------
    -- onExport: buang nilai non-JSON (Vector3 posisi yang di-hardcode) dari
    -- salinan data yang disimpan. Tanpa ini JSONEncode gagal karena Vector3
    -- bukan tipe JSON. Config live TIDAK diubah (hanya salinan export).
    --------------------------------------------------------------------------
    onExport = function(data)
        if type(data.Config) == "table" then
            local safe = {}
            for k, v in pairs(data.Config) do
                if type(v) ~= "userdata" then safe[k] = v end
            end
            data.Config = safe
        end
    end,

    --------------------------------------------------------------------------
    -- onUpdateStats: isi paragraf "Session Stats" di tab Overview (dipanggil
    -- otomatis tiap 1 detik oleh template).
    --------------------------------------------------------------------------
    onUpdateStats = function(paragraph)
        local S = G.Runtime
        if not S then return end
        local Cfg = ctx.Config
        local lp  = ctx.LocalPlayer
        pcall(function()
            local carrying = lp:GetAttribute("Carrying")
            local _, plot = G.plotSpot()
            local placed = plot and (plot:GetAttribute("AnimalsPlaced") or 0) or "-"
            local maxAnimals = plot and (plot:GetAttribute("MaxAnimals") or 8) or "-"
            paragraph:SetDesc(("Phase: %s | Zone: %s | Carry: %s\nStolen: %s | Secured: %s | Hits: %s | Bat: %s\nGuard: %s (%.0fm) | Plot: %s/%s\nMeta: %s | Loop: %s | MinInc: %s\nSnap: %s | BankBlock: %s | Settle: %.1fs | Fail: %s\nMove: %s | WalkStage: %s"):format(
                tostring(S.Phase), tostring(Cfg.EggFilter),
                carrying and tostring(carrying) or "-",
                tostring(S.Stolen or 0), tostring(S.Secured or 0), tostring(S.Hits or 0), tostring(S.BatSwings or 0),
                tostring(S.LastThreatState or "-"), tonumber(S.LastThreatDist) or 0,
                tostring(placed), tostring(maxAnimals),
                tostring(S.MetaStage or "-"), tostring(S.MetaSteals or 0), tostring(Cfg.AutoStealMinIncome or 0),
                tostring(S.SnapCount or 0), tostring(S.BankBlockCount or 0),
                tonumber(S.BankSettle) or 3.0, tostring(S.LastFailReason or "-"),
                tostring(Cfg.MovementMode or "TP v2"), tostring(S.WalkStage or "-")
            ))
        end)
    end,

    --------------------------------------------------------------------------
    -- onApply: normalisasi data yang TIDAK 1:1 dengan Config/Flags.
    -- Config/Flags biasa sudah otomatis di-apply template; di sini khusus
    -- Egg Type (key UI beda) dan Minimum Income (bisa berupa string "900m").
    --------------------------------------------------------------------------
    onApply = function(tbl, queue)
        local cfg = tbl and tbl.Config
        if type(cfg) ~= "table" then return end
        local UI = ctx.UIElements
        if cfg.EggTypeFilter ~= nil and UI.EggType then
            table.insert(queue, { element = UI.EggType, value = cfg.EggTypeFilter })
        end
        if cfg.PickaxeUpgradeFilter ~= nil and UI.PickaxeUpgradeFilter then
            table.insert(queue, { element = UI.PickaxeUpgradeFilter, value = cfg.PickaxeUpgradeFilter })
        end
        if cfg.MutationFilter ~= nil and UI.MutationFilter then
            table.insert(queue, { element = UI.MutationFilter, value = cfg.MutationFilter })
        end
        if cfg.AutoStealMinIncome ~= nil then
            local v = cfg.AutoStealMinIncome
            if G.Runtime and G.Runtime.parseIncome then v = G.Runtime.parseIncome(v) end
            ctx.Config.AutoStealMinIncome = v
            if UI.AutoStealMinIncome then
                table.insert(queue, { element = UI.AutoStealMinIncome, value = tostring(v) })
            end
        end
    end,

    --------------------------------------------------------------------------
    -- onWebhookFilters: kontrol filter webhook khusus game, ditambahkan ke tab
    -- Webhook milik template.
    --------------------------------------------------------------------------
    onWebhookFilters = function(TabWebhook, ctx)
        local Config     = ctx.Config
        local UIElements = ctx.UIElements
        local RARITIES_DESC     = G.RARITIES_DESC
        local PET_FILTER_VALUES = G.PET_FILTER_VALUES

        TabWebhook:Section({ Title = "Pet Filter", Icon = "filter" })

        UIElements.WebhookRarityFilter = TabWebhook:Dropdown({
            Title = "Filter Rarity",
            Desc = "Rarities to send. Empty = all.",
            Values = RARITIES_DESC,
            Value = {},
            Default = {},
            Multi = true,
            AllowNone = true,
            Callback = function(selected)
                local set = {}
                if type(selected) == "table" then
                    for k, v in pairs(selected) do
                        local name = (type(v) == "string" and v) or (type(k) == "string" and k) or nil
                        if name then set[name] = true end
                    end
                elseif type(selected) == "string" then
                    set[selected] = true
                end
                Config.WebhookRarityFilter = set
            end,
        })
        UIElements.WebhookNameFilter = TabWebhook:Dropdown({
            Title = "Filter by Name",
            Desc = "Pick 'All Pet' for all, or specific pet names.",
            Values = PET_FILTER_VALUES,
            Value = { "All Pet" },
            Default = { "All Pet" },
            Multi = true,
            AllowNone = true,
            SearchBarEnabled = true,
            Callback = function(selected)
                local set = {}
                local all = false
                if type(selected) == "table" then
                    for k, v in pairs(selected) do
                        local name = (type(v) == "string" and v) or (type(k) == "string" and k) or nil
                        if name == "All Pet" then all = true elseif name then set[name] = true end
                    end
                elseif selected == "All Pet" then
                    all = true
                elseif type(selected) == "string" then
                    set[selected] = true
                end
                Config.WebhookNameFilter = all and {} or set
            end,
        })
        UIElements.WebhookIncludePlot = TabWebhook:Toggle({
            Title = "Include Plot Section",
            Desc = "Include the plot pet list and income/s in the embed.",
            Value = Config.WebhookIncludePlot,
            Callback = function(v) Config.WebhookIncludePlot = v end,
        })
    end,

    --------------------------------------------------------------------------
    -- onTestWebhook: embed contoh untuk tombol "Send Test Webhook".
    --------------------------------------------------------------------------
    onTestWebhook = function(buildEmbed)
        return buildEmbed({
            title = "TEST WEBHOOK • Break and Steal an Egg",
            color = 14423100,
            fields = {
                { name = "Pet", value = "MEGALODON", inline = true },
                { name = "Rarity", value = "Secret", inline = true },
                { name = "Size / Weight", value = "x4.2 / 1234.5 KG", inline = false },
                { name = "Mutation / Variant", value = "Gold / Diamond", inline = false },
                { name = "Source", value = "Test Webhook", inline = false },
            },
        })
    end,

    --------------------------------------------------------------------------
    -- onCleanup: bersihkan state game-specific. Loop & UI sudah dibersihkan
    -- template sebelum callback ini dipanggil.
    --------------------------------------------------------------------------
    onCleanup = function()
        local S = G.Runtime

        -- Matikan Auto Swing bila kita yang menyalakannya.
        pcall(function() if S and S.autoSwing then S.autoSwing(false) end end)

        -- Matikan FPS boost & NoClip.
        pcall(function()
            local f = getgenv().__bsBoostCleanup
            if f then f() end
        end)
        pcall(function()
            local f = getgenv().__bsNoClip
            if f then f(false) end
        end)

        -- Lepas semua render-step binding milik engine.
        for _, name in ipairs({
            "BSTravelStep", "BSMetaWalkStep", "BSMetaForceStep", "BSTmGuard",
            "BSMetaKite", "BSHuntLock", "BSHuntForce", "BSAntiKnock", "BSWalkStep",
            "TreadmillFaceLock",
        }) do
            pcall(function() ctx.RunService:UnbindFromRenderStep(name) end)
        end

        -- Reset state movement / pin.
        pcall(function()
            if S then
                S.MetaWalkDest = nil; S.TravelDest = nil; S.MetaForcePos = nil; S.ForcePin = nil
                S.WalkDest = nil; S.WalkStage = nil
                if S.hideBody then pcall(S.hideBody, false) end
            end
        end)

        -- Hentikan karakter.
        pcall(function()
            local ch = ctx.LocalPlayer.Character
            local hu = ch and ch:FindFirstChildOfClass("Humanoid")
            if hu then hu:Move(Vector3.zero) end
        end)
    end,
})

--------------------------------------------------------------------------------
-- START (WAJIB dipanggil TEPAT SEKALI, setelah registerGame)
--------------------------------------------------------------------------------
ctx:start()
