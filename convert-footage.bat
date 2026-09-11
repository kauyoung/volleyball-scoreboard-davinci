@echo off
setlocal enabledelayedexpansion
REM ================================================================================
REM  Match footage converter — HEVC to H.264, filename-preserving
REM ================================================================================
REM
REM  Double-click this. No prompts, no drag-and-drop.
REM
REM  It finds the newest dated folder under wherever THIS FILE lives (so keep it
REM  in the root of your match-footage folder), converts every DJI_*.mov / DJI_*.mp4 it
REM  finds sitting directly in that folder from HEVC to H.264, and puts the
REM  result back under the EXACT SAME FILENAME. That last part matters: it's
REM  what assemble-match.lua's chapter-order sort depends on, and it's the thing
REM  Shutter Encoder broke once already by renaming a converted file with a
REM  shifted timestamp (see MATCH-DAY.md, "Known limits").
REM
REM  The original HEVC files aren't deleted — they're moved into a
REM  "raw_originals" subfolder inside the match folder, so you've still got the
REM  source if anything ever needs re-converting.
REM
REM  Safe to re-run: anything already converted (i.e. already has a copy sitting
REM  in raw_originals) is skipped, so running it again after copying more clips
REM  onto the card only converts what's new.
REM
REM  Requires ffmpeg on PATH. If you don't have it: https://ffmpeg.org/download.html
REM  (the "essentials" build from gyan.dev is the easiest on Windows — unzip it
REM  somewhere and add its \bin folder to PATH).
REM
REM  Uses your Nvidia GPU's hardware encoder (NVENC) rather than software
REM  encoding — several times faster for 4K60, with the GPU otherwise sitting
REM  idle during conversion anyway. If you ever swap to a PC without an Nvidia
REM  GPU, this needs switching back to software encoding (see convert-one.ps1)
REM  or every file will fail to convert.
REM
REM  Shows a live progress bar (percent + ETA) per clip while converting —
REM  that's done by convert-one.ps1, which MUST live in the same folder as
REM  this .bat file. If you move this .bat, move that file with it.
REM ================================================================================

where ffmpeg >nul 2>&1
if errorlevel 1 (
  echo.
  echo  *** ffmpeg not found on PATH. ***
  echo  Install it from https://ffmpeg.org/download.html and add its \bin folder
  echo  to your PATH, then run this again.
  echo.
  pause
  exit /b 1
)

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"

set "NEWEST="
for /f "delims=" %%D in ('dir "%ROOT%" /b /ad /o-d 2^>nul') do (
  if not defined NEWEST set "NEWEST=%%D"
)

if not defined NEWEST (
  echo.
  echo  No match folders found in "%ROOT%".
  echo  Make a dated folder here and copy the card into it first.
  echo.
  pause
  exit /b 1
)

REM Skip our own housekeeping folders if one somehow sorts newest.
if /i "%NEWEST%"=="raw_originals" (
  echo.
  echo  Newest folder found was "raw_originals" — that's not a match folder.
  echo  Nothing to do.
  echo.
  pause
  exit /b 1
)

set "MATCHDIR=%ROOT%\%NEWEST%"
set "RAWDIR=%MATCHDIR%\raw_originals"

echo.
echo  Match folder: %MATCHDIR%
echo.

if not exist "%RAWDIR%" mkdir "%RAWDIR%"

set /a FOUND=0
set /a CONVERTED=0
set /a SKIPPED=0
set /a FAILED=0

for %%F in ("%MATCHDIR%\DJI_*.mov" "%MATCHDIR%\DJI_*.mp4") do (
  if exist "%%~fF" (
    set /a FOUND+=1
    if exist "%RAWDIR%\%%~nxF" (
      echo  Skipping %%~nxF — already converted.
      set /a SKIPPED+=1
    ) else (
      call :convert "%%~fF"
    )
  )
)

echo.
if !FOUND!==0 (
  echo  No DJI_*.mov / DJI_*.mp4 files found directly in this folder.
  echo  Either it's already fully converted, or the card hasn't been copied in yet.
) else (
  echo  Done. !CONVERTED! converted, !SKIPPED! already done, !FAILED! failed.
  echo  Raw originals are in: %RAWDIR%
)
echo.
pause
exit /b 0

:convert
set "SRC=%~1"
set "NAME=%~nx1"
set "OUTFILE=%MATCHDIR%\_converting_%NAME%"

echo  Converting %NAME% ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0convert-one.ps1" -Src "%SRC%" -Out "%OUTFILE%"

if not exist "%OUTFILE%" (
  echo    *** FAILED — ffmpeg produced no output. Original left in place. ***
  set /a FAILED+=1
  goto :eof
)

move /y "%SRC%" "%RAWDIR%\%NAME%" >nul
move /y "%OUTFILE%" "%SRC%" >nul
echo    done.
set /a CONVERTED+=1
goto :eof
