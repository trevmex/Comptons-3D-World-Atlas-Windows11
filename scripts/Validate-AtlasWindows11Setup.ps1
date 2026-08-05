$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient

$errors = New-Object Collections.Generic.List[string]
function Test-Requirement {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { $script:errors.Add($Message) }
}

$base = Join-Path $env:LOCALAPPDATA 'Comptons 3D World Atlas Deluxe'
$runtime = Join-Path $env:LOCALAPPDATA 'Programs\Comptons 3D World Atlas Deluxe'
$atlasPath = Join-Path $runtime 'atlas.exe'
$shimPath = Join-Path $runtime 'Wlbrw32.dll'
$shimHashFile = Join-Path $runtime 'Wlbrw32.dll.sha256'
$originalShim = Join-Path $runtime 'Wlbrw32.dll.original-1998'
$installedDirectory = "C:\Program Files (x86)\Compton's Home Library\Compton's 3D World Atlas Deluxe"
$expectedAtlasHash = 'F2BC73684875E7E9333DAEDEE4628070698A1768D0EFFB12907EAE2BA9969A0C'
$expectedShimHash = if (Test-Path -LiteralPath $shimHashFile) {
    ((Get-Content -LiteralPath $shimHashFile -Raw).Trim() -split '\s+')[0].ToUpperInvariant()
} else {
    ''
}
$expectedOriginalShimHash = '84B83AEA33950FD462CE35090DEAD80B26AC699F3E67C1AE3695D14ACF681831'

$atlasProcesses = @(Get-Process -Name atlas -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -ieq $atlasPath })
Test-Requirement ($atlasProcesses.Count -eq 1) 'Expected exactly one user-local Atlas process.'
if ($atlasProcesses.Count -eq 1) {
    $atlas = $atlasProcesses[0]
    Test-Requirement $atlas.Responding 'Atlas is not responding.'

    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
        $atlas.Id
    )
    $windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        $condition
    )
    $fullscreen = $windows |
        Where-Object { $_.Current.ClassName -in @('pixeldouble', 'SJE_FULLSCREEN') } |
        Select-Object -First 1
    Test-Requirement ([bool] $fullscreen) 'Atlas is not in built-in fullscreen mode.'
    if ($fullscreen) {
        $rect = $fullscreen.Current.BoundingRectangle
        Test-Requirement ($rect.X -eq 0 -and $rect.Y -eq 0 -and $rect.Width -eq 3840 -and $rect.Height -eq 2160) `
            'Atlas fullscreen bounds are not 3840x2160 at 0,0.'
    }
}

Test-Requirement ((Get-FileHash -Algorithm SHA256 -LiteralPath $atlasPath).Hash -eq $expectedAtlasHash) `
    'The user-local Atlas executable hash changed.'
$actualShimHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $shimPath).Hash
Test-Requirement ($expectedShimHash -and $actualShimHash -eq $expectedShimHash) `
    'The Online Archive shim hash does not match its generated sidecar.'
Test-Requirement ((Get-FileHash -Algorithm SHA256 -LiteralPath $originalShim).Hash -eq $expectedOriginalShimHash) `
    'The original WonderLink backup hash changed.'
Test-Requirement ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $installedDirectory 'atlas.exe')).Hash -eq $expectedAtlasHash) `
    'The installed Atlas executable was modified.'
Test-Requirement ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $installedDirectory 'Wlbrw32.dll')).Hash -eq $expectedOriginalShimHash) `
    'The installed 1998 WonderLink DLL was modified.'

$atlasLog = Join-Path $runtime 'Atlas.log'
$logLines = Get-Content -LiteralPath $atlasLog
Test-Requirement ($logLines -contains 'URL=https://archive-mode.invalid/atlas.cgi') `
    'The inert Online fallback URL is not configured.'
Test-Requirement ($logLines -contains 'Volume=5') 'Atlas volume is not restored to 5.'
Test-Requirement ($logLines -contains 'Music=1') 'Atlas music is not enabled.'
Test-Requirement ($logLines -contains 'Narration=1') 'Atlas narration is not enabled.'
Test-Requirement ($logLines -contains "avi=$base\Converted Media\AVI") 'The converted AVI root is not active.'
Test-Requirement ($logLines -contains "game=$base\Converted Media") 'The converted game root is not active.'

$installedMappings = @()
$inInstalled = $false
foreach ($line in $logLines) {
    if ($line -eq '[Installed]') { $inInstalled = $true; continue }
    if ($inInstalled -and $line -match '^\[') { break }
    if ($inInstalled -and $line -match '=') { $installedMappings += $line }
}
$missingMappings = @($installedMappings | ForEach-Object {
    $mappedPath = ($_ -split '=', 2)[1]
    if (-not (Test-Path -LiteralPath $mappedPath)) { $_ }
})
Test-Requirement ($installedMappings.Count -eq 68) "Expected 68 installed mappings; found $($installedMappings.Count)."
Test-Requirement ($missingMappings.Count -eq 0) "Found $($missingMappings.Count) missing installed mappings."

$gameMovies = @(Get-ChildItem -LiteralPath (Join-Path $base 'Converted Media\GAME\MOVIES') -Filter '*.avi' -File)
Test-Requirement ($gameMovies.Count -eq 22) "Expected 22 local game movies; found $($gameMovies.Count)."

$onlineResultsPath = Join-Path $base 'Test Results\Online Archive\online-command-results.tsv'
$onlineResults = @(Import-Csv -LiteralPath $onlineResultsPath -Delimiter "`t")
Test-Requirement ($onlineResults.Count -eq 4) "Expected four Online command results; found $($onlineResults.Count)."
Test-Requirement (@($onlineResults | Where-Object { $_.Passed -ne 'True' }).Count -eq 0) `
    'At least one Online Archive command failed.'
$mirrorRoot = Join-Path $base 'Online Archive\Mirror'
$mirrorTargets = @(
    (Join-Path $mirrorRoot '3datlas\index.html'),
    (Join-Path $mirrorRoot '3datlas\download\f_main_dl.html'),
    (Join-Path $mirrorRoot '3datlas\sitemap.html'),
    (Join-Path $mirrorRoot 'comptons\index.html')
)
Test-Requirement (($mirrorTargets | Where-Object { -not (Test-Path -LiteralPath $_) }).Count -eq 0) `
    'One or more local archived Online targets are missing.'
Test-Requirement ((Get-ChildItem -LiteralPath $mirrorRoot -Recurse -File -ErrorAction SilentlyContinue).Count -ge 100) `
    'The local archived Online mirror is unexpectedly small.'

$shortcutRoot = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shortcuts = @(Get-ChildItem -LiteralPath $shortcutRoot -Recurse -Filter '*Windows 11*.lnk' |
    Where-Object { $_.Name -like "Compton's 3D World Atlas Deluxe*" })
Test-Requirement ($shortcuts.Count -eq 2) "Expected two Windows 11 shortcuts; found $($shortcuts.Count)."
if ($shortcuts.Count -eq 2) {
    $shell = New-Object -ComObject WScript.Shell
    foreach ($file in $shortcuts) {
        $shortcut = $shell.CreateShortcut($file.FullName)
        Test-Requirement ($shortcut.Arguments -like '*Launch-ComptonsAtlas.ps1*') `
            "Shortcut does not use the launcher: $($file.Name)"
        Test-Requirement ($shortcut.IconLocation -like "$atlasPath,*") `
            "Shortcut does not use the user-local Atlas icon: $($file.Name)"
    }
}

Test-Requirement (Test-Path -LiteralPath 'D:\ATLAS.EXE') 'The original disc is not mounted as D:.'
$disc = Get-Volume -DriveLetter D -ErrorAction SilentlyContinue
Test-Requirement ($disc.FileSystemLabel -eq '3DATLAS') "Drive D: label is not 3DATLAS."
Test-Requirement (-not (Test-Path 'Registry::HKEY_CURRENT_USER\Software\Classes\Software\CreativeWonders')) `
    'A legacy WonderLink browser-association override remains in the registry.'
Test-Requirement (-not (Get-Process -Name gdb -ErrorAction SilentlyContinue)) 'A GDB process is still attached or running.'
Test-Requirement (Test-Path -LiteralPath (Join-Path $base 'README-Windows-11-fix.txt')) `
    'Windows 11 documentation is missing.'

if ($errors.Count) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

[pscustomobject]@{
    Status = 'PASS'
    AtlasProcessId = if ($atlasProcesses.Count -eq 1) { $atlasProcesses[0].Id } else { 0 }
    Runtime = $runtime
    Fullscreen = '3840x2160'
    InstalledMappings = $installedMappings.Count
    MissingMappings = $missingMappings.Count
    GameMovies = $gameMovies.Count
    OnlineCommands = $onlineResults.Count
    LocalArchiveFiles = (Get-ChildItem -LiteralPath $mirrorRoot -Recurse -File).Count
    Shortcuts = $shortcuts.Count
    Disc = "$($disc.DriveLetter): $($disc.FileSystemLabel)"
    ArchiveShimSha256 = $actualShimHash
} | Format-List
