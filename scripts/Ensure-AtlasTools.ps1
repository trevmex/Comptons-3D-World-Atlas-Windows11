[CmdletBinding()]
param(
    [switch] $InstallMissing,
    [switch] $RequireNode,
    [string] $ToolsDirectory = (Join-Path $env:LOCALAPPDATA 'Comptons 3D World Atlas Deluxe\Tools'),
    [string] $OutputPath = ''
)

$ErrorActionPreference = 'Stop'

function Refresh-ProcessPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machine, $user, $env:Path) -join ';'
}

function Find-Executable([string] $Name) {
    Refresh-ProcessPath
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'),
        (Join-Path $env:LOCALAPPDATA 'Programs'),
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($root in $roots) {
        $candidate = Get-ChildItem -LiteralPath $root -Filter $Name -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }
    return $null
}

function Install-WingetPackage([string] $Id, [string] $Name) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "$Name is required, and winget.exe is not available. Install it or provide the executable on PATH, then rerun this installer."
    }
    Write-Host "Installing $Name with Windows Package Manager ($Id)..."
    & $winget.Source install --id $Id --exact --scope user --silent `
        --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE) { throw "winget could not install $Name (exit code $LASTEXITCODE)." }
    Refresh-ProcessPath
}

New-Item -ItemType Directory -Path $ToolsDirectory -Force | Out-Null
$ffmpeg = Find-Executable 'ffmpeg.exe'
$ffprobe = Find-Executable 'ffprobe.exe'
$node = Find-Executable 'node.exe'

if ($InstallMissing -and (-not $ffmpeg -or -not $ffprobe)) {
    # BtbN's LGPL build is sufficient for decoding the disc's Indeo files and
    # encoding Microsoft Video 1. It avoids installing a legacy system codec.
    Install-WingetPackage 'BtbN.FFmpeg.LGPL.8.1' 'the LGPL FFmpeg tools'
    $ffmpeg = Find-Executable 'ffmpeg.exe'
    $ffprobe = Find-Executable 'ffprobe.exe'
}
if ($RequireNode -and $InstallMissing -and -not $node) {
    Install-WingetPackage 'OpenJS.NodeJS.LTS' 'Node.js LTS'
    $node = Find-Executable 'node.exe'
}

$missing = @()
if (-not $ffmpeg) { $missing += 'ffmpeg.exe' }
if (-not $ffprobe) { $missing += 'ffprobe.exe' }
if ($RequireNode -and -not $node) { $missing += 'node.exe (18 or newer)' }
if ($missing.Count) {
    $action = if ($InstallMissing) { 'The automatic Windows 11 bootstrap did not find' } else { 'The installer did not find' }
    throw "$action $($missing -join ', '). Rerun with winget available or put the tools on PATH."
}

$nodeVersion = ''
if ($RequireNode) {
    $nodeVersion = (& $node --version 2>$null).Trim()
    if ($nodeVersion -notmatch '^v(1[89]|[2-9][0-9])\.') {
        throw "Node.js 18 or newer is required; found '$nodeVersion' at $node."
    }
}

$report = [pscustomobject]@{
    Node = $node
    NodeVersion = $nodeVersion
    FFmpeg = $ffmpeg
    FFprobe = $ffprobe
    ToolsDirectory = $ToolsDirectory
}
if ($OutputPath) {
    $report | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}
$report | ConvertTo-Json -Compress
