-- Wick's Ledger
-- UI.lua: slim bar + independent itemized panel + options

local ADDON, ns = ...
local WL = WicksLedger
WL.UI = WL.UI or {}
local UI = WL.UI

-- ============================================================
-- CONSTANTS
-- ============================================================
local BAR_W       = 280
local BAR_H       = 26
local PANEL_W_DEF = 360
local PANEL_H_MAX = 600
local PANEL_H_MIN = 120
local ROW_H       = 24
local ICON_SIZE   = 18
local HEADER_H    = 24
local TAB_H       = 20
local FOOTER_H    = 30
local PAD         = 8

-- Wick brand palette
local C_BG      = { 0.051, 0.039, 0.078, 0.97 }
local C_HEADER  = { 0.090, 0.067, 0.141, 1 }
local C_BORDER  = { 0.220, 0.188, 0.345, 1 }
local C_GREEN   = { 0.310, 0.780, 0.471, 1 }
local C_TEXT    = { 0.831, 0.784, 0.631, 1 }
local C_DIM     = { 0.42,  0.35,  0.54,  1 }

-- ============================================================
-- CHROME HELPERS
-- Rule: BACKGROUND textures go on a bg child frame.
--       FontStrings go on the parent (no bg texture on parent).
--       BORDER/ARTWORK textures on parent are fine -- only BACKGROUND blocks text.
-- ============================================================
local function MakeBgChild(parent, r, g, b, a)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    local lvl = parent:GetFrameLevel()
    f:SetFrameLevel(lvl > 0 and lvl - 1 or 0)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(); t:SetColorTexture(r, g, b, a)
    return f
end

local function AddBorder(f)
    for _, args in ipairs({
        {"TOPLEFT","TOPRIGHT",nil,1},{"BOTTOMLEFT","BOTTOMRIGHT",nil,1},
        {"TOPLEFT","BOTTOMLEFT",1,nil},{"TOPRIGHT","BOTTOMRIGHT",1,nil},
    }) do
        local e = f:CreateTexture(nil, "BORDER")
        e:SetColorTexture(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)
        e:SetPoint(args[1]); e:SetPoint(args[2])
        if args[3] then e:SetWidth(args[3]) end
        if args[4] then e:SetHeight(args[4]) end
    end
end

local function AddCornerAccents(f)
    for _, p in ipairs({"TOPLEFT","TOPRIGHT","BOTTOMLEFT","BOTTOMRIGHT"}) do
        local h = f:CreateTexture(nil, "BORDER")
        h:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
        h:SetPoint(p, f, p); h:SetSize(10, 2)
        local v = f:CreateTexture(nil, "BORDER")
        v:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
        v:SetPoint(p, f, p); v:SetSize(2, 10)
    end
end

-- ============================================================
-- POSITION / SIZE PERSISTENCE
-- ============================================================
local function SavePos(key, frame)
    if not WL.db then return end
    local pt, _, rpt, x, y = frame:GetPoint()
    WL.db[key] = { pt = pt, rpt = rpt, x = x, y = y }
end

local function SaveSize(key, frame)
    if not WL.db then return end
    WL.db[key] = { w = frame:GetWidth(), h = frame:GetHeight() }
end

local function LoadPos(key, frame, defPt, defX, defY)
    local p = WL.db and WL.db[key]
    if p and p.pt then
        frame:SetPoint(p.pt, UIParent, p.rpt, p.x, p.y)
    else
        frame:SetPoint(defPt, UIParent, defPt, defX, defY)
    end
end

local function LoadSize(key, frame, defW, defH)
    local s = WL.db and WL.db[key]
    if s and s.w then
        frame:SetSize(math.max(s.w, 200), math.max(s.h, PANEL_H_MIN))
    else
        frame:SetSize(defW, defH)
    end
end

-- ============================================================
-- ELAPSED FORMATTER
-- ============================================================
local function FormatElapsed(secs)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    local s = secs % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

local function FormatXP(xp)
    xp = math.floor(xp or 0)
    if xp >= 1000 then return string.format("%.1fk", xp / 1000) end
    return tostring(xp)
end

-- ============================================================
-- ROW POOL
-- Every row: bg child frame holds the separator BACKGROUND texture.
--            FontStrings live on the row frame itself (no BACKGROUND on it).
-- ============================================================
local rowPool    = {}
local activeRows = {}

local function AcquireRow(parent, panelW)
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Button", nil, parent)
        row:SetHeight(ROW_H)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        -- separator on bg child
        local bgChild = MakeBgChild(row, C_BORDER[1], C_BORDER[2], C_BORDER[3], 0)
        local sep = bgChild:CreateTexture(nil, "BACKGROUND")
        sep:SetColorTexture(C_BORDER[1], C_BORDER[2], C_BORDER[3], 0.3)
        sep:SetHeight(1)
        sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
        sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT")

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)
        row.icon:SetPoint("LEFT", row, "LEFT", PAD, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        row.name = row:CreateFontString(nil, "OVERLAY")
        row.name:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        row.name:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], 1)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row.value = row:CreateFontString(nil, "OVERLAY")
        row.value:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        row.value:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], 1)
        row.value:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
        row.value:SetJustifyH("RIGHT")
    end
    row:SetParent(parent)
    row:ClearAllPoints()
    -- name width: fills between icon+gap and value column
    local w = panelW or PANEL_W_DEF
    row.name:SetWidth(w - PAD - ICON_SIZE - 4 - 110)
    row:Show()
    return row
end

local function ReleaseRow(row)
    row:Hide()
    row:SetParent(nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:SetScript("OnMouseUp", nil)
    table.insert(rowPool, row)
end

-- ============================================================
-- SLIM BAR
-- ============================================================
local bar, expandBtn, statusText, panelOpen

local function BuildBar()
    bar = CreateFrame("Frame", "WicksLedgerBar", UIParent)
    bar:SetSize(BAR_W, BAR_H)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self)
        WicksSnap.Detach("ledger_bar")
        self:StartMoving()
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        WicksSnap.TrySnap("ledger_bar")
        SavePos("barPos", self)
    end)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)

    LoadPos("barPos", bar, "CENTER", 0, -300)

    -- bg on child so BACKGROUND doesn't block bar FontStrings
    MakeBgChild(bar, C_BG[1], C_BG[2], C_BG[3], C_BG[4])
    AddBorder(bar)
    AddCornerAccents(bar)

    local dot = bar:CreateTexture(nil, "OVERLAY")
    dot:SetSize(6, 6)
    dot:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
    dot:SetPoint("LEFT", bar, "LEFT", PAD, 0)
    bar.dot = dot
    dot:Hide()

    -- Expand button
    expandBtn = CreateFrame("Button", nil, bar)
    expandBtn:SetSize(20, BAR_H)
    expandBtn:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    local expandTex = expandBtn:CreateFontString(nil, "OVERLAY")
    expandTex:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    expandTex:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
    expandTex:SetAllPoints()
    expandTex:SetJustifyH("CENTER"); expandTex:SetJustifyV("MIDDLE")
    expandTex:SetText("+")
    expandBtn.label = expandTex
    expandBtn:SetScript("OnClick", function()
        if panelOpen then UI:ClosePanel() else UI:OpenPanel() end
    end)
    expandBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("|cff4FC778Wick's Ledger|r")
        GameTooltip:AddLine("Open itemized breakdown", 1, 1, 1)
        GameTooltip:Show()
    end)
    expandBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Start/stop icon button
    local ssBtn = CreateFrame("Button", nil, bar)
    ssBtn:SetSize(18, 18)
    ssBtn:SetPoint("RIGHT", expandBtn, "LEFT", -4, 0)
    local ssIcon = ssBtn:CreateTexture(nil, "ARTWORK")
    ssIcon:SetAllPoints()
    ssBtn.icon = ssIcon
    bar.ssBtn  = ssBtn

    local ICO_PLAY = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
    local ICO_STOP = "Interface\\Buttons\\UI-StopButton"

    local function UpdateSSBtn()
        local S = WL.Session
        if S and S.active then
            ssIcon:SetTexture(ICO_STOP)
            ssIcon:SetTexCoord(0, 1, 0, 1)
            ssIcon:SetVertexColor(1, 0.4, 0.4, 1)
        else
            ssIcon:SetTexture(ICO_PLAY)
            ssIcon:SetTexCoord(0, 1, 0, 1)
            ssIcon:SetVertexColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
        end
    end
    bar.UpdateSSBtn = UpdateSSBtn
    UpdateSSBtn()

    ssBtn:SetScript("OnClick", function()
        local S = WL.Session
        if S and S.active then S:Stop() else S:Start() end
        UpdateSSBtn()
    end)
    ssBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local S = WL.Session
        GameTooltip:AddLine(S and S.active and "Stop session" or "Start session", 1, 1, 1)
        GameTooltip:Show()
    end)
    ssBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    statusText = bar:CreateFontString(nil, "OVERLAY")
    statusText:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    statusText:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], 1)
    statusText:SetPoint("LEFT",  bar, "TOPLEFT", PAD + 10, -BAR_H / 2)
    statusText:SetPoint("RIGHT", ssBtn, "LEFT", -4, 0)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("idle")
    bar.statusText = statusText

    local tickAcc = 0
    bar:SetScript("OnUpdate", function(self, elapsed)
        tickAcc = tickAcc + elapsed
        if tickAcc < 0.5 then return end
        tickAcc = 0
        local S = WL.Session
        if S and S.active then
            bar.dot:Show()
            local P       = WL.Prices
            local elapsed = S:Elapsed()
            local hrFac   = elapsed > 60 and (3600 / elapsed) or 0
            local val     = P and P:FormatCopper(S.totalCopper) or "0c"
            if hrFac > 0 and P then
                val = val .. " |cff888888(" .. P:FormatGold(S.totalCopper * hrFac) .. "/hr)|r"
            end
            statusText:SetText(val .. "  " .. FormatElapsed(elapsed))
        else
            bar.dot:Hide()
            statusText:SetText("idle")
        end
    end)

    WicksSnap.Register("ledger_bar", bar)
    bar:Hide()
end

-- ============================================================
-- ITEMIZED PANEL
-- ============================================================
local panel
local PopulatePanel, PopulateHistory

local function BuildPanel()
    panel = CreateFrame("Frame", "WicksLedgerPanel", UIParent)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:SetResizable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self)
        WicksSnap.Detach("ledger_panel")
        self:StartMoving()
    end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        WicksSnap.TrySnap("ledger_panel")
        SavePos("panelPos", self)
    end)

    LoadSize("panelSize", panel, PANEL_W_DEF, 300)
    LoadPos("panelPos", panel, "CENTER", 0, -100)

    MakeBgChild(panel, C_BG[1], C_BG[2], C_BG[3], C_BG[4])
    AddBorder(panel)

    -- Header
    local header = CreateFrame("Frame", nil, panel)
    header:SetHeight(HEADER_H)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT")
    MakeBgChild(header, C_HEADER[1], C_HEADER[2], C_HEADER[3], 1)
    local hsep = header:CreateTexture(nil, "BORDER")
    hsep:SetColorTexture(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)
    hsep:SetHeight(1); hsep:SetPoint("BOTTOMLEFT"); hsep:SetPoint("BOTTOMRIGHT")
    do
        local function panelBrk(anchor)
            local h = header:CreateTexture(nil, "OVERLAY")
            h:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
            h:SetPoint(anchor, panel, anchor); h:SetSize(10, 2)
            local v = header:CreateTexture(nil, "OVERLAY")
            v:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
            v:SetPoint(anchor, panel, anchor); v:SetSize(2, 10)
        end
        panelBrk("TOPLEFT"); panelBrk("TOPRIGHT")
    end

    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    title:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
    title:SetPoint("LEFT", header, "TOPLEFT", PAD, -HEADER_H / 2)
    title:SetText("Wick's Ledger")

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(HEADER_H, HEADER_H)
    closeBtn:SetPoint("RIGHT", header, "TOPRIGHT", 0, -HEADER_H / 2)
    local closeTex = closeBtn:CreateFontString(nil, "OVERLAY")
    closeTex:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    closeTex:SetTextColor(C_DIM[1], C_DIM[2], C_DIM[3], 1)
    closeTex:SetAllPoints(); closeTex:SetJustifyH("CENTER"); closeTex:SetJustifyV("MIDDLE")
    closeTex:SetText("x")
    closeBtn:SetScript("OnClick", function() UI:ClosePanel() end)

    local gearBtn = CreateFrame("Button", nil, header)
    gearBtn:SetSize(16, 16)
    gearBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    local gearIcon = gearBtn:CreateTexture(nil, "ARTWORK")
    gearIcon:SetAllPoints()
    gearIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    gearIcon:SetVertexColor(C_DIM[1], C_DIM[2], C_DIM[3], 1)
    gearBtn:SetScript("OnClick", function() UI:ToggleOptions() end)
    gearBtn:SetScript("OnEnter", function(self)
        gearIcon:SetVertexColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Options", 1, 1, 1)
        GameTooltip:Show()
    end)
    gearBtn:SetScript("OnLeave", function()
        gearIcon:SetVertexColor(C_DIM[1], C_DIM[2], C_DIM[3], 1)
        GameTooltip:Hide()
    end)

    -- Tab strip (Session | History) below the header
    local tabStrip = CreateFrame("Frame", nil, panel)
    tabStrip:SetHeight(TAB_H)
    tabStrip:SetPoint("TOPLEFT",  panel, "TOPLEFT",  1, -HEADER_H)
    tabStrip:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -HEADER_H)
    MakeBgChild(tabStrip, C_HEADER[1], C_HEADER[2], C_HEADER[3], 0.7)
    local tabsep = tabStrip:CreateTexture(nil, "BORDER")
    tabsep:SetColorTexture(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)
    tabsep:SetHeight(1); tabsep:SetPoint("BOTTOMLEFT"); tabsep:SetPoint("BOTTOMRIGHT")

    local activeTab = "session"

    local function makeTab(label, xOff, key)
        local btn = CreateFrame("Button", nil, tabStrip)
        btn:SetSize(70, TAB_H)
        btn:SetPoint("LEFT", tabStrip, "LEFT", xOff, 0)
        local fs = btn:CreateFontString(nil, "OVERLAY")
        fs:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
        fs:SetAllPoints(); fs:SetJustifyH("CENTER"); fs:SetJustifyV("MIDDLE")
        fs.key = key
        btn._label = fs
        return btn, fs
    end

    local sessionTab, sessionFS = makeTab("Session", PAD, "session")
    local historyTab, historyFS = makeTab("History", PAD + 72, "history")

    local function RefreshTabs()
        if activeTab == "session" then
            sessionFS:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
            historyFS:SetTextColor(C_DIM[1], C_DIM[2], C_DIM[3], 1)
        else
            sessionFS:SetTextColor(C_DIM[1], C_DIM[2], C_DIM[3], 1)
            historyFS:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
        end
        sessionFS:SetText("Session")
        historyFS:SetText("History")
    end
    RefreshTabs()
    panel.RefreshTabs   = RefreshTabs
    panel.getActiveTab  = function() return activeTab end
    panel.switchTab     = function(key)
        if activeTab == key then return end
        activeTab = key
        RefreshTabs()
    end

    sessionTab:SetScript("OnClick", function()
        if activeTab == "session" then return end
        activeTab = "session"
        RefreshTabs()
        PopulatePanel()
    end)
    historyTab:SetScript("OnClick", function()
        if activeTab == "history" then return end
        activeTab = "history"
        RefreshTabs()
        PopulateHistory()
    end)

    -- Scroll area (sits below tab strip)
    local SCROLL_TOP = HEADER_H + TAB_H + 1
    local scroll = CreateFrame("ScrollFrame", "WicksLedgerScroll", panel)
    scroll:SetPoint("TOPLEFT",     panel, "TOPLEFT",     1, -SCROLL_TOP)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, FOOTER_H + 1)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PANEL_W_DEF - 2, 1)
    scroll:SetScrollChild(content)

    panel.scroll  = scroll
    panel.content = content

    -- Footer
    local footer = CreateFrame("Frame", nil, panel)
    footer:SetHeight(FOOTER_H)
    footer:SetPoint("BOTTOMLEFT"); footer:SetPoint("BOTTOMRIGHT")
    MakeBgChild(footer, C_HEADER[1], C_HEADER[2], C_HEADER[3], 1)
    local ftop = footer:CreateTexture(nil, "BORDER")
    ftop:SetColorTexture(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)
    ftop:SetHeight(1); ftop:SetPoint("TOPLEFT"); ftop:SetPoint("TOPRIGHT")
    panel.footer = footer

    local totalLabel = footer:CreateFontString(nil, "OVERLAY")
    totalLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    totalLabel:SetTextColor(C_DIM[1], C_DIM[2], C_DIM[3], 1)
    totalLabel:SetPoint("LEFT", footer, "TOPLEFT", PAD, -FOOTER_H / 2)
    totalLabel:SetText("Total")
    panel.totalLabel = totalLabel

    local totalValue = footer:CreateFontString(nil, "OVERLAY")
    totalValue:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    totalValue:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], 1)
    totalValue:SetPoint("RIGHT", footer, "TOPRIGHT", -PAD, -FOOTER_H / 2)
    totalValue:SetJustifyH("RIGHT")
    panel.totalValue = totalValue
    do
        local h = footer:CreateTexture(nil, "OVERLAY")
        h:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
        h:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT"); h:SetSize(10, 2)
        local v = footer:CreateTexture(nil, "OVERLAY")
        v:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
        v:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT"); v:SetSize(2, 10)
    end

    -- Resize grip
    local grip = CreateFrame("Frame", nil, panel)
    grip:SetSize(12, 12)
    grip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    grip:EnableMouse(true)
    do
        local h = grip:CreateTexture(nil, "OVERLAY")
        h:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
        h:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT"); h:SetSize(10, 2)
        local v = grip:CreateTexture(nil, "OVERLAY")
        v:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
        v:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT"); v:SetSize(2, 10)
    end
    grip:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        -- Pin TOPLEFT so the frame doesn't jump when sizing starts
        local x, y = panel:GetLeft(), panel:GetTop()
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        panel:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        panel:StopMovingOrSizing()
        local w = panel:GetWidth()
        local h = math.max(math.min(panel:GetHeight(), PANEL_H_MAX), PANEL_H_MIN)
        panel:SetHeight(h)
        SaveSize("panelSize", panel)
        panel.content:SetWidth(w - 2)
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Drag to resize", 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    WicksSnap.Register("ledger_panel", panel)
    panel:Hide()
end

-- ============================================================
-- OPTIONS PANEL
-- ============================================================
local optPanel

local function BuildOptions()
    local OPT_W = 290
    local OPT_H = 256
    local ROW_Y = 20

    optPanel = CreateFrame("Frame", "WicksLedgerOptions", UIParent)
    optPanel:SetSize(OPT_W, OPT_H)
    optPanel:SetFrameStrata("HIGH")
    optPanel:SetClampedToScreen(true)
    optPanel:SetMovable(true)
    optPanel:EnableMouse(true)
    optPanel:RegisterForDrag("LeftButton")
    optPanel:SetScript("OnDragStart", function(self)
        WicksSnap.Detach("ledger_opt")
        self:StartMoving()
    end)
    optPanel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        WicksSnap.TrySnap("ledger_opt")
        SavePos("optPos", self)
    end)

    LoadPos("optPos", optPanel, "CENTER", 100, 0)

    -- bg child so FontStrings on optPanel are visible
    MakeBgChild(optPanel, C_BG[1], C_BG[2], C_BG[3], 0.98)
    AddBorder(optPanel)

    -- Header: bg child on a header sub-frame
    local header = CreateFrame("Frame", nil, optPanel)
    header:SetHeight(HEADER_H)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT")
    MakeBgChild(header, C_HEADER[1], C_HEADER[2], C_HEADER[3], 1)
    local hsep = header:CreateTexture(nil, "BORDER")
    hsep:SetColorTexture(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)
    hsep:SetHeight(1); hsep:SetPoint("BOTTOMLEFT"); hsep:SetPoint("BOTTOMRIGHT")
    -- All 4 brackets on the header anchored to optPanel corners
    do
        local function optBrk(anchor)
            local h = header:CreateTexture(nil, "OVERLAY")
            h:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
            h:SetPoint(anchor, optPanel, anchor); h:SetSize(10, 2)
            local v = header:CreateTexture(nil, "OVERLAY")
            v:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
            v:SetPoint(anchor, optPanel, anchor); v:SetSize(2, 10)
        end
        optBrk("TOPLEFT"); optBrk("TOPRIGHT")
        optBrk("BOTTOMLEFT"); optBrk("BOTTOMRIGHT")
    end

    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    title:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
    title:SetPoint("LEFT", header, "TOPLEFT", PAD, -HEADER_H / 2)
    title:SetText("Options")

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(HEADER_H, HEADER_H)
    closeBtn:SetPoint("RIGHT", header, "TOPRIGHT", 0, -HEADER_H / 2)
    local closeTex = closeBtn:CreateFontString(nil, "OVERLAY")
    closeTex:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    closeTex:SetTextColor(C_DIM[1], C_DIM[2], C_DIM[3], 1)
    closeTex:SetAllPoints(); closeTex:SetJustifyH("CENTER"); closeTex:SetJustifyV("MIDDLE")
    closeTex:SetText("x")
    closeBtn:SetScript("OnClick", function() optPanel:Hide() end)

    -- ---- Price source section ----
    local srcLabel = optPanel:CreateFontString(nil, "OVERLAY")
    srcLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    srcLabel:SetTextColor(C_DIM[1], C_DIM[2], C_DIM[3], 1)
    srcLabel:SetPoint("TOPLEFT", optPanel, "TOPLEFT", PAD, -(HEADER_H + 10))
    srcLabel:SetText("PRICE SOURCE")

    local SOURCES = { "auto", "TSM", "Auctionator", "Auctioneer", "vendor" }
    local SOURCE_LABELS = {
        auto        = "Auto  (TSM > Auctionator > Auctioneer > Vendor)",
        TSM         = "TSM  (TradeSkillMaster)",
        Auctionator = "Auctionator",
        Auctioneer  = "Auctioneer",
        vendor      = "Vendor only",
    }

    local radioFrames = {}

    local function RefreshRadios()
        local cur = WL.db and WL.db.priceSource or "auto"
        for _, rf in ipairs(radioFrames) do
            local sel = (rf.src == cur)
            rf.dot:SetVertexColor(
                sel and C_GREEN[1] or C_DIM[1],
                sel and C_GREEN[2] or C_DIM[2],
                sel and C_GREEN[3] or C_DIM[3], 1)
            rf.lbl:SetTextColor(
                sel and C_TEXT[1] or C_DIM[1],
                sel and C_TEXT[2] or C_DIM[2],
                sel and C_TEXT[3] or C_DIM[3], 1)
        end
    end

    for i, src in ipairs(SOURCES) do
        local rf = CreateFrame("Button", nil, optPanel)
        rf:SetHeight(ROW_Y)
        local yOff = -(HEADER_H + 22 + (i - 1) * ROW_Y)
        rf:SetPoint("TOPLEFT",  optPanel, "TOPLEFT",  PAD,  yOff)
        rf:SetPoint("TOPRIGHT", optPanel, "TOPRIGHT", -PAD, yOff)
        rf.src = src

        local dot = rf:CreateTexture(nil, "ARTWORK")
        dot:SetSize(7, 7)
        dot:SetColorTexture(C_DIM[1], C_DIM[2], C_DIM[3], 1)
        dot:SetPoint("LEFT", rf, "LEFT", 0, 0)
        rf.dot = dot

        local lbl = rf:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        lbl:SetTextColor(C_DIM[1], C_DIM[2], C_DIM[3], 1)
        lbl:SetPoint("LEFT", dot, "RIGHT", 6, 0)
        lbl:SetText(SOURCE_LABELS[src])
        rf.lbl = lbl

        rf:SetScript("OnClick", function()
            if WL.db then WL.db.priceSource = src end
            RefreshRadios()
        end)
        table.insert(radioFrames, rf)
    end

    -- Divider
    local divY = HEADER_H + 22 + #SOURCES * ROW_Y + 6
    local div = optPanel:CreateTexture(nil, "BORDER")
    div:SetColorTexture(C_BORDER[1], C_BORDER[2], C_BORDER[3], 0.5)
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  optPanel, "TOPLEFT",  PAD,  -divY)
    div:SetPoint("TOPRIGHT", optPanel, "TOPRIGHT", -PAD, -divY)

    -- Auto mode toggle
    local autoY = divY + 10
    local autoBtn = CreateFrame("Button", nil, optPanel)
    autoBtn:SetHeight(ROW_Y)
    autoBtn:SetPoint("TOPLEFT",  optPanel, "TOPLEFT",  PAD,  -autoY)
    autoBtn:SetPoint("TOPRIGHT", optPanel, "TOPRIGHT", -PAD, -autoY)

    local autoDot = autoBtn:CreateTexture(nil, "ARTWORK")
    autoDot:SetSize(7, 7)
    autoDot:SetPoint("LEFT", autoBtn, "LEFT", 0, 0)
    autoBtn.dot = autoDot

    local autoLbl = autoBtn:CreateFontString(nil, "OVERLAY")
    autoLbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    autoLbl:SetPoint("LEFT", autoDot, "RIGHT", 6, 0)
    autoLbl:SetText("Auto-start on instance entry")
    autoBtn.lbl = autoLbl

    local function RefreshAutoBtn()
        local on = WL.db and WL.db.autoMode
        autoDot:SetVertexColor(
            on and C_GREEN[1] or C_DIM[1],
            on and C_GREEN[2] or C_DIM[2],
            on and C_GREEN[3] or C_DIM[3], 1)
        autoLbl:SetTextColor(
            on and C_TEXT[1] or C_DIM[1],
            on and C_TEXT[2] or C_DIM[2],
            on and C_TEXT[3] or C_DIM[3], 1)
    end

    autoBtn:SetScript("OnClick", function()
        if WL.db then WL.db.autoMode = not WL.db.autoMode end
        RefreshAutoBtn()
    end)

    -- Hard lock toggle
    local hardY = autoY + ROW_Y
    local hardBtn = CreateFrame("Button", nil, optPanel)
    hardBtn:SetHeight(ROW_Y)
    hardBtn:SetPoint("TOPLEFT",  optPanel, "TOPLEFT",  PAD,  -hardY)
    hardBtn:SetPoint("TOPRIGHT", optPanel, "TOPRIGHT", -PAD, -hardY)

    local hardDot = hardBtn:CreateTexture(nil, "ARTWORK")
    hardDot:SetSize(7, 7)
    hardDot:SetPoint("LEFT", hardBtn, "LEFT", 0, 0)
    hardBtn.dot = hardDot

    local hardLbl = hardBtn:CreateFontString(nil, "OVERLAY")
    hardLbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    hardLbl:SetPoint("LEFT", hardDot, "RIGHT", 6, 0)
    hardLbl:SetText("Hard lock  (persist across resets)")
    hardBtn.lbl = hardLbl

    local function RefreshHardBtn()
        local on = WL.db and WL.db.hardLock
        hardDot:SetVertexColor(
            on and C_GREEN[1] or C_DIM[1],
            on and C_GREEN[2] or C_DIM[2],
            on and C_GREEN[3] or C_DIM[3], 1)
        hardLbl:SetTextColor(
            on and C_TEXT[1] or C_DIM[1],
            on and C_TEXT[2] or C_DIM[2],
            on and C_TEXT[3] or C_DIM[3], 1)
    end

    hardBtn:SetScript("OnClick", function()
        if WL.db then WL.db.hardLock = not WL.db.hardLock end
        RefreshHardBtn()
    end)
    hardBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Hard lock", 1, 1, 1)
        GameTooltip:AddLine("Session pauses on instance exit instead of stopping.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Re-enter the instance to resume where you left off.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    hardBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Divider 2
    local div2Y = hardY + ROW_Y + 6
    local div2 = optPanel:CreateTexture(nil, "BORDER")
    div2:SetColorTexture(C_BORDER[1], C_BORDER[2], C_BORDER[3], 0.5)
    div2:SetHeight(1)
    div2:SetPoint("TOPLEFT",  optPanel, "TOPLEFT",  PAD,  -div2Y)
    div2:SetPoint("TOPRIGHT", optPanel, "TOPRIGHT", -PAD, -div2Y)

    -- Reset session button
    local resetY = div2Y + 10
    local resetBtn = CreateFrame("Button", nil, optPanel)
    resetBtn:SetHeight(ROW_Y)
    resetBtn:SetPoint("TOPLEFT",  optPanel, "TOPLEFT",  PAD,  -resetY)
    resetBtn:SetPoint("TOPRIGHT", optPanel, "TOPRIGHT", -PAD, -resetY)

    local resetTex = resetBtn:CreateFontString(nil, "OVERLAY")
    resetTex:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    resetTex:SetTextColor(1, 0.4, 0.4, 1)
    resetTex:SetPoint("LEFT", resetBtn, "LEFT", 0, 0)
    resetTex:SetText("Reset session")

    resetBtn:SetScript("OnClick", function()
        if WL.Session and WL.Session.Reset then WL.Session:Reset() end
    end)
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Clear all session data", 1, 0.4, 0.4)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    optPanel:SetScript("OnShow", function()
        RefreshRadios()
        RefreshAutoBtn()
        RefreshHardBtn()
    end)

    WicksSnap.Register("ledger_opt", optPanel)
    optPanel:Hide()
end

function UI:ToggleOptions()
    if not optPanel then BuildOptions() end
    if optPanel:IsShown() then
        optPanel:Hide()
        if WL.db then WL.db.optShown = false end
    else
        optPanel:Show()
        if WL.db then WL.db.optShown = true end
    end
end

-- ============================================================
-- CONTEXT MENU
-- A minimal right-click menu. One item at a time; hides on any click outside.
-- ============================================================
local ctxMenu

local function BuildContextMenu()
    ctxMenu = CreateFrame("Frame", "WicksLedgerCtxMenu", UIParent)
    ctxMenu:SetFrameStrata("TOOLTIP")
    ctxMenu:SetClampedToScreen(true)
    ctxMenu:EnableMouse(true)
    MakeBgChild(ctxMenu, C_BG[1], C_BG[2], C_BG[3], 0.98)
    AddBorder(ctxMenu)
    ctxMenu:Hide()
    ctxMenu:SetScript("OnLeave", function() ctxMenu:Hide() end)
    ctxMenu._items = {}
end

local function ShowContextMenu(x, y, items)
    if not ctxMenu then BuildContextMenu() end

    -- Release old item buttons
    for _, btn in ipairs(ctxMenu._items) do btn:Hide() end
    ctxMenu._items = {}

    local ITEM_H = 22
    local menuW   = 180
    local yOff    = -4

    for _, item in ipairs(items) do
        local btn = CreateFrame("Button", nil, ctxMenu)
        btn:SetSize(menuW - 8, ITEM_H)
        btn:SetPoint("TOPLEFT", ctxMenu, "TOPLEFT", 4, yOff)
        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        lbl:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], 1)
        lbl:SetAllPoints(); lbl:SetJustifyH("LEFT"); lbl:SetJustifyV("MIDDLE")
        lbl:SetText(item.label)
        btn:SetScript("OnEnter", function() lbl:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1) end)
        btn:SetScript("OnLeave", function() lbl:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], 1) end)
        btn:SetScript("OnClick", function()
            ctxMenu:Hide()
            if item.onClick then item.onClick() end
        end)
        yOff = yOff - ITEM_H
        table.insert(ctxMenu._items, btn)
    end

    ctxMenu:SetSize(menuW, -yOff + 4)
    ctxMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    ctxMenu:Show()
end


-- ============================================================
-- PANEL POPULATION
-- ============================================================
PopulateHistory = function()
    local content = panel.content
    for _, row in ipairs(activeRows) do ReleaseRow(row) end
    activeRows = {}

    if panel.footer then panel.footer:Hide() end

    local P = WL.Prices
    local history = WL.charDB and WL.charDB.history or {}
    local panW    = panel:GetWidth()
    local y       = 0

    if #history == 0 then
        local row = AcquireRow(content, panW)
        table.insert(activeRows, row)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        row.icon:SetTexture(nil)
        row.name:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        row.name:SetTextColor(C_DIM[1], C_DIM[2], C_DIM[3], 1)
        row.name:SetText("No past sessions yet")
        row.value:SetText("")
        y = y + ROW_H
    else
        for i, entry in ipairs(history) do
            -- Section header: date + zone
            local dateStr = entry.startTime and date("%Y-%m-%d %H:%M", entry.startTime) or "?"
            local zone = entry.zoneName or "?"
            local hdr = AcquireRow(content, panW)
            table.insert(activeRows, hdr)
            hdr:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
            hdr:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
            hdr.icon:SetTexture(nil)
            hdr.name:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
            hdr.name:SetTextColor(C_DIM[1], C_DIM[2], C_DIM[3], 1)
            hdr.name:SetText(string.format("#%d  %s  %s", i, dateStr, zone))
            -- elapsed + total on right
            local elapsed = entry.elapsed or 0
            local h = math.floor(elapsed / 3600)
            local m = math.floor((elapsed % 3600) / 60)
            local timeStr = h > 0 and string.format("%dh%dm", h, m) or string.format("%dm", m)
            hdr.value:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
            hdr.value:SetTextColor(C_DIM[1], C_DIM[2], C_DIM[3], 1)
            hdr.value:SetText(timeStr)
            y = y + ROW_H

            -- Total earned row
            local totalRow = AcquireRow(content, panW)
            table.insert(activeRows, totalRow)
            totalRow:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
            totalRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
            totalRow.icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
            totalRow.icon:SetTexCoord(0, 1, 0, 1)
            totalRow.name:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            totalRow.name:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], 1)
            totalRow.name:SetText("Total earned")
            local hrFactor = (elapsed > 60) and (3600 / elapsed) or 0
            local totalStr = P and P:FormatCopper(entry.totalCopper or 0) or "?"
            if hrFactor > 0 and P then
                totalStr = totalStr .. "  |cff888888(" .. P:FormatGold((entry.totalCopper or 0) * hrFactor) .. "/hr)|r"
            end
            totalRow.value:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            totalRow.value:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], 1)
            totalRow.value:SetText(totalStr)
            y = y + ROW_H

            -- Divider between sessions
            if i < #history then
                local divRow = AcquireRow(content, panW)
                table.insert(activeRows, divRow)
                divRow:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
                divRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
                divRow:SetHeight(6)
                divRow.icon:SetTexture(nil)
                divRow.name:SetText("")
                divRow.value:SetText("")
                y = y + 6
            end
        end
    end

    content:SetWidth(panW - 2)
    content:SetHeight(math.max(y, 1))
end

PopulatePanel = function()
    local content = panel.content
    for _, row in ipairs(activeRows) do ReleaseRow(row) end
    activeRows = {}

    if panel.footer then panel.footer:Show() end
    if panel.totalLabel then panel.totalLabel:SetText("Total") end

    local S = WL.Session
    if not S then return end
    local P = WL.Prices

    local elapsed  = S:Elapsed()
    local hrFactor = elapsed > 60 and (3600 / elapsed) or 0
    local panW     = panel:GetWidth()

    local y = 0

    local function SectionLabel(txt)
        local row = AcquireRow(content, panW)
        table.insert(activeRows, row)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        row.icon:SetTexture(nil)
        row.name:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
        row.name:SetTextColor(C_DIM[1], C_DIM[2], C_DIM[3], 1)
        row.name:SetText(txt)
        row.value:SetText("")
        y = y + ROW_H
    end

    -- ---- Gold ----
    SectionLabel("Gold")
    local goldRow = AcquireRow(content, panW)
    table.insert(activeRows, goldRow)
    goldRow:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
    goldRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
    goldRow.icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    goldRow.icon:SetTexCoord(0, 1, 0, 1)
    goldRow.name:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    goldRow.name:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], 1)
    goldRow.name:SetText("Raw gold")
    goldRow.value:SetText(P:FormatCopper(S.goldDelta))
    y = y + ROW_H

    -- ---- Items ----
    local items = {}
    for _, entry in pairs(S.loot) do
        if not entry.isJunk then table.insert(items, entry) end
    end
    table.sort(items, function(a, b)
        return (a.copper or 0) * (a.count or 1) > (b.copper or 0) * (b.count or 1)
    end)

    local junk = S.loot["junk"]
    if #items > 0 or junk then
        SectionLabel("Items")
        for _, entry in ipairs(items) do
            local row = AcquireRow(content, panW)
            table.insert(activeRows, row)
            row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
            row.name:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            row.name:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], 1)

            if entry.icon then
                row.icon:SetTexture(entry.icon)
                row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            else
                row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end

            local nameStr = entry.link or ("item:" .. entry.itemID)
            if entry.count > 1 then
                nameStr = nameStr .. " |cff888888x" .. entry.count .. "|r"
            end
            row.name:SetText(nameStr)

            local lineVal = (entry.copper or 0) * (entry.count or 1)
            local valStr  = P:FormatCopper(lineVal)
            if entry.source == "vendor" then
                valStr = valStr .. " |cff888888v|r"
            elseif entry.source == "unknown" then
                valStr = "|cff888888?|r"
            end
            row.value:SetText(valStr)

            local itemKey = tostring(entry.itemID)
            row:SetScript("OnEnter", function(self)
                if entry.link then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(entry.link)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row:SetScript("OnMouseUp", function(self, btn)
                if btn ~= "RightButton" then return end
                GameTooltip:Hide()
                local cx, cy = GetCursorPosition()
                local scale  = UIParent:GetEffectiveScale()
                local sx, sy = cx / scale, cy / scale
                local menuItems = {}
                if entry.source ~= "vendor" then
                    table.insert(menuItems, {
                        label   = "Revert to vendor price",
                        onClick = function()
                            if WL.Session then WL.Session:SetItemVendorPrice(itemKey) end
                        end,
                    })
                end
                if #menuItems > 0 then
                    ShowContextMenu(sx, sy, menuItems)
                end
            end)

            y = y + ROW_H
        end

        -- Junk row: collapsed grey items at the bottom of the items list
        if junk and (junk.copper or 0) > 0 then
            local row = AcquireRow(content, panW)
            table.insert(activeRows, row)
            row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
            row.name:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            row.name:SetTextColor(C_DIM[1], C_DIM[2], C_DIM[3], 1)
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_07")
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local nameStr = "Junk"
            if (junk.count or 0) > 1 then
                nameStr = nameStr .. " |cff888888x" .. junk.count .. "|r"
            end
            row.name:SetText(nameStr)
            row.value:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            row.value:SetTextColor(C_DIM[1], C_DIM[2], C_DIM[3], 1)
            row.value:SetText(P:FormatCopper(junk.copper) .. " |cff888888v|r")
            y = y + ROW_H
        end
    end

    -- ---- XP ----
    if not S.maxLevel then
        SectionLabel("Experience")
        local xpRow = AcquireRow(content, panW)
        table.insert(activeRows, xpRow)
        xpRow:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
        xpRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        xpRow.icon:SetTexture("Interface\\Icons\\Spell_Holy_BorrowedTime")
        xpRow.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        xpRow.name:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        xpRow.name:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], 1)
        xpRow.name:SetText("Experience")
        local xpStr = FormatXP(S.xpDelta or 0) .. " XP"
        if hrFactor > 0 then
            xpStr = xpStr .. "  |cff888888(" .. FormatXP(math.floor((S.xpDelta or 0) * hrFactor)) .. "/hr)|r"
        end
        xpRow.value:SetText(xpStr)
        y = y + ROW_H
    end

    -- ---- Rep ----
    if next(S.rep) then
        SectionLabel("Reputation")
        local factions = {}
        for _, data in pairs(S.rep) do table.insert(factions, data) end
        table.sort(factions, function(a, b) return (a.delta or 0) > (b.delta or 0) end)
        for _, data in ipairs(factions) do
            local row = AcquireRow(content, panW)
            table.insert(activeRows, row)
            row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
            row.icon:SetTexture("Interface\\Icons\\Spell_Holy_PrayerofSpirit")
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            row.name:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            row.name:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], 1)
            row.name:SetText(data.name or "?")
            local repStr = (data.delta or 0) .. " rep"
            if hrFactor > 0 then
                repStr = repStr .. "  |cff888888(" .. math.floor((data.delta or 0) * hrFactor) .. "/hr)|r"
            end
            row.value:SetText(repStr)
            y = y + ROW_H
        end
    end

    content:SetWidth(panW - 2)
    content:SetHeight(math.max(y, 1))

    -- Clamp panel height to content (respecting saved resize)
    local savedH = WL.db and WL.db.panelSize and WL.db.panelSize.h
    if not savedH then
        local innerH = HEADER_H + 2 + y + FOOTER_H + 2
        panel:SetHeight(math.max(math.min(innerH, PANEL_H_MAX), PANEL_H_MIN + HEADER_H + FOOTER_H))
    end

    local totalStr = P:FormatCopper(S.totalCopper)
    if hrFactor > 0 then
        totalStr = totalStr .. "  |cff888888(" .. P:FormatGold(S.totalCopper * hrFactor) .. "/hr)|r"
    end
    panel.totalValue:SetText(totalStr)
end

-- ============================================================
-- PUBLIC API
-- ============================================================
function UI:OpenPanel()
    if not panel then BuildPanel() end
    PopulatePanel()
    panel:Show()
    panelOpen = true
    if expandBtn then expandBtn.label:SetText("-") end
    if WL.db then WL.db.panelShown = true end
end

function UI:ClosePanel()
    if panel then panel:Hide() end
    panelOpen = false
    if expandBtn then expandBtn.label:SetText("+") end
    if WL.db then WL.db.panelShown = false end
end

function UI:Toggle()
    if bar and bar:IsShown() then
        bar:Hide()
        if WL.db then WL.db.barShown = false end
        UI:ClosePanel()
    else
        if not bar then BuildBar() end
        bar:Show()
        if WL.db then WL.db.barShown = true end
    end
end

function UI:OnSessionStart()
    if not bar then BuildBar() end
    bar:Show()
    if WL.db then WL.db.barShown = true end
    if bar.UpdateSSBtn then bar.UpdateSSBtn() end
    if panelOpen then
        if panel and panel.switchTab then panel.switchTab("session") end
        PopulatePanel()
    end
end

function UI:OnSessionStop()
    if bar and bar.UpdateSSBtn then bar.UpdateSSBtn() end
    if panelOpen then
        if panel and panel.getActiveTab and panel.getActiveTab() ~= "history" then
            PopulatePanel()
        end
    end
end

function UI:OnSessionReset()
    if statusText then statusText:SetText("idle") end
    if panelOpen then
        if panel and panel.switchTab then panel.switchTab("session") end
        PopulatePanel()
    end
end

function UI:OnUpdate()
    if panelOpen then
        if panel and panel.getActiveTab and panel.getActiveTab() == "history" then return end
        PopulatePanel()
    end
end

-- ============================================================
-- INIT
-- ============================================================
WL:On("LOGIN", function()
    -- Restore window visibility from last session
    if WL.db.barShown then
        if not bar then BuildBar() end
        bar:Show()
        if bar.UpdateSSBtn then bar.UpdateSSBtn() end
    end
    if WL.db.panelShown then
        UI:OpenPanel()
    end
end)
