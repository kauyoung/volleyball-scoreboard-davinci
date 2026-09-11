--[[
================================================================================
 Volleyball scoreboard — Fusion node graph builder
================================================================================

 Builds the entire scoreboard node graph described in
 fusion-scoreboard-walkthrough.md, correctly merged and correctly named.

 HOW TO RUN
   1. Edit page -> add a Fusion Composition to V2 -> click the Fusion tab.
   2. Workspace -> Console. Open this FIRST — it is the only place this
      script's output and warnings appear. If the Console window doesn't show
      up, it has probably remembered a position on a monitor you're no longer
      using; drag it back or reset the UI layout.
   3. Workspace -> Scripts -> Comp -> build-scoreboard
      This file must live in:
        %APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Comp\
      Editing the copy in your working folder does NOT change what the Scripts
      menu runs — copy it over each time, or run it straight from source with:
        dofile("C:/Users/YOURNAME/scoreboard-pipeline/build-scoreboard.lua")

 BEFORE EACH MATCH
   Change TEAM2_NAME below and re-run. Do NOT type the opponent's name into
   the Team2Name node in Fusion:
     - this script computes each name's X position FROM the string, so a name
       typed into the node keeps the position calculated for the old one; and
     - CLEAR_EXISTING wipes the graph on every run, so it would be lost anyway.

 WARNING — CLEAR_EXISTING is true, so every run deletes the whole graph and
   rebuilds it. That's harmless today. It stops being harmless the moment the
   phase-2 script writes score/serve keyframes: re-running this builder will
   destroy them. Set CLEAR_EXISTING = false before keyframing a real match.

 Node names match the walkthrough exactly, so the phase-2 keyframing script
 will find them. Nothing needs finishing by hand.
================================================================================
--]]

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------

local SERVE_ICON_PATH = [[C:\Users\YOURNAME\Documents\Resolve Assets\volleyball-serve-icon.png]]

local TEAM1_NAME = "Home Team"
local TEAM2_NAME = "Opponent"

local FONT       = "Gotham"
local FONT_STYLE = "Medium"

local CLEAR_EXISTING = true    -- true = delete every node except MediaOut1 first

-- Overall scale of the whole scorebar. 1.0 = the original full-width version.
-- This drives the MasterSize Transform, which scales about the bar's own centre
-- so the bar stays put at the bottom of frame as you change it.
local OVERALL_SIZE = 0.70

-- Serve ball size, relative to the SOURCE PNG (512px), not the frame.
-- Set by measuring the render, not by calculation: the icon has transparent
-- padding inside its 512px canvas, so the visible ball is meaningfully smaller
-- than the canvas and the arithmetic (512 x size) overstates it. At 0.11 the
-- ball measured ~80% of the team name's cap height; 0.14 brings it level.
local SERVE_SIZE = 0.14

-- Team colours — change these to your own
local GREEN = { 0.439, 0.835, 0.286 }   -- #70D549  Team 1 (example)
local BLUE  = { 0.039, 0.518, 1.000 }   -- #0A84FF  Team 2 (example)
local BLACK = { 0.008, 0.012, 0.012 }   -- #020303  club black
local WHITE = { 1.0,   1.0,   1.0   }

--------------------------------------------------------------------------------
-- SETUP
--------------------------------------------------------------------------------

local comp = comp or (fusion and fusion:GetCurrentComp())
if not comp then
  print("ERROR: No composition found. Open the Fusion page on a Fusion Composition clip, then run again.")
  return
end

-- Node graph layout grid
local COL, ROW = 1, 1
local function pos(col, row) return col * 1.1, row * 1.1 end

-- Tidy layout. Every node gets placed again as the chain is built, so that each
-- Merge sits in one straight row with the element it composites directly below
-- it, and that element's mask (or loader) directly below again:
--
--   BarBG ─ Merge1 ─ Merge2 ─ Merge3 ─ ...      <- row 0
--             │        │        │
--         ScoreCell ScoreDiv  SepLeft           <- row 1  (the new element)
--             │        │        │
--          ...Shape  ...Shape ...Shape          <- row 2  (its mask)
--
-- Without this, elements keep whatever column they happened to be created in,
-- so the connecting wires fan out across the graph and cross each other.
local flow = comp.CurrentFrame and comp.CurrentFrame.FlowView
local childOf = {}

local function setPos(tool, col, row)
  if tool and flow then
    pcall(function() flow:SetPos(tool, col * 1.1, row * 1.1) end)
  end
end

--------------------------------------------------------------------------------
-- HELPERS  (defensive: input names differ slightly between Resolve versions,
--           so every set is wrapped — a miss warns instead of aborting)
--------------------------------------------------------------------------------

local warnings = {}

local function warn(msg)
  warnings[#warnings + 1] = msg
end

local function setv(tool, name, value)
  if not tool then return end
  local ok = pcall(function() tool[name][0] = value end)
  if not ok then
    ok = pcall(function() tool:SetInput(name, value, 0) end)
  end
  if not ok then
    warn(string.format("Could not set '%s' on %s — set it by hand in the Inspector.",
                       name, tool:GetAttrs().TOOLS_Name or "?"))
  end
end

local function setPoint(tool, name, x, y)
  if not tool then return end
  local ok = pcall(function() tool[name][0] = { x, y } end)
  if not ok then
    ok = pcall(function() tool:SetInput(name, { x, y }, 0) end)
  end
  if not ok then
    warn(string.format("Could not set point '%s' on %s — position it by hand.",
                       name, tool:GetAttrs().TOOLS_Name or "?"))
  end
end

local function add(toolID, name, col, row)
  local x, y = pos(col, row)
  local t = comp:AddTool(toolID, x, y)
  if not t then
    warn(string.format("Could not create a '%s' node (for %s). Add it by hand.", toolID, name))
    return nil
  end
  t:SetAttrs({ TOOLS_Name = name })
  return t
end

-- A "plate": solid-colour Background masked by a RectangleMask.
-- This is the Background + Rectangle-in-the-blue-input pattern from the guide.
local function plate(name, colour, alpha, rect, col, row)
  local bg = add("Background", name, col, row)
  if not bg then return nil end
  setv(bg, "TopLeftRed",   colour[1])
  setv(bg, "TopLeftGreen", colour[2])
  setv(bg, "TopLeftBlue",  colour[3])
  -- NOTE: don't put the translucency on the Background's own alpha. Once an
  -- Effect Mask is attached, the mask drives the alpha channel and the
  -- Background's alpha is ignored — which is why a 0.74 bar renders solid.
  -- The mask's Level is the lever that actually works (set below).
  setv(bg, "TopLeftAlpha", 1.0)
  setv(bg, "UseFrameFormatSettings", 1)

  local mask = add("RectangleMask", name .. "Shape", col, row - 1)
  if mask then
    setv(mask, "UseFrameFormatSettings", 1)
    setv(mask, "Level", alpha)   -- this is the element's real opacity
    setv(mask, "Width",  rect.w)
    setv(mask, "Height", rect.h)
    setPoint(mask, "Center", rect.x, rect.y)
    setv(mask, "CornerRadius", rect.r or 0)

    -- Connect the mask into the Background's Effect Mask (the blue input).
    -- Note: a RectangleMask's output is named "Mask", NOT "Output" — assigning
    -- mask.Output here silently does nothing and the Background fills frame.
    pcall(function() bg:ConnectInput("EffectMask", mask) end)

    local connected = false
    pcall(function() connected = bg.EffectMask:GetConnectedOutput() ~= nil end)
    if not connected then
      pcall(function() bg.EffectMask = mask.Mask end)
      pcall(function() connected = bg.EffectMask:GetConnectedOutput() ~= nil end)
    end
    if not connected then
      warn(string.format("%s: mask not connected — drag %s into its blue input by hand.",
                         name, name .. "Shape"))
    end
    childOf[bg] = mask   -- so the layout pass can stack it under its Background
  end
  return bg
end

local function text(name, str, size, colour, alpha, x, y, col, row)
  local t = add("TextPlus", name, col, row)
  if not t then return nil end
  setv(t, "UseFrameFormatSettings", 1)
  setv(t, "StyledText", str)
  setv(t, "Font",  FONT)
  setv(t, "Style", FONT_STYLE)
  setv(t, "Size",  size)
  setv(t, "Red1",   colour[1])
  setv(t, "Green1", colour[2])
  setv(t, "Blue1",  colour[3])
  setv(t, "Alpha1", alpha or 1.0)
  setPoint(t, "Center", x, y)
  return t
end

--------------------------------------------------------------------------------
-- BUILD
--------------------------------------------------------------------------------

comp:Lock()
comp:StartUndo("Build scoreboard")

-- Optionally clear the graph
if CLEAR_EXISTING then
  for _, t in pairs(comp:GetToolList(false)) do
    local n = t:GetAttrs().TOOLS_Name or ""
    if not n:match("^MediaOut") then t:Delete() end
  end
end

local mediaOut = comp:FindTool("MediaOut1")

-- Step 2 — the bar --------------------------------------------------------
local top = plate("BarBG", BLACK, 0.74,
                  { w = 0.75, h = 0.115, x = 0.5, y = 0.115, r = 0.50 }, COL, ROW)

if not top then
  comp:EndUndo(true) comp:Unlock()
  print("ERROR: could not create the base bar. Aborting.")
  return
end

setPos(top, 0, 0)             -- BarBG starts the row
setPos(childOf[top], 0, 1)    -- BarShape sits under it

local mergeCount = 0

-- Stack a new element on top of everything so far.
-- previous -> orange (Background) | new -> green (Foreground)
local function stack(element, name, blend)
  if not element then return end
  mergeCount = mergeCount + 1
  local m = add("Merge", name or ("Merge" .. mergeCount), COL + mergeCount, ROW)
  if not m then return end
  m.Background = top.Output      -- orange: everything so far
  m.Foreground = element.Output  -- green:  the one new thing
  if blend then setv(m, "Blend", blend) end

  -- Line this merge up with the element it composites, and the element's mask
  -- or loader below that. Keeps every wire short and vertical.
  setPos(m, mergeCount, 0)
  setPos(element, mergeCount, 1)
  setPos(childOf[element], mergeCount, 2)

  top = m
end

local function place(element, name, blend)
  stack(element, name, blend)
end

-- Step 3 — score cell, hairline, separators -------------------------------
place(plate("ScoreCellBG", WHITE, 0.055,
      { w = 0.134, h = 0.115, x = 0.5, y = 0.115, r = 0 }, COL + 1, ROW + 2))

-- Divider between the two live scores. Raised from 0.22 to 0.50 and thickened
-- from 0.0006 to 0.001. Both were needed: at OVERALL_SIZE 0.7 the original
-- hairline lands on ~1.6 screen pixels at 4K, which renders soft and washed out.
place(plate("ScoreDivider", WHITE, 0.50,
      { w = 0.0010, h = 0.072, x = 0.5, y = 0.115 }, COL + 2, ROW + 2))

-- Cell separators. All four share one weight so the bar reads as five cells:
--   [ name ] | [ sets ] | [ score ] | [ sets ] | [ name ]
-- Raised from 0.10 to 0.16 for the same scale-down reason as above.
place(plate("SepLeft", WHITE, 0.16,
      { w = 0.0008, h = 0.115, x = 0.433, y = 0.115 }, COL + 3, ROW + 2))

place(plate("SepRight", WHITE, 0.16,
      { w = 0.0008, h = 0.115, x = 0.567, y = 0.115 }, COL + 4, ROW + 2))

-- Dividers between each team name and its SETS column, at 0.379 / 0.621.
-- These sit 0.027 from the SETS columns (0.406 / 0.594) — exactly the same gap
-- the SETS columns have to the score separators at 0.433 / 0.567 — so each
-- SETS block is optically centred in its own cell.
place(plate("SepNameLeft", WHITE, 0.16,
      { w = 0.0008, h = 0.115, x = 0.379, y = 0.115 }, COL + 4, ROW + 4))

place(plate("SepNameRight", WHITE, 0.16,
      { w = 0.0008, h = 0.115, x = 0.621, y = 0.115 }, COL + 4, ROW + 6))

-- Step 4 — team accent bars -----------------------------------------------
place(plate("AccentLeft", GREEN, 1.0,
      { w = 0.0016, h = 0.052, x = 0.1335, y = 0.115, r = 1.0 }, COL + 5, ROW + 2))

place(plate("AccentRight", BLUE, 1.0,
      { w = 0.0016, h = 0.052, x = 0.8665, y = 0.115, r = 1.0 }, COL + 6, ROW + 2))

-- Step 5 — text ------------------------------------------------------------
-- TEAM NAMES ---------------------------------------------------------------
-- Text+ ignores a left/right anchor when it's set from a script, so both names
-- are centre-anchored. A fixed centre gives UNEQUAL margins the moment the two
-- names differ in length — a long name sat nearer its edge than a short one
-- did. So instead of hard-coding the centre, we work back from the outer edge:
-- estimate the name's width, then place its centre so the OUTER edge always
-- lands NAME_MARGIN in from the end of the bar. Both sides then match, whatever
-- the opponent is called.
local NAME_SIZE   = 0.026
local NAME_CHAR_W = 0.0138   -- Gotham Medium at NAME_SIZE, width of an average character
local NAME_MARGIN = 0.020    -- gap from the end of the bar to the start of the text
local BAR_L, BAR_R = 0.125, 0.875

-- Manual trim, if a particular pair of names still looks lopsided to the eye.
-- Positive numbers move the name to the RIGHT. Units are fractions of frame
-- width, so 0.002 is about 8px on a 4K frame.
-- -0.003 shifts Team2Name 8px left on the finished 4K frame. Note the division:
-- these units are applied BEFORE the MasterSize Transform, so they get scaled by
-- OVERALL_SIZE. 8 / (3840 * 0.70) = 0.003, not 8 / 3840.
local NAME1_NUDGE = 0.0
local NAME2_NUDGE = -0.003

-- Gotham is proportional, so counting characters and multiplying by one average
-- width is too crude: a space is roughly 40% of an average character and "l"/"i"
-- about 45%, while "W"/"M" run 35% over. Treating them all as equal made
-- "Home Team" (which contains a space) measure WIDER than it really is and
-- "Opponent" (which ends in a narrow "t") measure NARROWER — and because the two
-- names sit on opposite edges, those two errors push in opposite directions.
-- Net effect: one name drifted away from its edge while the other crept
-- toward its own. Weighting the characters removes most of that.
local CHAR_W = {
  [" "] = 0.42,
  ["i"] = 0.45, ["l"] = 0.45, ["I"] = 0.45, ["j"] = 0.45,
  ["."] = 0.45, [","] = 0.45, ["'"] = 0.45, ["!"] = 0.45, [":"] = 0.45, [";"] = 0.45,
  ["f"] = 0.60, ["t"] = 0.60, ["r"] = 0.60,
  ["W"] = 1.35, ["M"] = 1.35, ["m"] = 1.35, ["w"] = 1.35,
}

local function nameWidth(str)
  local units = 0
  for i = 1, #str do
    local c = str:sub(i, i)
    units = units + (CHAR_W[c] or 1.0)
  end
  return units * NAME_CHAR_W
end

local function nameCentre(str, side)
  local w = nameWidth(str)
  if side == "left" then return BAR_L + NAME_MARGIN + w / 2 + NAME1_NUDGE end
  return BAR_R - NAME_MARGIN - w / 2 + NAME2_NUDGE
end

-- Gotham is proportional, so a per-character average is an approximation —
-- a name full of W's and M's runs wide, one full of I's and L's runs narrow.
-- Warn if a name is long enough to reach the serve ball at 0.365 / 0.635.
local function checkName(str, side)
  local w = nameWidth(str)
  local inner = (side == "left") and (nameCentre(str, side) + w / 2)
                                 or  (nameCentre(str, side) - w / 2)
  if (side == "left" and inner > 0.350) or (side == "right" and inner < 0.650) then
    warn(string.format("Team name %q is long enough to crowd the serve ball. "
      .. "Shorten it, or drop NAME_SIZE / switch FONT to \"Gotham Narrow\".", str))
  end
end

checkName(TEAM1_NAME, "left")
checkName(TEAM2_NAME, "right")

place(text("Team1Name", TEAM1_NAME, NAME_SIZE, WHITE, 1.0,
           nameCentre(TEAM1_NAME, "left"),  0.115, COL + 7, ROW + 2))
place(text("Team2Name", TEAM2_NAME, NAME_SIZE, WHITE, 1.0,
           nameCentre(TEAM2_NAME, "right"), 0.115, COL + 8, ROW + 2))

-- SETS caption sits at 0.139 with the count at 0.101. The walkthrough's
-- 0.132 / 0.106 left only a hairline of air between the caption and the
-- number below it, which read as cramped rather than as a pair.
local l1 = text("Team1SetsLabel", "SETS", 0.011, WHITE, 0.45, 0.406, 0.139, COL + 9,  ROW + 2)
setv(l1, "CharacterSpacing", 1.25)
place(l1)

place(text("Team1Sets", "0", 0.030, WHITE, 1.0, 0.406, 0.101, COL + 10, ROW + 2))

local l2 = text("Team2SetsLabel", "SETS", 0.011, WHITE, 0.45, 0.594, 0.139, COL + 11, ROW + 2)
setv(l2, "CharacterSpacing", 1.25)
place(l2)

place(text("Team2Sets",  "0", 0.030, WHITE, 1.0, 0.594, 0.101, COL + 12, ROW + 2))
place(text("Team1Score", "0", 0.054, WHITE, 1.0, 0.466, 0.115, COL + 13, ROW + 2))
place(text("Team2Score", "0", 0.054, WHITE, 1.0, 0.534, 0.115, COL + 14, ROW + 2))

-- Step 6 — serve balls -----------------------------------------------------
-- The Loader is named Team1Serve / Team2Serve (per the spec), but the thing
-- that actually animates is the MERGE's Blend — so the merges get the
-- predictable names Team1ServeMerge / Team2ServeMerge. Phase-2 drives those.
local function serveBall(name, col)
  local ld = add("Loader", name, col, ROW + 3)
  if not ld then return nil end
  pcall(function() ld.Clip[1] = SERVE_ICON_PATH end)

  local tr = add("Transform", name .. "Xf", col, ROW + 2)
  if not tr then return ld end
  tr.Input = ld.Output
  -- A Transform's Size is relative to the SOURCE image, not the frame. The PNG
  -- is 512px, so the walkthrough's 0.02 rendered a 10px dot. See SERVE_SIZE.
  setv(tr, "Size", SERVE_SIZE)
  childOf[tr] = ld
  return tr
end

-- Position the ball on the MERGE, not on the Transform.
-- The Loader outputs a 512x512 image, so everything downstream of it works on a
-- 512x512 canvas. Setting the Transform's Center only moves the ball around
-- inside that small canvas; the Merge then drops the whole canvas at frame
-- centre, which is why the ball appeared near the middle of the picture instead
-- of on the bar. A Merge's Center IS in frame coordinates, so it goes here.
local function serveAt(mergeName, cx)
  local m = comp:FindTool(mergeName)
  if m then setPoint(m, "Center", cx, 0.115) end
end

-- Nudged 5px further from the name/sets dividers at 0.379 / 0.621 — so the left
-- ball moves left and the right ball moves right, away from its own divider.
-- These coordinates are applied BEFORE the MasterSize Transform, so 5 finished
-- pixels is 5 / (3840 * OVERALL_SIZE) = 0.00186, not 5 / 3840.
place(serveBall("Team1Serve", COL + 15), "Team1ServeMerge", 0.0)
serveAt("Team1ServeMerge", 0.3631)

place(serveBall("Team2Serve", COL + 16), "Team2ServeMerge", 0.0)
serveAt("Team2ServeMerge", 0.6369)

-- Step 7 — set pill --------------------------------------------------------
-- Pill grown from 0.05 x 0.024 to 0.075 x 0.034, with the text up from 0.014
-- to 0.017. The height/text ratio goes 1.7 -> 2.0, so the text sits inside a
-- ring of padding rather than filling the pill edge to edge.
-- Y dropped 0.038 -> 0.030 to keep the taller pill clear of the bar above it.
-- Corner radius 0.50 to match the bar, down from the full-pill 1.0.
-- Note this is a RELATIVE value: 1.0 means "as round as this shape can go",
-- i.e. radius = half the short side. Because the pill is 0.034 tall and the bar
-- is 0.115, the same 0.50 gives the same *proportional* roundness but a smaller
-- absolute radius. Matching the bar's absolute radius isn't possible here —
-- it's larger than the pill's own half-height, so it would clamp back to 1.0.
-- SET n text raised from 0.017 to 0.022, i.e. just under the team names at
-- NAME_SIZE 0.026. The pill grows with it rather than staying put: at the old
-- 0.075 x 0.034 the bigger text would have filled it edge to edge, losing the
-- padding ring. Height stays at 2x the text size and the width scales to match,
-- and the whole thing drops 0.004 to keep clear of the bar above it.
local PILL_TEXT = 0.022
local PILL_Y    = 0.026

place(plate("PillBG", BLACK, 0.74,
      { w = 0.097, h = PILL_TEXT * 2, x = 0.5, y = PILL_Y, r = 0.50 }, COL + 17, ROW + 2))

-- Text sits 0.002 above the pill's centre. Text+ centres on the font's full em
-- box (ascender to descender), but "SET 1" is all caps with no descenders, so
-- centring the box leaves the visible glyphs low. This nudge optically centres
-- the caps instead of the box.
local pillText = text("SetNumber", "SET 1", PILL_TEXT, WHITE, 0.70,
                      0.5, PILL_Y + PILL_TEXT * 0.118, COL + 18, ROW + 2)
-- Wide tracking on small caps. NOTE: in Text+ this input is CharacterSpacing
-- and it is a MULTIPLIER (1.0 = normal), not the 0.10 figure in the walkthrough
-- — 0.10 would crush the letters together rather than spread them.
setv(pillText, "CharacterSpacing", 1.20)
place(pillText)

-- Step 9 — master size dial (before the shadow, per the guide) -------------
local master = add("Transform", "MasterSize", COL + 19, ROW)
if master then
  master.Input = top.Output
  setv(master, "Size", OVERALL_SIZE)
  -- Scale about the bar's own centre, not the frame centre — otherwise shrinking
  -- the bar also lifts it up toward the middle of the picture.
  -- NOTE: on a Transform, Center is the image's POSITION; the scale anchor is
  -- Pivot. Setting Center here moves the whole comp off the bottom of frame.
  setPoint(master, "Pivot", 0.5, 0.115)
  top = master
end

-- Step 8 — drop shadow -----------------------------------------------------
local shadow = add("Shadow", "BarShadow", COL + 20, ROW)
if shadow then
  shadow.Input = top.Output
  -- The input is "Softness", not "ShadowSoftness" — the old name silently did
  -- nothing, and inspecting BarShadow confirmed Softness was still 0, i.e. the
  -- shadow was invisible. ShadowOffset is a point where 0.5,0.5 means "no
  -- offset", so the shadow also needs nudging down to be seen at all.
  setv(shadow, "Softness", 4)
  setPoint(shadow, "ShadowOffset", 0.5, 0.492)
  setv(shadow, "Alpha", 0.45)
  top = shadow
else
  warn("Drop Shadow not created — add a 'Drop Shadow' node between the last Merge and MediaOut1 by hand (Softness 16, Opacity 0.45).")
end

-- Connect to output --------------------------------------------------------
if mediaOut then
  mediaOut.Input = top.Output
else
  warn("MediaOut1 not found — connect the last node to your output by hand.")
end

-- Tail of the chain continues the same straight row.
setPos(master,   mergeCount + 1, 0)
setPos(shadow,   mergeCount + 2, 0)
setPos(mediaOut, mergeCount + 3, 0)

comp:EndUndo(true)
comp:Unlock()

--------------------------------------------------------------------------------
-- REPORT
--------------------------------------------------------------------------------

print("=====================================================")
print(" Scoreboard built.")
print(string.format(" %d merges, chained left to right.", mergeCount))
print(string.format(" Teams: %s  vs  %s", TEAM1_NAME, TEAM2_NAME))
print("")

if TEAM2_NAME == "Opponent" then
  print(" ** TEAM2_NAME is still the placeholder \"Opponent\".")
  print("    Set it at the top of THIS SCRIPT (not in the Team2Name node) and")
  print("    re-run — the name's position is calculated from the string.")
  print("")
end

if CLEAR_EXISTING then
  print(" ** CLEAR_EXISTING is on: this run deleted and rebuilt the whole graph.")
  print("    Set it to false once the phase-2 script has written keyframes,")
  print("    otherwise the next run will wipe them.")
  print("")
end

print(" If a serve ball is missing, check the icon is still at:")
print("   " .. SERVE_ICON_PATH)

if #warnings > 0 then
  print("")
  print(" Notes:")
  for _, w in ipairs(warnings) do print("   - " .. w) end
end
print("=====================================================")
