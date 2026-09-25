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
- **DaVinci Resolve Studio** (optional): Studio decodes HEVC/H.265 natively on
  Windows, so if you have it you can skip the conversion step entirely and
  import the camera files as-is.
- **ffmpeg** on your PATH (only needed if your camera shoots HEVC/H.265 and
  you're on the free edition — see `convert-footage.bat` below). Free
  download from ffmpeg.org.
- **Fonts**: the scoreboard uses **Gotham** (Medium) for scores and labels and
  **Gotham Narrow** (Bold) for team names. They're commercial fonts — change
  `FONT` / `NAME_FONT` at the top of `build-scoreboard.lua` to anything you
  have installed (a condensed font for names fits the most characters).
- **Python 3 + Pillow** (optional, only for `tools/make-thumbnail.py`).
- An Nvidia GPU is used for hardware-accelerated video conversion
  (`h264_nvenc`) in `convert-one.ps1`. Without one, edit that file to use
  software encoding (`libx264`) instead, or every conversion will fail.
- The `.bat` / `.ps1` conversion tooling is Windows-specific. The Lua
  scripts and the scorekeeper web app are platform-independent (Resolve's
  scripting console and any browser).

## What's in this repo

```
├── resolve-scripts/     Lua scripts run from DaVinci Resolve's Console
├── footage-conversion/  Windows HEVC→H.264 converter (.bat + .ps1)
├── scorekeeper/         The scorekeeping web app
├── assets/              Serve-ball icon used by the overlay
├── tools/               YouTube thumbnail generator
└── docs/                Manual walkthrough + a sample match file
```

| File | What it does |
|---|---|
| `footage-conversion/convert-footage.bat` | Double-click-to-run converter. Finds the newest dated match folder, converts every `DJI_*.mov`/`.mp4` from HEVC to H.264 (hardware-accelerated), preserves exact filenames, keeps the originals in a `raw_originals` backup folder. Safe to re-run — skips anything already converted. |
| `footage-conversion/convert-one.ps1` | Helper script `convert-footage.bat` calls per clip — shows a live percent/ETA progress bar during conversion. Not meant to be run by hand. |
| `resolve-scripts/assemble-match.lua` | Run once per match from Resolve's Console. Imports every clip from the newest match folder and builds a gap-free timeline at the right resolution/frame rate. Prints a verification report — total length vs. sum of source clips, and a chapter-order sanity check — so a bad import shows up as text instead of a silent, drifting overlay. |
| `resolve-scripts/build-scoreboard.lua` | Builds the entire scoreboard's Fusion node graph from scratch: bar, score cells, team names, sets, serve indicator, drop shadow. Team names are anchored on their outer edge, so both sit the same distance from the ends of the bar whatever their length. Bar width (`BAR_WIDTH`) and team-name font (`NAME_FONT`) are configurable. Run once per match. |
| `resolve-scripts/apply-match.lua` | Reads a match JSON file (see below) and writes keyframes onto the nodes `build-scoreboard.lua` created — score, sets, set number, and serve indicator, all as instant "step" changes rather than animated ramps. Also sets the team names from the file and **automatically re-aligns each set to its clip join** (see below). |
| `resolve-scripts/run-overlay.lua` | Convenience wrapper — runs `build-scoreboard.lua` then `apply-match.lua` back to back. |
| `scorekeeper/volleyball-scorekeeper.html` | Self-contained scorekeeping web app (works live at the gym on a phone, or on a laptop during editing while replaying the assembled footage). Tracks score, sets, serve, and timestamps every event automatically. Exports the JSON file the Lua scripts consume. |
| `tools/make-thumbnail.py` | Builds a 1280×720 YouTube thumbnail from the match file and a frame of the finished video: date, team names, team logo, and one score tile per set. |
| `assets/volleyball-serve-icon.png` | The serve-indicator icon `build-scoreboard.lua` places on whichever team is serving. |
| `docs/fusion-scoreboard-walkthrough.md` | Manual, click-by-click guide to building the same scoreboard graph by hand in Fusion — useful for understanding what the script automates, or for customizing the look yourself. |
| `docs/match-sample.json` | A synthetic example match file (not a real game) showing the data format `apply-match.lua` expects. |

## Setup

Copy the contents of `resolve-scripts/` to wherever you want to run them
from (they don't need to stay inside a cloned repo). Each script has a
small `CONFIG` section near the top — edit these to match your own machine:

- **`assemble-match.lua`** — `CLIP_ROOT` (the folder containing your dated
  match folders) and `WORK_DIR` (where you copied these scripts to, used
  for logs and the printed next-step commands).
- **`apply-match.lua`** — same `MATCH_ROOT` / `WORK_DIR` idea.
- **`run-overlay.lua`** — `BASE`, the folder you copied these scripts to.
- **`build-scoreboard.lua`** — `SERVE_ICON_PATH` (point this at wherever
  you save `volleyball-serve-icon.png` — somewhere permanent, not a
  Downloads folder that gets cleared) and `TEAM1_NAME` / `TEAM2_NAME`.

Every placeholder path in the scripts is written as an obvious
`C:/Users/YOURNAME/...`-style string — search for `YOURNAME` if you want
to find every line that needs a personal value.

## Workflow

1. **Record** at 4K60 (or whatever resolution/frame rate you configure the
   timeline to match).
2. **Copy the card** into a dated folder under your configured match root.
   **Convert** only if your camera shoots HEVC and you're on the free
   edition: double-click `footage-conversion/convert-footage.bat`. (Resolve
   Studio reads HEVC directly — skip this.)
3. **Assemble**: open a new, empty Resolve project (frame rate can't change
   once a timeline exists) and run `assemble-match.lua` from the Console.
   Read its verification output before continuing — a reported gap or
   out-of-order chapter list means don't trust the timeline yet.
4. **Add the overlay track**: add a Fusion Composition to track V2 (drag
   any item from Effects Library → Fusion Generators — not Solid Color,
   which looks similar but doesn't carry a Fusion page comp), then resize
   it to span the whole timeline. Resolve's scripting API can't do this
   part reliably, so it's a manual step.
5. **Score the match**: open `scorekeeper/volleyball-scorekeeper.html` and tap along —
   either live at the game (tap Start the instant you press record) or
   later during editing (play the assembled timeline back at 1x speed and
   tap along to it). Whenever the camera stops — normally at set breaks —
   tap **Stop Recording** (it asks for a second tap to confirm), then
   **End Set**; when the camera starts again tap **Resume Recording** (it
   turns solid green while you're stopped, and +1 taps are refused with a
   warning until you resume). After the final set, use **End Match**.
   Export the JSON when the match ends.
6. **Build and apply the scoreboard**: with the Fusion Composition clip
   selected and the Fusion page open, run `run-overlay.lua` from the
   Console.
7. **Check before rendering**: scrub to the start (0-0, Set 1, no serve
   ball shown), scrub to somewhere late in the match (score should match
   the play on screen — this is what catches assembly errors), and check
   the final frame (correct winning score and sets tally).
8. **Render.** For YouTube, H.265 at roughly 30–35 Mbps (4K60) keeps close
   to the camera's quality at about two-thirds the size of an equivalent
   H.264 file. Save it as a render preset so every match exports the same.
9. **Thumbnail (optional)**: grab a frame from the finished video and run
   `python tools/make-thumbnail.py match.json frame.jpg thumbnail.jpg`.
   YouTube chapters need at least three timestamps, starting at 0:00 — for
   a two-set match add a third (e.g. "Match point").

## Automatic set alignment

Every set break is a camera stop, so every set after the first begins at a
clip join on the timeline. If Stop/Resume Recording was tapped a few seconds
early or late, every score in that set is off by the same amount — which a
single global offset can't fix. `apply-match.lua` measures where each set's
0–0 falls in the data against where its clip join actually is, and shifts
that whole set by the difference. It reports each shift, and skips itself
(with a message) if the number of set breaks doesn't match the number of
clip joins — i.e. the camera was also stopped mid-set — or if a shift would
be larger than `ALIGN_MAX_SEC`. The match file itself is never modified.
Turn it off with `AUTO_ALIGN_SETS = false`.

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
- **An accidental "Stop Recording" tap in the scorekeeper app can't be
  undone** — the excluded time is baked into every timestamp logged after
  it. The app requires a two-tap confirm to make this unlikely, and
  automatic set alignment corrects mistimed taps at set breaks.
- **Team names are width-estimated for truncation.** Positioning is exact
  (edge-anchored), but the "too long, add ..." check uses an average
  character width calibrated for Gotham Narrow Bold. If you change
  `NAME_FONT`, re-measure `NAME_CHAR_W` in both `build-scoreboard.lua`
  and `apply-match.lua`.
- Team names longer than about 22 characters get automatically truncated
  with "..." so they don't overlap the serve-ball icon.
- The serve ball fades in/out over a few frames rather than cutting
  instantly. Cosmetic only.

## License

MIT — see `LICENSE`. Use it, fork it, adapt it for other sports (the
scorekeeping logic in `volleyball-scorekeeper.html` is volleyball-specific:
25-point sets, best of 3 — everything else in the pipeline is sport-agnostic).
