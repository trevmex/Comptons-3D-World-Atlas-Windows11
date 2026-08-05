param(
    [switch] $Fullscreen
)

$ErrorActionPreference = 'Stop'
# Read the generated per-user profile so a non-default install remains
# launchable. The physical disc path is deliberately part of that profile.
$workspaceDirectory = $PSScriptRoot
$configPath = Join-Path $workspaceDirectory 'Atlas-Config.json'
if (-not (Test-Path -LiteralPath $configPath)) { throw "Atlas-Config.json is missing from $workspaceDirectory. Run the installer first." }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$atlasDirectory = $config.RuntimeDirectory
$atlasExecutable = $config.AtlasExecutable
$atlasLog = $config.AtlasLog
$archiveShim = Join-Path $atlasDirectory 'Wlbrw32.dll'
$archiveShimHashFile = Join-Path $atlasDirectory 'Wlbrw32.dll.sha256'
$archiveShimSha256 = if ($config.ShimSha256) { $config.ShimSha256.ToUpperInvariant() } elseif (Test-Path -LiteralPath $archiveShimHashFile) {
    ((Get-Content -LiteralPath $archiveShimHashFile -Raw).Trim() -split '\s+')[0].ToUpperInvariant()
} else { '' }
$discExe = Join-Path $config.DiscDrive 'ATLAS.EXE'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class AtlasLauncherNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT point);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll")]
    public static extern IntPtr GetWindow(IntPtr window, uint command);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr window);

    [DllImport("user32.dll")]
    public static extern bool IsWindowEnabled(IntPtr window);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr window, StringBuilder className, int capacity);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(
        IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags
    );

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr window);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr window,
        uint message,
        IntPtr wParam,
        IntPtr lParam,
        uint flags,
        uint timeout,
        out IntPtr result
    );
}
"@

function Get-AtlasWindows {
    param([Diagnostics.Process] $Process)

    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
        $Process.Id
    )
    return [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        $condition
    )
}

function Find-AtlasWindow {
    param(
        [Diagnostics.Process] $Process,
        [string] $ClassName
    )

    return Get-AtlasWindows -Process $Process |
        Where-Object { $_.Current.ClassName -eq $ClassName } |
        Select-Object -First 1
}

function Repair-AtlasZOrder {
    param([Diagnostics.Process] $Process)

    if ($Process.HasExited) { return }
    $foreground = [AtlasLauncherNative]::GetForegroundWindow()
    if ($foreground -eq [IntPtr]::Zero) { return }

    [uint32] $foregroundProcessId = 0
    [void] [AtlasLauncherNative]::GetWindowThreadProcessId(
        $foreground,
        [ref] $foregroundProcessId
    )
    if ($foregroundProcessId -ne $Process.Id) { return }

    # Never interfere with either Atlas fullscreen implementation.
    if ((Find-AtlasWindow -Process $Process -ClassName 'pixeldouble') -or
        (Find-AtlasWindow -Process $Process -ClassName 'SJE_FULLSCREEN')) {
        return
    }

    $mainWindow = Find-AtlasWindow -Process $Process -ClassName 'WOBJClass'
    if (-not $mainWindow -or -not $mainWindow.Current.IsEnabled) { return }
    $mainHandle = [IntPtr] $mainWindow.Current.NativeWindowHandle

    # Some 1998 modal dialogs are created without a reliable owner and can
    # fall behind WOBJClass. Bring an enabled popup back above the main window
    # so Online Connection Needed and similar dialogs can always be dismissed.
    $popupHandle = [AtlasLauncherNative]::GetWindow($mainHandle, 6) # GW_ENABLEDPOPUP
    $popupClass = New-Object Text.StringBuilder 128
    if ($popupHandle -ne [IntPtr]::Zero) {
        [void] [AtlasLauncherNative]::GetClassName(
            $popupHandle,
            $popupClass,
            $popupClass.Capacity
        )
    }
    if ($popupHandle -ne [IntPtr]::Zero -and
        $popupHandle -ne $mainHandle -and
        $popupClass.ToString() -eq '#32770' -and
        [AtlasLauncherNative]::IsWindowVisible($popupHandle) -and
        [AtlasLauncherNative]::IsWindowEnabled($popupHandle)) {
        [void] [AtlasLauncherNative]::SetWindowPos(
            $popupHandle,
            [IntPtr]::Zero, # HWND_TOP
            0, 0, 0, 0,
            0x0013 # SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE
        )
        [void] [AtlasLauncherNative]::BringWindowToTop($popupHandle)
        [void] [AtlasLauncherNative]::SetForegroundWindow($popupHandle)
        return
    }

    $className = New-Object Text.StringBuilder 128
    [void] [AtlasLauncherNative]::GetClassName(
        $foreground,
        $className,
        $className.Capacity
    )
    if ($className.ToString() -ne 'BlackOutWnd') { return }

    [void] [AtlasLauncherNative]::SetWindowPos(
        $mainHandle,
        [IntPtr]::Zero, # HWND_TOP
        0, 0, 0, 0,
        0x0013 # SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE
    )
    [void] [AtlasLauncherNative]::BringWindowToTop($mainHandle)
    [void] [AtlasLauncherNative]::SetForegroundWindow($mainHandle)
}

function Enter-AtlasFullscreen {
    param([Diagnostics.Process] $Process)

    $fullscreenWindow = Find-AtlasWindow -Process $Process -ClassName 'pixeldouble'
    if (-not $fullscreenWindow) {
        $fullscreenWindow = Find-AtlasWindow -Process $Process -ClassName 'SJE_FULLSCREEN'
    }
    if ($fullscreenWindow) {
        [void] [AtlasLauncherNative]::SetForegroundWindow(
            [IntPtr] $fullscreenWindow.Current.NativeWindowHandle
        )
        return
    }

    $mainWindow = Find-AtlasWindow -Process $Process -ClassName 'WOBJClass'
    if (-not $mainWindow) { throw 'The Atlas main window was not found.' }

    $messageResult = [IntPtr]::Zero
    [void] [AtlasLauncherNative]::SendMessageTimeout(
        [IntPtr] $mainWindow.Current.NativeWindowHandle,
        0x0111, # WM_COMMAND
        [IntPtr] 3400, # Display -> Superplay
        [IntPtr]::Zero,
        0x0002, # SMTO_ABORTIFHUNG
        10000,
        [ref] $messageResult
    )

    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $fullscreenWindow = Find-AtlasWindow -Process $Process -ClassName 'pixeldouble'
        if (-not $fullscreenWindow) {
            $fullscreenWindow = Find-AtlasWindow -Process $Process -ClassName 'SJE_FULLSCREEN'
        }
    } while (-not $fullscreenWindow -and (Get-Date) -lt $deadline)

    if (-not $fullscreenWindow) { throw 'The Atlas did not enter Superplay mode.' }
    [void] [AtlasLauncherNative]::SetForegroundWindow(
        [IntPtr] $fullscreenWindow.Current.NativeWindowHandle
    )
}

if (-not (Test-Path -LiteralPath $atlasExecutable)) {
    [void] [Windows.Forms.MessageBox]::Show(
        "The installed Atlas was not found.`n`n$atlasExecutable",
        "Compton's 3D World Atlas Deluxe",
        'OK',
        'Error'
    )
    exit 1
}

$actualShimHash = if (Test-Path -LiteralPath $archiveShim) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $archiveShim).Hash
} else { '' }
if (-not $archiveShimSha256 -or $actualShimHash -ne $archiveShimSha256) {
    [void] [Windows.Forms.MessageBox]::Show(
        "The verified Windows 11 Online Archive component is missing or changed.`n`n$archiveShim",
        "Compton's 3D World Atlas Deluxe",
        'OK',
        'Error'
    )
    exit 4
}

if (-not (Test-Path -LiteralPath $discExe)) {
    [void] [Windows.Forms.MessageBox]::Show(
        "Please insert the Compton's 3D World Atlas Deluxe disc in drive $($config.DiscDrive) and try again.",
        "Compton's 3D World Atlas Deluxe",
        'OK',
        'Information'
    )
    exit 2
}

$atlasProcesses = @(Get-Process -Name atlas -ErrorAction SilentlyContinue)
$process = $atlasProcesses |
    Where-Object { $_.Path -ieq $atlasExecutable } |
    Sort-Object StartTime -Descending |
    Select-Object -First 1

if (-not $process -and $atlasProcesses.Count -gt 0) {
    [void] [Windows.Forms.MessageBox]::Show(
        'Another copy of Atlas is already running outside Windows 11 Archive Mode. Please close it, then use this shortcut again.',
        "Compton's 3D World Atlas Deluxe",
        'OK',
        'Information'
    )
    exit 3
}

if (-not $process) {
    # Defense in depth: if the archive shim were ever bypassed, the configured
    # base URL uses the reserved .invalid domain rather than the retired HTTP
    # service. Atlas may rewrite Atlas.log on exit, so enforce this at launch.
    $logText = [IO.File]::ReadAllText($atlasLog)
    if ($logText -notmatch '(?m)^URL=') {
        throw 'Atlas.log does not contain the expected Online URL setting.'
    }
    $safeLogText = [Text.RegularExpressions.Regex]::Replace(
        $logText,
        '(?m)^URL=.*$',
        'URL=https://archive-mode.invalid/atlas.cgi'
    )
    if ($safeLogText -cne $logText) {
        [IO.File]::WriteAllText(
            $atlasLog,
            $safeLogText,
            (New-Object Text.UTF8Encoding($false))
        )
    }

    $archiveRoot = $config.ArchiveDirectory
    if (-not $archiveRoot) { throw 'The generated Atlas configuration has no archive directory.' }
    $env:ATLAS_ARCHIVE_ROOT = $archiveRoot
    $process = Start-Process -FilePath $atlasExecutable -WorkingDirectory $atlasDirectory -PassThru

    # The 1998 splash exits on WM_SETCURSOR. If the pointer is parked on a
    # monitor left of the primary display, it never receives that message.
    $splashDeadline = (Get-Date).AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 250
        $process.Refresh()
    } while (-not $process.HasExited -and
             $process.MainWindowTitle -ne 'Startup window' -and
             (Get-Date) -lt $splashDeadline)

    if (-not $process.HasExited -and $process.MainWindowTitle -eq 'Startup window') {
        $point = New-Object AtlasLauncherNative+POINT
        [void] [AtlasLauncherNative]::GetCursorPos([ref] $point)
        $splash = Find-AtlasWindow -Process $process -ClassName 'startup'
        if ($splash) {
            $splashHandle = [IntPtr] $splash.Current.NativeWindowHandle
            [void] [AtlasLauncherNative]::SetForegroundWindow($splashHandle)
            [void] [AtlasLauncherNative]::SetCursorPos(100, 100)
            Start-Sleep -Milliseconds 250
            $messageResult = [IntPtr]::Zero
            [void] [AtlasLauncherNative]::SendMessageTimeout(
                $splashHandle,
                0x0020, # WM_SETCURSOR
                [IntPtr]::Zero,
                [IntPtr]::Zero,
                0x0002,
                1000,
                [ref] $messageResult
            )
            # The original splash exits on the first mouse input. Send one
            # synthetic click rather than leaving the launch dependent on
            # where the user's pointer happens to be parked.
            [AtlasLauncherNative]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
            [AtlasLauncherNative]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 250
        }
        [void] [AtlasLauncherNative]::SetCursorPos($point.X, $point.Y)
    }

    $mainDeadline = (Get-Date).AddSeconds(45)
    do {
        Start-Sleep -Milliseconds 500
        $process.Refresh()
        $mainWindow = Find-AtlasWindow -Process $process -ClassName 'WOBJClass'
    } while (-not $process.HasExited -and -not $mainWindow -and (Get-Date) -lt $mainDeadline)

    if ($process.HasExited -or -not $mainWindow) {
        throw 'The Atlas did not reach its main window.'
    }
}

if ($Fullscreen) {
    Enter-AtlasFullscreen -Process $process
} else {
    $mainWindow = Find-AtlasWindow -Process $process -ClassName 'WOBJClass'
    if ($mainWindow) {
        [void] [AtlasLauncherNative]::SetForegroundWindow(
            [IntPtr] $mainWindow.Current.NativeWindowHandle
        )
    }
}

# Keep one hidden, low-overhead watcher for the lifetime of the Atlas. The
# 1998 application occasionally leaves its own BlackOutWnd above the main
# window after a fullscreen movie. Repair that one state only when an Atlas
# window already owns the foreground; never take focus from another program.
$watchdogMutex = New-Object Threading.Mutex($false, 'Local\ComptonsAtlasZOrderWatchdog')
$ownsWatchdog = $false
try {
    $ownsWatchdog = $watchdogMutex.WaitOne(0)
    if ($ownsWatchdog) {
        while (-not $process.HasExited) {
            Repair-AtlasZOrder -Process $process
            Start-Sleep -Milliseconds 500
            $process.Refresh()
        }
    }
} finally {
    if ($ownsWatchdog) { [void] $watchdogMutex.ReleaseMutex() }
    $watchdogMutex.Dispose()
}
