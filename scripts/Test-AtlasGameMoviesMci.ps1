param(
    [string] $MovieDirectory = "$env:LOCALAPPDATA\Comptons 3D World Atlas Deluxe\Converted Media\GAME\MOVIES",
    [string] $OutputDirectory = "$env:LOCALAPPDATA\Comptons 3D World Atlas Deluxe\Test Results\Game MCI"
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;

public static class AtlasMciMovieTest
{
    const uint WS_POPUP = 0x80000000;
    const uint WS_CHILD = 0x40000000;
    const uint WS_VISIBLE = 0x10000000;
    const uint WS_EX_TOOLWINDOW = 0x00000080;
    const uint WS_EX_NOACTIVATE = 0x08000000;
    const uint MCIWNDF_NOPLAYBAR = 0x0002;
    const uint MCIWNDF_NOMENU = 0x0008;
    const uint MCIWNDF_NOERRORDLG = 0x4000;
    const uint WM_USER = 0x0400;
    const uint MCI_PLAY = 0x0806;
    const uint MCI_STOP = 0x0808;
    const uint MCI_SEEK = 0x0807;
    const uint MCIWNDM_GETLENGTH = WM_USER + 104;
    const uint MCIWNDM_SETVOLUME = WM_USER + 110;
    const uint MCIWNDM_CAN_PLAY = WM_USER + 144;
    const uint PM_REMOVE = 0x0001;

    [StructLayout(LayoutKind.Sequential)]
    struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public UIntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr GetModuleHandle(string name);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr CreateWindowEx(uint exStyle, string className, string windowName,
        uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu,
        IntPtr instance, IntPtr parameter);

    [DllImport("user32.dll")]
    static extern bool DestroyWindow(IntPtr window);

    [DllImport("user32.dll")]
    static extern bool ShowWindow(IntPtr window, int command);

    [DllImport("user32.dll")]
    static extern bool UpdateWindow(IntPtr window);

    [DllImport("user32.dll")]
    static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    static extern bool PeekMessage(out MSG message, IntPtr window, uint minimum, uint maximum, uint remove);

    [DllImport("user32.dll")]
    static extern bool TranslateMessage(ref MSG message);

    [DllImport("user32.dll")]
    static extern IntPtr DispatchMessage(ref MSG message);

    [DllImport("user32.dll")]
    static extern bool GetClientRect(IntPtr window, out RECT rectangle);

    [DllImport("user32.dll")]
    static extern bool PrintWindow(IntPtr window, IntPtr targetDc, uint flags);

    [DllImport("msvfw32.dll", CharSet = CharSet.Ansi)]
    static extern IntPtr MCIWndCreateA(IntPtr parent, IntPtr instance, uint style,
        [MarshalAs(UnmanagedType.LPStr)] string fileName);

    public sealed class Result
    {
        public string FileName { get; set; }
        public string Path { get; set; }
        public bool WindowCreated { get; set; }
        public bool CanPlay { get; set; }
        public long Length { get; set; }
        public long PositionAfter800ms { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public int UniqueSampledColors { get; set; }
        public bool CaptureSucceeded { get; set; }
        public bool Passed { get; set; }
        public string Error { get; set; }
    }

    static void Pump(int milliseconds)
    {
        var stopwatch = Stopwatch.StartNew();
        MSG message;
        while (stopwatch.ElapsedMilliseconds < milliseconds)
        {
            while (PeekMessage(out message, IntPtr.Zero, 0, 0, PM_REMOVE))
            {
                TranslateMessage(ref message);
                DispatchMessage(ref message);
            }
            Thread.Sleep(10);
        }
    }

    public static Result Test(string path)
    {
        var result = new Result { FileName = System.IO.Path.GetFileName(path), Path = path, Error = "" };
        IntPtr host = IntPtr.Zero;
        IntPtr movie = IntPtr.Zero;
        try
        {
            IntPtr instance = GetModuleHandle(null);
            host = CreateWindowEx(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, "STATIC", "Atlas MCI Test",
                WS_POPUP, -10000, -10000, 640, 480, IntPtr.Zero, IntPtr.Zero, instance, IntPtr.Zero);
            if (host == IntPtr.Zero) throw new InvalidOperationException("Could not create the hidden MCI host window.");
            ShowWindow(host, 4);
            UpdateWindow(host);

            movie = MCIWndCreateA(host, instance,
                WS_CHILD | WS_VISIBLE | MCIWNDF_NOPLAYBAR | MCIWNDF_NOMENU | MCIWNDF_NOERRORDLG,
                path);
            result.WindowCreated = movie != IntPtr.Zero;
            if (movie == IntPtr.Zero) throw new InvalidOperationException("MCIWndCreateA returned NULL.");
            Pump(200);

            result.CanPlay = SendMessage(movie, MCIWNDM_CAN_PLAY, IntPtr.Zero, IntPtr.Zero) != IntPtr.Zero;
            result.Length = SendMessage(movie, MCIWNDM_GETLENGTH, IntPtr.Zero, IntPtr.Zero).ToInt64();
            SendMessage(movie, MCIWNDM_SETVOLUME, IntPtr.Zero, IntPtr.Zero); // mute this exhaustive test
            SendMessage(movie, MCI_SEEK, IntPtr.Zero, IntPtr.Zero);
            SendMessage(movie, MCI_PLAY, IntPtr.Zero, IntPtr.Zero);
            Pump(800);
            // ANSI MCIWnd uses WM_USER + 102 for position.
            result.PositionAfter800ms = SendMessage(movie, WM_USER + 102, IntPtr.Zero, IntPtr.Zero).ToInt64();

            RECT rectangle;
            GetClientRect(movie, out rectangle);
            result.Width = Math.Max(1, rectangle.Right - rectangle.Left);
            result.Height = Math.Max(1, rectangle.Bottom - rectangle.Top);
            using (var bitmap = new Bitmap(result.Width, result.Height))
            using (var graphics = Graphics.FromImage(bitmap))
            {
                IntPtr dc = graphics.GetHdc();
                try { result.CaptureSucceeded = PrintWindow(movie, dc, 2); }
                finally { graphics.ReleaseHdc(dc); }
                var colors = new HashSet<int>();
                for (int y = 0; y < bitmap.Height; y += Math.Max(1, bitmap.Height / 20))
                    for (int x = 0; x < bitmap.Width; x += Math.Max(1, bitmap.Width / 20))
                        colors.Add(bitmap.GetPixel(x, y).ToArgb());
                result.UniqueSampledColors = colors.Count;
            }

            SendMessage(movie, MCI_STOP, IntPtr.Zero, IntPtr.Zero);
            result.Passed = result.WindowCreated && result.CanPlay && result.Length > 0 &&
                result.PositionAfter800ms > 0;
        }
        catch (Exception exception)
        {
            result.Error = exception.GetType().Name + ": " + exception.Message;
            result.Passed = false;
        }
        finally
        {
            if (movie != IntPtr.Zero) DestroyWindow(movie);
            if (host != IntPtr.Zero) DestroyWindow(host);
        }
        return result;
    }
}
"@

$movies = Get-ChildItem -LiteralPath $MovieDirectory -File -Filter *.avi | Sort-Object Name
$results = foreach ($movie in $movies) {
    $native = [AtlasMciMovieTest]::Test($movie.FullName)
    [pscustomobject]@{
        FileName = $native.FileName
        WindowCreated = $native.WindowCreated
        CanPlay = $native.CanPlay
        Length = $native.Length
        PositionAfter800ms = $native.PositionAfter800ms
        Width = $native.Width
        Height = $native.Height
        CaptureSucceeded = $native.CaptureSucceeded
        UniqueSampledColors = $native.UniqueSampledColors
        Passed = $native.Passed
        Error = $native.Error
        Path = $native.Path
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$csv = Join-Path $OutputDirectory "game-mci-$stamp.csv"
$results | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
$summary = [pscustomobject]@{
    Movies = $results.Count
    Passed = @($results | Where-Object Passed).Count
    Failed = @($results | Where-Object { -not $_.Passed }).Count
    VisibleCaptures = @($results | Where-Object { $_.UniqueSampledColors -gt 8 }).Count
    Results = $csv
}
$results | Format-Table FileName, CanPlay, Length, PositionAfter800ms, UniqueSampledColors, Passed -AutoSize
$summary | Format-List
if ($summary.Failed -gt 0) { exit 1 }
