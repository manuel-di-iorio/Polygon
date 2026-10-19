<#
.SYNOPSIS
    Rebuilds editor.yymps, the distributable Polygon asset package.

.DESCRIPTION
    Runs GameMaker's ProjectTool headlessly to export a Local Asset Package
    from polygon.yyp - the same package the IDE creates with
    Tools > Create Local Package - then compares its *content* against the
    committed editor.yymps and rewrites it only when something really changed.

    The .yymps is a zip and embeds timestamps, so a fresh export almost always
    differs byte-for-byte even when no source file changed. That is why this
    script compares per-entry (name + MD5) instead of file hashes, and why
    `git status` alone is not a reliable staleness check.

    Included in the package:
      * every resource in the "Polygon Editor" project folder
        (scripts, sprites, shaders)
      * the Included Files under datafiles/__PolygonEditor__
    The demo datafiles (Kenney) are stripped with POSTREMOVALS so the package
    only ships the editor's own datafiles.

.PARAMETER Strict
    Fail (exit 1) when ProjectTool is missing or the export fails, instead of
    warning and exiting 3. The default keeps the pre-push hook from blocking a
    push on a machine without GameMaker installed.

.PARAMETER Force
    Skip the content comparison and always overwrite editor.yymps.

.PARAMETER Destination
    Output path. Defaults to editor.yymps in the repository root.

.OUTPUTS
    0  editor.yymps is up to date (content identical)
    2  content changed, editor.yymps was rewritten
    3  skipped: ProjectTool missing or the export failed (not a hard error)
    1  error (only with -Strict)

.NOTES
    Override the ProjectTool location with the POLYGON_PROJECTTOOL env var.
    Run the pre-push hook with POLYGON_SKIP_PACK=1 to skip this script.
#>
[CmdletBinding()]
param(
    [switch]$Strict,
    [switch]$Force,
    [string]$Destination
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$yyp  = Join-Path $root 'polygon.yyp'
if ($Destination) { $dest = $Destination } else { $dest = Join-Path $root 'editor.yymps' }

function Get-ProjectTool {
    if ($env:POLYGON_PROJECTTOOL -and (Test-Path -LiteralPath $env:POLYGON_PROJECTTOOL)) {
        return (Resolve-Path -LiteralPath $env:POLYGON_PROJECTTOOL).Path
    }

    $patterns = @(
        (Join-Path $env:ProgramData 'GameMakerStudio2*\Plugins\@gm-tools-project-tool-*\ProjectTool.exe'),
        (Join-Path $env:ProgramFiles 'GameMaker Studio 2\ProjectTool\ProjectTool.exe')
    )

    foreach ($pattern in $patterns) {
        $hit = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }

    return $null
}

function Get-ZipContentMap([string]$Path) {
    $map = @{}
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        foreach ($entry in $zip.Entries) {
            $stream = $entry.Open()
            try {
                $buffer = New-Object System.IO.MemoryStream
                $stream.CopyTo($buffer)
                $md5 = [System.Security.Cryptography.MD5]::Create()
                try {
                    $hash = [BitConverter]::ToString($md5.ComputeHash($buffer.ToArray())).Replace('-', '')
                } finally {
                    $md5.Dispose()
                }
                $map[$entry.FullName] = $hash
                $buffer.Dispose()
            } finally {
                $stream.Close()
            }
        }
    } finally {
        $zip.Dispose()
    }
    return $map
}

function Test-SameContent($Current, $Fresh) {
    if ($Current.Count -ne $Fresh.Count) { return $false }
    foreach ($key in $Fresh.Keys) {
        if (-not $Current.ContainsKey($key)) { return $false }
        if ($Current[$key] -ne $Fresh[$key]) { return $false }
    }
    return $true
}

if (-not (Test-Path -LiteralPath $yyp)) {
    Write-Host "pack_yymps: project not found: $yyp" -ForegroundColor Red
    if ($Strict) { exit 1 }
    exit 3
}

$tool = Get-ProjectTool
if (-not $tool) {
    Write-Host 'pack_yymps: ProjectTool not found. Set POLYGON_PROJECTTOOL or install GameMaker.' -ForegroundColor Yellow
    if ($Strict) { exit 1 }
    exit 3
}

# Included Files shipped with the editor (datafiles/__PolygonEditor__), by name.
$editorDataDir = Join-Path $root 'datafiles\__PolygonEditor__'
$includeResources = ''
if (Test-Path -LiteralPath $editorDataDir) {
    $includeResources = ((Get-ChildItem -LiteralPath $editorDataDir -Recurse -File |
        Select-Object -ExpandProperty Name | Sort-Object) -join ',')
}

# Strip the demo datafiles from the package (everything but __PolygonEditor__).
$dataDir = Join-Path $root 'datafiles'
$postRemovals = ''
if (Test-Path -LiteralPath $dataDir) {
    $postRemovals = ((Get-ChildItem -LiteralPath $dataDir -Directory |
        Where-Object { $_.Name -ne '__PolygonEditor__' } |
        ForEach-Object { 'datafiles/' + $_.Name } | Sort-Object) -join ',')
}

$temp = Join-Path $env:TEMP ('polygon_pack_' + [guid]::NewGuid().ToString('N') + '.yymps')

$ptArgs = @(
    'EXPORT',
    "SOURCE=$yyp",
    "DESTINATION=$temp",
    'PACKAGETYPE=PACKAGE',
    'PACKAGEID=editor',
    'PACKAGENAME=editor',
    'PACKAGEVERSION=1.0.0',
    'PUBLISHERNAME=editor',
    'INCLUDEFOLDERS=Polygon Editor',
    'READONLY=TRUE'
)
if ($includeResources) { $ptArgs += "INCLUDERESOURCES=$includeResources" }
if ($postRemovals)     { $ptArgs += "POSTREMOVALS=$postRemovals" }

Write-Host "pack_yymps: export in progress ($tool) ..."
$output = & $tool @ptArgs 2>&1
$failed = ($LASTEXITCODE -ne 0) -or (-not (Test-Path -LiteralPath $temp)) -or ($output -match 'ProjectTool failed')

if ($failed) {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    Write-Host 'pack_yymps: export failed.' -ForegroundColor Red
    $output | Select-Object -Last 15 | ForEach-Object { Write-Host "  $_" }
    if ($Strict) { exit 1 }
    exit 3
}

function Publish-Package {
    Copy-Item -LiteralPath $temp -Destination $dest -Force
    Remove-Item -LiteralPath $temp -Force
}

if ($Force) {
    Publish-Package
    Write-Host 'pack_yymps: editor.yymps rewritten (-Force).' -ForegroundColor Green
    exit 2
}

if (-not (Test-Path -LiteralPath $dest)) {
    Publish-Package
    Write-Host 'pack_yymps: editor.yymps created.' -ForegroundColor Green
    exit 2
}

$current = Get-ZipContentMap $dest
$fresh   = Get-ZipContentMap $temp

if (Test-SameContent -Current $current -Fresh $fresh) {
    Remove-Item -LiteralPath $temp -Force
    Write-Host 'pack_yymps: editor.yymps already up to date (content identical).'
    exit 0
}

Publish-Package
Write-Host 'pack_yymps: content changed, editor.yymps updated.' -ForegroundColor Green
exit 2
