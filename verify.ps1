<#
.SYNOPSIS
    Checks that every source file in the migrated range exists at the destination with the same
    size and checksum.

.DESCRIPTION
    Runs 'rclone check --one-way' over the same units migrate.ps1 copies (same Source, Destination,
    Layout, From, To - read from config.psd1 or the command line) and writes three lists to the
    state folder:
        verify-missing.txt  files at the source that are not at the destination
        verify-differ.txt   files present on both sides whose size or checksum differ
        verify-match.txt    files that match
    Files that migrate.ps1 deliberately copied without the checksum check (because the source's
    stored checksum is wrong) will show up in verify-differ.txt; they are pointed out separately.

.EXAMPLE
    .\verify.ps1
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string]$Destination,
    [ValidateSet('YearMonth', 'Single')][string]$Layout,
    [string]$From,
    [string]$To,
    [int]$Checkers,
    [string]$StateDir,
    [string]$Rclone,
    [string]$ConfigFile,   # default: config.psd1 next to this script
    [switch]$SizeOnly
)

$ErrorActionPreference = 'Stop'
# $PSScriptRoot is empty inside param() defaults on Windows PowerShell 5.1, so resolve the default here.
if (-not $ConfigFile) { $ConfigFile = Join-Path $PSScriptRoot 'config.psd1' }
. (Join-Path $PSScriptRoot 'lib\common.ps1')
$s = Get-MigratorSettings -Bound $PSBoundParameters -ConfigFile $ConfigFile -ScriptRoot $PSScriptRoot
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force $s.StateDir | Out-Null

$checkArgs = @('check', $s.Source, $s.Destination, '--one-way', '--checkers', $s.Checkers)
if ($s.Layout -eq 'YearMonth') {
    $units = Get-WorkUnits $s
    if ($units.Count -eq 0) { Write-Host "No YYYY/MM folders found in the source for that range." -ForegroundColor Red; exit 2 }
    foreach ($u in $units) { $checkArgs += @('--include', "/$u/**") }
}
if ($SizeOnly) { $checkArgs += '--size-only' }

$missing = Join-Path $s.StateDir 'verify-missing.txt'
$differ  = Join-Path $s.StateDir 'verify-differ.txt'
$match   = Join-Path $s.StateDir 'verify-match.txt'
$checkArgs += @('--missing-on-dst', $missing, '--differ', $differ, '--match', $match)

Write-Host "Comparing $($s.Source)  ->  $($s.Destination) ..."
& $s.Rclone @checkArgs 2>&1 | Where-Object { "$_" -match 'NOTICE|ERROR' } | ForEach-Object { Write-Host "  $_" }

$nMatch   = @(Get-Content $match   | Where-Object { $_ }).Count
$nMissing = @(Get-Content $missing | Where-Object { $_ }).Count
$diffs    = @(Get-Content $differ  | Where-Object { $_ })

$skipFile = Join-Path $s.StateDir 'checksum-skipped.txt'
$known = @()
if (Test-Path $skipFile) { $known = Get-Content $skipFile | ForEach-Object { ($_ -split "`t")[1] } }
$expected   = @($diffs | Where-Object { $known -contains $_ })
$unexpected = @($diffs | Where-Object { $known -notcontains $_ })

Write-Host ""
Write-Host "Matching files:          $nMatch"
Write-Host "Missing at destination:  $nMissing$(if ($nMissing) { "   -> $missing" })"
Write-Host "Different:               $($unexpected.Count)$(if ($unexpected.Count) { "   -> $differ" })"
if ($expected.Count) {
    Write-Host "Copied without checksum: $($expected.Count)   (source checksum was wrong; open these to confirm they're fine)"
    $expected | ForEach-Object { Write-Host "    $_" }
}

if ($nMissing -eq 0 -and $unexpected.Count -eq 0) {
    Write-Host "`nAll files verified." -ForegroundColor Green; exit 0
}
Write-Host "`nSome files need attention. Running migrate.ps1 again (after deleting state\done.txt for the affected months) will copy anything missing." -ForegroundColor Yellow
exit 1

