$ErrorActionPreference = 'Stop'

$base = Join-Path $env:LOCALAPPDATA 'Comptons 3D World Atlas Deluxe'
$launcher = Join-Path $base 'Launch-ComptonsAtlas.ps1'
$atlas = Join-Path $env:LOCALAPPDATA 'Programs\Comptons 3D World Atlas Deluxe\atlas.exe'
$folder = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Compton's Home Library\Compton's 3D World Atlas Deluxe"
$powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

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

Get-ChildItem -LiteralPath $folder -Filter '*Windows 11*.lnk' |
    Select-Object Name, FullName, Length, LastWriteTime |
    Format-Table -AutoSize
