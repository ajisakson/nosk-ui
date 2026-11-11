local ADDON_NAME, ns = ...

ns.modules = {}

local defaults = {
    roleMode = "auto", -- "auto" | "tank" | "dps"
    threat = {
        enabled = true,
        colors = {
            good = { 0.10, 0.80, 0.10 }, -- green
            warn = { 1.00, 0.80, 0.00 }, -- yellow
            bad  = { 0.90, 0.10, 0.10 }, -- red
        },
    },
}

local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Midnight-era clients (which WoW Forever runs on) hide some API results
-- behind "secret values" in combat. Secrets can't be compared, so every
-- value we branch on goes through IsSecret first.
function ns.IsSecret(v)
    return type(issecretvalue) == "function" and issecretvalue(v) or false
end

-- Calls fn and returns its first result, or nil plus `true` when the call
-- errored or the result is a secret value we can't inspect.
function ns.Query(fn, ...)
    if type(fn) ~= "function" then return nil, true end
    local ok, result = pcall(fn, ...)
    if not ok or ns.IsSecret(result) then return nil, true end
    return result, false
end

function ns.Print(...)
    print("|cff33ccffNoskUI|r:", ...)
end

function ns:RegisterModule(name, module)
    self.modules[name] = module
    self[name] = module
    return module
end

-- Lightweight internal callbacks so modules don't reference each other directly.
local callbacks = {}
function ns:On(event, fn)
    callbacks[event] = callbacks[event] or {}
    table.insert(callbacks[event], fn)
end
function ns:Fire(event, ...)
    local list = callbacks[event]
    if not list then return end
    for _, fn in ipairs(list) do fn(...) end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        NoskUIDB = NoskUIDB or {}
        ApplyDefaults(NoskUIDB, defaults)
        ns.db = NoskUIDB
        for _, m in pairs(ns.modules) do
            if m.OnInitialize then m:OnInitialize() end
        end
    elseif event == "PLAYER_LOGIN" then
        for _, m in pairs(ns.modules) do
            if m.OnEnable then m:OnEnable() end
        end
    end
end)

-- Slash commands ---------------------------------------------------------

local function ShowValue(v)
    if ns.IsSecret(v) then return "|cffff8800<secret>|r" end
    return tostring(v)
end

local function Debug()
    local isTank, source = ns.Role:IsTank()
    ns.Print(("role: %s (via %s, mode=%s)"):format(isTank and "TANK" or "non-tank", source or "?", ns.db.roleMode))
    ns.Print("in combat:", ShowValue(InCombatLockdown()))
    if UnitExists("target") then
        local ok, status = pcall(UnitThreatSituation, "player", "target")
        ns.Print("UnitThreatSituation(player, target):", ok and ShowValue(status) or ("error: " .. tostring(status)))
        local ok2, tm = pcall(UnitIsUnit, "targettarget", "player")
        ns.Print("UnitIsUnit(targettarget, player):", ok2 and ShowValue(tm) or ("error: " .. tostring(tm)))
    else
        ns.Print("target an enemy (ideally in combat) to test threat APIs")
    end
    if ns.ThreatColor and ns.ThreatColor.secretSeen then
        ns.Print("threat API returned secret values this session; using target-based fallback")
    end
end

SLASH_NOSKUI1 = "/nosk"
SLASH_NOSKUI2 = "/noskui"
SlashCmdList.NOSKUI = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "role" and (arg == "auto" or arg == "tank" or arg == "dps") then
        ns.db.roleMode = arg
        ns.Role:Refresh()
        ns.Print("role mode set to", arg)
    elseif cmd == "threat" and (arg == "on" or arg == "off") then
        ns.db.threat.enabled = (arg == "on")
        ns:Fire("THREAT_SETTINGS_CHANGED")
        ns.Print("threat colors", arg)
    elseif cmd == "debug" then
        Debug()
    else
        ns.Print("commands:")
        print("  /nosk role auto||tank||dps  - tank detection (current: " .. ns.db.roleMode .. ")")
        print("  /nosk threat on||off        - threat-colored nameplates (current: " .. (ns.db.threat.enabled and "on" or "off") .. ")")
        print("  /nosk debug                 - show role and test threat APIs on your target")
    end
end
