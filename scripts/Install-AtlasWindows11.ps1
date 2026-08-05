[CmdletBinding()]
param(
    [string] $DiscDrive = 'D:',
    [string] $InstalledDirectory = "C:\Program Files (x86)\Compton's Home Library\Compton's 3D World Atlas Deluxe",
    [string] $WorkspaceDirectory = (Join-Path $env:LOCALAPPDATA 'Comptons 3D World Atlas Deluxe'),
    [string] $RuntimeDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\Comptons 3D World Atlas Deluxe'),
    [switch] $SkipArchiveMirror,
    [switch] $SkipShortcutCreation
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$drive = $DiscDrive.TrimEnd('\')
$discExe = Join-Path $drive 'ATLAS.EXE'

if (-not (Test-Path -LiteralPath $discExe)) {
    throw "The Atlas CD was not found at $drive. Insert the disc and verify that it is mounted as drive D:."
}
$volume = Get-Volume -DriveLetter $drive.TrimEnd(':') -ErrorAction SilentlyContinue
if ($volume -and $volume.FileSystemLabel -ne '3DATLAS') {
    throw "The selected drive is not labeled 3DATLAS: $($volume.FileSystemLabel)"
}
if (-not (Test-Path -LiteralPath (Join-Path $InstalledDirectory 'atlas.exe'))) {
    throw "The original Atlas installation was not found at $InstalledDirectory. Run the disc's original setup first."
}

$scriptFiles = @(
    'Launch-ComptonsAtlas.ps1', 'Create-AtlasShortcuts.ps1', 'Invoke-AtlasCommand.ps1',
    'Capture-AtlasWindow.ps1', 'Click-AtlasPoint.ps1', 'Run-AtlasContentSmokeTests.ps1',
    'Run-AtlasDisplayTests.ps1', 'Test-AtlasAudioSession.ps1', 'Test-AtlasGameMoviesMci.ps1',
    'Test-AtlasOnlineArchive.ps1', 'Validate-AtlasWindows11Setup.ps1'
)
$onlineDirectory = Join-Path $WorkspaceDirectory 'Online Archive'
$convertedDirectory = Join-Path $WorkspaceDirectory 'Converted Media'
New-Item -ItemType Directory -Path $WorkspaceDirectory, $RuntimeDirectory, $onlineDirectory -Force | Out-Null

# Preserve the installed program and copy only the user-local compatibility
# runtime. The original Program Files installation is never modified.
Copy-Item -Path (Join-Path $InstalledDirectory '*') -Destination $RuntimeDirectory -Recurse -Force
foreach ($file in $scriptFiles) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $WorkspaceDirectory -Force
}
Set-Content -LiteralPath (Join-Path $WorkspaceDirectory 'ArchiveRoot.txt') -Value $onlineDirectory -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $repoRoot 'src\Atlas-WonderLink-Archive.c') -Destination $onlineDirectory -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'src\Wlbrw32.def') -Destination $onlineDirectory -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\Sync-AtlasLocalArchive.js') -Destination $onlineDirectory -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'archive\Atlas-Online-Archive.html') -Destination $onlineDirectory -Force

# Convert the obsolete Indeo AVI files into Microsoft Video 1, retaining the
# original PCM audio streams. The disc remains the source of all content.
& (Join-Path $PSScriptRoot 'Convert-AtlasMedia.ps1') -DiscDrive $drive -OutputRoot $convertedDirectory

$runtimeLog = Join-Path $RuntimeDirectory 'Atlas.log'
if (-not (Test-Path -LiteralPath $runtimeLog)) { throw "Atlas.log was not copied to $RuntimeDirectory." }
$encoding = [Text.Encoding]::Default
$logText = [IO.File]::ReadAllText($runtimeLog, $encoding)
$installed = [ordered]@{}
$installedMatch = [regex]::Match($logText, '(?ms)^\[Installed\]\r?\n(?<body>.*?)(?=^\[InstallPaths\])')
if ($installedMatch.Success) {
    foreach ($line in ($installedMatch.Groups['body'].Value -split '\r?\n')) {
        if ($line -match '^\s*([^=]+?)\s*=\s*(.+?)\s*$') { $installed[$matches[1].Trim().ToLowerInvariant()] = $matches[2].Trim() }
    }
}
foreach ($file in (Get-ChildItem -LiteralPath $convertedDirectory -Recurse -File -Filter '*.avi')) {
    $installed[$file.Name.ToLowerInvariant()] = $file.FullName
}
$installedBody = ($installed.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`r`n"
$newSection = "[Installed]`r`n$installedBody`r`n`r`n"
if ($installedMatch.Success) {
    $logText = $logText.Substring(0, $installedMatch.Index) + $newSection + $logText.Substring($installedMatch.Index + $installedMatch.Length)
} else {
    $logText = "[version]`r`nVersion = 1.00.000`r`nName = Compton's 3D World Atlas Deluxe`r`n`r`n" + $newSection + $logText
}

$discPaths = @{
    sounds = (Join-Path $drive 'sounds'); bitmaps = (Join-Path $drive 'dibs'); jpegs = (Join-Path $drive 'dibs');
    stats = (Join-Path $drive 'stats'); postcard = $drive; help = (Join-Path $drive 'help');
    text = (Join-Path $drive 'stats'); chunks = (Join-Path $drive 'chunks'); pins = (Join-Path $drive 'chunks\mappins');
    dibs = (Join-Path $drive 'dibs'); jpeg = $drive; tdf = (Join-Path $drive 'tdf')
}
foreach ($entry in $discPaths.GetEnumerator()) {
    $pattern = "(?m)^$([regex]::Escape($entry.Key))=.*$"
    $logText = [regex]::Replace($logText, $pattern, "$($entry.Key)=$($entry.Value)")
}
$logText = [regex]::Replace($logText, '(?m)^avi=.*$', "avi=$(Join-Path $convertedDirectory 'AVI')")
$logText = [regex]::Replace($logText, '(?m)^game=.*$', "game=$convertedDirectory")
$logText = [regex]::Replace($logText, '(?m)^URL=.*$', 'URL=https://archive-mode.invalid/atlas.cgi')
$logText = [regex]::Replace($logText, '(?m)^Volume=.*$', 'Volume=5')
$logText = [regex]::Replace($logText, '(?m)^Music=.*$', 'Music=1')
$logText = [regex]::Replace($logText, '(?m)^Narration=.*$', 'Narration=1')
$backupLog = "$runtimeLog.backup-before-windows11-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item -LiteralPath $runtimeLog -Destination $backupLog -Force
[IO.File]::WriteAllText($runtimeLog, $logText, $encoding)

$runtimeIni = Join-Path $RuntimeDirectory 'Atlas.ini'
if (Test-Path -LiteralPath $runtimeIni) {
    $ini = [IO.File]::ReadAllText($runtimeIni, $encoding)
    if ($ini -notmatch '(?m)^\[Ereg\]') { $ini += "`r`n[Ereg]`r`nMaxLaunch=0`r`nLaunchCount=0`r`n" }
    else { $ini = [regex]::Replace($ini, '(?m)^MaxLaunch=.*$', 'MaxLaunch=0') }
    [IO.File]::WriteAllText($runtimeIni, $ini, $encoding)
}

# The native shim is built from source, then installed beside the user-local
# Atlas.exe. A copied original DLL is retained for rollback.
$buildScript = Join-Path $repoRoot 'scripts\Build-WonderLink-Archive.cmd'
& $buildScript
if ($LASTEXITCODE) { throw "The WonderLink archive shim build failed with exit code $LASTEXITCODE." }
$builtShim = Join-Path $repoRoot 'build\Wlbrw32.dll'
$runtimeShim = Join-Path $RuntimeDirectory 'Wlbrw32.dll'
if (-not (Test-Path -LiteralPath $builtShim)) { throw "The shim build did not produce $builtShim." }
if (-not (Test-Path -LiteralPath (Join-Path $RuntimeDirectory 'Wlbrw32.dll.original-1998'))) {
    Copy-Item -LiteralPath (Join-Path $RuntimeDirectory 'Wlbrw32.dll') -Destination (Join-Path $RuntimeDirectory 'Wlbrw32.dll.original-1998') -Force
}
Copy-Item -LiteralPath $builtShim -Destination $runtimeShim -Force
(Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeShim).Hash | Set-Content -LiteralPath (Join-Path $RuntimeDirectory 'Wlbrw32.dll.sha256') -Encoding ASCII

if (-not $SkipArchiveMirror) {
    $oldMirrorRoot = $env:ATLAS_ARCHIVE_MIRROR_ROOT
    try {
        $env:ATLAS_ARCHIVE_MIRROR_ROOT = Join-Path $onlineDirectory 'Mirror'
        & node (Join-Path $onlineDirectory 'Sync-AtlasLocalArchive.js')
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 1) { throw "The local archive mirror failed with exit code $LASTEXITCODE." }
    } finally {
        if ($null -eq $oldMirrorRoot) { Remove-Item Env:ATLAS_ARCHIVE_MIRROR_ROOT -ErrorAction SilentlyContinue }
        else { $env:ATLAS_ARCHIVE_MIRROR_ROOT = $oldMirrorRoot }
    }
}

Copy-Item -LiteralPath (Join-Path $repoRoot 'README.md') -Destination (Join-Path $WorkspaceDirectory 'README-Windows-11-fix.txt') -Force
if (-not $SkipShortcutCreation) { & (Join-Path $WorkspaceDirectory 'Create-AtlasShortcuts.ps1') }

[pscustomobject]@{
    Status = 'INSTALLED'
    Disc = "$drive ($($volume.FileSystemLabel))"
    Runtime = $RuntimeDirectory
    Workspace = $WorkspaceDirectory
    ConvertedMedia = $convertedDirectory
    LocalArchive = (Join-Path $onlineDirectory 'Mirror')
    ArchiveShimSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeShim).Hash
} | Format-List
