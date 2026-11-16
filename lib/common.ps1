# Shared helpers for migrate.ps1 and verify.ps1.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+ (Windows, macOS, Linux).

$script:Defaults = [ordered]@{
    Source      = ''          # rclone path to copy from, e.g. 'jotta,device=Jotta,mountpoint=Photos:'
    Destination = ''          # rclone path to copy to,   e.g. 'gdrive:Jotta Cloud Files/Photos'
    Layout      = 'YearMonth' # 'YearMonth' = source has YYYY/MM folders, copied one month at a time
                              # 'Single'    = copy the whole source as one unit
    From        = ''          # first month to copy, 'YYYY-MM' (YearMonth layout only; empty = oldest)
    To          = ''          # last month to copy,  'YYYY-MM' (YearMonth layout only; empty = newest)
    Transfers   = 8           # files uploaded in parallel
    Checkers    = 16          # files compared in parallel
    ChunkSize   = '32M'       # Google Drive upload chunk size (ignored by other backends)
    MaxAttempts = 100         # attempts per unit before giving up (outages wait for the network first)
    StateDir    = ''          # where the log and progress files go (default: .\state next to the scripts)
    Rclone      = ''          # path to rclone (default: rclone on PATH, or rclone(.exe) next to the scripts)
}

function Get-MigratorSettings {
    param([hashtable]$Bound, [string]$ConfigFile, [string]$ScriptRoot)
    $s = [ordered]@{}
    foreach ($k in $script:Defaults.Keys) { $s[$k] = $script:Defaults[$k] }
    if ($ConfigFile -and (Test-Path $ConfigFile)) {
        $cfg = Import-PowerShellDataFile $ConfigFile
        foreach ($k in $cfg.Keys) {
            if (-not $s.Contains($k)) { throw "Unknown setting '$k' in $ConfigFile" }
            $s[$k] = $cfg[$k]
        }
    }
    foreach ($k in $Bound.Keys) { if ($s.Contains($k)) { $s[$k] = $Bound[$k] } }

    if (-not $s.Source)      { throw "Source is not set. Pass -Source or set it in config.psd1." }
    if (-not $s.Destination) { throw "Destination is not set. Pass -Destination or set it in config.psd1." }
    foreach ($k in 'From', 'To') {
        if ($s[$k] -and $s[$k] -notmatch '^\d{4}-\d{2}$') { throw "$k must look like YYYY-MM (got '$($s[$k])')." }
    }
    if ($s.Layout -notin 'YearMonth', 'Single') { throw "Layout must be 'YearMonth' or 'Single'." }
    if (-not $s.StateDir) { $s.StateDir = Join-Path $ScriptRoot 'state' }
    if (-not $s.Rclone)   { $s.Rclone = Find-Rclone $ScriptRoot }
    return $s
}

function Find-Rclone {
    param([string]$ScriptRoot)
    $cmd = Get-Command rclone -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($name in 'rclone.exe', 'rclone') {
        $p = Join-Path $ScriptRoot $name
        if (Test-Path $p) { return $p }
    }
    throw "rclone not found. Install it (https://rclone.org/downloads/) or set Rclone in config.psd1."
}

# Join an rclone path and a relative folder without breaking 'remote:' roots.
function Join-RemotePath {
    param([string]$Base, [string]$Rel)
    if (-not $Rel) { return $Base }
    if ($Base -match '[:/\\]$') { return "$Base$Rel" }
    return "$Base/$Rel"
}

# The root of an rclone path ('remote:sub/dir' -> 'remote:'), used for connectivity checks.
function Get-RemoteRoot {
    param([string]$Path)
    if ($Path -match '^(.+?:)') { return $Matches[1] }
    return $Path
}

# Work units: 'YYYY/MM' folders inside the source (oldest first), or '' for the whole source.
function Get-WorkUnits {
    param($Settings)
    if ($Settings.Layout -eq 'Single') { return , @('') }
    $r = $Settings.Rclone
    $units = @()
    foreach ($y in & $r lsf $Settings.Source --dirs-only) {
        $y = $y.TrimEnd('/')
        if ($y -notmatch '^\d{4}$') { continue }
        foreach ($m in & $r lsf (Join-RemotePath $Settings.Source $y) --dirs-only) {
            $m = $m.TrimEnd('/')
            if ($m -match '^\d{2}$') { $units += "$y/$m" }
        }
    }
    if ($LASTEXITCODE -ne 0 -and -not $units) { throw "Could not list '$($Settings.Source)'. Check the remote name and your connection." }
    $units = $units | Where-Object {
        $ym = $_ -replace '/', '-'
        (-not $Settings.From -or $ym -ge $Settings.From) -and (-not $Settings.To -or $ym -le $Settings.To)
    } | Sort-Object
    return , @($units)
}

# Find files whose upload failed the checksum check, from rclone log lines.
# Returns objects with File (path relative to the unit) and DstHash (hash the destination computed).
function Get-ChecksumMismatches {
    param([string[]]$Lines)
    foreach ($line in $Lines) {
        if ($line -match ' ERROR : (?!Attempt )(.+?): corrupted on transfer: \w+ hashes differ .*"[0-9a-fA-F]+" vs dst.*"([0-9a-fA-F]+)"') {
            [pscustomobject]@{ File = $Matches[1]; DstHash = $Matches[2].ToLower() }
        }
    }
}

# A file is "consistently mismatched" when it failed at least $MinFailures times and the destination
# computed the same hash every time: the data is stable, so the source's stored checksum is what's wrong.
function Test-ConsistentMismatch {
    param([string[]]$Hashes, [int]$MinFailures = 3)
    return ($Hashes.Count -ge $MinFailures) -and (@($Hashes | Select-Object -Unique).Count -eq 1)
}

# Block until both sides answer (used after a failed attempt, e.g. Wi-Fi drop or VPN).
function Wait-ForRemotes {
    param($Settings)
    $roots = @(Get-RemoteRoot $Settings.Source; Get-RemoteRoot $Settings.Destination) | Select-Object -Unique
    $warned = $false
    while ($true) {
        $ok = $true
        foreach ($root in $roots) {
            & $Settings.Rclone lsf $root --max-depth 1 --dirs-only --contimeout 15s --timeout 30s --low-level-retries 1 --retries 1 *> $null
            if ($LASTEXITCODE -ne 0) { $ok = $false; break }
        }
        if ($ok) { return }
        if (-not $warned) { Write-Host "Waiting for both clouds to be reachable (check internet / VPN)..." -ForegroundColor Yellow; $warned = $true }
        Start-Sleep -Seconds 30
    }
}

# Ask Windows not to sleep while this process runs. No-op elsewhere.
function Enable-KeepAwake {
    if ($env:OS -ne 'Windows_NT') { return }
    if (-not ('KeepAwake.Native' -as [type])) {
        Add-Type -Namespace KeepAwake -Name Native -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
    }
    # ES_CONTINUOUS | ES_SYSTEM_REQUIRED. Written as a UInt32 because 0x80000001 is a negative Int32 in PowerShell 5.1.
    [KeepAwake.Native]::SetThreadExecutionState([uint32]2147483649) | Out-Null
}
