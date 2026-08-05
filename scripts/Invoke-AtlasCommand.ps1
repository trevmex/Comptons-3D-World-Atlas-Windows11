param(
    [Parameter(Mandatory = $true)]
    [int] $CommandId,
    [string] $WindowClass = 'WOBJClass',
    [int] $WaitMilliseconds = 1000,
    [switch] $BringToFront
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class AtlasCommandNative
{
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessageTimeout(IntPtr window, uint message,
        IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr window);
}
"@

$process = Get-Process -Name atlas -ErrorAction Stop |
    Sort-Object StartTime -Descending |
    Select-Object -First 1
$condition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
    $process.Id
)
function Get-Windows {
    [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        $condition
    )
}

$window = Get-Windows |
    Where-Object { $_.Current.ClassName -eq $WindowClass } |
    Select-Object -First 1
if (-not $window) { throw "No Atlas window of class $WindowClass was found." }
$handle = [IntPtr] $window.Current.NativeWindowHandle
if ($BringToFront) { [void] [AtlasCommandNative]::SetForegroundWindow($handle) }
$messageResult = [IntPtr]::Zero
$sendResult = [AtlasCommandNative]::SendMessageTimeout(
    $handle, 0x0111, [IntPtr] $CommandId, [IntPtr]::Zero,
    0x0002, 15000, [ref] $messageResult
)
if ($WaitMilliseconds -gt 0) { Start-Sleep -Milliseconds $WaitMilliseconds }
$process.Refresh()
$windows = Get-Windows
$dialogs = @($windows | Where-Object { $_.Current.ClassName -eq '#32770' })
[pscustomobject]@{
    ProcessId = $process.Id
    CommandId = $CommandId
    SendResult = $sendResult.ToInt64()
    MessageResult = $messageResult.ToInt64()
    Responding = $process.Responding
    MainWindowTitle = $process.MainWindowTitle
    DialogCount = $dialogs.Count
    DialogNames = ($dialogs | ForEach-Object { $_.Current.Name }) -join '; '
    TopLevelClasses = ($windows | ForEach-Object { $_.Current.ClassName }) -join '; '
}
