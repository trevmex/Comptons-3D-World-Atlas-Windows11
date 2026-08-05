param(
    [Parameter(Mandatory = $true)] [string] $Path,
    [switch] $BringToFront
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class AtlasCaptureNative
{
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
}
"@
$process = Get-Process -Name atlas -ErrorAction Stop |
    Sort-Object StartTime -Descending | Select-Object -First 1
$condition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
    $process.Id
)
$window = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
    [System.Windows.Automation.TreeScope]::Children,
    $condition
) | Where-Object { $_.Current.ClassName -eq 'WOBJClass' } | Select-Object -First 1
if (-not $window) { throw 'The Atlas main window was not found.' }
if ($BringToFront) {
    [void] [AtlasCaptureNative]::SetForegroundWindow([IntPtr] $window.Current.NativeWindowHandle)
    Start-Sleep -Milliseconds 150
}
$rectangle = $window.Current.BoundingRectangle
$bitmap = New-Object Drawing.Bitmap ([int] $rectangle.Width), ([int] $rectangle.Height)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
try {
    $graphics.CopyFromScreen([int] $rectangle.X, [int] $rectangle.Y, 0, 0, $bitmap.Size)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
} finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}
$item = Get-Item -LiteralPath $Path
[pscustomobject]@{
    ProcessId = $process.Id
    Path = $item.FullName
    Width = [int] $rectangle.Width
    Height = [int] $rectangle.Height
    Bytes = $item.Length
    SHA256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
}
