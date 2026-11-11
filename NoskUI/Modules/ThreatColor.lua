local _, ns = ...

-- Colors enemy nameplate health bars by threat while the player is in combat.
--
--              status 3 (secure aggro)   1-2 (contested)   0 / not on list
--   tank       green                     yellow            red
--   non-tank   red                       yellow            green
--
-- UnitThreatSituation("player", unit):
--   nil = unit has no threat entry for player
--   0   = not tanking, lower threat than tank
--   1   = not tanking, higher threat than tank (about to pull)
--   2   = tanking, but someone else has more threat (insecure)
--   3   = tanking securely

local M = ns:RegisterModule("ThreatColor", {})

local Query = ns.Query
local IsSecret = ns.IsSecret

local inCombat = false
local ticker
local hookedBars = {}   -- [bar] = true once SetStatusBarColor is hooked
local barState = {}     -- [bar] = { color = {r,g,b} | nil, orig = {r,g,b} | nil }
local applying = false  -- guards our own SetStatusBarColor calls from the hook

local function GetHealthBar(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    local uf = plate.UnitFrame
    if not uf then return end
    return uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)
end

local function SetBarColor(bar, c)
    applying = true
    pcall(bar.SetStatusBarColor, bar, c[1], c[2], c[3])
    applying = false
end

-- Blizzard re-colors bars on its own schedule (reaction change, tapped, etc).
-- Post-hook SetStatusBarColor so we remember Blizzard's latest color for
-- restoring later, and immediately put our threat color back on top.
local function HookBar(bar)
    if hookedBars[bar] then return end
    hookedBars[bar] = true
    hooksecurefunc(bar, "SetStatusBarColor", function(self, r, g, b)
        if applying then return end
        local st = barState[self]
        if not st or not st.color then return end
        st.orig = { r, g, b }
        SetBarColor(self, st.color)
    end)
end

local function Apply(bar, color)
    local st = barState[bar]
    if not st then
        st = {}
        barState[bar] = st
    end
    if not st.color then
        -- Remember the default color before the first override.
        local ok, r, g, b = pcall(bar.GetStatusBarColor, bar)
        st.orig = ok and { r, g, b } or nil
    end
    st.color = color
    SetBarColor(bar, color)
end

local function Restore(bar)
    local st = barState[bar]
    if not st then return end
    barState[bar] = nil
    if st.color and st.orig then
        SetBarColor(bar, st.orig)
    end
end

-- Returns a threat status 0-3, or nil when we shouldn't color this unit.
local function GetStatus(unit)
    local canAttack = Query(UnitCanAttack, "player", unit)
    if not canAttack then return end

    local mobInCombat, combatHidden = Query(UnitAffectingCombat, unit)
    if not mobInCombat and not combatHidden then return end

    local status, hidden = Query(UnitThreatSituation, "player", unit)
    if hidden then
        -- Threat is secret on this client. Fall back to "is it attacking me?",
        -- which gives green/red but no yellow.
        M.secretSeen = true
        local targetingMe = Query(UnitIsUnit, unit .. "target", "player")
        if targetingMe == nil then return end
        return targetingMe and 3 or 0
    end

    if status == nil then
        -- We aren't on its threat table. In a group, a mob beating on a
        -- groupmate still counts as "threat lost" for a tank.
        if not IsInGroup() then return end
        local tgt = unit .. "target"
        local inGroup = Query(UnitInParty, tgt) or Query(UnitInRaid, tgt)
        if not inGroup then return end
        return 0
    end

    return status
end

local function PickColor(status)
    local colors = ns.db.threat.colors
    local isTank = ns.Role:IsTank()
    if status == 1 or status == 2 then return colors.warn end
    if isTank then
        return status == 3 and colors.good or colors.bad
    else
        return status == 0 and colors.good or colors.bad
    end
end

function M:UpdateUnit(unit)
    if not unit or IsSecret(unit) then return end
    local bar = GetHealthBar(unit)
    if not bar then return end

    if not (ns.db.threat.enabled and inCombat) then
        Restore(bar)
        return
    end

    local status = GetStatus(unit)
    if status == nil then
        Restore(bar)
        return
    end

    HookBar(bar)
    Apply(bar, PickColor(status))
end

function M:UpdateAll()
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then self:UpdateUnit(unit) end
    end
end

local function IsNamePlateUnit(unit)
    return type(unit) == "string" and not IsSecret(unit) and unit:find("^nameplate%d") ~= nil
end

local function SetCombat(state)
    inCombat = state
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if state then
        -- Safety net for changes no event reports (e.g. mob swapping targets).
        ticker = C_Timer.NewTicker(0.25, function() M:UpdateAll() end)
    end
    M:UpdateAll()
end

function M:OnEnable()
    local f = CreateFrame("Frame")
    for _, ev in ipairs({
        "NAME_PLATE_UNIT_ADDED",
        "NAME_PLATE_UNIT_REMOVED",
        "UNIT_THREAT_LIST_UPDATE",
        "UNIT_THREAT_SITUATION_UPDATE",
        "UNIT_TARGET",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_ENTERING_WORLD",
    }) do
        pcall(f.RegisterEvent, f, ev)
    end

    f:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_DISABLED" then
            SetCombat(true)
        elseif event == "PLAYER_REGEN_ENABLED" then
            SetCombat(false)
        elseif event == "PLAYER_ENTERING_WORLD" then
            SetCombat(InCombatLockdown() and true or false)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            if IsNamePlateUnit(unit) then
                local bar = GetHealthBar(unit)
                if bar then Restore(bar) end
            end
        elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
            M:UpdateAll()
        elseif IsNamePlateUnit(unit) then
            M:UpdateUnit(unit)
        end
    end)

    ns:On("ROLE_CHANGED", function() M:UpdateAll() end)
    ns:On("THREAT_SETTINGS_CHANGED", function() M:UpdateAll() end)
end
