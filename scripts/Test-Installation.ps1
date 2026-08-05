param(
    [string] $DiscDrive = 'D:',
    [string] $WorkspaceDirectory = (Join-Path $env:LOCALAPPDATA 'Comptons 3D World Atlas Deluxe'),
    [string] $RuntimeDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\Comptons 3D World Atlas Deluxe')
)

$ErrorActionPreference = 'Stop'
$errors = New-Object Collections.Generic.List[string]
function Require([bool] $condition, [string] $message) { if (-not $condition) { $errors.Add($message) } }

$disc = $DiscDrive.TrimEnd('\')
Require (Test-Path -LiteralPath (Join-Path $disc 'ATLAS.EXE')) "Atlas disc is not mounted at $disc."
$volume = Get-Volume -DriveLetter $disc.TrimEnd(':') -ErrorAction SilentlyContinue
Require ($volume.FileSystemLabel -eq '3DATLAS') 'The optical volume is not labeled 3DATLAS.'
$atlas = Join-Path $RuntimeDirectory 'atlas.exe'
$shim = Join-Path $RuntimeDirectory 'Wlbrw32.dll'
Require (Test-Path -LiteralPath $atlas) 'The user-local Atlas executable is missing.'
Require (Test-Path -LiteralPath $shim) 'The local archive shim is missing.'
Require (Test-Path -LiteralPath (Join-Path $RuntimeDirectory 'Wlbrw32.dll.original-1998')) 'The original WonderLink DLL backup is missing.'

$mirror = Join-Path $WorkspaceDirectory 'Online Archive\Mirror'
foreach ($relative in @('3datlas\index.html','3datlas\download\f_main_dl.html','3datlas\sitemap.html','3datlas\entry-links.html','comptons\index.html')) {
    Require (Test-Path -LiteralPath (Join-Path $mirror $relative)) "Local archive target is missing: $relative"
}
Require ((Get-ChildItem -LiteralPath $mirror -Recurse -File -ErrorAction SilentlyContinue).Count -ge 100) 'The local archive mirror is unexpectedly small.'

$log = Join-Path $RuntimeDirectory 'Atlas.log'
$lines = Get-Content -LiteralPath $log
Require ($lines -contains 'URL=https://archive-mode.invalid/atlas.cgi') 'The inert Online URL is not configured.'
Require ($lines -contains 'Volume=5') 'Atlas volume is not set to 5.'
Require ($lines -contains 'Music=1') 'Atlas music is not enabled.'
Require ($lines -contains 'Narration=1') 'Atlas narration is not enabled.'
Require (($lines | Where-Object { $_ -eq "avi=$(Join-Path $WorkspaceDirectory 'Converted Media\AVI')" }).Count -eq 1) 'The converted AVI root is not active.'
Require (($lines | Where-Object { $_ -eq "game=$(Join-Path $WorkspaceDirectory 'Converted Media')" }).Count -eq 1) 'The converted game root is not active.'

$converted = Join-Path $WorkspaceDirectory 'Converted Media'
$movies = @(Get-ChildItem -LiteralPath (Join-Path $converted 'GAME\MOVIES') -Filter '*.avi' -File -ErrorAction SilentlyContinue)
Require ($movies.Count -eq 22) "Expected 22 local game movies; found $($movies.Count)."
$failures = @(Get-ChildItem -LiteralPath $converted -Recurse -File | Where-Object Extension -ieq '.avi' | ForEach-Object {
    $codec = (& (Get-Command ffprobe.exe -ErrorAction Stop).Source -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 $_.FullName 2>$null).Trim()
    if ($codec -match '(?i)^indeo[345]$') { $_.FullName }
})
Require ($failures.Count -eq 0) "Effective media still contains obsolete Indeo codecs: $($failures -join '; ')"

$results = Join-Path $WorkspaceDirectory 'Test Results\Online Archive\online-command-results.tsv'
if (Test-Path -LiteralPath $results) {
    $online = @(Import-Csv -LiteralPath $results -Delimiter "`t")
    Require ($online.Count -eq 4) 'Expected four Online command results.'
    Require (@($online | Where-Object Passed -ne 'True').Count -eq 0) 'At least one Online command failed.'
}

if ($errors.Count) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }
[pscustomobject]@{
    Status = 'PASS'
    Disc = "$($volume.DriveLetter): $($volume.FileSystemLabel)"
    Runtime = $RuntimeDirectory
    LocalArchiveFiles = (Get-ChildItem -LiteralPath $mirror -Recurse -File).Count
    GameMovies = $movies.Count
    ArchiveShimSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $shim).Hash
} | Format-List
