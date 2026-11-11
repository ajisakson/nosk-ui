local _, ns = ...

local Role = ns:RegisterModule("Role", {})

local Query = ns.Query
local _, playerClass = UnitClass("player")

-- Shapeshift form IDs that mean "I'm tanking".
local TANK_FORMS = {
    WARRIOR = { [18] = true },          -- Defensive Stance
    DRUID   = { [5] = true, [8] = true }, -- Bear Form, Dire Bear Form
}

-- Player buffs that mean "I'm tanking".
local TANK_AURAS = {
    PALADIN = { 25780 }, -- Righteous Fury
}

local cachedTank, cachedSource = false, "default"

-- Returns isTank, source; isTank is nil when the answer is hidden from us
-- (secret values in combat), in which case the cached answer is kept.
local function Compute()
    local mode = ns.db and ns.db.roleMode or "auto"
    if mode == "tank" then return true, "manual" end
    if mode == "dps" then return false, "manual" end

    local unknown = false

    -- 1. Explicit group role (LFG / role check).
    if UnitGroupRolesAssigned then
        local r, blocked = Query(UnitGroupRolesAssigned, "player")
        unknown = unknown or blocked
        if r == "TANK" then return true, "group role" end
        if r == "DAMAGER" or r == "HEALER" then return false, "group role" end
    end

    -- 2. Tank stance / form.
    local forms = TANK_FORMS[playerClass]
    if forms and GetShapeshiftFormID then
        local id, blocked = Query(GetShapeshiftFormID)
        unknown = unknown or blocked
        if id and forms[id] then return true, "form" end
    end

    -- 3. Tank buff.
    local auras = TANK_AURAS[playerClass]
    if auras and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for _, spellID in ipairs(auras) do
            local aura, blocked = Query(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
            unknown = unknown or blocked
            if aura then return true, "buff" end
        end
    end

    -- 4. Specialization role, where the client has specs.
    if GetSpecialization and GetSpecializationRole then
        local spec, blocked = Query(GetSpecialization)
        unknown = unknown or blocked
        if spec and spec > 0 then
            local r = Query(GetSpecializationRole, spec)
            if r then return r == "TANK", "spec" end
        end
    end

    if unknown then return nil end
    return false, "default"
end

function Role:Refresh()
    local isTank, source = Compute()
    if isTank == nil then return end -- hidden right now; keep last known
    if isTank ~= cachedTank or source ~= cachedSource then
        cachedTank, cachedSource = isTank, source
        ns:Fire("ROLE_CHANGED", isTank)
    end
end

function Role:IsTank()
    return cachedTank, cachedSource
end

function Role:OnEnable()
    local f = CreateFrame("Frame")
    for _, ev in ipairs({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_DISABLED",
        "UPDATE_SHAPESHIFT_FORM",
        "GROUP_ROSTER_UPDATE",
        "PLAYER_ROLES_ASSIGNED",
        "PLAYER_SPECIALIZATION_CHANGED",
        "PLAYER_TALENT_UPDATE",
    }) do
        pcall(f.RegisterEvent, f, ev) -- some events may not exist on every client
    end
    pcall(f.RegisterUnitEvent, f, "UNIT_AURA", "player")
    f:SetScript("OnEvent", function() Role:Refresh() end)
    self:Refresh()
end
