[CmdletBinding()]
param(
    [string] $DiscDrive = 'D:',
    [string] $WorkspaceDirectory = (Join-Path $env:LOCALAPPDATA 'Comptons 3D World Atlas Deluxe'),
    [string] $RuntimeDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\Comptons 3D World Atlas Deluxe'),
    [switch] $SkipArchiveMirror,
    [switch] $SkipToolBootstrap,
    [switch] $SkipShortcutCreation
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$drive = $DiscDrive.TrimEnd('\')
$driveLetter = $drive.TrimEnd(':')
$discExe = Join-Path $drive 'ATLAS.EXE'

if (-not (Test-Path -LiteralPath $discExe)) {
    throw "The Atlas CD was not found at $drive. Insert your lawful Compton's 3D World Atlas Deluxe disc and verify that it is mounted as drive D:."
}
$volume = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
if (-not $volume -or $volume.FileSystemLabel -ne '3DATLAS') {
    $label = if ($volume) { $volume.FileSystemLabel } else { '(volume unavailable)' }
    throw "The selected drive is not the 3DATLAS physical disc. Found label '$label' at $drive."
}

$runtimeProcess = @(Get-Process -Name atlas -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -ieq (Join-Path $RuntimeDirectory 'atlas.exe') } catch { $false }
})
if ($runtimeProcess.Count) { throw 'Close the user-local Atlas process before reinstalling.' }

$scriptFiles = @(
    'Ensure-AtlasTools.ps1', 'Launch-ComptonsAtlas.ps1', 'Create-AtlasShortcuts.ps1',
    'Invoke-AtlasCommand.ps1', 'Capture-AtlasWindow.ps1', 'Click-AtlasPoint.ps1',
    'Run-AtlasContentSmokeTests.ps1', 'Run-AtlasDisplayTests.ps1', 'Test-AtlasAudioSession.ps1',
    'Test-AtlasGameMoviesMci.ps1', 'Test-AtlasOnlineArchive.ps1', 'Validate-AtlasLocalArchive.ps1',
    'Validate-AtlasWindows11Setup.ps1', 'Convert-AtlasMedia.ps1', 'Validate-AtlasMedia.ps1',
    'Test-Installation.ps1', 'Sync-AtlasLocalArchive.js'
)
foreach ($file in $scriptFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file))) {
        throw "The toolkit file is missing: $file"
    }
}

New-Item -ItemType Directory -Path $WorkspaceDirectory, $RuntimeDirectory -Force | Out-Null
$onlineDirectory = Join-Path $WorkspaceDirectory 'Online Archive'
$convertedDirectory = Join-Path $WorkspaceDirectory 'Converted Media'
New-Item -ItemType Directory -Path $onlineDirectory -Force | Out-Null

$toolReportPath = Join-Path $WorkspaceDirectory 'tool-report.json'
$toolArgs = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Ensure-AtlasTools.ps1'),
    '-ToolsDirectory', (Join-Path $WorkspaceDirectory 'Tools'), '-OutputPath', $toolReportPath)
if (-not $SkipToolBootstrap) { $toolArgs += '-InstallMissing' }
if (-not $SkipArchiveMirror) { $toolArgs += '-RequireNode' }
& (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') @toolArgs
if ($LASTEXITCODE) { throw "The prerequisite check failed with exit code $LASTEXITCODE." }
$toolReport = Get-Content -LiteralPath $toolReportPath -Raw | ConvertFrom-Json
$ffmpegPath = $toolReport.FFmpeg
$ffprobePath = $toolReport.FFprobe
$nodePath = $toolReport.Node

# A direct copy from the physical disc is intentional. Running the 1998
# setup first would install obsolete system codecs and 16-bit components.
# Only the executable's small root runtime is copied; content remains on D:.
$runtimeFiles = @(
    'ATLAS.EXE', 'ATLAS.INI', 'ATLAS.LOG', 'ATLASFT.FON', 'ALIAS.EXE', 'ALIAS.INI',
    'LAUNCH32.DLL', 'MSVCIRT.DLL', 'MSVCRT.DLL', 'STARTUP.ICO', 'SYSINFO.DLL',
    'WLBRW32.DLL', 'ZLIB32.DLL', 'README.TXT'
)
foreach ($file in $runtimeFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $drive $file))) {
        throw "The physical disc is missing required runtime file $file."
    }
}
if (Test-Path -LiteralPath $RuntimeDirectory) {
    Get-ChildItem -LiteralPath $RuntimeDirectory -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
foreach ($file in $runtimeFiles) {
    Copy-Item -LiteralPath (Join-Path $drive $file) -Destination $RuntimeDirectory -Force
}
foreach ($file in (Get-ChildItem -LiteralPath $RuntimeDirectory -Recurse -File)) {
    $file.IsReadOnly = $false
}
$runtimeExe = Join-Path $RuntimeDirectory 'atlas.exe'
$runtimeLog = Join-Path $RuntimeDirectory 'Atlas.log'
$runtimeIni = Join-Path $RuntimeDirectory 'Atlas.ini'
$originalShim = Join-Path $RuntimeDirectory 'Wlbrw32.dll.original-1998'
Copy-Item -LiteralPath (Join-Path $drive 'WLBRW32.DLL') -Destination $originalShim -Force

# Rebuild the generated media tree rather than allowing stale files from a
# previous installation to masquerade as current disc content.
Remove-Item -LiteralPath $convertedDirectory -Recurse -Force -ErrorAction SilentlyContinue
& (Join-Path $PSScriptRoot 'Convert-AtlasMedia.ps1') -DiscDrive $drive -OutputRoot $convertedDirectory `
    -FfmpegPath $ffmpegPath -FfprobePath $ffprobePath
if ($LASTEXITCODE) { throw "Atlas media conversion failed with exit code $LASTEXITCODE." }

function Set-SectionBody([string] $Text, [string] $Section, [string] $Body) {
    $pattern = "(?ms)^\[$([regex]::Escape($Section))\]\r?\n(?<body>.*?)(?=^\[|\z)"
    $match = [regex]::Match($Text, $pattern)
    $replacement = "[$Section]`r`n$Body`r`n"
    if ($match.Success) {
        return $Text.Substring(0, $match.Index) + $replacement +
            $Text.Substring($match.Index + $match.Length)
    }
    return $Text.TrimEnd() + "`r`n`r`n$replacement"
}

function Set-SectionValue([string] $Text, [string] $Section, [string] $Key, [string] $Value) {
    $pattern = "(?ms)^\[$([regex]::Escape($Section))\]\r?\n(?<body>.*?)(?=^\[|\z)"
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        return $Text.TrimEnd() + "`r`n`r`n[$Section]`r`n$Key=$Value`r`n"
    }
    $body = $match.Groups['body'].Value
    $keyPattern = "(?im)^$([regex]::Escape($Key))\s*=.*$"
    if ([regex]::IsMatch($body, $keyPattern)) {
        $body = [regex]::Replace($body, $keyPattern, "$Key=$Value")
    } else {
        $body = $body.TrimEnd("`r", "`n") + "`r`n$Key=$Value`r`n"
    }
    return $Text.Substring(0, $match.Index) + "[$Section]`r`n$body" +
        $Text.Substring($match.Index + $match.Length)
}

$encoding = [Text.Encoding]::Default
$logText = [IO.File]::ReadAllText($runtimeLog, $encoding)
$installed = [ordered]@{}
$installedMatch = [regex]::Match($logText, '(?ms)^\[Installed\]\r?\n(?<body>.*?)(?=^\[|\z)')
if ($installedMatch.Success) {
    foreach ($line in ($installedMatch.Groups['body'].Value -split '\r?\n')) {
        if ($line -match '^\s*([^=]+?)\s*=\s*(.+?)\s*$') {
            $installed[$matches[1].Trim().ToLowerInvariant()] = $matches[2].Trim()
        }
    }
}
foreach ($file in (Get-ChildItem -LiteralPath $convertedDirectory -Recurse -File -Filter '*.avi')) {
    $installed[$file.Name.ToLowerInvariant()] = $file.FullName
}
foreach ($name in @('cities.chk', 'captions.chk')) {
    $discPath = Join-Path $drive (Join-Path 'chunks' $name)
    if (Test-Path -LiteralPath $discPath) { $installed[$name] = $discPath }
}
$installedBody = ($installed.GetEnumerator() | Sort-Object Key | ForEach-Object {
    "$($_.Key)=$($_.Value)"
}) -join "`r`n"
$logText = Set-SectionBody $logText 'Installed' $installedBody

$discPaths = [ordered]@{
    sounds = (Join-Path $drive 'sounds')
    bitmaps = (Join-Path $drive 'dibs')
    jpegs = (Join-Path $drive 'dibs')
    stats = (Join-Path $drive 'stats')
    avi = (Join-Path $convertedDirectory 'AVI')
    postcard = $drive
    help = (Join-Path $drive 'help')
    text = (Join-Path $drive 'stats')
    chunks = (Join-Path $drive 'chunks')
    pins = (Join-Path $drive 'chunks\mappins')
    dibs = (Join-Path $drive 'dibs')
    game = $convertedDirectory
    jpeg = $drive
}
foreach ($entry in $discPaths.GetEnumerator()) {
    $logText = Set-SectionValue $logText 'InstallPaths' $entry.Key $entry.Value
}
$logText = Set-SectionValue $logText 'WLPreferences' 'URL' 'https://archive-mode.invalid/atlas.cgi'
$logText = Set-SectionValue $logText 'Sounds' 'Volume' '5'
$logText = Set-SectionValue $logText 'Sounds' 'Music' '1'
$logText = Set-SectionValue $logText 'Sounds' 'Narration' '1'
Copy-Item -LiteralPath $runtimeLog -Destination "$runtimeLog.backup-before-windows11-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
[IO.File]::WriteAllText($runtimeLog, $logText, $encoding)

if (Test-Path -LiteralPath $runtimeIni) {
    $ini = [IO.File]::ReadAllText($runtimeIni, $encoding)
    if ($ini -notmatch '(?im)^\[Ereg\]') {
        $ini = $ini.TrimEnd() + "`r`n`r`n[Ereg]`r`nMaxLaunch=0`r`nLaunchCount=0`r`n"
    } else {
        $ini = [regex]::Replace($ini, '(?im)^MaxLaunch=.*$', 'MaxLaunch=0')
    }
    [IO.File]::WriteAllText($runtimeIni, $ini, $encoding)
}

foreach ($file in $scriptFiles) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $WorkspaceDirectory -Force
}
Set-Content -LiteralPath (Join-Path $WorkspaceDirectory 'ArchiveRoot.txt') -Value $onlineDirectory -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $repoRoot 'src\Atlas-WonderLink-Archive.c') -Destination $onlineDirectory -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'src\Wlbrw32.def') -Destination $onlineDirectory -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'archive\Atlas-Online-Archive.html') -Destination $onlineDirectory -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'archive\Atlas-Online-Entry.html') -Destination $onlineDirectory -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Sync-AtlasLocalArchive.js') -Destination $onlineDirectory -Force

$prebuiltShim = Join-Path $repoRoot 'build\Wlbrw32.dll'
if (-not (Test-Path -LiteralPath $prebuiltShim)) {
    $buildScript = Join-Path $repoRoot 'scripts\Build-WonderLink-Archive.cmd'
    & $buildScript
    if ($LASTEXITCODE) { throw "The WonderLink archive shim build failed with exit code $LASTEXITCODE." }
}
if (-not (Test-Path -LiteralPath $prebuiltShim)) { throw "The toolkit did not provide a built x86 Wlbrw32.dll." }
$shimBytes = [IO.File]::ReadAllBytes($prebuiltShim)
$shimPeOffset = [BitConverter]::ToInt32($shimBytes, 0x3c)
$shimMachine = [BitConverter]::ToUInt16($shimBytes, $shimPeOffset + 4)
if ($shimMachine -ne 0x014c) { throw 'The archive shim is not an x86 PE DLL.' }
$runtimeShim = Join-Path $RuntimeDirectory 'Wlbrw32.dll'
Copy-Item -LiteralPath $prebuiltShim -Destination $runtimeShim -Force
$shimHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeShim).Hash
$shimHash | Set-Content -LiteralPath (Join-Path $RuntimeDirectory 'Wlbrw32.dll.sha256') -Encoding ASCII

if (-not $SkipArchiveMirror) {
    $oldMirrorRoot = $env:ATLAS_ARCHIVE_MIRROR_ROOT
    $oldConcurrency = $env:ATLAS_ARCHIVE_CONCURRENCY
    try {
        $env:ATLAS_ARCHIVE_MIRROR_ROOT = Join-Path $onlineDirectory 'Mirror'
        $env:ATLAS_ARCHIVE_CONCURRENCY = '6'
        & $nodePath (Join-Path $onlineDirectory 'Sync-AtlasLocalArchive.js')
        if ($LASTEXITCODE) { throw "The Internet Archive mirror failed with exit code $LASTEXITCODE." }
    } finally {
        if ($null -eq $oldMirrorRoot) { Remove-Item Env:ATLAS_ARCHIVE_MIRROR_ROOT -ErrorAction SilentlyContinue }
        else { $env:ATLAS_ARCHIVE_MIRROR_ROOT = $oldMirrorRoot }
        if ($null -eq $oldConcurrency) { Remove-Item Env:ATLAS_ARCHIVE_CONCURRENCY -ErrorAction SilentlyContinue }
        else { $env:ATLAS_ARCHIVE_CONCURRENCY = $oldConcurrency }
    }
    & (Join-Path $WorkspaceDirectory 'Validate-AtlasLocalArchive.ps1') -MirrorRoot (Join-Path $onlineDirectory 'Mirror')
    if ($LASTEXITCODE) { throw 'The downloaded Online Archive did not pass completeness validation.' }
}

$mediaInventoryPath = Join-Path $convertedDirectory 'media-inventory.json'
$mediaInventory = Get-Content -LiteralPath $mediaInventoryPath -Raw | ConvertFrom-Json
$atlasHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeExe).Hash
$originalShimHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $originalShim).Hash
$config = [ordered]@{
    Schema = 1
    InstalledAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    DiscDrive = $drive
    DiscLabel = $volume.FileSystemLabel
    WorkspaceDirectory = $WorkspaceDirectory
    RuntimeDirectory = $RuntimeDirectory
    ArchiveDirectory = $onlineDirectory
    ArchiveMirror = (Join-Path $onlineDirectory 'Mirror')
    ConvertedMedia = $convertedDirectory
    AtlasExecutable = $runtimeExe
    AtlasLog = $runtimeLog
    Launcher = (Join-Path $WorkspaceDirectory 'Launch-ComptonsAtlas.ps1')
    AtlasExeSha256 = $atlasHash
    OriginalShimSha256 = $originalShimHash
    ShimSha256 = $shimHash
    ArchiveStatus = if ($SkipArchiveMirror) { 'NOT_SYNCED' } else { 'COMPLETE' }
    MediaFiles = [int]$mediaInventory.Files
    ConvertedFiles = [int]$mediaInventory.Converted
    GameMovies = [int]$mediaInventory.GameMovies
    Tools = $toolReport
}
$config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $WorkspaceDirectory 'Atlas-Config.json') -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $repoRoot 'README.md') -Destination (Join-Path $WorkspaceDirectory 'README-Windows-11-fix.txt') -Force
foreach ($doc in (Get-ChildItem -LiteralPath (Join-Path $repoRoot 'docs') -File -Filter '*.md')) {
    Copy-Item -LiteralPath $doc.FullName -Destination (Join-Path $WorkspaceDirectory $doc.Name) -Force
}
if (-not $SkipShortcutCreation) { & (Join-Path $WorkspaceDirectory 'Create-AtlasShortcuts.ps1') }

[pscustomobject]@{
    Status = if ($SkipArchiveMirror) { 'INSTALLED_ARCHIVE_NOT_SYNCED' } else { 'INSTALLED' }
    Disc = "$drive ($($volume.FileSystemLabel))"
    Runtime = $RuntimeDirectory
    Workspace = $WorkspaceDirectory
    ConvertedMedia = $convertedDirectory
    MediaFiles = $mediaInventory.Files
    ConvertedVideos = $mediaInventory.Converted
    LocalArchive = (Join-Path $onlineDirectory 'Mirror')
    ArchiveShimSha256 = $shimHash
} | Format-List
