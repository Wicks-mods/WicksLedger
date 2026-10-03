-- Wick's Ledger
-- UI.lua: slim bar + independent itemized panel + options

local ADDON, ns = ...
if not WickCore then return end   -- said once in Core.lua
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

-- Palette: tokens are references into Chrome.Colors, never copies, so a
-- look or theme change repaints every panel at once. The dim label colour
-- is the addon's own.
local Chrome    = WickCore.Chrome
local C_BG      = Chrome.Colors.voidBG
local C_HEADER  = Chrome.Colors.shadow
local C_BORDER  = Chrome.Colors.border
local C_GREEN   = Chrome.Colors.fel
local C_TEXT    = Chrome.Colors.text
local C_DIM     = { 0.42,  0.35,  0.54,  1 }

-- ============================================================
-- CHROME HELPERS
-- Rule: BACKGROUND textures go on a bg child frame.
--       FontStrings go on the parent (no bg texture on parent).
--       BORDER/ARTWORK textures on parent are fine -- only BACKGROUND blocks text.
-- A colour set on a region after it was made is remembered by Chrome, so
-- a theme change finds it; a colour that is not a token is left alone.
-- ============================================================
local function Ink(fs, c, a)
    fs:SetTextColor(c[1], c[2], c[3], a or c[4] or 1)
    Chrome:Register(fs, c, "text", a)
end
local function Paint(tex, c, a)
    tex:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1)
    Chrome:Register(tex, c, "texture", a)
end
local function Tint(tex, c, a)
    tex:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
    Chrome:Register(tex, c, "vertex", a)
end

local function MakeBgChild(parent, c, a)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    local lvl = parent:GetFrameLevel()
    f:SetFrameLevel(lvl > 0 and lvl - 1 or 0)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    Paint(t, c, a)
    return f
end

-- The border and the corner marks are the look's: a 1px line and fel
-- brackets in the flat styles, a ring in the textured ones.
local function AddBorder(f) Chrome:AddBorder(f) end
local function AddCornerAccents(f) Chrome:AddBrackets(f) end

-- One corner mark drawn on `host` at a corner of `rel`: the header and
-- footer carry the panel's marks so they draw above their own backgrounds.
-- Drawn only where the look draws marks at all.
local function Bracket(host, anchor, rel)
    if Chrome:Modern() or Chrome:Corners() == "none" then return end
    local B = Chrome.BRACKET
    local h = Chrome:Texture(host, "OVERLAY", C_GREEN); h:SetPoint(anchor, rel, anchor); h:SetSize(B, 2)
    local v = Chrome:Texture(host, "OVERLAY", C_GREEN); v:SetPoint(anchor, rel, anchor); v:SetSize(2, B)
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
        local bgChild = MakeBgChild(row, C_BORDER, 0)
        local sep = bgChild:CreateTexture(nil, "BACKGROUND")
        Paint(sep, C_BORDER, 0.3)
        sep:SetHeight(1)
        sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
        sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT")

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)
        row.icon:SetPoint("LEFT", row, "LEFT", PAD, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        row.name = row:CreateFontString(nil, "OVERLAY")
        Chrome:SetFont(row.name, 10, "")
        Ink(row.name, C_TEXT)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row.value = row:CreateFontString(nil, "OVERLAY")
        Chrome:SetFont(row.value, 10, "")
        Ink(row.value, C_TEXT)
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
    MakeBgChild(bar, C_BG)
    AddBorder(bar)
    AddCornerAccents(bar)

    local dot = bar:CreateTexture(nil, "OVERLAY")
    dot:SetSize(6, 6)
    Paint(dot, C_GREEN)
    dot:SetPoint("LEFT", bar, "LEFT", PAD, 0)
    bar.dot = dot
    dot:Hide()

    -- Expand button
    expandBtn = CreateFrame("Button", nil, bar)
    expandBtn:SetSize(20, BAR_H)
    expandBtn:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    local expandTex = expandBtn:CreateFontString(nil, "OVERLAY")
    Chrome:SetFont(expandTex, 14, "")
    Ink(expandTex, C_GREEN)
    expandTex:SetAllPoints()
    expandTex:SetJustifyH("CENTER"); expandTex:SetJustifyV("MIDDLE")
    expandTex:SetText("+")
    expandBtn.label = expandTex
    expandBtn:SetScript("OnClick", function()
        if panelOpen then UI:ClosePanel() else UI:OpenPanel() end
    end)
    expandBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Chrome:TitleMarkup("Wick's Ledger"))
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
            Tint(ssIcon, C_GREEN)
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
    Chrome:SetFont(statusText, 12, "")
    Ink(statusText, C_TEXT)
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

    MakeBgChild(panel, C_BG)
    AddBorder(panel)

    -- Header
    local header = CreateFrame("Frame", nil, panel)
    header:SetHeight(HEADER_H)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT")
    MakeBgChild(header, C_HEADER)
    local hsep = header:CreateTexture(nil, "BORDER")
    Paint(hsep, C_BORDER)
    hsep:SetHeight(1); hsep:SetPoint("BOTTOMLEFT"); hsep:SetPoint("BOTTOMRIGHT")
    Bracket(header, "TOPLEFT", panel); Bracket(header, "TOPRIGHT", panel)

    local title = header:CreateFontString(nil, "OVERLAY")
    Chrome:SetFont(title, 11, "")
    Ink(title, C_GREEN)
    title:SetPoint("LEFT", header, "TOPLEFT", PAD, -HEADER_H / 2)
    title:SetText("Wick's Ledger")

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(HEADER_H, HEADER_H)
    closeBtn:SetPoint("RIGHT", header, "TOPRIGHT", 0, -HEADER_H / 2)
    local closeTex = closeBtn:CreateFontString(nil, "OVERLAY")
    Chrome:SetFont(closeTex, 14, "")
    Ink(closeTex, C_DIM)
    closeTex:SetAllPoints(); closeTex:SetJustifyH("CENTER"); closeTex:SetJustifyV("MIDDLE")
    closeTex:SetText("x")
    closeBtn:SetScript("OnClick", function() UI:ClosePanel() end)

    local gearBtn = CreateFrame("Button", nil, header)
    gearBtn:SetSize(16, 16)
    gearBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    local gearIcon = gearBtn:CreateTexture(nil, "ARTWORK")
    gearIcon:SetAllPoints()
    gearIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    Tint(gearIcon, C_DIM)
    gearBtn:SetScript("OnClick", function() UI:ToggleOptions() end)
    gearBtn:SetScript("OnEnter", function(self)
        Tint(gearIcon, C_GREEN)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Options", 1, 1, 1)
        GameTooltip:Show()
    end)
    gearBtn:SetScript("OnLeave", function()
        Tint(gearIcon, C_DIM)
        GameTooltip:Hide()
    end)

    -- Tab strip (Session | History) below the header
    local tabStrip = CreateFrame("Frame", nil, panel)
    tabStrip:SetHeight(TAB_H)
    tabStrip:SetPoint("TOPLEFT",  panel, "TOPLEFT",  1, -HEADER_H)
    tabStrip:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -HEADER_H)
    MakeBgChild(tabStrip, C_HEADER, 0.7)
    local tabsep = tabStrip:CreateTexture(nil, "BORDER")
    Paint(tabsep, C_BORDER)
    tabsep:SetHeight(1); tabsep:SetPoint("BOTTOMLEFT"); tabsep:SetPoint("BOTTOMRIGHT")

    local activeTab = "session"

    local function makeTab(label, xOff, key)
        local btn = CreateFrame("Button", nil, tabStrip)
        btn:SetSize(70, TAB_H)
        btn:SetPoint("LEFT", tabStrip, "LEFT", xOff, 0)
        local fs = btn:CreateFontString(nil, "OVERLAY")
        Chrome:SetFont(fs, 9, "")
        fs:SetAllPoints(); fs:SetJustifyH("CENTER"); fs:SetJustifyV("MIDDLE")
        fs.key = key
        btn._label = fs
        return btn, fs
    end

    local sessionTab, sessionFS = makeTab("Session", PAD, "session")
    local historyTab, historyFS = makeTab("History", PAD + 72, "history")

    local function RefreshTabs()
        if activeTab == "session" then
            Ink(sessionFS, C_GREEN)
            Ink(historyFS, C_DIM)
        else
            Ink(sessionFS, C_DIM)
            Ink(historyFS, C_GREEN)
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
    MakeBgChild(footer, C_HEADER)
    local ftop = footer:CreateTexture(nil, "BORDER")
    Paint(ftop, C_BORDER)
    ftop:SetHeight(1); ftop:SetPoint("TOPLEFT"); ftop:SetPoint("TOPRIGHT")
    panel.footer = footer

    local totalLabel = footer:CreateFontString(nil, "OVERLAY")
    Chrome:SetFont(totalLabel, 10, "")
    Ink(totalLabel, C_DIM)
    totalLabel:SetPoint("LEFT", footer, "TOPLEFT", PAD, -FOOTER_H / 2)
    totalLabel:SetText("Total")
    panel.totalLabel = totalLabel

    local totalValue = footer:CreateFontString(nil, "OVERLAY")
    Chrome:SetFont(totalValue, 11, "")
    Ink(totalValue, C_TEXT)
    totalValue:SetPoint("RIGHT", footer, "TOPRIGHT", -PAD, -FOOTER_H / 2)
    totalValue:SetJustifyH("RIGHT")
    panel.totalValue = totalValue
    Bracket(footer, "BOTTOMLEFT", panel)

    -- Resize grip
    local grip = CreateFrame("Frame", nil, panel)
    grip:SetSize(12, 12)
    grip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    grip:EnableMouse(true)
    Bracket(grip, "BOTTOMRIGHT", grip)
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
    MakeBgChild(optPanel, C_BG, 0.98)
    AddBorder(optPanel)

    -- Header: bg child on a header sub-frame
    local header = CreateFrame("Frame", nil, optPanel)
    header:SetHeight(HEADER_H)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT")
    MakeBgChild(header, C_HEADER)
    local hsep = header:CreateTexture(nil, "BORDER")
    Paint(hsep, C_BORDER)
    hsep:SetHeight(1); hsep:SetPoint("BOTTOMLEFT"); hsep:SetPoint("BOTTOMRIGHT")
    -- All 4 brackets on the header anchored to optPanel corners
    for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do Bracket(header, corner, optPanel) end

    local title = header:CreateFontString(nil, "OVERLAY")
    Chrome:SetFont(title, 11, "")
    Ink(title, C_GREEN)
    title:SetPoint("LEFT", header, "TOPLEFT", PAD, -HEADER_H / 2)
    title:SetText("Options")

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(HEADER_H, HEADER_H)
    closeBtn:SetPoint("RIGHT", header, "TOPRIGHT", 0, -HEADER_H / 2)
    local closeTex = closeBtn:CreateFontString(nil, "OVERLAY")
    Chrome:SetFont(closeTex, 14, "")
    Ink(closeTex, C_DIM)
    closeTex:SetAllPoints(); closeTex:SetJustifyH("CENTER"); closeTex:SetJustifyV("MIDDLE")
    closeTex:SetText("x")
    closeBtn:SetScript("OnClick", function() optPanel:Hide() end)

    -- ---- Price source section ----
    local srcLabel = optPanel:CreateFontString(nil, "OVERLAY")
    Chrome:SetFont(srcLabel, 9, "")
    Ink(srcLabel, C_DIM)
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
            Tint(rf.dot, sel and C_GREEN or C_DIM)
            Ink(rf.lbl, sel and C_TEXT or C_DIM)
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
        Paint(dot, C_DIM)
        dot:SetPoint("LEFT", rf, "LEFT", 0, 0)
        rf.dot = dot

        local lbl = rf:CreateFontString(nil, "OVERLAY")
        Chrome:SetFont(lbl, 10, "")
        Ink(lbl, C_DIM)
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
    Paint(div, C_BORDER, 0.5)
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
    Chrome:SetFont(autoLbl, 10, "")
    autoLbl:SetPoint("LEFT", autoDot, "RIGHT", 6, 0)
    autoLbl:SetText("Auto-start on instance entry")
    autoBtn.lbl = autoLbl

    local function RefreshAutoBtn()
        local on = WL.db and WL.db.autoMode
        Tint(autoDot, on and C_GREEN or C_DIM)
        Ink(autoLbl, on and C_TEXT or C_DIM)
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
    Chrome:SetFont(hardLbl, 10, "")
    hardLbl:SetPoint("LEFT", hardDot, "RIGHT", 6, 0)
    hardLbl:SetText("Hard lock  (persist across resets)")
    hardBtn.lbl = hardLbl

    local function RefreshHardBtn()
        local on = WL.db and WL.db.hardLock
        Tint(hardDot, on and C_GREEN or C_DIM)
        Ink(hardLbl, on and C_TEXT or C_DIM)
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
    Paint(div2, C_BORDER, 0.5)
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
    Chrome:SetFont(resetTex, 10, "")
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
    MakeBgChild(ctxMenu, C_BG, 0.98)
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
        Chrome:SetFont(lbl, 10, "")
        Ink(lbl, C_TEXT)
        lbl:SetAllPoints(); lbl:SetJustifyH("LEFT"); lbl:SetJustifyV("MIDDLE")
        lbl:SetText(item.label)
        btn:SetScript("OnEnter", function() Ink(lbl, C_GREEN) end)
        btn:SetScript("OnLeave", function() Ink(lbl, C_TEXT) end)
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
        Chrome:SetFont(row.name, 10, "")
        Ink(row.name, C_DIM)
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
            Chrome:SetFont(hdr.name, 9, "")
            Ink(hdr.name, C_DIM)
            hdr.name:SetText(string.format("#%d  %s  %s", i, dateStr, zone))
            -- elapsed + total on right
            local elapsed = entry.elapsed or 0
            local h = math.floor(elapsed / 3600)
            local m = math.floor((elapsed % 3600) / 60)
            local timeStr = h > 0 and string.format("%dh%dm", h, m) or string.format("%dm", m)
            Chrome:SetFont(hdr.value, 9, "")
            Ink(hdr.value, C_DIM)
            hdr.value:SetText(timeStr)
            y = y + ROW_H

            -- Total earned row
            local totalRow = AcquireRow(content, panW)
            table.insert(activeRows, totalRow)
            totalRow:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
            totalRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
            totalRow.icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
            totalRow.icon:SetTexCoord(0, 1, 0, 1)
            Chrome:SetFont(totalRow.name, 10, "")
            Ink(totalRow.name, C_TEXT)
            totalRow.name:SetText("Total earned")
            local hrFactor = (elapsed > 60) and (3600 / elapsed) or 0
            local totalStr = P and P:FormatCopper(entry.totalCopper or 0) or "?"
            if hrFactor > 0 and P then
                totalStr = totalStr .. "  |cff888888(" .. P:FormatGold((entry.totalCopper or 0) * hrFactor) .. "/hr)|r"
            end
            Chrome:SetFont(totalRow.value, 10, "")
            Ink(totalRow.value, C_TEXT)
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
        Chrome:SetFont(row.name, 9, "")
        Ink(row.name, C_DIM)
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
    Chrome:SetFont(goldRow.name, 10, "")
    Ink(goldRow.name, C_TEXT)
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
            Chrome:SetFont(row.name, 10, "")
            Ink(row.name, C_TEXT)

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
            Chrome:SetFont(row.name, 10, "")
            Ink(row.name, C_DIM)
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_07")
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local nameStr = "Junk"
            if (junk.count or 0) > 1 then
                nameStr = nameStr .. " |cff888888x" .. junk.count .. "|r"
            end
            row.name:SetText(nameStr)
            Chrome:SetFont(row.value, 10, "")
            Ink(row.value, C_DIM)
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
        Chrome:SetFont(xpRow.name, 10, "")
        Ink(xpRow.name, C_TEXT)
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
            Chrome:SetFont(row.name, 10, "")
            Ink(row.name, C_TEXT)
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
