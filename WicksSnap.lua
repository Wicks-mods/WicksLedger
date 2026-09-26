-- WicksSnap.lua
-- Shared snap-to-frame system for the Wick suite.
-- Drop this file into any Wick addon and add it to the TOC before UI.lua.
--
-- Usage in each addon's UI.lua:
--
--   After building a draggable frame:
--     WicksSnap.Register("mykey", frame)
--
--   In OnDragStart:
--     WicksSnap.Detach("mykey")
--
--   In OnDragStop:
--     WicksSnap.TrySnap("mykey")

WicksSnapRegistry = WicksSnapRegistry or {}
WicksSnap        = WicksSnap        or {}

local SNAP_DIST  = 40   -- px: edge proximity to trigger snap (UIParent coords)
local RESIZE_TOL = 60   -- px: perpendicular difference allowed before resize kicks in
local GAP        = 0    -- px: resting gap between snapped edges (borders touch flush)

local Reg = WicksSnapRegistry

-- ============================================================
-- REGISTRY
-- ============================================================
function WicksSnap.Register(key, frame)
    Reg[key] = Reg[key] or {}
    Reg[key].frame     = frame
    Reg[key].preSnapW  = nil
    Reg[key].preSnapH  = nil
end

-- ============================================================
-- GEOMETRY
-- All coordinates in UIParent pixel space (what GetLeft etc return).
-- ============================================================
local function Edges(f)
    local l = f:GetLeft()   or 0
    local r = f:GetRight()  or 0
    local t = f:GetTop()    or 0
    local b = f:GetBottom() or 0
    return l, r, t, b
end

-- ============================================================
-- FIND BEST SNAP
-- Returns newL, newB, newW, newH (all in UIParent px).
-- newW/newH are 0 when no resize should happen.
-- ============================================================
local function FindSnap(dragKey)
    local dragEntry = Reg[dragKey]
    if not dragEntry or not dragEntry.frame then return end
    local df = dragEntry.frame
    if not df:IsShown() then return end

    local dl, dr, dt, db = Edges(df)
    local dw = dr - dl
    local dh = dt - db

    local bestDist = SNAP_DIST + 1
    local bestL, bestB, bestW, bestH

    for key, other in pairs(Reg) do
        if key ~= dragKey and other.frame and other.frame:IsShown() then
            local ol, or_, ot, ob = Edges(other.frame)
            local ow = or_ - ol
            local oh = ot  - ob

            -- Each candidate: which drag-edge meets which target-edge,
            -- resulting anchor position, and perpendicular info for resize.
            local candidates = {
                -- horizontal snaps (left/right edges meet — gap between)
                { de = dr,  te = ol,  -- drag-right meets target-left
                  l = ol - dw - GAP, b = db,
                  axis = "x", pd = dh, po = oh, pa = ob },
                { de = dl,  te = or_, -- drag-left meets target-right
                  l = or_ + GAP,      b = db,
                  axis = "x", pd = dh, po = oh, pa = ob },
                -- horizontal aligns (same-side flush, no gap)
                { de = dl,  te = ol,  -- drag-left aligns target-left
                  l = ol,     b = db,
                  axis = "x", pd = dh, po = oh, pa = ob },
                { de = dr,  te = or_, -- drag-right aligns target-right
                  l = or_ - dw, b = db,
                  axis = "x", pd = dh, po = oh, pa = ob },
                -- vertical snaps (top/bottom edges meet — gap between)
                { de = db,  te = ot,  -- drag-bottom meets target-top
                  l = dl,    b = ot + GAP,
                  axis = "y", pd = dw, po = ow, pa = ol },
                { de = dt,  te = ob,  -- drag-top meets target-bottom
                  l = dl,    b = ob - dh - GAP,
                  axis = "y", pd = dw, po = ow, pa = ol },
                -- vertical aligns (same-side flush, no gap)
                { de = dt,  te = ot,  -- drag-top aligns target-top
                  l = dl,    b = ot - dh,
                  axis = "y", pd = dw, po = ow, pa = ol },
                { de = db,  te = ob,  -- drag-bottom aligns target-bottom
                  l = dl,    b = ob,
                  axis = "y", pd = dw, po = ow, pa = ol },
            }

            for _, c in ipairs(candidates) do
                local dist = math.abs(c.de - c.te)
                if dist < bestDist then
                    bestDist = dist
                    bestL    = c.l
                    bestB    = c.b
                    bestW    = 0
                    bestH    = 0

                    local diff = math.abs(c.pd - c.po)
                    if diff <= RESIZE_TOL then
                        if c.axis == "x" then
                            bestH = c.po   -- resize height to match
                            bestB = c.pa   -- align bottoms
                        else
                            bestW = c.po   -- resize width to match
                            bestL = c.pa   -- align lefts
                        end
                    end
                end
            end
        end
    end

    if bestDist <= SNAP_DIST then
        return bestL, bestB, bestW, bestH
    end
end

-- ============================================================
-- PUBLIC API
-- ============================================================
function WicksSnap.Detach(key)
    local e = Reg[key]
    if not e or not e.frame then return end
    if e.preSnapW and e.preSnapW > 0 then
        e.frame:SetWidth(e.preSnapW)
        e.preSnapW = nil
    end
    if e.preSnapH and e.preSnapH > 0 then
        e.frame:SetHeight(e.preSnapH)
        e.preSnapH = nil
    end
end

function WicksSnap.TrySnap(key)
    local e = Reg[key]
    if not e or not e.frame then return end
    local df = e.frame

    local snapL, snapB, newW, newH = FindSnap(key)
    if not snapL then return end

    df:ClearAllPoints()
    df:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", snapL, snapB)

    if newH and newH > 0 then
        e.preSnapH = df:GetHeight()
        df:SetHeight(newH)
    end
    if newW and newW > 0 then
        e.preSnapW = df:GetWidth()
        df:SetWidth(newW)
    end
end
