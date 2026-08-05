param(
    [int] $ProcessId = 0,
    [string] $OutputDirectory = "$env:LOCALAPPDATA\Comptons 3D World Atlas Deluxe\Test Results\Display"
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class AtlasDisplayNative
{
    [DllImport("user32.dll")] public static extern IntPtr GetMenu(IntPtr window);
    [DllImport("user32.dll")] public static extern uint GetMenuState(IntPtr menu, uint id, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
}
"@
if ($ProcessId -eq 0) { $process = Get-Process -Name atlas -ErrorAction Stop | Sort-Object StartTime -Descending | Select-Object -First 1 }
else { $process = Get-Process -Id $ProcessId -ErrorAction Stop }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $process.Id)
function Get-Windows { [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $condition) }
function Get-Main { Get-Windows | Where-Object { $_.Current.ClassName -eq 'WOBJClass' } | Select-Object -First 1 }
function Send-Command([int] $id, [string] $class = 'WOBJClass') {
    $window = Get-Windows | Where-Object { $_.Current.ClassName -eq $class } | Select-Object -First 1
    if (-not $window) { throw "Window class $class was not found." }
    $handle = [IntPtr] $window.Current.NativeWindowHandle
    [void] [AtlasDisplayNative]::SetForegroundWindow($handle)
    $result = [IntPtr]::Zero
    [void] [AtlasDisplayNative]::SendMessageTimeout($handle, 0x0111, [IntPtr] $id, [IntPtr]::Zero, 2, 15000, [ref] $result)
}
function Menu-State([int] $id) {
    $handle = [IntPtr] (Get-Main).Current.NativeWindowHandle
    [AtlasDisplayNative]::GetMenuState([AtlasDisplayNative]::GetMenu($handle), [uint32] $id, 0)
}
function Capture([string] $name) {
    $window = Get-Main; $rectangle = $window.Current.BoundingRectangle
    [void] [AtlasDisplayNative]::SetForegroundWindow([IntPtr] $window.Current.NativeWindowHandle)
    Start-Sleep -Milliseconds 150
    $bitmap = New-Object Drawing.Bitmap ([int] $rectangle.Width), ([int] $rectangle.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen([int] $rectangle.X, [int] $rectangle.Y, 0, 0, $bitmap.Size)
        $path = Join-Path $OutputDirectory ($name + '.png')
        $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Png)
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
}

Send-Command 2000
Start-Sleep -Seconds 4
$baselineHash = Capture 'baseline'
$tests = @(
    [pscustomobject]@{ Id=141; Name='Grid' },
    [pscustomobject]@{ Id=142; Name='Cities' },
    [pscustomobject]@{ Id=143; Name='Map Pins' },
    [pscustomobject]@{ Id=144; Name='Mountains' },
    [pscustomobject]@{ Id=145; Name='Ocean Depths' },
    [pscustomobject]@{ Id=229; Name='Rivers' },
    [pscustomobject]@{ Id=230; Name='Seas and Lakes' },
    [pscustomobject]@{ Id=146; Name='Volcanoes' }
)
$results = foreach ($test in $tests) {
    $before = Menu-State $test.Id
    Send-Command $test.Id
    Start-Sleep -Seconds 2
    $after = Menu-State $test.Id
    $hash = Capture ('{0}-{1}-on' -f $test.Id, ($test.Name -replace ' ', '_'))
    Send-Command $test.Id
    Start-Sleep -Seconds 1
    $restored = Menu-State $test.Id
    [pscustomobject]@{
        Id=$test.Id; Name=$test.Name; Before=('0x{0:X}' -f $before); After=('0x{0:X}' -f $after); Restored=('0x{0:X}' -f $restored)
        BecameChecked=[bool]($after -band 8); RestoredUnchecked=(-not [bool]($restored -band 8)); VisualChanged=($hash -ne $baselineHash)
        Responding=$process.Responding; Passed=([bool]($after -band 8) -and -not [bool]($restored -band 8) -and $hash -ne $baselineHash)
    }
}

$zoomBefore = Capture 'zoom-before'
Send-Command 135; Start-Sleep -Seconds 3
$zoomIn = Capture 'zoom-in'
$zoomOutState = Menu-State 136
Send-Command 136; Start-Sleep -Seconds 3
$zoomRestored = Capture 'zoom-restored'
$zoomResult = [pscustomobject]@{
    Id=135; Name='Zoom In and Zoom Out'; Before=''; After=('ZoomOutState=0x{0:X}' -f $zoomOutState); Restored=''; BecameChecked=$false; RestoredUnchecked=$true
    VisualChanged=($zoomIn -ne $zoomBefore); Responding=$process.Responding; Passed=($zoomIn -ne $zoomBefore -and -not [bool]($zoomOutState -band 3))
}

Send-Command 3400; Start-Sleep -Seconds 4
$fullscreen = Get-Windows | Where-Object { $_.Current.ClassName -eq 'pixeldouble' } | Select-Object -First 1
$fullscreenBounds = if ($fullscreen) { $fullscreen.Current.BoundingRectangle.ToString() } else { '' }
$fullscreenResult = [pscustomobject]@{
    Id=3400; Name='Superplay'; Before=''; After=$fullscreenBounds; Restored=''; BecameChecked=$false; RestoredUnchecked=$true
    VisualChanged=[bool]$fullscreen; Responding=$process.Responding; Passed=([bool]$fullscreen -and $fullscreen.Current.BoundingRectangle.Width -eq 3840 -and $fullscreen.Current.BoundingRectangle.Height -eq 2160)
}
if ($fullscreen) { Send-Command 3400 'pixeldouble'; Start-Sleep -Seconds 2 }

$all = @($results) + @($zoomResult, $fullscreenResult)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$csv = Join-Path $OutputDirectory "display-tests-$stamp.csv"
$all | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
$all
Write-Output "RESULT_CSV=$csv"
