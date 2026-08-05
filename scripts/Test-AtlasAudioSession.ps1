param(
    [int] $ProcessId,
    [int] $DurationMilliseconds = 3000,
    [int] $SampleIntervalMilliseconds = 50
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

public static class CoreAudioSessionTest
{
    enum EDataFlow { eRender, eCapture, eAll }
    enum ERole { eConsole, eMultimedia, eCommunications }

    [Flags]
    enum CLSCTX : uint
    {
        INPROC_SERVER = 0x1,
        INPROC_HANDLER = 0x2,
        LOCAL_SERVER = 0x4,
        REMOTE_SERVER = 0x10,
        ALL = INPROC_SERVER | INPROC_HANDLER | LOCAL_SERVER | REMOTE_SERVER
    }

    [ComImport]
    [Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumeratorComObject { }

    [ComImport]
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        int EnumAudioEndpoints(EDataFlow dataFlow, uint stateMask, out IntPtr devices);
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice endpoint);
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
        int RegisterEndpointNotificationCallback(IntPtr client);
        int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        int Activate(ref Guid iid, CLSCTX context, IntPtr activationParameters,
            [MarshalAs(UnmanagedType.IUnknown)] out object activatedInterface);
        int OpenPropertyStore(uint access, out IntPtr properties);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetState(out uint state);
    }

    [ComImport]
    [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2
    {
        int GetAudioSessionControl(IntPtr sessionGuid, uint streamFlags, out IntPtr sessionControl);
        int GetSimpleAudioVolume(IntPtr sessionGuid, uint streamFlags, out IntPtr audioVolume);
        int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnumerator);
        int RegisterSessionNotification(IntPtr sessionNotification);
        int UnregisterSessionNotification(IntPtr sessionNotification);
        int RegisterDuckNotification([MarshalAs(UnmanagedType.LPWStr)] string sessionId, IntPtr duckNotification);
        int UnregisterDuckNotification(IntPtr duckNotification);
    }

    [ComImport]
    [Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator
    {
        int GetCount(out int count);
        int GetSession(int index, out IAudioSessionControl sessionControl);
    }

    [ComImport]
    [Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl
    {
        int GetState(out int state);
        int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string displayName);
        int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string displayName, IntPtr eventContext);
        int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string iconPath);
        int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string iconPath, IntPtr eventContext);
        int GetGroupingParam(out Guid groupingId);
        int SetGroupingParam(ref Guid groupingId, IntPtr eventContext);
        int RegisterAudioSessionNotification(IntPtr client);
        int UnregisterAudioSessionNotification(IntPtr client);
    }

    [ComImport]
    [Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl2
    {
        int GetState(out int state);
        int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string displayName);
        int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string displayName, IntPtr eventContext);
        int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string iconPath);
        int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string iconPath, IntPtr eventContext);
        int GetGroupingParam(out Guid groupingId);
        int SetGroupingParam(ref Guid groupingId, IntPtr eventContext);
        int RegisterAudioSessionNotification(IntPtr client);
        int UnregisterAudioSessionNotification(IntPtr client);
        int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string sessionIdentifier);
        int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string sessionInstanceIdentifier);
        int GetProcessId(out uint processId);
        int IsSystemSoundsSession();
        int SetDuckingPreference([MarshalAs(UnmanagedType.Bool)] bool optOut);
    }

    [ComImport]
    [Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioMeterInformation
    {
        int GetPeakValue(out float peak);
        int GetMeteringChannelCount(out int channelCount);
        int GetChannelsPeakValues(int channelCount, [Out, MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 0)] float[] peaks);
        int QueryHardwareSupport(out uint hardwareSupportMask);
    }

    public sealed class Measurement
    {
        public int ProcessId { get; set; }
        public int SessionsFound { get; set; }
        public int Samples { get; set; }
        public float MaximumPeak { get; set; }
        public int NonZeroSamples { get; set; }
        public string[] DisplayNames { get; set; }
    }

    public static Measurement Measure(int targetProcessId, int durationMilliseconds, int intervalMilliseconds)
    {
        var names = new List<string>();
        var meters = new List<IAudioMeterInformation>();
        var controls = new List<object>();
        IMMDevice device = null;
        object managerObject = null;
        IAudioSessionEnumerator sessions = null;

        try
        {
            var deviceEnumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            Marshal.ThrowExceptionForHR(deviceEnumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eMultimedia, out device));
            Guid managerGuid = typeof(IAudioSessionManager2).GUID;
            Marshal.ThrowExceptionForHR(device.Activate(ref managerGuid, CLSCTX.ALL, IntPtr.Zero, out managerObject));
            var manager = (IAudioSessionManager2)managerObject;
            Marshal.ThrowExceptionForHR(manager.GetSessionEnumerator(out sessions));
            int count;
            Marshal.ThrowExceptionForHR(sessions.GetCount(out count));

            for (int index = 0; index < count; index++)
            {
                IAudioSessionControl control;
                if (sessions.GetSession(index, out control) < 0 || control == null) continue;
                var control2 = (IAudioSessionControl2)control;
                uint processId;
                if (control2.GetProcessId(out processId) < 0 || processId != (uint)targetProcessId)
                {
                    Marshal.FinalReleaseComObject(control);
                    continue;
                }

                string name;
                if (control2.GetDisplayName(out name) < 0 || String.IsNullOrWhiteSpace(name)) name = "(unnamed)";
                names.Add(name);
                meters.Add((IAudioMeterInformation)control);
                controls.Add(control);
            }

            int samples = Math.Max(1, durationMilliseconds / Math.Max(1, intervalMilliseconds));
            float maximum = 0f;
            int nonZero = 0;
            for (int sample = 0; sample < samples; sample++)
            {
                float samplePeak = 0f;
                foreach (var meter in meters)
                {
                    float peak;
                    if (meter.GetPeakValue(out peak) >= 0 && peak > samplePeak) samplePeak = peak;
                }
                if (samplePeak > maximum) maximum = samplePeak;
                if (samplePeak > 0.00001f) nonZero++;
                Thread.Sleep(Math.Max(1, intervalMilliseconds));
            }

            return new Measurement {
                ProcessId = targetProcessId,
                SessionsFound = meters.Count,
                Samples = samples,
                MaximumPeak = maximum,
                NonZeroSamples = nonZero,
                DisplayNames = names.ToArray()
            };
        }
        finally
        {
            foreach (var control in controls)
            {
                try { Marshal.FinalReleaseComObject(control); } catch { }
            }
            if (sessions != null) try { Marshal.FinalReleaseComObject(sessions); } catch { }
            if (managerObject != null) try { Marshal.FinalReleaseComObject(managerObject); } catch { }
            if (device != null) try { Marshal.FinalReleaseComObject(device); } catch { }
        }
    }
}
"@

$result = [CoreAudioSessionTest]::Measure($ProcessId, $DurationMilliseconds, $SampleIntervalMilliseconds)
[pscustomobject]@{
    ProcessId = $result.ProcessId
    SessionsFound = $result.SessionsFound
    Samples = $result.Samples
    NonZeroSamples = $result.NonZeroSamples
    MaximumPeak = [Math]::Round($result.MaximumPeak, 6)
    DisplayNames = ($result.DisplayNames -join '; ')
}
