$ErrorActionPreference = 'Stop'

$base = $PSScriptRoot
$configPath = Join-Path $base 'Atlas-Config.json'
if (-not (Test-Path -LiteralPath $configPath)) { throw "Atlas-Config.json is missing from $base. Run the installer first." }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$launcher = $config.Launcher
$atlas = $config.AtlasExecutable
$folder = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Compton's Home Library\Compton's 3D World Atlas Deluxe"
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

if (-not (Test-Path -LiteralPath $launcher)) { throw "The Atlas launcher is missing: $launcher" }
if (-not (Test-Path -LiteralPath $atlas)) { throw "The Atlas executable is missing: $atlas" }
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$shell = New-Object -ComObject WScript.Shell

$shortcuts = @(
    [pscustomobject]@{
        Name = "Compton's 3D World Atlas Deluxe - Windows 11 Fullscreen.lnk"
        Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`" -Fullscreen"
        Description = "Launch Compton's 3D World Atlas Deluxe in Windows 11 Archive Mode and built-in Superplay fullscreen"
    },
    [pscustomobject]@{
        Name = "Compton's 3D World Atlas Deluxe - Windows 11 Windowed.lnk"
        Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`""
        Description = "Launch Compton's 3D World Atlas Deluxe in Windows 11 Archive Mode (windowed)"
    }
)

foreach ($item in $shortcuts) {
    $path = Join-Path $folder $item.Name
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = $item.Arguments
    $shortcut.WorkingDirectory = $base
    $shortcut.IconLocation = "$atlas,0"
    $shortcut.Description = $item.Description
    $shortcut.WindowStyle = 7
    $shortcut.Save()
}

$desktop = [Environment]::GetFolderPath('Desktop')
$desktopShortcutPath = Join-Path $desktop "Compton's 3D World Atlas Deluxe - Windows 11 Archive Mode.lnk"
$desktopShortcut = $shell.CreateShortcut($desktopShortcutPath)
$desktopShortcut.TargetPath = $powershell
$desktopShortcut.Arguments = $shortcuts[1].Arguments
$desktopShortcut.WorkingDirectory = $base
$desktopShortcut.IconLocation = "$atlas,0"
$desktopShortcut.Description = 'Launch Compton''s 3D World Atlas Deluxe with the Windows 11 local archive replacement'
$desktopShortcut.WindowStyle = 7
$desktopShortcut.Save()

Get-ChildItem -LiteralPath $folder -Filter '*Windows 11*.lnk' |
    Select-Object Name, FullName, Length, LastWriteTime |
    Format-Table -AutoSize
[pscustomobject]@{ Name = $desktopShortcutPath; Target = $powershell; Arguments = $desktopShortcut.Arguments } |
    Format-List
