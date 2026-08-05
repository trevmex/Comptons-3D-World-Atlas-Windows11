param(
    [int] $ProcessId = 0,
    [string] $OutputPath = "$env:LOCALAPPDATA\Comptons 3D World Atlas Deluxe\Test Results\Online Archive\online-command-results.tsv"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class AtlasOnlineTestNative
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr window, uint message, IntPtr wParam, IntPtr lParam,
        uint flags, uint timeout, out IntPtr result
    );

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr window);
}
"@

if (-not $ProcessId) {
    $atlas = Get-Process -Name atlas -ErrorAction Stop |
        Where-Object { $_.Path -like "$env:LOCALAPPDATA\Programs\Comptons 3D World Atlas Deluxe\*" } |
        Sort-Object StartTime -Descending |
        Select-Object -First 1
} else {
    $atlas = Get-Process -Id $ProcessId -ErrorAction Stop
}
if (-not $atlas) { throw 'The user-local Atlas process was not found.' }

$processCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
    $atlas.Id
)
$atlasWindow = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
    [System.Windows.Automation.TreeScope]::Children,
    $processCondition
) | Where-Object { $_.Current.ClassName -eq 'WOBJClass' } | Select-Object -First 1
if (-not $atlasWindow) { throw 'The Atlas main window was not found.' }

function Get-EdgeAddress {
    foreach ($edge in Get-Process -Name msedge -ErrorAction SilentlyContinue |
             Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }) {
        try {
            $window = [System.Windows.Automation.AutomationElement]::FromHandle($edge.MainWindowHandle)
            $editCondition = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::Edit
            )
            $address = $window.FindAll(
                [System.Windows.Automation.TreeScope]::Descendants,
                $editCondition
            ) | Where-Object { $_.Current.Name -eq 'Address and search bar' } | Select-Object -First 1
            if ($address) {
                $value = $address.GetCurrentPattern(
                    [System.Windows.Automation.ValuePattern]::Pattern
                ).Current.Value
                if ($value) {
                    [pscustomobject]@{
                        Address = $value
                        Window = $window
                    }
                }
            }
        } catch {
            # Edge may recreate its accessibility tree while navigating.
        }
    }
}

$tests = @(
    [pscustomobject]@{
        CommandId = 261
        Name = 'Downloadable Extras'
        Expected = 'Mirror/3datlas/download/f_main_dl.html'
    },
    [pscustomobject]@{
        CommandId = 264
        Name = '3D World Atlas Home'
        Expected = 'Mirror/3datlas/index.html'
    },
    [pscustomobject]@{
        CommandId = 265
        Name = "Compton's Home"
        Expected = 'Mirror/comptons/index.html'
    },
    [pscustomobject]@{
        CommandId = 263
        Name = 'Entry-specific Context Links'
        Expected = 'Mirror/3datlas/entry-links-'
    }
)

$results = foreach ($test in $tests) {
    $messageResult = [IntPtr]::Zero
    [void] [AtlasOnlineTestNative]::SendMessageTimeout(
        [IntPtr] $atlasWindow.Current.NativeWindowHandle,
        0x0111,
        [IntPtr] $test.CommandId,
        [IntPtr]::Zero,
        0x0002,
        10000,
        [ref] $messageResult
    )

    $match = $null
    $deadline = (Get-Date).AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 300
        $expectedAddress = $test.Expected.Replace('\\', '/').ToLowerInvariant()
        $match = Get-EdgeAddress | Where-Object {
            $_.Address.Replace('\\', '/').ToLowerInvariant().Contains($expectedAddress)
        } | Select-Object -First 1
    } while (-not $match -and (Get-Date) -lt $deadline)

    $passed = [bool] $match
    $openedAddress = if ($match) { $match.Address } else { '' }

    if ($match) {
        # Close only the tab whose address was just verified; preserve every
        # pre-existing browser tab and window.
        [void] [AtlasOnlineTestNative]::SetForegroundWindow(
            [IntPtr] $match.Window.Current.NativeWindowHandle
        )
        Start-Sleep -Milliseconds 200
        [Windows.Forms.SendKeys]::SendWait('^w')
        Start-Sleep -Milliseconds 600
    }

    [pscustomobject]@{
        CommandId = $test.CommandId
        Name = $test.Name
        Passed = $passed
        OpenedAddress = $openedAddress
    }
}

$directory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$results | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation |
    Set-Content -LiteralPath $OutputPath -Encoding UTF8
$results | Format-Table -AutoSize
if ($results.Passed -contains $false) { exit 1 }
