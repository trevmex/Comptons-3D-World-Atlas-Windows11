[CmdletBinding()]
param(
    [string] $WorkspaceDirectory = (Join-Path $env:LOCALAPPDATA 'Comptons 3D World Atlas Deluxe')
)

$ErrorActionPreference = 'Stop'
$errors = New-Object Collections.Generic.List[string]
function Test-Requirement {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:errors.Add($Message) }
}

$configPath = Join-Path $WorkspaceDirectory 'Atlas-Config.json'
Test-Requirement (Test-Path -LiteralPath $configPath) "Atlas-Config.json is missing: $configPath"
if (-not (Test-Path -LiteralPath $configPath)) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$runtime = $config.RuntimeDirectory
$archive = $config.ArchiveMirror
$converted = $config.ConvertedMedia
$atlasPath = $config.AtlasExecutable
$shimPath = Join-Path $runtime 'Wlbrw32.dll'
$shimHashPath = Join-Path $runtime 'Wlbrw32.dll.sha256'
$originalShim = Join-Path $runtime 'Wlbrw32.dll.original-1998'
$logPath = $config.AtlasLog

foreach ($path in @($atlasPath, $shimPath, $originalShim, $logPath, $archive, $converted)) {
    Test-Requirement (Test-Path -LiteralPath $path) "Installed path is missing: $path"
}
if (Test-Path -LiteralPath $atlasPath) {
    Test-Requirement ((Get-FileHash -Algorithm SHA256 -LiteralPath $atlasPath).Hash -eq $config.AtlasExeSha256) 'The user-local Atlas executable hash changed.'
}
if (Test-Path -LiteralPath $shimPath) {
    $actualShimHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $shimPath).Hash
    Test-Requirement ($actualShimHash -eq $config.ShimSha256) 'The archive shim hash does not match Atlas-Config.json.'
    Test-Requirement (Test-Path -LiteralPath $shimHashPath) 'The archive shim sidecar hash is missing.'
    if (Test-Path -LiteralPath $shimHashPath) {
        $sidecarHash = ((Get-Content -LiteralPath $shimHashPath -Raw).Trim() -split '\s+')[0].ToUpperInvariant()
        Test-Requirement ($sidecarHash -eq $actualShimHash.ToUpperInvariant()) 'The archive shim sidecar hash does not match the installed DLL.'
    }
}
if (Test-Path -LiteralPath $originalShim) {
    Test-Requirement ((Get-FileHash -Algorithm SHA256 -LiteralPath $originalShim).Hash -eq $config.OriginalShimSha256) 'The original WonderLink backup hash changed.'
}

if (Test-Path -LiteralPath $logPath) {
    $logLines = Get-Content -LiteralPath $logPath
    Test-Requirement ($logLines -contains 'URL=https://archive-mode.invalid/atlas.cgi') 'The inert Online URL is not configured.'
    Test-Requirement ($logLines -contains 'Volume=5') 'Atlas volume is not restored to 5.'
    Test-Requirement ($logLines -contains 'Music=1') 'Atlas music is not enabled.'
    Test-Requirement ($logLines -contains 'Narration=1') 'Atlas narration is not enabled.'
    Test-Requirement ($logLines -contains "avi=$converted\AVI") 'The converted AVI root is not active.'
    Test-Requirement ($logLines -contains "game=$converted") 'The converted game root is not active.'

    $installedMappings = @()
    $inInstalled = $false
    foreach ($line in $logLines) {
        if ($line -eq '[Installed]') { $inInstalled = $true; continue }
        if ($inInstalled -and $line -match '^\[') { break }
        if ($inInstalled -and $line -match '=') { $installedMappings += $line }
    }
    Test-Requirement ($installedMappings.Count -gt 0) 'Atlas.log has no installed media mappings.'
    $missingMappings = @($installedMappings | ForEach-Object {
        $mappedPath = ($_ -split '=', 2)[1]
        if (-not (Test-Path -LiteralPath $mappedPath)) { $_ }
    })
    Test-Requirement ($missingMappings.Count -eq 0) "Found $($missingMappings.Count) missing installed mappings."
}

$aviFiles = @()
if (Test-Path -LiteralPath $converted) { $aviFiles = @(Get-ChildItem -LiteralPath $converted -Recurse -File -Filter '*.avi') }
$inventoryPath = Join-Path $converted 'media-inventory.json'
Test-Requirement (Test-Path -LiteralPath $inventoryPath) 'The media inventory is missing.'
if (Test-Path -LiteralPath $inventoryPath) {
    $inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
    Test-Requirement ($aviFiles.Count -eq [int]$inventory.Files) "Media inventory/file count mismatch ($($aviFiles.Count) vs $($inventory.Files))."
    $gameMovies = @(Get-ChildItem -LiteralPath (Join-Path $converted 'GAME\MOVIES') -Filter '*.avi' -File -ErrorAction SilentlyContinue)
    Test-Requirement ($gameMovies.Count -eq [int]$inventory.GameMovies) 'Game movie count does not match the media inventory.'
}

$ffprobe = if ($config.Tools -and $config.Tools.FFprobe) { $config.Tools.FFprobe } else { (Get-Command ffprobe.exe -ErrorAction SilentlyContinue).Source }
if ($ffprobe -and $aviFiles.Count) {
    $indeo = @($aviFiles | Where-Object {
        $codec = (& $ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 $_.FullName 2>$null).Trim()
        $codec -match '(?i)^indeo'
    })
    Test-Requirement ($indeo.Count -eq 0) "Obsolete Indeo remains in $($indeo.Count) converted videos."
}

if ($config.ArchiveStatus -eq 'COMPLETE' -and (Test-Path -LiteralPath $archive)) {
    & (Join-Path $WorkspaceDirectory 'Validate-AtlasLocalArchive.ps1') -MirrorRoot $archive
    Test-Requirement ($LASTEXITCODE -eq 0) 'The local Online Archive failed completeness validation.'
} else {
    Test-Requirement $false 'The installed profile does not contain a complete local Online Archive.'
}

$shortcutRoot = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shortcuts = @(Get-ChildItem -LiteralPath $shortcutRoot -Recurse -Filter '*Windows 11*.lnk' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "Compton's 3D World Atlas Deluxe*" })
Test-Requirement ($shortcuts.Count -eq 2) "Expected two Windows 11 shortcuts; found $($shortcuts.Count)."
Test-Requirement (-not (Test-Path 'Registry::HKEY_CURRENT_USER\Software\Classes\Software\CreativeWonders')) 'A legacy WonderLink browser-association override remains in the registry.'

$disc = Get-Volume -DriveLetter $config.DiscDrive.TrimEnd(':') -ErrorAction SilentlyContinue
Test-Requirement (Test-Path -LiteralPath (Join-Path $config.DiscDrive 'ATLAS.EXE')) 'The original disc is not mounted.'
Test-Requirement ($disc -and $disc.FileSystemLabel -eq '3DATLAS') 'The configured optical volume is not labeled 3DATLAS.'

if ($errors.Count) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

[pscustomobject]@{
    Status = 'PASS'
    Runtime = $runtime
    MediaFiles = $aviFiles.Count
    ArchiveFiles = (Get-ChildItem -LiteralPath $archive -Recurse -File).Count
    Shortcuts = $shortcuts.Count
    Disc = "$($disc.DriveLetter): $($disc.FileSystemLabel)"
    ArchiveShimSha256 = $config.ShimSha256
} | Format-List
