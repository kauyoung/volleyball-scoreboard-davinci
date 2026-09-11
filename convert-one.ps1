<#
================================================================================
 Converts one clip and shows a live progress bar (percent + ETA).
================================================================================

 Called by convert-footage.bat — not meant to be run by hand, though it's
 harmless to: .\convert-one.ps1 -Src "in.mov" -Out "out.mov"

 How the progress bar works: ffmpeg's -progress flag writes machine-readable
 lines (out_time_ms=...) to a file as it works. This script asks ffprobe for
 the clip's total duration up front, starts ffmpeg in the background, then
 polls that progress file twice a second to compute percent complete and an
 ETA from how fast progress has moved so far.
================================================================================
#>
param(
  [Parameter(Mandatory=$true)][string]$Src,
  [Parameter(Mandatory=$true)][string]$Out
)

$ErrorActionPreference = "Stop"

$durStr = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$Src" 2>$null
$duration = 0.0
[double]::TryParse($durStr, [ref]$duration) | Out-Null
if ($duration -le 0) { $duration = 1 }  # avoid divide-by-zero; percent just won't mean much for a bad probe

$progressFile = [System.IO.Path]::GetTempFileName()
$errorFile    = [System.IO.Path]::GetTempFileName()
$name = Split-Path $Src -Leaf

$ffArgs = @(
  "-y", "-loglevel", "error",
  "-i", $Src,
  "-c:v", "h264_nvenc", "-preset", "p6", "-rc", "vbr", "-cq", "19", "-b:v", "0",
  "-pix_fmt", "yuv420p",
  "-c:a", "aac", "-b:a", "192k",
  "-movflags", "+faststart",
  "-progress", $progressFile, "-nostats",
  $Out
)

# Passing an array straight to -ArgumentList doesn't reliably quote elements
# that contain spaces (e.g. "D:\Volleyball Matches\..."), which silently broke the
# input/output paths here. Quoting every element ourselves and joining into
# one string sidesteps that entirely.
$argString = ($ffArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '

$proc = Start-Process -FilePath "ffmpeg" -ArgumentList $argString -PassThru `
        -WindowStyle Hidden -RedirectStandardError $errorFile
$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
  while (-not $proc.HasExited) {
    Start-Sleep -Milliseconds 500
    try {
      # The progress file exists the instant GetTempFileName() creates it, but
      # is empty (0 bytes) until ffmpeg's first write. Get-Content -Raw on an
      # empty file returns $null rather than "", which crashed regex matching
      # here originally and made every conversion falsely report FAILED. This
      # whole block is wrapped in try/catch too, so any other hiccup on one
      # poll just gets skipped rather than aborting the conversion outright.
      if (Test-Path $progressFile) {
        $content = Get-Content $progressFile -Raw -ErrorAction SilentlyContinue
        if ($content) {
          $allMatches = [regex]::Matches($content, 'out_time_ms=(\d+)')
          if ($allMatches.Count -gt 0) {
            $lastMs = [double]$allMatches[$allMatches.Count - 1].Groups[1].Value
            $outSec = $lastMs / 1000000.0
            $pct = [Math]::Min(100, [Math]::Round(($outSec / $duration) * 100, 1))
            $elapsed = $sw.Elapsed.TotalSeconds
            if ($outSec -gt 1) {
              $etaSec = [Math]::Max(0, ($elapsed / $outSec) * ($duration - $outSec))
              $eta = [TimeSpan]::FromSeconds($etaSec).ToString("mm\:ss")
            } else {
              $eta = "--:--"
            }
            Write-Progress -Activity "Converting $name" -Status "$pct% complete, ETA $eta" -PercentComplete $pct
          }
        }
      }
    } catch {
      # Don't let a bad poll kill the conversion — just skip this update.
    }
  }
} finally {
  # However this loop exits, never leave ffmpeg running orphaned in the
  # background — if the try block above ever throws past its inner catch,
  # this still fires and cleans up.
  if (-not $proc.HasExited) {
    $proc.WaitForExit()
  }
  Write-Progress -Activity "Converting $name" -Completed
  Remove-Item $progressFile -ErrorAction SilentlyContinue
}

if ($proc.ExitCode -ne 0) {
  Write-Host "ffmpeg failed (exit code $($proc.ExitCode)) on $name :"
  if (Test-Path $errorFile) { Get-Content $errorFile | Write-Host }
}
Remove-Item $errorFile -ErrorAction SilentlyContinue

exit $proc.ExitCode
