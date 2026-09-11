--[[
================================================================================
 Volleyball scoreboard — apply match data
================================================================================

 Reads a match JSON file and writes keyframes onto the scoreboard nodes built by
 build-scoreboard.lua:

   Team1Score / Team2Score   StyledText   every point
   Team1Sets  / Team2Sets    StyledText   at set end
   SetNumber                 StyledText   "SET 1" -> "SET 2" -> "SET 3"
   Team1ServeMerge.Blend     0 <-> 1      when serve changes
   Team2ServeMerge.Blend     0 <-> 1      when serve changes

 HOW TO RUN
   1. Open the Fusion Composition on the Fusion page.
   2. Workspace -> Console (so you can see the report).
   3. Workspace -> Scripts -> Comp -> apply-match

 BEFORE YOU RUN
   Set CLEAR_EXISTING = false in build-scoreboard.lua. Re-running the builder
   after this script deletes every keyframe it wrote.

 All values are held as STEP keyframes — a score must snap from 14 to 15, never
 tween through 14.5.
================================================================================
--]]

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------

-- WHERE THE MATCH FILE LIVES
--
-- Normally leave MATCH_FILE empty. The script looks for the newest .json in
-- two places, in order:
--
--   1. The newest match folder under MATCH_ROOT — i.e. alongside the footage,
--      which is the tidiest place for it
--   2. MATCH_FALLBACK, the working folder
--
-- So the routine after a game is: export from the phone, drop the .json into
-- the same folder you copied the card into, run this.
--
-- It prints the file it chose and the team names, so if it grabs the wrong one
-- you'll see it immediately rather than wondering why the scores look odd.
-- Set MATCH_FILE to a full path to override the search entirely.
local MATCH_ROOT     = [[D:\Volleyball Matches]]

-- Where this script (and its siblings assemble-match.lua / build-scoreboard.lua /
-- run-overlay.lua) live. Doubles as the fallback search location for the match
-- JSON, and where the log file below gets written. One line to change if you
-- ever move the working folder.
local WORK_DIR       = "C:/Users/YOURNAME/scoreboard-pipeline"
local MATCH_FALLBACK = WORK_DIR
local MATCH_FILE     = ""

-- Frame in the COMP that corresponds to t = 0 in the match data (i.e. the first
-- frame of your video). If the Fusion Composition starts at the same point on
-- the timeline as the footage, leave this at 0.
local COMP_START_FRAME = 0

-- Extra seconds to shift every event. Use the scorekeeper's own offset field
-- first; this is a second-chance nudge if the overlay drifts from the play.
local EXTRA_OFFSET_SEC = 0.0

local CLEAR_FIRST = true   -- remove existing keyframes before writing new ones

-- Frames per second. Leave at 0 — the script reads the real rate from the
-- composition. Only set a number here to deliberately override it.
local FPS_OVERRIDE = 0

--------------------------------------------------------------------------------
-- SETUP
--------------------------------------------------------------------------------

local comp = comp or (fusion and fusion:GetCurrentComp())
if not comp then
  print("ERROR: no composition. Open the Fusion page on your scoreboard comp.")
  return
end

local problems = {}
local function fail(msg) problems[#problems + 1] = msg end

--------------------------------------------------------------------------------
-- MINIMAL JSON READER
-- Resolve's Lua has no JSON library, so this parses the subset we emit:
-- objects, arrays, strings, numbers, true/false/null. No unicode escapes.
--------------------------------------------------------------------------------

local function parseJSON(str)
  local pos = 1

  local function skip()
    while pos <= #str and str:sub(pos, pos):match("[ \t\r\n]") do pos = pos + 1 end
  end

  local parseValue

  local function parseString()
    pos = pos + 1                        -- opening quote
    local out = {}
    while pos <= #str do
      local c = str:sub(pos, pos)
      if c == '"' then pos = pos + 1 return table.concat(out) end
      if c == "\\" then
        local n = str:sub(pos + 1, pos + 1)
        local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" }
        out[#out + 1] = map[n] or n
        pos = pos + 2
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
    error("unterminated string")
  end

  local function parseNumber()
    local s, e = str:find("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    local num = tonumber(str:sub(s, e))
    pos = e + 1
    return num
  end

  local function parseArray()
    pos = pos + 1
    local arr = {}
    skip()
    if str:sub(pos, pos) == "]" then pos = pos + 1 return arr end
    while true do
      arr[#arr + 1] = parseValue()
      skip()
      local c = str:sub(pos, pos)
      pos = pos + 1
      if c == "]" then return arr end
      if c ~= "," then error("expected , or ] at " .. pos) end
      skip()
    end
  end

  local function parseObject()
    pos = pos + 1
    local obj = {}
    skip()
    if str:sub(pos, pos) == "}" then pos = pos + 1 return obj end
    while true do
      skip()
      local key = parseString()
      skip()
      pos = pos + 1                      -- colon
      obj[key] = parseValue()
      skip()
      local c = str:sub(pos, pos)
      pos = pos + 1
      if c == "}" then return obj end
      if c ~= "," then error("expected , or } at " .. pos) end
    end
  end

  parseValue = function()
    skip()
    local c = str:sub(pos, pos)
    if c == "{" then return parseObject() end
    if c == "[" then return parseArray() end
    if c == '"' then return parseString() end
    if str:sub(pos, pos + 3) == "true"  then pos = pos + 4 return true end
    if str:sub(pos, pos + 4) == "false" then pos = pos + 5 return false end
    if str:sub(pos, pos + 3) == "null"  then pos = pos + 4 return nil end
    return parseNumber()
  end

  return parseValue()
end

--------------------------------------------------------------------------------
-- LOAD THE MATCH
--------------------------------------------------------------------------------

-- Find the newest .json in MATCH_FOLDER unless a file was named explicitly.
local function newestMatchFile(folder)
  local items
  local ok = pcall(function() items = bmd.readdir(folder .. "\\*.json") end)
  if not ok or type(items) ~= "table" then return nil end

  local bestName, bestTime
  for _, it in ipairs(items) do
    if it and it.Name and it.IsDir ~= true then
      -- LastWriteTime isn't guaranteed across versions; fall back to the name,
      -- which works because exports are prefixed with the ISO date.
      local stamp = it.LastWriteTime or it.Name
      if bestTime == nil or stamp > bestTime then
        bestTime, bestName = stamp, it.Name
      end
    end
  end
  if bestName then return folder .. "\\" .. bestName end
end

-- Newest dated subfolder of the match root, so the export can sit with the
-- footage it belongs to.
local function newestSubfolder(root)
  local items
  local ok = pcall(function() items = bmd.readdir(root .. "\\*") end)
  if not ok or type(items) ~= "table" then return nil end

  local bestName, bestStamp
  for _, it in ipairs(items) do
    if it and it.Name and it.IsDir == true
       and it.Name ~= "." and it.Name ~= ".." then
      local stamp = it.LastWriteTime or it.Name
      if bestStamp == nil or stamp > bestStamp then
        bestStamp, bestName = stamp, it.Name
      end
    end
  end
  if bestName then return root .. "\\" .. bestName end
end

if MATCH_FILE == "" then
  local matchFolder = newestSubfolder(MATCH_ROOT)
  if matchFolder then
    MATCH_FILE = newestMatchFile(matchFolder) or ""
  end
  if MATCH_FILE == "" then
    MATCH_FILE = newestMatchFile(MATCH_FALLBACK) or ""
  end
  if MATCH_FILE == "" then
    print("ERROR: no .json found in either:")
    print("  " .. tostring(matchFolder or (MATCH_ROOT .. " (no subfolders)")))
    print("  " .. MATCH_FALLBACK)
    print("Save your export in one of those, or set MATCH_FILE to a full path.")
    return
  end
end

local fh = io.open(MATCH_FILE, "r")
if not fh then
  print("ERROR: can't open match file:")
  print("  " .. MATCH_FILE)
  print("Check MATCH_ROOT / MATCH_FALLBACK / MATCH_FILE at the top of this script.")
  return
end

print("Match file: " .. MATCH_FILE)
local raw = fh:read("*a")
fh:close()

local ok, match = pcall(parseJSON, raw)
if not ok or type(match) ~= "table" or not match.events then
  print("ERROR: couldn't parse the match file — " .. tostring(match))
  return
end

--------------------------------------------------------------------------------
-- FRAME RATE
-- Event times in the match file are in SECONDS, which is deliberately frame-rate
-- agnostic — the same file has to work whether the footage was shot at 24, 30 or
-- 60 fps. The conversion to frames must therefore use the COMPOSITION's rate,
-- never a number baked into the file.
--
-- Trusting the file is what went wrong first time round: the JSON said 30, the
-- comp ran at 24, and every event landed 25% too late. Nothing errored — the
-- overlay just drifted further behind the play with every point, which over a
-- full match means the score updates minutes after the rally.
--------------------------------------------------------------------------------

local compFps
pcall(function() compFps = tonumber(comp:GetPrefs("Comp.FrameFormat.Rate")) end)

local fps, fpsSource
if FPS_OVERRIDE and FPS_OVERRIDE > 0 then
  fps, fpsSource = FPS_OVERRIDE, "FPS_OVERRIDE in this script"
elseif compFps and compFps > 0 then
  fps, fpsSource = compFps, "the composition"
else
  fps, fpsSource = (match.fps or 30), "the match file (couldn't read the comp)"
  fail("Couldn't read the composition's frame rate — fell back to the match "
    .. "file's value. Check timing before trusting the render.")
end

local baseOffset = (match.offset or 0) + EXTRA_OFFSET_SEC

if match.fps and math.abs(match.fps - fps) > 0.01 then
  fail(string.format("Match file says %g fps but the comp is %g fps. Using the "
    .. "comp — the file's value is ignored on purpose.", match.fps, fps))
end

print(string.format("Loaded %d events: %s vs %s", #match.events,
      tostring(match.team1), tostring(match.team2)))
print(string.format("Frame rate: %g fps (from %s)", fps, fpsSource))

--------------------------------------------------------------------------------
-- KEYFRAME HELPERS
--------------------------------------------------------------------------------

local function frameOf(t)
  return math.floor((t + baseOffset) * fps + 0.5) + COMP_START_FRAME
end

local function tool(name)
  local t = comp:FindTool(name)
  if not t then fail("node not found: " .. name) end
  return t
end

-- Write a series of {frame, value} pairs onto one input as STEP keyframes.
-- Consecutive duplicates are skipped, so a score that doesn't change doesn't
-- get a redundant key.
local function animate(node, inputName, series, label, stepHold)
  if not node then return 0 end

  -- Clear any spline left by a previous run.
  if CLEAR_FIRST then
    pcall(function()
      local out = node[inputName]:GetConnectedOutput()
      if out then out:GetTool():Delete() end
    end)
  end

  -- Attach a spline BEFORE writing anything. This is the fix for the scoreboard
  -- that froze on the final score: on an un-animated input, node[input][frame]
  -- does not create a keyframe, it just overwrites the one static value. So all
  -- 125 writes landed on the same slot and the last one won. Confirmed by
  -- diagnostic: a numeric input written at frames 0 and 200 read back as the
  -- same value at both, and only sprouted a spline once AddModifier was called.
  local attached = false
  pcall(function()
    attached = node:AddModifier(inputName, "BezierSpline") and true or false
  end)
  if not attached then
    fail(string.format("%s: couldn't attach a spline to %s — values will not "
      .. "change over time.", label, inputName))
  end

  local written, last = 0, nil
  for _, kv in ipairs(series) do
    local f, v = kv[1], kv[2]
    if v ~= last then
      -- Hold the previous value until one frame before the change, so the value
      -- snaps rather than ramping. Scores must never read 14.5.
      if stepHold and last ~= nil and f > 0 then
        pcall(function() node[inputName][f - 1] = last end)
      end
      local okSet = pcall(function() node[inputName][f] = v end)
      if not okSet then
        fail(string.format("%s: couldn't write %s at frame %d", label, inputName, f))
        return written
      end
      written = written + 1
      last = v
    end
  end
  return written
end

-- Sample an input across the match and report how many distinct values appear.
-- Deliberately more than two samples: the serve Blend only ever holds 0 or 1, so
-- checking just the start and midpoint reported "STILL STATIC" whenever those
-- two moments happened to share a value — a false alarm on a working setup.
local function verify(nodeName, inputName, fFirst, fLast)
  local n = comp:FindTool(nodeName)
  if not n then return "node missing" end

  local seen, order = {}, {}
  local SAMPLES = 9
  for i = 0, SAMPLES - 1 do
    local f = math.floor(fFirst + (fLast - fFirst) * i / (SAMPLES - 1))
    local v
    pcall(function() v = n[inputName][f] end)
    v = tostring(v)
    if not seen[v] then seen[v] = true order[#order + 1] = v end
  end

  return string.format("%d distinct across %d samples [%s] %s",
    #order, SAMPLES, table.concat(order, " "),
    (#order > 1) and "OK" or "*** STILL STATIC ***")
end

--------------------------------------------------------------------------------
-- BUILD THE SERIES
--------------------------------------------------------------------------------

local sc1, sc2, st1, st2, setNo, srv1, srv2 = {}, {}, {}, {}, {}, {}, {}

for _, e in ipairs(match.events) do
  local f = frameOf(e.t)
  sc1[#sc1 + 1]     = { f, tostring(e.score1) }
  sc2[#sc2 + 1]     = { f, tostring(e.score2) }
  st1[#st1 + 1]     = { f, tostring(e.sets1) }
  st2[#st2 + 1]     = { f, tostring(e.sets2) }
  setNo[#setNo + 1] = { f, "SET " .. tostring(e.set) }
  srv1[#srv1 + 1]   = { f, (e.serve == 1) and 1 or 0 }
  srv2[#srv2 + 1]   = { f, (e.serve == 2) and 1 or 0 }
end

--------------------------------------------------------------------------------
-- APPLY
--------------------------------------------------------------------------------

comp:Lock()
comp:StartUndo("Apply match data")

local counts = {}
-- stepHold on EVERYTHING. Fusion resolves a spline to the NEAREST key, not the
-- previous one, so with keys at frame 0 ("0") and frame 1254 ("1") the value
-- flipped at frame 627 — halfway — and the opponent's set count read 1 before
-- they'd won a set. Writing the outgoing value again at f-1 pins each change to
-- its own frame instead of drifting to the midpoint.
counts["Team1Score"] = animate(tool("Team1Score"), "StyledText", sc1, "Team1Score", true)
counts["Team2Score"] = animate(tool("Team2Score"), "StyledText", sc2, "Team2Score", true)
counts["Team1Sets"]  = animate(tool("Team1Sets"),  "StyledText", st1, "Team1Sets", true)
counts["Team2Sets"]  = animate(tool("Team2Sets"),  "StyledText", st2, "Team2Sets", true)
counts["SetNumber"]  = animate(tool("SetNumber"),  "StyledText", setNo, "SetNumber", true)
-- stepHold = true: Blend is numeric, so without a held key it would ramp the
-- serve ball in and out rather than switching it.
counts["Team1Serve"] = animate(tool("Team1ServeMerge"), "Blend", srv1, "Team1ServeMerge", true)
counts["Team2Serve"] = animate(tool("Team2ServeMerge"), "Blend", srv2, "Team2ServeMerge", true)

--------------------------------------------------------------------------------
-- TEAM NAMES
-- Static for the match, so no keyframes — but they DO need repositioning.
-- The builder calculated each name's centre from whatever was in its config
-- ("Opponent"). Dropping a longer name in without recalculating leaves it
-- centred on a point meant for a shorter one, which is how "Riverside Rapids"
-- ended up hanging off the end of the bar.
--------------------------------------------------------------------------------

local NAME_CHAR_W  = 0.0138   -- Gotham Medium at 0.026, average character width
local NAME_MARGIN  = 0.020    -- gap from the end of the bar to the text
local BAR_L, BAR_R = 0.125, 0.875
local NAME1_NUDGE  = 0.0
local NAME2_NUDGE  = -0.003

-- Widest a name may be before it reaches the serve ball. The ball sits at
-- 0.3631 / 0.6369 and is ~0.0093 wide either side of that; this leaves a small
-- gap beyond it. Symmetric, so one number covers both sides.
local NAME_MAX_W = 0.196
local ELLIPSIS   = "..."

local CHAR_W = {
  [" "] = 0.42,
  ["i"] = 0.45, ["l"] = 0.45, ["I"] = 0.45, ["j"] = 0.45,
  ["."] = 0.45, [","] = 0.45, ["'"] = 0.45, ["!"] = 0.45, [":"] = 0.45, [";"] = 0.45,
  ["f"] = 0.60, ["t"] = 0.60, ["r"] = 0.60,
  ["W"] = 1.35, ["M"] = 1.35, ["m"] = 1.35, ["w"] = 1.35,
}

local function nameWidth(str)
  local units = 0
  for i = 1, #str do units = units + (CHAR_W[str:sub(i, i)] or 1.0) end
  return units * NAME_CHAR_W
end

-- Trim from the end and append "..." until it fits. Any trailing space is
-- stripped first, so we get "Riverside Rap..." rather than "Riverside Rap ...".
local function fitName(str)
  if nameWidth(str) <= NAME_MAX_W then return str, false end
  local s = str
  while #s > 1 do
    s = s:sub(1, #s - 1):gsub("%s+$", "")
    if nameWidth(s .. ELLIPSIS) <= NAME_MAX_W then return s .. ELLIPSIS, true end
  end
  return ELLIPSIS, true
end

local function nameCentre(str, side)
  local w = nameWidth(str)
  if side == "left" then return BAR_L + NAME_MARGIN + w / 2 + NAME1_NUDGE end
  return BAR_R - NAME_MARGIN - w / 2 + NAME2_NUDGE
end

local function setName(nodeName, raw, side)
  local node = comp:FindTool(nodeName)
  if not node then fail("node not found: " .. nodeName) return end
  if not raw then return end

  local shown, wasCut = fitName(raw)
  pcall(function() node.StyledText[0] = shown end)
  pcall(function() node.Center[0] = { nameCentre(shown, side), 0.115 } end)

  if wasCut then
    fail(string.format("%q was too wide for the bar — showing %q", raw, shown))
  end
end

setName("Team1Name", match.team1, "left")
setName("Team2Name", match.team2, "right")

comp:EndUndo(true)
comp:Unlock()

--------------------------------------------------------------------------------
-- REPORT
--------------------------------------------------------------------------------

local firstF = frameOf(match.events[1].t)
local lastF  = frameOf(match.events[#match.events].t)

local rep = {}
local function say(s) rep[#rep + 1] = s print(s) end

say("=====================================================")
say(" Match applied " .. os.date("%Y-%m-%d %H:%M:%S"))
say(" From: " .. MATCH_FILE)
say(string.format(" Teams: %s vs %s", tostring(match.team1), tostring(match.team2)))
say(string.format(" Frame rate used: %g fps (from %s)", fps, fpsSource))
say("")
for _, k in ipairs({"Team1Score", "Team2Score", "Team1Sets", "Team2Sets",
                    "SetNumber", "Team1Serve", "Team2Serve"}) do
  say(string.format("   %-12s %d keyframes", k, counts[k] or 0))
end

say("")
say(string.format(" Covers frames %d to %d (%.1f seconds at %g fps).",
    firstF, lastF, match.events[#match.events].t - match.events[1].t, fps))

-- Did it actually take? Compare the start of the match against the end.
say("")
say(" Verification — values should differ between the two frames:")
say("   Team1Score      " .. verify("Team1Score", "StyledText", firstF, lastF))
say("   Team2Score      " .. verify("Team2Score", "StyledText", firstF, lastF))
say("   Team1Sets       " .. verify("Team1Sets",  "StyledText", firstF, lastF))
say("   Team2Sets       " .. verify("Team2Sets",  "StyledText", firstF, lastF))
say("   SetNumber       " .. verify("SetNumber",  "StyledText", firstF, lastF))
say("   Team1ServeMerge " .. verify("Team1ServeMerge", "Blend", firstF, lastF))
say("   Team2ServeMerge " .. verify("Team2ServeMerge", "Blend", firstF, lastF))

if #problems > 0 then
  say("")
  say(" PROBLEMS:")
  for _, p in ipairs(problems) do say("   - " .. p) end
end
say("=====================================================")

-- Also write the report to a file, because the Fusion Console isn't always
-- reachable and a silent script is a script you can't trust.
local logPath = WORK_DIR .. "/apply-match-log.txt"
local lf = io.open(logPath, "w")
if lf then
  lf:write(table.concat(rep, "\n"))
  lf:close()
end
