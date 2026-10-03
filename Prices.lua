-- Wick's Ledger
-- Prices.lua: item valuation chain -- TSM > Auctionator > Auctioneer > vendor

local ADDON, ns = ...
if not WickCore then return end   -- said once in Core.lua
local WL = WicksLedger
WL.Prices = WL.Prices or {}
local P = WL.Prices

-- ============================================================
-- TSM
-- ============================================================
local function GetTSMPrice(itemID)
    local api = _G["TSM_API"]
    if not api or not api.GetCustomPriceValue then return nil end
    local itemString = "i:" .. itemID
    local ok, v = pcall(api.GetCustomPriceValue, "dbminbuyout", itemString)
    if ok and v and v > 0 then return v end
    ok, v = pcall(api.GetCustomPriceValue, "dbmarket", itemString)
    return (ok and v and v > 0) and v or nil
end

-- ============================================================
-- Auctionator
-- ============================================================
local function GetAuctionatorPrice(itemID)
    local db = _G["AUCTIONATOR_PRICE_DATABASE"]
    if not db then return nil end
    -- Auctionator keys: "realm/itemId" or just itemId depending on version
    local realm = GetRealmName()
    local v = db[realm .. "/" .. itemID] or db[tostring(itemID)] or nil
    if type(v) == "number" then return v end
    if type(v) == "table" then return v[1] or nil end
    return nil
end

-- ============================================================
-- Auctioneer
-- ============================================================
local function GetAuctioneerPrice(itemID)
    -- AucStatSimple stores data in AucAdvancedData.UtilSimpleAuction
    local auc = _G["AucAdvancedData"]
    if not auc then return nil end
    local simple = auc.UtilSimpleAuction
    if not simple then return nil end
    local realm = GetRealmName()
    -- Auctioneer uses a data path: [realm]["horde"/"alliance"/nil][itemKey]
    -- Try common paths
    local function tryPath(root)
        if not root then return nil end
        local key = "i:" .. itemID
        if root[key] then
            local entry = root[key]
            if type(entry) == "number" then return entry end
            if type(entry) == "table" then return entry.price or entry[1] or nil end
        end
        return nil
    end
    return tryPath(simple[realm]) or tryPath(simple[realm .. "-Horde"]) or tryPath(simple[realm .. "-Alliance"])
end

-- ============================================================
-- Vendor fallback
-- ============================================================
local function GetVendorPrice(itemID)
    -- GetItemInfo returns sellPrice in copper for the vendor sell price
    local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemID)
    if sellPrice and sellPrice > 0 then return sellPrice end
    return nil
end

-- ============================================================
-- Public API
-- ============================================================

-- Returns copper, source for itemID. source may be nil if unvalued.
function P:GetPrice(itemID)
    local src = WL.db and WL.db.priceSource or "auto"
    local v

    if src == "TSM" then
        v = GetTSMPrice(itemID)
        if v and v > 0 then return v, "TSM" end
        -- fallthrough to vendor only
        v = GetVendorPrice(itemID)
        if v and v > 0 then return v, "vendor" end
        return nil, nil
    end

    if src == "Auctionator" then
        v = GetAuctionatorPrice(itemID)
        if v and v > 0 then return v, "Auctionator" end
        v = GetVendorPrice(itemID)
        if v and v > 0 then return v, "vendor" end
        return nil, nil
    end

    if src == "Auctioneer" then
        v = GetAuctioneerPrice(itemID)
        if v and v > 0 then return v, "Auctioneer" end
        v = GetVendorPrice(itemID)
        if v and v > 0 then return v, "vendor" end
        return nil, nil
    end

    if src == "vendor" then
        v = GetVendorPrice(itemID)
        if v and v > 0 then return v, "vendor" end
        return nil, nil
    end

    -- "auto": full waterfall TSM > Auctionator > Auctioneer > vendor
    v = GetTSMPrice(itemID)
    if v and v > 0 then return v, "TSM" end

    v = GetAuctionatorPrice(itemID)
    if v and v > 0 then return v, "Auctionator" end

    v = GetAuctioneerPrice(itemID)
    if v and v > 0 then return v, "Auctioneer" end

    v = GetVendorPrice(itemID)
    if v and v > 0 then return v, "vendor" end

    return nil, nil
end

-- Format copper rounded to whole gold only (for /hr projections).
function P:FormatGold(copper)
    local g = math.floor((copper or 0) / 10000)
    if g <= 0 then return "|cffffd7000g|r" end
    return string.format("|cffffd700%dg|r", g)
end

-- Format copper as "Xg Ys Zc" with WoW gold/silver/copper coloring.
function P:FormatCopper(copper)
    copper = math.floor(copper or 0)
    if copper <= 0 then return "|cffaaaaaa0c|r" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then table.insert(parts, string.format("|cffffd700%dg|r", g)) end
    if s > 0 then table.insert(parts, string.format("|cffc0c0c0%ds|r", s)) end
    if c > 0 or copper == 0 then table.insert(parts, string.format("|cffeda55f%dc|r", c)) end
    return table.concat(parts, " ")
end
