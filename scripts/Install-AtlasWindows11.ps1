[CmdletBinding()]
param(
    [string] $DiscDrive = 'D:',
    [string] $WorkspaceDirectory = (Join-Path $env:LOCALAPPDATA 'Comptons 3D World Atlas Deluxe'),
    [string] $RuntimeDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\Comptons 3D World Atlas Deluxe'),
    [string] $LogPath = '',
    [switch] $SkipArchiveMirror,
    [switch] $SkipToolBootstrap,
    [switch] $SkipShortcutCreation
)

$ErrorActionPreference = 'Stop'
$transcriptStarted = $false
$transactionId = [Guid]::NewGuid().ToString('N')
$stagingRoot = ''
$runtimeBackupPath = ''
$convertedBackupPath = ''
$archiveBackupPath = ''
$runtimePublished = $false
$convertedPublished = $false
$archivePublished = $false
$configBackupPath = ''
$configHadExisting = $false
$configWriteStarted = $false
$transactionCommitted = $false
if ($LogPath) {
    try {
        $logParent = Split-Path -Parent $LogPath
        if ($logParent) { New-Item -ItemType Directory -Path $logParent -Force | Out-Null }
        Start-Transcript -LiteralPath $LogPath -Force | Out-Null
        $transcriptStarted = $true
    } catch {
        Write-Warning "Could not start installer log at '$LogPath': $($_.Exception.Message)"
    }
}

function Restore-PublishedDirectory {
    param(
        [string] $LivePath,
        [string] $BackupPath,
        [bool] $WasPublished
    )

    if (-not $WasPublished) { return }
    if (Test-Path -LiteralPath $LivePath) {
        Remove-Item -LiteralPath $LivePath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($BackupPath -and (Test-Path -LiteralPath $BackupPath)) {
        Move-Item -LiteralPath $BackupPath -Destination $LivePath -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

function Publish-StagedDirectory {
    param(
        [string] $StagedPath,
        [string] $LivePath
    )

    if (-not (Test-Path -LiteralPath $StagedPath)) {
        throw "The staged installation directory is missing: $StagedPath"
    }
    $liveParent = Split-Path -Parent $LivePath
    if ($liveParent) { New-Item -ItemType Directory -Path $liveParent -Force | Out-Null }

    $backupPath = ''
    if (Test-Path -LiteralPath $LivePath) {
        $backupPath = "$LivePath.install-backup-$transactionId"
        if (Test-Path -LiteralPath $backupPath) {
            Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction Stop
        }
        Move-Item -LiteralPath $LivePath -Destination $backupPath -Force -ErrorAction Stop | Out-Null
    }

    try {
        Move-Item -LiteralPath $StagedPath -Destination $LivePath -Force -ErrorAction Stop | Out-Null
    } catch {
        if (Test-Path -LiteralPath $LivePath) {
            Remove-Item -LiteralPath $LivePath -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
            Move-Item -LiteralPath $backupPath -Destination $LivePath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        throw
    }
    return $backupPath
}

trap {
    $failure = $_
    try {
        if (-not $transactionCommitted) {
            if ($configWriteStarted) {
                $liveConfigPath = Join-Path $WorkspaceDirectory 'Atlas-Config.json'
                if ($configHadExisting -and $configBackupPath -and (Test-Path -LiteralPath $configBackupPath)) {
                    Copy-Item -LiteralPath $configBackupPath -Destination $liveConfigPath -Force -ErrorAction SilentlyContinue
                } elseif (-not $configHadExisting -and (Test-Path -LiteralPath $liveConfigPath)) {
                    Remove-Item -LiteralPath $liveConfigPath -Force -ErrorAction SilentlyContinue
                }
            }
            Restore-PublishedDirectory (Join-Path $WorkspaceDirectory 'Online Archive\Mirror') $archiveBackupPath $archivePublished
            Restore-PublishedDirectory (Join-Path $WorkspaceDirectory 'Converted Media') $convertedBackupPath $convertedPublished
            Restore-PublishedDirectory $RuntimeDirectory $runtimeBackupPath $runtimePublished
            if ($stagingRoot -and (Test-Path -LiteralPath $stagingRoot)) {
                Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Warning "The failed installation could not be fully rolled back: $($_.Exception.Message)"
    }
    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
    throw $failure
}
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
    'Convert-AtlasMediaWorker.ps1',
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

$prebuiltShim = Join-Path $repoRoot 'build\Wlbrw32.dll'
if (-not (Test-Path -LiteralPath $prebuiltShim)) {
    $buildScript = Join-Path $repoRoot 'scripts\Build-WonderLink-Archive.cmd'
    & $buildScript
    if ($LASTEXITCODE) { throw "The WonderLink archive shim build failed with exit code $LASTEXITCODE." }
}
if (-not (Test-Path -LiteralPath $prebuiltShim)) { throw "The toolkit did not provide a built x86 Wlbrw32.dll." }
$shimBytes = [IO.File]::ReadAllBytes($prebuiltShim)
if ($shimBytes.Length -lt 0x40) { throw 'The archive shim is too small to be a PE DLL.' }
$shimPeOffset = [BitConverter]::ToInt32($shimBytes, 0x3c)
if ($shimPeOffset -lt 0 -or ($shimPeOffset + 6) -gt $shimBytes.Length) {
    throw 'The archive shim has an invalid PE header.'
}
$shimMachine = [BitConverter]::ToUInt16($shimBytes, $shimPeOffset + 4)
if ($shimMachine -ne 0x014c) { throw 'The archive shim is not an x86 PE DLL.' }
$prebuiltShimHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $prebuiltShim).Hash

$onlineDirectory = Join-Path $WorkspaceDirectory 'Online Archive'
$convertedDirectory = Join-Path $WorkspaceDirectory 'Converted Media'
$stagingParent = Split-Path -Parent $WorkspaceDirectory
$stagingRoot = Join-Path $stagingParent ('.Comptons-3D-World-Atlas-Install-' + $transactionId)
$stagingWorkspaceDirectory = Join-Path $stagingRoot 'Workspace'
$stagingRuntimeDirectory = Join-Path $stagingRoot 'Runtime'
$stagingOnlineDirectory = Join-Path $stagingWorkspaceDirectory 'Online Archive'
$stagingConvertedDirectory = Join-Path $stagingWorkspaceDirectory 'Converted Media'
New-Item -ItemType Directory -Path $stagingWorkspaceDirectory, $stagingRuntimeDirectory, $stagingOnlineDirectory -Force | Out-Null

$toolReportPath = Join-Path $stagingWorkspaceDirectory 'tool-report.json'
$toolArgs = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Ensure-AtlasTools.ps1'),
    '-ToolsDirectory', (Join-Path $stagingWorkspaceDirectory 'Tools'), '-OutputPath', $toolReportPath)
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
# Prepare every generated file away from the live installation. A failed
# conversion, archive download, or disc read must never replace a working
# runtime with the original 1998 DLL while the old config still expects the
# Windows 11 shim.
foreach ($file in $runtimeFiles) {
    Copy-Item -LiteralPath (Join-Path $drive $file) -Destination $stagingRuntimeDirectory -Force
}
foreach ($file in (Get-ChildItem -LiteralPath $stagingRuntimeDirectory -Recurse -File)) {
    $file.IsReadOnly = $false
}
$stagingRuntimeExe = Join-Path $stagingRuntimeDirectory 'atlas.exe'
$stagingRuntimeLog = Join-Path $stagingRuntimeDirectory 'Atlas.log'
$stagingRuntimeIni = Join-Path $stagingRuntimeDirectory 'Atlas.ini'
$stagingOriginalShim = Join-Path $stagingRuntimeDirectory 'Wlbrw32.dll.original-1998'
$stagingRuntimeShim = Join-Path $stagingRuntimeDirectory 'Wlbrw32.dll'
Copy-Item -LiteralPath (Join-Path $drive 'WLBRW32.DLL') -Destination $stagingOriginalShim -Force
Copy-Item -LiteralPath $prebuiltShim -Destination $stagingRuntimeShim -Force
$shimHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stagingRuntimeShim).Hash
if ($shimHash -ne $prebuiltShimHash) {
    throw 'The staged Windows 11 Online Archive component did not match the verified toolkit artifact.'
}
$shimHash | Set-Content -LiteralPath (Join-Path $stagingRuntimeDirectory 'Wlbrw32.dll.sha256') -Encoding ASCII

# Rebuild the generated media tree rather than allowing stale files from a
# previous installation to masquerade as current disc content. The live tree
# is not touched until this conversion and all later validation succeeds.
& (Join-Path $PSScriptRoot 'Convert-AtlasMedia.ps1') -DiscDrive $drive -OutputRoot $stagingConvertedDirectory `
    -FfmpegPath $ffmpegPath -FfprobePath $ffprobePath
if ($LASTEXITCODE) { throw "Atlas media conversion failed with exit code $LASTEXITCODE." }

$runtimeExe = Join-Path $RuntimeDirectory 'atlas.exe'
$runtimeLog = Join-Path $RuntimeDirectory 'Atlas.log'
$runtimeIni = Join-Path $RuntimeDirectory 'Atlas.ini'
$originalShim = Join-Path $RuntimeDirectory 'Wlbrw32.dll.original-1998'
$runtimeShim = Join-Path $RuntimeDirectory 'Wlbrw32.dll'

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
$logText = [IO.File]::ReadAllText($stagingRuntimeLog, $encoding)
$installed = [ordered]@{}
$installedMatch = [regex]::Match($logText, '(?ms)^\[Installed\]\r?\n(?<body>.*?)(?=^\[|\z)')
if ($installedMatch.Success) {
    foreach ($line in ($installedMatch.Groups['body'].Value -split '\r?\n')) {
        if ($line -match '^\s*([^=]+?)\s*=\s*(.+?)\s*$') {
            $installed[$matches[1].Trim().ToLowerInvariant()] = $matches[2].Trim()
        }
    }
}
foreach ($file in (Get-ChildItem -LiteralPath $stagingConvertedDirectory -Recurse -File -Filter '*.avi')) {
    $relativePath = $file.FullName.Substring($stagingConvertedDirectory.Length).TrimStart('\')
    $installed[$file.Name.ToLowerInvariant()] = Join-Path $convertedDirectory $relativePath
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
Copy-Item -LiteralPath $stagingRuntimeLog -Destination "$stagingRuntimeLog.backup-before-windows11-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
[IO.File]::WriteAllText($stagingRuntimeLog, $logText, $encoding)

if (Test-Path -LiteralPath $stagingRuntimeIni) {
    $ini = [IO.File]::ReadAllText($stagingRuntimeIni, $encoding)
    if ($ini -notmatch '(?im)^\[Ereg\]') {
        $ini = $ini.TrimEnd() + "`r`n`r`n[Ereg]`r`nMaxLaunch=0`r`nLaunchCount=0`r`n"
    } else {
        $ini = [regex]::Replace($ini, '(?im)^MaxLaunch=.*$', 'MaxLaunch=0')
    }
    [IO.File]::WriteAllText($stagingRuntimeIni, $ini, $encoding)
}

foreach ($file in $scriptFiles) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $stagingWorkspaceDirectory -Force
}
Set-Content -LiteralPath (Join-Path $stagingWorkspaceDirectory 'ArchiveRoot.txt') -Value $onlineDirectory -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $repoRoot 'src\Atlas-WonderLink-Archive.c') -Destination $stagingOnlineDirectory -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'src\Wlbrw32.def') -Destination $stagingOnlineDirectory -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'archive\Atlas-Online-Archive.html') -Destination $stagingOnlineDirectory -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'archive\Atlas-Online-Entry.html') -Destination $stagingOnlineDirectory -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Sync-AtlasLocalArchive.js') -Destination $stagingOnlineDirectory -Force

$toolReportForConfig = $toolReport | Select-Object *
$toolReportForConfig.ToolsDirectory = Join-Path $WorkspaceDirectory 'Tools'
$toolReportForConfig | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $toolReportPath -Encoding UTF8

$archiveRoot = Join-Path $onlineDirectory 'Mirror'
$stagingArchiveRoot = Join-Path $stagingOnlineDirectory 'Mirror'
$archiveNeedsPublish = $false
if (-not $SkipArchiveMirror) {
    $archiveValidationScript = Join-Path $stagingWorkspaceDirectory 'Validate-AtlasLocalArchive.ps1'
    $archiveReused = $false
    if (Test-Path -LiteralPath $archiveRoot) {
        Write-Host 'Checking the existing offline Online documentation mirror...'
        & $archiveValidationScript -MirrorRoot $archiveRoot
        $archiveReused = ($LASTEXITCODE -eq 0)
        if ($archiveReused) { Write-Host 'Existing archive mirror is complete; skipping its re-download.' }
    }
    if (-not $archiveReused) {
        $oldMirrorRoot = $env:ATLAS_ARCHIVE_MIRROR_ROOT
        $oldConcurrency = $env:ATLAS_ARCHIVE_CONCURRENCY
        try {
            $env:ATLAS_ARCHIVE_MIRROR_ROOT = $stagingArchiveRoot
            if (-not $oldConcurrency) { $env:ATLAS_ARCHIVE_CONCURRENCY = '20' }
            & $nodePath (Join-Path $stagingOnlineDirectory 'Sync-AtlasLocalArchive.js')
            if ($LASTEXITCODE) { throw "The Internet Archive mirror failed with exit code $LASTEXITCODE." }
        } finally {
            if ($null -eq $oldMirrorRoot) { Remove-Item Env:ATLAS_ARCHIVE_MIRROR_ROOT -ErrorAction SilentlyContinue }
            else { $env:ATLAS_ARCHIVE_MIRROR_ROOT = $oldMirrorRoot }
            if ($null -eq $oldConcurrency) { Remove-Item Env:ATLAS_ARCHIVE_CONCURRENCY -ErrorAction SilentlyContinue }
            else { $env:ATLAS_ARCHIVE_CONCURRENCY = $oldConcurrency }
        }
        & $archiveValidationScript -MirrorRoot $stagingArchiveRoot
        if ($LASTEXITCODE) { throw 'The downloaded Online Archive did not pass completeness validation.' }
        $archiveNeedsPublish = $true
    }
}

$mediaInventoryPath = Join-Path $stagingConvertedDirectory 'media-inventory.json'
$mediaInventory = Get-Content -LiteralPath $mediaInventoryPath -Raw | ConvertFrom-Json
$atlasHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stagingRuntimeExe).Hash
$originalShimHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stagingOriginalShim).Hash
if ($shimHash -ne $prebuiltShimHash) {
    throw 'The verified Windows 11 Online Archive component changed while the installation was being prepared.'
}
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
    Tools = $toolReportForConfig
}
$stagedConfigPath = Join-Path $stagingWorkspaceDirectory 'Atlas-Config.json'
$config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $stagedConfigPath -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $repoRoot 'README.md') -Destination (Join-Path $stagingWorkspaceDirectory 'README-Windows-11-fix.txt') -Force
foreach ($doc in (Get-ChildItem -LiteralPath (Join-Path $repoRoot 'docs') -File -Filter '*.md')) {
    Copy-Item -LiteralPath $doc.FullName -Destination (Join-Path $stagingWorkspaceDirectory $doc.Name) -Force
}

# The staged config is deliberately written before publication, then the live
# DLL is checked again after publication. Shortcuts are created only after
# both checks pass, so they never point at a half-installed runtime.
$stagedConfig = Get-Content -LiteralPath $stagedConfigPath -Raw | ConvertFrom-Json
if ($stagedConfig.ShimSha256 -ne $shimHash -or $shimHash -ne $prebuiltShimHash) {
    throw 'The staged Atlas configuration does not match the verified archive shim.'
}

New-Item -ItemType Directory -Path $WorkspaceDirectory, $onlineDirectory, (Join-Path $WorkspaceDirectory 'Tools') -Force | Out-Null
$runtimeBackupPath = Publish-StagedDirectory $stagingRuntimeDirectory $RuntimeDirectory
$runtimePublished = $true
$convertedBackupPath = Publish-StagedDirectory $stagingConvertedDirectory $convertedDirectory
$convertedPublished = $true
if ($archiveNeedsPublish) {
    $archiveBackupPath = Publish-StagedDirectory $stagingArchiveRoot $archiveRoot
    $archivePublished = $true
}

$stagedWorkspaceFiles = @(Get-ChildItem -LiteralPath $stagingWorkspaceDirectory -Recurse -File | Where-Object {
    $relativePath = $_.FullName.Substring($stagingWorkspaceDirectory.Length).TrimStart('\')
    $relativePath -ine 'Atlas-Config.json' -and
        $relativePath -notlike 'Converted Media\*' -and
        $relativePath -notlike 'Online Archive\*'
})
foreach ($file in $stagedWorkspaceFiles) {
    $relativePath = $file.FullName.Substring($stagingWorkspaceDirectory.Length).TrimStart('\')
    $destination = Join-Path $WorkspaceDirectory $relativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
}
$stagedOnlineFiles = @(Get-ChildItem -LiteralPath $stagingOnlineDirectory -Recurse -File | Where-Object {
    $relativePath = $_.FullName.Substring($stagingOnlineDirectory.Length).TrimStart('\')
    $relativePath -notlike 'Mirror\*'
})
foreach ($file in $stagedOnlineFiles) {
    $relativePath = $file.FullName.Substring($stagingOnlineDirectory.Length).TrimStart('\')
    $destination = Join-Path $onlineDirectory $relativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
}

$liveConfigPath = Join-Path $WorkspaceDirectory 'Atlas-Config.json'
$configHadExisting = Test-Path -LiteralPath $liveConfigPath
if ($configHadExisting) {
    $configBackupPath = "$liveConfigPath.install-backup-$transactionId"
    Copy-Item -LiteralPath $liveConfigPath -Destination $configBackupPath -Force
}
$configWriteStarted = $true
Copy-Item -LiteralPath $stagedConfigPath -Destination $liveConfigPath -Force
$liveShimHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeShim).Hash
if ($liveShimHash -ne $shimHash) {
    throw 'The published Windows 11 Online Archive component failed final verification.'
}
$publishedConfig = Get-Content -LiteralPath $liveConfigPath -Raw | ConvertFrom-Json
if ($publishedConfig.ShimSha256 -ne $liveShimHash) {
    throw 'The published Atlas configuration does not match the installed archive shim.'
}

$transactionCommitted = $true
foreach ($backupPath in @($runtimeBackupPath, $convertedBackupPath, $archiveBackupPath, $configBackupPath)) {
    if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
        Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
if ($stagingRoot -and (Test-Path -LiteralPath $stagingRoot)) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}
if (-not $SkipShortcutCreation) { & (Join-Path $WorkspaceDirectory 'Create-AtlasShortcuts.ps1') }

if ($transcriptStarted) { Stop-Transcript | Out-Null }

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
