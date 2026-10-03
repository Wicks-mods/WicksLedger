-- Wick's Ledger
-- Session.lua: session lifecycle, loot tracking, gold delta, persist/restore, history

local ADDON, ns = ...
if not WickCore then return end   -- said once in Core.lua
local WL = WicksLedger
WL.Session = WL.Session or {}
local S = WL.Session

local MAX_HISTORY = 5

-- ============================================================
-- STATE
-- ============================================================
S.active      = false
S.startTime   = nil
S.startMoney  = nil
S.goldDelta   = 0
S.loot        = {}   -- { [itemLink] = { itemID, name, icon, count, copper, source } }
S.totalCopper = 0    -- goldDelta + loot value
S.zoneName    = nil

-- XP
S.startXP     = nil
S.xpDelta     = 0
S.maxLevel    = false

-- Rep: { [factionID] = { name, delta } }
S.rep         = {}

-- ============================================================
-- HELPERS
-- ============================================================
local function ItemIDFromLink(link)
    local id = link and link:match("item:(%d+)")
    return id and tonumber(id)
end

local function RecalcTotal()
    local total = S.goldDelta
    for _, entry in pairs(S.loot) do
        if entry.isJunk then
            -- Junk bucket: copper is already the running total, not per-item
            total = total + (entry.copper or 0)
        else
            total = total + (entry.copper or 0) * (entry.count or 1)
        end
    end
    S.totalCopper = total
end

-- ============================================================
-- PERSIST / RESTORE
-- ============================================================
local function PersistActive()
    if not WL.charDB then return end
    if not S.active then
        WL.charDB.activeSession = nil
        return
    end
    -- Serialize loot (keyed by itemID string) and rep
    WL.charDB.activeSession = {
        startTime  = S.startTime,
        startMoney = S.startMoney,
        goldDelta  = S.goldDelta,
        totalCopper= S.totalCopper,
        zoneName   = S.zoneName,
        startXP    = S.startXP,
        xpDelta    = S.xpDelta,
        maxLevel   = S.maxLevel,
        loot       = S.loot,
        rep        = S.rep,
    }
end

local function RestoreActive()
    if not WL.charDB then return end
    local saved = WL.charDB.activeSession
    if not saved or not saved.startTime then return end

    -- Stale-session guard: discard if older than 8 hours.
    -- Covers crashes, force-quits, and forgotten sessions.
    if (time() - saved.startTime) > 28800 then
        WL.charDB.activeSession = nil
        return
    end

    S.active      = true
    S.startTime   = saved.startTime
    S.startMoney  = saved.startMoney
    S.goldDelta   = saved.goldDelta   or 0
    S.totalCopper = saved.totalCopper or 0
    S.zoneName    = saved.zoneName
    S.startXP     = saved.startXP
    S.xpDelta     = saved.xpDelta    or 0
    S.maxLevel    = saved.maxLevel   or false
    S.loot        = saved.loot       or {}
    S.rep         = saved.rep        or {}
end

-- ============================================================
-- HISTORY
-- ============================================================
local function CommitToHistory()
    if not WL.charDB then return end
    -- Discard sessions with nothing earned
    if (S.totalCopper or 0) <= 0 then return end

    local entry = {
        startTime   = S.startTime,
        elapsed     = S:Elapsed(),
        goldDelta   = S.goldDelta,
        totalCopper = S.totalCopper,
        zoneName    = S.zoneName,
        xpDelta     = S.xpDelta,
        loot        = S.loot,
        rep         = S.rep,
    }

    local history = WL.charDB.history
    table.insert(history, 1, entry)   -- newest first
    while #history > MAX_HISTORY do
        table.remove(history)
    end
end

-- ============================================================
-- LOOT PARSING
-- ============================================================
local LOOT_PATTERNS = {
    "You receive loot: (.+)$",
    "You loot (.+)$",
}

local function ParseLootMessage(msg)
    local body
    for _, pat in ipairs(LOOT_PATTERNS) do
        body = msg:match(pat)
        if body then break end
    end
    if not body then return nil, nil, nil end

    body = body:gsub("%.$", "")

    local count = 1
    local suffix = body:match(" x(%d+)$")
    if suffix then
        count = tonumber(suffix)
        body  = body:gsub(" x%d+$", "")
    end

    local link = body:match("|H(item:[^|]+)|h%[.-%]|h")
    if link then link = "|H" .. link .. "|h[" .. (body:match("|h%[(.-)%]|h") or "?") .. "]|h" end
    if not link then link = body end

    local itemID = ItemIDFromLink(link)
    return itemID, link, count
end

-- ============================================================
-- PRICE OVERRIDE
-- ============================================================
function S:SetItemVendorPrice(key)
    local entry = S.loot[key]
    if not entry or entry.isJunk then return end
    local _, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(entry.itemID)
    if not vendorPrice or vendorPrice <= 0 then return end
    entry.copper = vendorPrice
    entry.source = "vendor"
    RecalcTotal()
    PersistActive()
    if WL.UI and WL.UI.OnUpdate then WL.UI:OnUpdate() end
end

-- ============================================================
-- SESSION CONTROL
-- ============================================================
local function SnapshotXP()
    local level = UnitLevel("player")
    local maxLvl = 70
    if level >= maxLvl then return nil, true end
    return UnitXP("player"), false
end

function S:Start()
    if S.active then return end
    S.active      = true
    S.startTime   = time()
    S.startMoney  = GetMoney()
    S.goldDelta   = 0
    S.loot        = {}
    S.totalCopper = 0
    S.rep         = {}
    S.zoneName    = GetRealZoneText()

    S.startXP, S.maxLevel = SnapshotXP()
    S.xpDelta = 0

    PersistActive()
    if WL.UI and WL.UI.OnSessionStart then WL.UI:OnSessionStart() end
    WL.A:Print(string.format("session started in %s", S.zoneName or "?"))
end

function S:Stop()
    if not S.active then return end
    S.active = false
    S.goldDelta = GetMoney() - (S.startMoney or GetMoney())
    if not S.maxLevel and S.startXP then
        S.xpDelta = UnitXP("player") - S.startXP
        if S.xpDelta < 0 then S.xpDelta = S.xpDelta + UnitXPMax("player") end
    end
    RecalcTotal()
    CommitToHistory()
    PersistActive()   -- clears activeSession
    if WL.UI and WL.UI.OnSessionStop then WL.UI:OnSessionStop() end
    WL.A:Print(string.format("session ended -- %s earned",
        WL.Prices and WL.Prices:FormatCopper(S.totalCopper) or "?"))
end

function S:Reset()
    S.active      = false
    S.startTime   = nil
    S.startMoney  = nil
    S.goldDelta   = 0
    S.loot        = {}
    S.totalCopper = 0
    S.rep         = {}
    S.startXP     = nil
    S.xpDelta     = 0
    S.maxLevel    = false
    PersistActive()   -- clears activeSession
    if WL.UI and WL.UI.OnSessionReset then WL.UI:OnSessionReset() end
end

function S:Elapsed()
    if not S.startTime then return 0 end
    return time() - S.startTime
end

-- ============================================================
-- EVENT HANDLERS
-- ============================================================
WL:On("LOGIN", function()
    RestoreActive()
    if S.active then
        WL.A:Print(string.format("session resumed in %s (%s elapsed)",
            S.zoneName or "?",
            (function()
                local e = S:Elapsed()
                local h = math.floor(e/3600)
                local m = math.floor((e%3600)/60)
                if h > 0 then return string.format("%dh %dm", h, m) end
                return string.format("%dm", m)
            end)()))
        if WL.UI and WL.UI.OnSessionStart then WL.UI:OnSessionStart() end
    end
end)

WL:On("ZONE", function(isInstance, instanceType)
    if not WL.db or not WL.db.autoMode then return end
    if isInstance and not S.active then
        if WL.db.hardLock and WL.charDB and WL.charDB.activeSession then
            -- Hard-lock resume: restore the paused session instead of starting fresh.
            -- startMoney is adjusted so goldDelta stays accurate across the zone gap.
            RestoreActive()
            S.startMoney = GetMoney() - S.goldDelta
            PersistActive()
            if WL.UI and WL.UI.OnSessionStart then WL.UI:OnSessionStart() end
        else
            S:Start()
        end
    elseif not isInstance and S.active then
        -- Ghost after a wipe: player released to graveyard outside the instance.
        -- Don't stop -- they'll run back in.
        if UnitIsGhost("player") then return end
        if WL.db.hardLock then
            -- Hard-lock: pause instead of stop. Save state, go idle, resume on re-entry.
            S.goldDelta = GetMoney() - (S.startMoney or GetMoney())
            if not S.maxLevel and S.startXP then
                local cur = UnitXP("player")
                local delta = cur - S.startXP
                if delta < 0 then delta = delta + UnitXPMax("player") end
                S.xpDelta = delta
            end
            RecalcTotal()
            S.active = false
            PersistActive()
            if WL.UI and WL.UI.OnSessionStop then WL.UI:OnSessionStop() end
            WL.A:Print("session paused (hard lock -- re-enter to resume)")
        else
            S:Stop()
        end
    end
end)

WL:On("MONEY", function()
    if not S.active then return end
    local current = GetMoney()
    S.goldDelta   = current - (S.startMoney or current)
    RecalcTotal()
    PersistActive()
    if WL.UI and WL.UI.OnUpdate then WL.UI:OnUpdate() end
end)

WL:On("XP", function()
    if not S.active or S.maxLevel or not S.startXP then return end
    local cur = UnitXP("player")
    local delta = cur - S.startXP
    if delta < 0 then delta = delta + UnitXPMax("player") end
    S.xpDelta = delta
    PersistActive()
    if WL.UI and WL.UI.OnUpdate then WL.UI:OnUpdate() end
end)

WL:On("REP", function(factionName, amount)
    if not S.active then return end
    if not S.rep[factionName] then
        S.rep[factionName] = { name = factionName, delta = 0 }
    end
    S.rep[factionName].delta = S.rep[factionName].delta + amount
    PersistActive()
    if WL.UI and WL.UI.OnUpdate then WL.UI:OnUpdate() end
end)

WL:On("LOOT_MSG", function(msg)
    if not S.active then return end
    local itemID, link, count = ParseLootMessage(msg)
    if not itemID then return end

    local copper, source
    local _, _, quality, _, _, _, _, _, _, icon, vendorPrice = GetItemInfo(itemID)

    -- Grey (Poor quality) items: collapse into a single "Junk" bucket using vendor price.
    if quality == 0 then
        local vendorCopper = (vendorPrice or 0) * count
        if S.loot["junk"] then
            S.loot["junk"].count  = S.loot["junk"].count + count
            S.loot["junk"].copper = S.loot["junk"].copper + vendorCopper
        else
            S.loot["junk"] = {
                itemID = 0,
                link   = nil,
                icon   = "Interface\\Icons\\INV_Misc_Bag_07",
                count  = count,
                copper = vendorCopper,
                source = "vendor",
                isJunk = true,
            }
        end
        RecalcTotal()
        PersistActive()
        if WL.UI and WL.UI.OnUpdate then WL.UI:OnUpdate() end
        return
    end

    if WL.Prices then copper, source = WL.Prices:GetPrice(itemID) end

    local key = tostring(itemID)
    if S.loot[key] then
        S.loot[key].count = S.loot[key].count + count
    else
        S.loot[key] = {
            itemID = itemID,
            link   = link,
            icon   = icon,
            count  = count,
            copper = copper or 0,
            source = source or "unknown",
        }
    end

    RecalcTotal()
    PersistActive()
    if WL.UI and WL.UI.OnUpdate then WL.UI:OnUpdate() end
end)
