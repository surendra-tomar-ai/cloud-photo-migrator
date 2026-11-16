<#
.SYNOPSIS
    Resumable, month-by-month cloud-to-cloud copy using rclone.

.DESCRIPTION
    Copies Source to Destination one YYYY/MM folder at a time, oldest first (or the whole source
    with -Layout Single). Designed for long migrations over unreliable home connections:

      * Resumable    - finished months are recorded in state\done.txt and skipped on the next run;
                       rclone never re-uploads files that already exist at the destination.
      * Self-healing - after a failure (Wi-Fi drop, VPN, DNS) it waits until both clouds answer,
                       then retries the month, up to MaxAttempts times.
      * Checksum-aware - every file is verified by checksum. If a file fails 3+ times and the
                       destination receives byte-identical data every time, the *source's stored*
                       checksum is wrong; that file is copied once without the check and listed in
                       state\checksum-skipped.txt for you to review.
      * Keeps Windows awake while running.

    Settings come from (lowest to highest priority): built-in defaults, config.psd1, command-line.

.EXAMPLE
    .\migrate.ps1 -Source 'jotta,device=Jotta,mountpoint=Photos:' -Destination 'gdrive:From Jottacloud/Photos' -To 2026-06

.EXAMPLE
    .\migrate.ps1 -DryRun        # uses config.psd1, shows what would be copied
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string]$Destination,
    [ValidateSet('YearMonth', 'Single')][string]$Layout,
    [string]$From,
    [string]$To,
    [int]$Transfers,
    [int]$Checkers,
    [string]$ChunkSize,
    [int]$MaxAttempts,
    [string]$StateDir,
    [string]$Rclone,
    [string]$ConfigFile = (Join-Path $PSScriptRoot 'config.psd1'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$s = Get-MigratorSettings -Bound $PSBoundParameters -ConfigFile $ConfigFile -ScriptRoot $PSScriptRoot
$ErrorActionPreference = 'Continue'   # rclone writes progress to stderr; don't treat it as fatal

New-Item -ItemType Directory -Force $s.StateDir | Out-Null
$log     = Join-Path $s.StateDir 'migrate.log'
$done    = Join-Path $s.StateDir 'done.txt'
$skipped = Join-Path $s.StateDir 'checksum-skipped.txt'
if (-not (Test-Path $done)) { New-Item -ItemType File $done | Out-Null }

try { $Host.UI.RawUI.WindowTitle = "cloud-photo-migrator: $($s.Source) -> $($s.Destination)" } catch {}
Enable-KeepAwake

function Write-Marker([string]$text) {
    $line = "===== $text $(Get-Date -Format s)"
    if (-not $DryRun) { Add-Content $log $line }
}

Write-Host "Source:      $($s.Source)"
Write-Host "Destination: $($s.Destination)"
Write-Host "Layout:      $($s.Layout)$(if ($s.From -or $s.To) { "  ($($s.From) .. $($s.To))" })"
Write-Host "State/logs:  $($s.StateDir)$(if ($DryRun) { '   [DRY RUN - nothing is copied or recorded]' })"

$units = Get-WorkUnits $s
if ($s.Layout -eq 'YearMonth' -and $units.Count -eq 0) {
    Write-Host "No YYYY/MM folders found in the source for that range. Use -Layout Single to copy everything as one unit." -ForegroundColor Red
    exit 2
}
Write-Host "Units to process: $($units.Count)`n"

$common = @('--transfers', $s.Transfers, '--checkers', $s.Checkers, '--drive-chunk-size', $s.ChunkSize,
            '--retries', '3', '--low-level-retries', '20')
if ($DryRun) { $common += '--dry-run' } else { $common += @('--log-file', $log, '--log-level', 'INFO') }

foreach ($unit in $units) {
    $name = if ($unit) { $unit -replace '/', '-' } else { '(all)' }
    if ((Get-Content $done) -contains $name) { Write-Host "$name already done, skipping"; continue }

    $src = Join-RemotePath $s.Source $unit
    $dst = Join-RemotePath $s.Destination $unit
    Write-Host "===== $name  ($(Get-Date -Format 'dd-MMM HH:mm')) =====" -ForegroundColor Cyan
    Write-Marker "START $name"

    $mismatch = @{}
    $ok = $false
    for ($attempt = 1; $attempt -le $s.MaxAttempts; $attempt++) {
        $logStart = if (Test-Path $log) { @(Get-Content $log).Count } else { 0 }
        & $s.Rclone copy $src $dst -P @common
        if ($LASTEXITCODE -eq 0) { $ok = $true; break }
        if ($DryRun) { break }
        Write-Marker "FAILED $name attempt $attempt exit $LASTEXITCODE"

        # Files with a wrong checksum stored at the source can never pass verification. Detect them
        # (same destination hash on every failure) and copy them once without the checksum check.
        foreach ($m in Get-ChecksumMismatches (Get-Content $log | Select-Object -Skip $logStart)) {
            if (-not $mismatch.ContainsKey($m.File)) { $mismatch[$m.File] = @() }
            $mismatch[$m.File] += $m.DstHash
        }
        $fixedAny = $false
        foreach ($rel in @($mismatch.Keys)) {
            if (-not (Test-ConsistentMismatch $mismatch[$rel])) { continue }
            Write-Host "$name/$rel - source checksum is wrong (identical data every time); copying without checksum check" -ForegroundColor Yellow
            & $s.Rclone copyto (Join-RemotePath $src $rel) (Join-RemotePath $dst $rel) --ignore-checksum --retries 3 --log-file $log --log-level INFO
            if ($LASTEXITCODE -eq 0) {
                Add-Content $skipped "$(Get-Date -Format s)`t$(Join-RemotePath $unit $rel)`tdestination hash $($mismatch[$rel][0])"
                Write-Marker "CHECKSUM-SKIP $name $rel (destination hash $($mismatch[$rel][0]), seen $($mismatch[$rel].Count)x)"
                $mismatch.Remove($rel)
                $fixedAny = $true
            }
        }
        if ($fixedAny) { $attempt--; continue }   # not a connectivity problem; retry straight away

        Write-Host "$name attempt $attempt failed - waiting for both clouds, then retrying..." -ForegroundColor Yellow
        Wait-ForRemotes $s
        Start-Sleep -Seconds 30
    }

    if ($DryRun) { if (-not $ok) { Write-Host "$name dry run reported errors (see above)." -ForegroundColor Yellow }; continue }
    if ($ok) { Add-Content $done $name; Write-Marker "DONE $name" }
    else {
        Write-Host "`n$name still failing after $($s.MaxAttempts) attempts. See $log, fix the cause, and run again - finished work is kept." -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n===== ALL UNITS FINISHED =====" -ForegroundColor Green
if (-not $DryRun) { Write-Host "Next: run .\verify.ps1 to compare every file at the destination with the source." }
