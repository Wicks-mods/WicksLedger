-- Wick's Ledger
-- Minimap.lua: draggable minimap toggle button

local ADDON, ns = ...
if not WickCore then return end   -- said once in Core.lua
local WL = WicksLedger
WL.Minimap = WL.Minimap or {}
local M = WL.Minimap

-- Palette tokens by reference, so the button follows a theme change.
local Chrome  = WickCore.Chrome
local C_GREEN = Chrome.Colors.fel
local C_VOID  = Chrome.Colors.void

function M:OnLogin()
    if M.button then return end

    local btn = CreateFrame("Button", "WicksLedgerMinimapButton", Minimap)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("AnyUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)
    btn:SetSize(32, 32)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    bg:SetVertexColor(C_VOID[1], C_VOID[2], C_VOID[3], 0.97)
    Chrome:Register(bg, C_VOID, "vertex", 0.97)

    local glyph = btn:CreateFontString(nil, "ARTWORK")
    Chrome:SetFont(glyph, 13, "OUTLINE")
    glyph:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3])
    Chrome:Register(glyph, C_GREEN, "text")
    glyph:SetText("LE")
    glyph:SetPoint("CENTER", 0, 0)
    btn.glyph = glyph

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(Chrome:TitleMarkup("Wick's Ledger"))
        GameTooltip:AddLine("Session earnings tracker", 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffaaaaaaLeft-click:|r toggle panel")
        GameTooltip:AddLine("|cffaaaaaaRight-click:|r hide button")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            if WL.UI and WL.UI.Toggle then WL.UI:Toggle() end
        elseif button == "RightButton" then
            M:Toggle()
        end
    end)

    local db = WL.db

    local function positionAt(angle)
        local rad = math.rad(angle)
        local x   = math.cos(rad) * 80
        local y   = math.sin(rad) * 80
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
    positionAt(db.minimap.position or 225)

    btn:SetScript("OnDragStart", function(self) self:LockHighlight(); self.isDragging = true end)
    btn:SetScript("OnDragStop",  function(self) self:UnlockHighlight(); self.isDragging = false end)
    btn:SetScript("OnUpdate", function(self)
        if not self.isDragging then return end
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale  = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        local angle  = math.deg(math.atan2(py - my, px - mx))
        db.minimap.position = angle
        positionAt(angle)
    end)

    if db.minimap.hide then btn:Hide() end
    M.button = btn
end

function M:Toggle()
    local db = WL.db
    db.minimap.hide = not db.minimap.hide
    if M.button then
        if db.minimap.hide then M.button:Hide() else M.button:Show() end
    end
end

WL:On("LOGIN", function() M:OnLogin() end)
