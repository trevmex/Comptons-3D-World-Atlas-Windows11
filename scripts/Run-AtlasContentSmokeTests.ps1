param(
    [int] $ProcessId = 0,
    [string] $OutputDirectory = "$env:LOCALAPPDATA\Comptons 3D World Atlas Deluxe\Test Results\Content"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class AtlasContentTestNative
{
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessageTimeout(IntPtr window, uint message,
        IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr window);
}
"@

if ($ProcessId -eq 0) {
    $process = Get-Process -Name atlas -ErrorAction Stop |
        Sort-Object StartTime -Descending | Select-Object -First 1
} else {
    $process = Get-Process -Id $ProcessId -ErrorAction Stop
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$condition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
    $process.Id
)
function Get-AtlasWindows {
    [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        $condition
    )
}
function Get-MainWindow {
    Get-AtlasWindows | Where-Object { $_.Current.ClassName -eq 'WOBJClass' } |
        Select-Object -First 1
}
function Send-AtlasCommand([int] $commandId) {
    $window = Get-MainWindow
    if (-not $window) { throw 'The WOBJClass Atlas window is missing.' }
    $handle = [IntPtr] $window.Current.NativeWindowHandle
    [void] [AtlasContentTestNative]::SetForegroundWindow($handle)
    $result = [IntPtr]::Zero
    $sent = [AtlasContentTestNative]::SendMessageTimeout(
        $handle, 0x0111, [IntPtr] $commandId, [IntPtr]::Zero,
        0x0002, 15000, [ref] $result
    )
    return $sent.ToInt64()
}
function Save-AtlasCapture([string] $path) {
    $window = Get-MainWindow
    if (-not $window) { throw 'The WOBJClass Atlas window is missing.' }
    $handle = [IntPtr] $window.Current.NativeWindowHandle
    [void] [AtlasContentTestNative]::SetForegroundWindow($handle)
    Start-Sleep -Milliseconds 150
    $rectangle = $window.Current.BoundingRectangle
    $width = [int] $rectangle.Width
    $height = [int] $rectangle.Height
    $bitmap = New-Object Drawing.Bitmap $width, $height
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen([int] $rectangle.X, [int] $rectangle.Y, 0, 0, $bitmap.Size)
        $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Png)
        $colors = New-Object 'System.Collections.Generic.HashSet[int]'
        $sampleCount = 0
        $nearBlack = 0
        for ($y = 70; $y -lt $height; $y += 12) {
            for ($x = 0; $x -lt $width; $x += 12) {
                $color = $bitmap.GetPixel($x, $y)
                [void] $colors.Add($color.ToArgb())
                $sampleCount++
                if ($color.R -lt 12 -and $color.G -lt 12 -and $color.B -lt 12) { $nearBlack++ }
            }
        }
        return [pscustomobject]@{
            UniqueSampledColors = $colors.Count
            NearBlackFraction = if ($sampleCount) { [Math]::Round($nearBlack / $sampleCount, 4) } else { 1 }
        }
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$tests = @(
    # Three primary globe modes
    [pscustomobject]@{ Id = 2000; Name = 'Environmental Globe'; Wait = 5000 },
    [pscustomobject]@{ Id = 2001; Name = 'Physical Globe'; Wait = 5000 },
    [pscustomobject]@{ Id = 2002; Name = 'Political Globe'; Wait = 5000 },

    # Geological Forces
    [pscustomobject]@{ Id = 2102; Name = 'Geological Forces 2102'; Wait = 3500 },
    [pscustomobject]@{ Id = 2104; Name = 'Geological Forces 2104'; Wait = 3500 },
    [pscustomobject]@{ Id = 2302; Name = 'Geological Forces 2302'; Wait = 3500 },
    [pscustomobject]@{ Id = 2101; Name = 'Geological Forces 2101'; Wait = 3500 },
    [pscustomobject]@{ Id = 2105; Name = 'Geological Forces 2105'; Wait = 3500 },

    # Physical Features
    [pscustomobject]@{ Id = 2505; Name = 'Physical Features 2505'; Wait = 3500 },
    [pscustomobject]@{ Id = 2106; Name = 'Physical Features 2106'; Wait = 3500 },
    [pscustomobject]@{ Id = 2201; Name = 'Physical Features 2201'; Wait = 3500 },
    [pscustomobject]@{ Id = 2202; Name = 'Physical Features 2202'; Wait = 3500 },
    [pscustomobject]@{ Id = 2203; Name = 'Physical Features 2203'; Wait = 3500 },
    [pscustomobject]@{ Id = 2507; Name = 'Physical Features 2507'; Wait = 3500 },
    [pscustomobject]@{ Id = 2204; Name = 'Physical Features 2204'; Wait = 3500 },

    # Climatic Conditions
    [pscustomobject]@{ Id = 2506; Name = 'Climatic Conditions 2506'; Wait = 3500 },
    [pscustomobject]@{ Id = 2601; Name = 'Climatic Conditions 2601'; Wait = 3500 },
    [pscustomobject]@{ Id = 2604; Name = 'Climatic Conditions 2604'; Wait = 3500 },
    [pscustomobject]@{ Id = 2605; Name = 'Climatic Conditions 2605'; Wait = 3500 },
    [pscustomobject]@{ Id = 2602; Name = 'Climatic Conditions 2602'; Wait = 3500 },
    [pscustomobject]@{ Id = 2603; Name = 'Climatic Conditions 2603'; Wait = 3500 },
    [pscustomobject]@{ Id = 2606; Name = 'Climatic Conditions 2606'; Wait = 3500 },
    [pscustomobject]@{ Id = 2303; Name = 'Climatic Conditions 2303'; Wait = 3500 },
    [pscustomobject]@{ Id = 2503; Name = 'Climatic Conditions 2503'; Wait = 3500 },
    [pscustomobject]@{ Id = 2304; Name = 'Climatic Conditions 2304'; Wait = 3500 },

    # Human Impact
    [pscustomobject]@{ Id = 2501; Name = 'Human Impact 2501'; Wait = 3500 },
    [pscustomobject]@{ Id = 2502; Name = 'Human Impact 2502'; Wait = 3500 },
    [pscustomobject]@{ Id = 2504; Name = 'Human Impact 2504'; Wait = 3500 },
    [pscustomobject]@{ Id = 2103; Name = 'Human Impact 2103'; Wait = 3500 },
    [pscustomobject]@{ Id = 2508; Name = 'Human Impact 2508'; Wait = 3500 },
    [pscustomobject]@{ Id = 2301; Name = 'Human Impact 2301'; Wait = 3500 },

    # Satellite Photos
    [pscustomobject]@{ Id = 2401; Name = 'Satellite Photo 2401'; Wait = 3000 },
    [pscustomobject]@{ Id = 2402; Name = 'Satellite Photo 2402'; Wait = 3000 },
    [pscustomobject]@{ Id = 2403; Name = 'Satellite Photo 2403'; Wait = 3000 },
    [pscustomobject]@{ Id = 2404; Name = 'Satellite Photo 2404'; Wait = 3000 },
    [pscustomobject]@{ Id = 2405; Name = 'Satellite Photo 2405'; Wait = 3000 },
    [pscustomobject]@{ Id = 2406; Name = 'Satellite Photo 2406'; Wait = 3000 },

    # Indexes and data browsers. Around the World is tested separately because its intro is timed.
    [pscustomobject]@{ Id = 2005; Name = 'Multimedia Index'; Wait = 3500 },
    [pscustomobject]@{ Id = 3007; Name = 'Countries'; Wait = 3500 },
    [pscustomobject]@{ Id = 2003; Name = 'Statistics'; Wait = 3500 }
)

$results = New-Object System.Collections.Generic.List[object]
foreach ($test in $tests) {
    $process.Refresh()
    $cpuBefore = $process.TotalProcessorTime.TotalMilliseconds
    $sendResult = Send-AtlasCommand $test.Id
    Start-Sleep -Milliseconds $test.Wait
    $process.Refresh()
    $windows = Get-AtlasWindows
    $dialogs = @($windows | Where-Object { $_.Current.ClassName -eq '#32770' })
    $safeName = '{0:D4}-{1}' -f $test.Id, ($test.Name -replace '[^A-Za-z0-9.-]', '_')
    $capturePath = Join-Path $OutputDirectory ($safeName + '.png')
    $capture = Save-AtlasCapture $capturePath
    $hash = (Get-FileHash -LiteralPath $capturePath -Algorithm SHA256).Hash
    $badDialog = @($dialogs | Where-Object { $_.Current.Name -match '(?i)fatal|error|not found|insert.*CD' })
    $results.Add([pscustomobject]@{
        Id = $test.Id
        Name = $test.Name
        SendResult = $sendResult
        Responding = $process.Responding
        Dialogs = ($dialogs | ForEach-Object { $_.Current.Name }) -join '; '
        BadDialogCount = $badDialog.Count
        CpuMilliseconds = [Math]::Round($process.TotalProcessorTime.TotalMilliseconds - $cpuBefore)
        UniqueSampledColors = $capture.UniqueSampledColors
        NearBlackFraction = $capture.NearBlackFraction
        ScreenshotSHA256 = $hash
        Screenshot = $capturePath
        Passed = ($process.Responding -and $badDialog.Count -eq 0 -and $capture.UniqueSampledColors -gt 32)
    })
}

# Return to a known state.
[void] (Send-AtlasCommand 2000)
Start-Sleep -Seconds 3

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$csvPath = Join-Path $OutputDirectory "content-smoke-$timestamp.csv"
$results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
$summaryPath = Join-Path $OutputDirectory "content-smoke-$timestamp.txt"
@(
    "Atlas process: $($process.Id)"
    "Tests: $($results.Count)"
    "Passed: $(@($results | Where-Object Passed).Count)"
    "Failed: $(@($results | Where-Object { -not $_.Passed }).Count)"
    "CSV: $csvPath"
) | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$results
Write-Output "RESULT_CSV=$csvPath"
Write-Output "RESULT_SUMMARY=$summaryPath"
if (@($results | Where-Object { -not $_.Passed }).Count) { exit 1 }
