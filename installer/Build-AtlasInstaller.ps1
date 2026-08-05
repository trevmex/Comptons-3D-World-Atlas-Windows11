[CmdletBinding()]
param(
    [string] $OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'dist' }
$script = Join-Path $PSScriptRoot 'Comptons-3D-World-Atlas-Windows11.iss'

$isccCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
$isccPath = if ($isccCommand) { $isccCommand.Source } else { '' }
if (-not $isccPath) {
    $known = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if ($known) { $isccPath = $known }
}
if (-not $isccPath) {
    throw 'Inno Setup 6 (ISCC.exe) is required to build the Windows installer. Install JRSoftware.InnoSetup with winget.'
}
if (-not (Test-Path -LiteralPath $script)) { throw "Installer script is missing: $script" }
$shimPath = Join-Path $repoRoot 'build\Wlbrw32.dll'
if (-not (Test-Path -LiteralPath $shimPath)) {
    throw 'The published x86 archive shim is missing. Build or restore build\Wlbrw32.dll first.'
}
$shimHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $shimPath).Hash
$shimHash | ForEach-Object { "$_  Wlbrw32.dll" } |
    Set-Content -LiteralPath (Join-Path $repoRoot 'build\Wlbrw32.dll.sha256') -Encoding ASCII

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
& $isccPath /Qp "/O$OutputDirectory" $script
if ($LASTEXITCODE) { throw "Inno Setup failed with exit code $LASTEXITCODE." }

$setup = Get-ChildItem -LiteralPath $OutputDirectory -Filter '*-Setup.exe' -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $setup) { throw "Inno Setup did not produce an installer in $OutputDirectory." }
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $setup.FullName).Hash
$hashLine = "$hash  $($setup.Name)"
Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Value $hashLine -Encoding ASCII
[pscustomobject]@{
    Installer = $setup.FullName
    Bytes = $setup.Length
    SHA256 = $hash
    Checksums = (Join-Path $OutputDirectory 'SHA256SUMS.txt')
} | Format-List
