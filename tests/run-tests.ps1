# Tests for cloud-photo-migrator. No dependencies beyond rclone on PATH.
#   powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1
# Unit tests cover the helpers; the end-to-end test migrates a local fake photo library into a
# local "destination", interrupts nothing, re-runs to prove resume, and verifies.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'lib\common.ps1')

$script:failed = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host "Unit tests"
Assert ((Join-RemotePath 'jotta,device=Jotta,mountpoint=Photos:' '2022/12') -eq 'jotta,device=Jotta,mountpoint=Photos:2022/12') 'join after remote root'
Assert ((Join-RemotePath 'gdrive:A/B' '2022/12') -eq 'gdrive:A/B/2022/12') 'join inside remote folder'
Assert ((Join-RemotePath 'gdrive:A/B/' '') -eq 'gdrive:A/B/') 'join with empty unit'
Assert ((Get-RemoteRoot 'gdrive:A/B') -eq 'gdrive:') 'remote root'
Assert ((Get-RemoteRoot 'jotta,device=Jotta,mountpoint=Photos:2022') -eq 'jotta,device=Jotta,mountpoint=Photos:') 'connection-string remote root'

$lines = @(
    '2026/11/13 14:29:06 ERROR : 23/20230623_101500.mp4: corrupted on transfer: md5 hashes differ src(jottacloud root ''2023/06'') "0f4e1d2c3b4a59687766554433221100" vs dst(Google drive root ''X/2023/06'') "9a8b7c6d5e4f30211203f4e5d6c7b8a9"'
    '2026/11/13 14:29:07 ERROR : Attempt 2/3 failed with 1 errors and: corrupted on transfer: md5 hashes differ src(jottacloud root ''2023/06'') "0f4e1d2c3b4a59687766554433221100" vs dst(Google drive root ''X'') "9a8b7c6d5e4f30211203f4e5d6c7b8a9"'
    '2026/11/13 14:30:00 INFO  : 23/other.jpg: Copied (new)'
)
$mm = @(Get-ChecksumMismatches $lines)
Assert ($mm.Count -eq 1) 'mismatch parser ignores rclone "Attempt n/3" summary lines'
Assert ($mm[0].File -eq '23/20230623_101500.mp4' -and $mm[0].DstHash -eq '9a8b7c6d5e4f30211203f4e5d6c7b8a9') 'mismatch parser extracts file and destination hash'
Assert (Test-ConsistentMismatch @('aa', 'aa', 'aa')) 'same hash 3x = source checksum wrong'
Assert (-not (Test-ConsistentMismatch @('aa', 'aa'))) 'fewer than 3 failures = keep retrying'
Assert (-not (Test-ConsistentMismatch @('aa', 'bb', 'aa'))) 'different hashes = real corruption, keep retrying'

Write-Host "`nEnd-to-end test (local folders)"
$work = Join-Path ([IO.Path]::GetTempPath()) ("cpm-test-" + [guid]::NewGuid())
$src = Join-Path $work 'src'; $dst = Join-Path $work 'dst'; $state = Join-Path $work 'state'
foreach ($p in '2022/12/24', '2023/01/05', '2023/02/10', '2023/02/11', 'not-a-year/x') {
    $d = Join-Path $src $p; New-Item -ItemType Directory -Force $d | Out-Null
    1..3 | ForEach-Object { [IO.File]::WriteAllBytes((Join-Path $d "IMG_$_.jpg"), [byte[]](1..(100 * $_) | ForEach-Object { $_ % 256 })) }
}
$migrate = Join-Path $root 'migrate.ps1'; $verify = Join-Path $root 'verify.ps1'
$none = Join-Path $work 'no-config.psd1'

& powershell -NoProfile -ExecutionPolicy Bypass -File $migrate -Source $src -Destination $dst -To 2023-01 -StateDir $state -ConfigFile $none *> $null
Assert ($LASTEXITCODE -eq 0) 'migrate exits 0'
Assert ((Test-Path "$dst/2022/12/24/IMG_1.jpg") -and (Test-Path "$dst/2023/01/05/IMG_3.jpg")) 'months in range copied'
Assert (-not (Test-Path "$dst/2023/02")) 'month after -To not copied'
Assert (-not (Test-Path "$dst/not-a-year")) 'non YYYY folders ignored'
Assert (((Get-Content "$state/done.txt") -join ',') -eq '2022-12,2023-01') 'done.txt records finished months in order'

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $migrate -Source $src -Destination $dst -StateDir $state -ConfigFile $none 2>&1 | Out-String
Assert ($out -match '2022-12 already done, skipping') 'resume skips finished months'
Assert (Test-Path "$dst/2023/02/11/IMG_2.jpg") 'resume continues with remaining months'

& powershell -NoProfile -ExecutionPolicy Bypass -File $verify -Source $src -Destination $dst -StateDir $state -ConfigFile $none *> $null
Assert ($LASTEXITCODE -eq 0) 'verify passes when everything matches'

Remove-Item "$dst/2023/01/05/IMG_2.jpg"
& powershell -NoProfile -ExecutionPolicy Bypass -File $verify -Source $src -Destination $dst -StateDir $state -ConfigFile $none *> $null
Assert ($LASTEXITCODE -eq 1) 'verify fails when a file is missing'
Assert ((Get-Content "$state/verify-missing.txt") -contains '2023/01/05/IMG_2.jpg') 'verify lists the missing file'

Remove-Item $work -Recurse -Force
Write-Host ""
if ($script:failed) { Write-Host "$script:failed test(s) failed" -ForegroundColor Red; exit 1 }
Write-Host "All tests passed" -ForegroundColor Green
