-- Wick's Ledger
-- Core.lua: WickCore addon object, saved variables, event dispatch

local ADDON, ns = ...

local Core = WickCore
if not Core then
    -- WickCore is missing or switched off.
    --
    -- The TOC asks for it with OptionalDeps rather than Dependencies on
    -- purpose. A hard dependency makes the client refuse to load this addon
    -- at all, so nothing of ours runs and the player is told nothing beyond
    -- a greyed line in the AddOns list. Loading anyway lets us say what is
    -- wrong and where to get it.
    --
    -- One line for the lot of them, not one per addon: with the whole suite
    -- installed and WickCore switched off, a line each would be a wall.
    local need = _G.WicksNeedCore
    if not need then
        need = {}
        _G.WicksNeedCore = need
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function()
            table.sort(need)
            print(("|cff4FC778Wick's Mods|r: %s %s WickCore, which is not installed or not switched on. It is in the same download as the rest of the suite: |cffD4C8A1wicksmods.com|r")
                :format(table.concat(need, ", "), #need == 1 and "needs" or "need"))
        end)
    end
    need[#need + 1] = "Wick's Ledger"
    return
end
local Chrome = Core.Chrome

WicksLedger = WicksLedger or {}
local WL = WicksLedger
ns.WL = WL

-- No saved variable through WickCore: WicksLedgerDB and the character
-- table stay as they are. The version is the TOC's, read once.
local A = Core:NewAddon("WicksLedger", {
    title   = "Wick's Ledger",
    version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version"),
})
WL.A = A
WL.version = A.version or "0.2.6"

-- ============================================================
-- DEFAULTS
-- ============================================================
local DEFAULTS = {
    minimap     = { hide = false, position = 225 },
    lock        = false,
    autoMode    = true,
    hardLock    = false,  -- when true, zone changes never auto-stop the session
    priceSource = "auto",   -- "auto" | "TSM" | "Auctionator" | "Auctioneer" | "vendor"
    barPos      = nil,
    panelPos    = nil,
    panelSize   = nil,
    optPos      = nil,
    barShown    = false,
    panelShown  = false,
    optShown    = false,
}

-- ============================================================
-- CALLBACKS
-- ============================================================
local callbacks = {}

function WL:On(event, fn)
    callbacks[event] = callbacks[event] or {}
    table.insert(callbacks[event], fn)
end

local function Fire(event, ...)
    if callbacks[event] then
        for _, fn in ipairs(callbacks[event]) do fn(...) end
    end
end

-- ============================================================
-- EVENTS
-- ============================================================
local frame = CreateFrame("Frame")
WL.eventFrame = frame

local EVENTS = {
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_MONEY",
    "CHAT_MSG_LOOT",
    "BAG_UPDATE",
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_XP_UPDATE",
    "COMBAT_TEXT_UPDATE",
}
for _, e in ipairs(EVENTS) do
    pcall(frame.RegisterEvent, frame, e)
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Merge defaults into saved vars
        WicksLedgerDB = WicksLedgerDB or {}
        local db = WicksLedgerDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then
                if type(v) == "table" then
                    db[k] = {}
                    for k2, v2 in pairs(v) do db[k][k2] = v2 end
                else
                    db[k] = v
                end
            end
        end
        WL.db = db
        -- Per-character DB: active session + history
        WicksLedgerCharDB = WicksLedgerCharDB or {}
        WL.charDB = WicksLedgerCharDB
        WL.charDB.history = WL.charDB.history or {}
        Fire("LOGIN")
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        local isInstance, instanceType = IsInInstance()
        Fire("ZONE", isInstance, instanceType)
        return
    end

    if event == "ZONE_CHANGED_NEW_AREA" then
        local isInstance, instanceType = IsInInstance()
        Fire("ZONE", isInstance, instanceType)
        return
    end

    if event == "PLAYER_MONEY" then
        Fire("MONEY")
        return
    end

    if event == "CHAT_MSG_LOOT" then
        Fire("LOOT_MSG", ...)
        return
    end

    if event == "BAG_UPDATE" then
        Fire("BAG_UPDATE", ...)
        return
    end

    if event == "PLAYER_XP_UPDATE" then
        Fire("XP")
        return
    end

    if event == "COMBAT_TEXT_UPDATE" then
        local combatType, factionName, amount = ...
        if combatType == "FACTION" and factionName and amount then
            Fire("REP", factionName, tonumber(amount) or 0)
        end
        return
    end
end)

-- ============================================================
-- SLASH COMMANDS
-- ============================================================
SLASH_WICKSLEDGER1 = "/wicksledger"
SLASH_WICKSLEDGER2 = "/wledger"
SlashCmdList.WICKSLEDGER = function(input)
    input = input or ""
    local cmd = (input:match("^(%S*)") or ""):lower()

    if cmd == "start" then
        if WL.Session and WL.Session.Start then WL.Session:Start() end
    elseif cmd == "stop" then
        if WL.Session and WL.Session.Stop then WL.Session:Stop() end
    elseif cmd == "reset" then
        if WL.Session and WL.Session.Reset then WL.Session:Reset() end
    elseif cmd == "auto" then
        WL.db.autoMode = not WL.db.autoMode
        A:Print(string.format("auto mode %s", WL.db.autoMode and "on" or "off"))
    elseif cmd == "lock" then
        WL.db.hardLock = not WL.db.hardLock
        A:Print(string.format("hard lock %s", WL.db.hardLock and "on -- session persists across instance resets" or "off"))
    elseif cmd == "help" or cmd == "?" then
        A:Print("commands:")
        print("  /wledger            toggle panel")
        print("  /wledger start      start session manually")
        print("  /wledger stop       stop session manually")
        print("  /wledger reset      clear current session")
        print("  /wledger auto       toggle auto instance-detection")
        print("  /wledger lock       toggle hard lock (persist across resets)")
    else
        if WL.UI and WL.UI.Toggle then WL.UI:Toggle() end
    end
end

-- ============================================================
-- WICKCORE OPTIONS PAGE AND LAUNCHER LINE
-- ============================================================
function A:OnEnable()
    self:RegisterOptions(function(body)
        local O = Core.Options
        local y = 0
        y = O:Note(body, "What a session earned: loot, raw gold and auction-valued drops, on a slim bar with an itemised panel behind it.", y)
        y = O:Heading(body, "Sessions", y)
        y = O:Check(body, "Start a session when you enter an instance",
            function() return WL.db and WL.db.autoMode end,
            function(v) if WL.db then WL.db.autoMode = v and true or false end end, y)
        y = O:Check(body, "Hard lock: a zone change never ends the session",
            function() return WL.db and WL.db.hardLock end,
            function(v) if WL.db then WL.db.hardLock = v and true or false end end, y)
        y = O:Heading(body, "Minimap", y)
        y = O:Check(body, "Minimap button",
            function() return WL.db and not WL.db.minimap.hide end,
            function(v)
                if WL.db and (not v) ~= WL.db.minimap.hide and WL.Minimap and WL.Minimap.Toggle then WL.Minimap:Toggle() end
            end, y)
        y = O:Heading(body, "Windows", y)
        y = O:Button(body, "Open the ledger", function() if WL.UI and WL.UI.Toggle then WL.UI:Toggle() end end, y, 160)
        y = O:Button(body, "Open the ledger's settings", function() if WL.UI and WL.UI.ToggleOptions then WL.UI:ToggleOptions() end end, y, 200)
        y = O:Note(body, "The price source, junk handling and the rest are in the ledger's own settings window.", y)
    end)
    self:RegisterLauncher({
        onClick = function() if WL.UI and WL.UI.Toggle then WL.UI:Toggle() end end,
        tooltip = function(tt)
            tt:AddLine(Chrome:TitleMarkup("Wick's Ledger"))
            tt:AddLine("Session earnings. Click for the ledger.", 1, 1, 1)
        end,
    })
end
