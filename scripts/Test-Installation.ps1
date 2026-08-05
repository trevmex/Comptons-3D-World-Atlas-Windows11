[CmdletBinding()]
param(
    [string] $WorkspaceDirectory = (Join-Path $env:LOCALAPPDATA 'Comptons 3D World Atlas Deluxe')
)

$ErrorActionPreference = 'Stop'
$validator = Join-Path $PSScriptRoot 'Validate-AtlasWindows11Setup.ps1'
& $validator -WorkspaceDirectory $WorkspaceDirectory
if ($LASTEXITCODE) { exit $LASTEXITCODE }
