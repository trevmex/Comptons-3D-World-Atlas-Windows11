param(
    [Parameter(Mandatory = $true)] [int] $X,
    [Parameter(Mandatory = $true)] [int] $Y,
    [int] $WaitMilliseconds = 250,
    [switch] $LeavePointer
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class AtlasPointNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
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

$rectangle = $window.Current.BoundingRectangle
$oldPoint = New-Object AtlasPointNative+POINT
[void] [AtlasPointNative]::GetCursorPos([ref] $oldPoint)
[void] [AtlasPointNative]::SetForegroundWindow([IntPtr] $window.Current.NativeWindowHandle)
[void] [AtlasPointNative]::SetCursorPos([int] $rectangle.X + $X, [int] $rectangle.Y + $Y)
Start-Sleep -Milliseconds 150
[AtlasPointNative]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
[AtlasPointNative]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
if ($WaitMilliseconds -gt 0) { Start-Sleep -Milliseconds $WaitMilliseconds }
if (-not $LeavePointer) { [void] [AtlasPointNative]::SetCursorPos($oldPoint.X, $oldPoint.Y) }

$process.Refresh()
[pscustomobject]@{
    ProcessId = $process.Id
    ClientX = $X
    ClientY = $Y
    Responding = $process.Responding
    MainWindowTitle = $process.MainWindowTitle
}
