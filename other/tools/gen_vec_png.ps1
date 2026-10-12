<#
.SYNOPSIS
  Rasterizza gli sprite vettoriali (.svg) in PNG per GameMaker.

.DESCRIPTION
  Per ogni sprites/*/*.svg genera il PNG omonimo (stesso basename) se mancante
  o più vecchio dell'SVG. Dimensioni lette dallo .yy dello sprite ("width"/"height"),
  fallback agli attributi width/height dell'SVG, fallback 64x64.
  Rendering via Edge headless con sfondo trasparente (--default-background-color=00000000).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/gen_vec_png.ps1
  powershell -ExecutionPolicy Bypass -File tools/gen_vec_png.ps1 -Force
#>
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$edge = @(
  'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
  'C:\Program Files\Microsoft\Edge\Application\msedge.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw 'Microsoft Edge non trovato: impossibile rasterizzare.' }

Add-Type -AssemblyName System.Drawing
$tmp = Join-Path ([IO.Path]::GetTempPath()) 'poly_vec_png'
New-Item -ItemType Directory -Force $tmp | Out-Null
$profile = Join-Path $tmp ('profile_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $profile | Out-Null

$made = 0; $skipped = 0; $failed = @()
foreach ($svg in Get-ChildItem (Join-Path $root 'sprites') -Recurse -Filter *.svg) {
  $png = Join-Path $svg.DirectoryName ($svg.BaseName + '.png')
  if ((Test-Path $png) -and -not $Force -and (Get-Item $png).LastWriteTime -ge $svg.LastWriteTime) {
    $skipped++
    continue
  }
  $w = 0; $h = 0
  $yy = Get-ChildItem $svg.DirectoryName -Filter *.yy | Select-Object -First 1
  if ($yy) {
    $t = Get-Content $yy.FullName -Raw
    if ($t -match '"width"\s*:\s*(\d+)') { $w = [int]$Matches[1] }
    if ($t -match '"height"\s*:\s*(\d+)') { $h = [int]$Matches[1] }
  }
  if ($w -le 0 -or $h -le 0) {
    $s = Get-Content $svg.FullName -Raw
    if ($s -match 'width="(\d+)(px)?"') { $w = [int]$Matches[1] }
    if ($s -match 'height="(\d+)(px)?"') { $h = [int]$Matches[1] }
  }
  if ($w -le 0) { $w = 64 }
  if ($h -le 0) { $h = 64 }
  $html = Join-Path $tmp ($svg.BaseName + '.html')
  Set-Content $html ("<html><body style='margin:0;padding:0'><img src='file:///$($svg.FullName -replace '\\','/')' width='$w' height='$h'></body></html>") -Encoding Ascii
  Remove-Item $png -ErrorAction SilentlyContinue
  & $edge --headless --disable-gpu --no-first-run --no-default-browser-check --user-data-dir=$profile --screenshot=$png --window-size=$w,$h --default-background-color=00000000 $html *>$null
  $deadline = (Get-Date).AddSeconds(30)
  while (-not (Test-Path $png) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }
  $ok = $false
  if (Test-Path $png) {
    $img = [System.Drawing.Bitmap]::FromFile($png)
    $ok = ($img.Width -eq $w -and $img.Height -eq $h)
    $img.Dispose()
  }
  if ($ok) { $made++; Write-Output "OK  $($svg.Name) -> ${w}x${h}" }
  else { $failed += $svg.FullName; Write-Warning "FAIL $($svg.FullName)" }
}
Write-Output "--- fatti: $made, aggiornati: $skipped, falliti: $($failed.Count)"
if ($failed.Count -gt 0) { exit 1 }
