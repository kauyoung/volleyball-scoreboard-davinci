# DIY Volleyball Scoreboard Overlay Pipeline

A from-scratch pipeline for putting a live, animated scoreboard overlay on
volleyball match footage — built for parents/coaches recording their own
team's games with a 4K60 action camera and DaVinci Resolve, without paying
for a subscription filming/scoring service.

End to end: record on a 4K60 camera → convert footage to an editing-friendly
codec → assemble the clips into one gapless timeline in DaVinci Resolve →
score the match on a phone or laptop (live at the game, or later during
editing) → apply that scoring data onto a scripted Fusion scoreboard graph →
render.

The scoreboard shows: live score, sets won, current set number, and which
team is serving — built once as a reusable Fusion composition, then driven
entirely by a JSON file of timestamped scoring events.

## Why this exists

Paid scoreboard-overlay apps for phone recording exist, but they cap out at
1080p30 and bake the overlay into the video permanently. This pipeline
keeps the camera and the scoreboard as two independent layers — shoot in
4K60, keep raw footage untouched, and the overlay lives in an editable
Fusion composition until final render.

## Requirements

- A 4K60-capable camera (this was built around a DJI Osmo Action-series
  camera; any camera producing MP4/MOV/MXF files works with the assembly
  script).
- **DaVinci Resolve** (free edition works). One thing to know up front: a
  new project's **Playback frame rate** setting (Project Settings → Master
  Settings) defaults to 24 and is separate from **Timeline frame rate** — if
  your live preview plays back in obvious slow motion despite everything
  else looking correct, that mismatch is almost always why. Exports are
  unaffected either way; it's a preview-only setting.
- **ffmpeg** on your PATH (only needed if your camera shoots HEVC/H.265 —
  see `convert-footage.bat` below). Free download from ffmpeg.org.
- An Nvidia GPU is used for hardware-accelerated video conversion
  (`h264_nvenc`) in `convert-one.ps1`. Without one, edit that file to use
  software encoding (`libx264`) instead, or every conversion will fail.
- The `.bat` / `.ps1` conversion tooling is Windows-specific. The Lua
  scripts and the scorekeeper web app are platform-independent (Resolve's
  scripting console and any browser).

## What's in this repo

| File | What it does |
|---|---|
| `convert-footage.bat` | Double-click-to-run converter. Finds the newest dated match folder, converts every `DJI_*.mov`/`.mp4` from HEVC to H.264 (hardware-accelerated), preserves exact filenames, keeps the originals in a `raw_originals` backup folder. Safe to re-run — skips anything already converted. |
| `convert-one.ps1` | Helper script `convert-footage.bat` calls per clip — shows a live percent/ETA progress bar during conversion. Not meant to be run by hand. |
| `assemble-match.lua` | Run once per match from Resolve's Console. Imports every clip from the newest match folder and builds a gap-free timeline at the right resolution/frame rate. Prints a verification report — total length vs. sum of source clips, and a chapter-order sanity check — so a bad import shows up as text instead of a silent, drifting overlay. |
| `build-scoreboard.lua` | Builds the entire scoreboard's Fusion node graph from scratch: bar, score cells, team names, sets, serve indicator, drop shadow. Run once per match (or once per season if you reuse the composition as a template). |
| `apply-match.lua` | Reads a match JSON file (see below) and writes keyframes onto the nodes `build-scoreboard.lua` created — score, sets, set number, and serve indicator, all as instant "step" changes rather than animated ramps. |
| `run-overlay.lua` | Convenience wrapper — runs `build-scoreboard.lua` then `apply-match.lua` back to back. |
| `volleyball-scorekeeper.html` | Self-contained scorekeeping web app (works live at the gym on a phone, or on a laptop during editing while replaying the assembled footage). Tracks score, sets, serve, and timestamps every event automatically. Exports the JSON file the Lua scripts consume. |
| `volleyball-serve-icon.png` | The serve-indicator icon `build-scoreboard.lua` places on whichever team is serving. |
| `fusion-scoreboard-walkthrough.md` | Manual, click-by-click guide to building the same scoreboard graph by hand in Fusion — useful for understanding what the script automates, or for customizing the look yourself. |
| `match-sample.json` | A synthetic example match file (not a real game) showing the data format `apply-match.lua` expects. |

## Setup

Each Lua script has a small `CONFIG` section near the top. Before running
anything, edit these to match your own machine:

- **`assemble-match.lua`** — `CLIP_ROOT` (the folder containing your dated
  match folders) and `WORK_DIR` (where these scripts live, used for logs
  and the printed next-step commands).
- **`apply-match.lua`** — same `MATCH_ROOT` / `WORK_DIR` idea.
- **`run-overlay.lua`** — `BASE`, the folder these scripts live in.
- **`build-scoreboard.lua`** — `SERVE_ICON_PATH` (point this at wherever
  you save `volleyball-serve-icon.png` — somewhere permanent, not a
  Downloads folder that gets cleared) and `TEAM1_NAME` / `TEAM2_NAME`.

Every placeholder path in the scripts is written as an obvious
`C:/Users/YOURNAME/...`-style string — search for `YOURNAME` if you want
to find every line that needs a personal value.

## Workflow

1. **Record** at 4K60 (or whatever resolution/frame rate you configure the
   timeline to match).
2. **Convert** (only needed if your camera shoots HEVC): copy the card into
   a dated folder under your configured match root, double-click
   `convert-footage.bat`.
3. **Assemble**: open a new, empty Resolve project (frame rate can't change
   once a timeline exists) and run `assemble-match.lua` from the Console.
   Read its verification output before continuing — a reported gap or
   out-of-order chapter list means don't trust the timeline yet.
4. **Add the overlay track**: add a Fusion Composition to track V2 (drag
   any item from Effects Library → Fusion Generators — not Solid Color,
   which looks similar but doesn't carry a Fusion page comp), then resize
   it to span the whole timeline. Resolve's scripting API can't do this
   part reliably, so it's a manual step.
5. **Score the match**: open `volleyball-scorekeeper.html` and tap along —
   either live at the game (tap Start the instant you press record) or
   later during editing (play the assembled timeline back at 1x speed and
   tap along to it; use the app's Camera Stopped/Restarted buttons to
   bracket any review pauses so they don't get counted as match time).
   Export the JSON when the match ends.
6. **Build and apply the scoreboard**: with the Fusion Composition clip
   selected and the Fusion page open, run `run-overlay.lua` from the
   Console.
7. **Check before rendering**: scrub to the start (0-0, Set 1, no serve
   ball shown), scrub to somewhere late in the match (score should match
   the play on screen — this is what catches assembly errors), and check
   the final frame (correct winning score and sets tally).
8. **Render.**

## Known limitations

- **A converter can silently scramble clip order.** Some converters rename
  files with an altered embedded timestamp, which can throw off Resolve's
  media-pool import order (it doesn't preserve the order clips are handed
  to it in). `assemble-match.lua` guards against this by sorting on the
  camera's own embedded chapter number rather than trusting import order,
  and prints an explicit ascending-order check.
- **Fusion Composition placement can't be scripted.** Resolve's API can
  insert a Fusion composition onto a timeline, but always at a fixed
  position on track V1 with no resize/reposition API available — placing
  it on V2 and stretching it to fit has to be done by hand (see step 4
  above).
- **An accidental "Camera Stopped" tap in the scorekeeper app can't be
  undone** — the excluded time is baked into every timestamp logged after
  it. The app requires a two-tap confirm specifically to make this
  unlikely.
- Team names longer than about 22 characters get automatically truncated
  with "..." so they don't overlap the serve-ball icon.
- The serve ball fades in/out over a few frames rather than cutting
  instantly. Cosmetic only.

## License

MIT — see `LICENSE`. Use it, fork it, adapt it for other sports (the
scorekeeping logic in `volleyball-scorekeeper.html` is volleyball-specific:
25-point sets, best of 3 — everything else in the pipeline is sport-agnostic).
