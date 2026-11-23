[CmdletBinding()]
param(
    [ValidateSet('dark', 'light')][string]$Theme = 'dark',
    [string]$Dir = $PSScriptRoot,
    [string]$ImageDirectory = (Join-Path $env:LOCALAPPDATA 'DeliberatePracticeWallpaper\desktop'),
    [switch]$List
)

$ErrorActionPreference = 'Stop'
if (-not ('DeliberatePractice.DesktopWallpaper' -as [type])) {
    Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace DeliberatePractice {
    [StructLayout(LayoutKind.Sequential)]
    internal struct Rect { public int Left, Top, Right, Bottom; }

    [ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IDesktopWallpaper {
        void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
        [return: MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
        [return: MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint monitorIndex);
        uint GetMonitorDevicePathCount();
        [PreserveSig] int GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID, out Rect rect);
        void SetBackgroundColor(uint color);
        uint GetBackgroundColor();
        void SetPosition(int position);
        int GetPosition();
    }

    [ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")]
    internal class DesktopWallpaperClass { }

    public sealed class Monitor {
        public uint Index;
        public string Id, Current;
        public int Width, Height;
        public bool Connected;
    }

    public static class DesktopWallpaper {
        [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
        [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct MonitorInfo {
            public int Size;
            public Rect Bounds, WorkArea;
            public uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DisplayDevice {
            public int Size;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Name;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
            public uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Id;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Key;
        }

        private delegate bool MonitorEnumProc(IntPtr monitor, IntPtr dc, ref Rect rect, IntPtr data);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorEnumProc callback, IntPtr data);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern bool EnumDisplayDevices(string name, uint index, ref DisplayDevice device, uint flags);

        private static Monitor[] ReadActiveMonitors() {
            var monitors = new List<Monitor>();
            int error = 0;
            bool completed = EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero,
                delegate(IntPtr handle, IntPtr dc, ref Rect rect, IntPtr data) {
                    var info = new MonitorInfo();
                    info.Size = Marshal.SizeOf(info);
                    if (!GetMonitorInfo(handle, ref info)) {
                        error = Marshal.GetLastWin32Error();
                        return false;
                    }
                    for (uint i = 0; ; i++) {
                        var device = new DisplayDevice();
                        device.Size = Marshal.SizeOf(device);
                        // EDD_GET_DEVICE_INTERFACE_NAME returns the full monitor ID,
                        // including the port identity for otherwise identical models.
                        if (!EnumDisplayDevices(info.DeviceName, i, ref device, 1)) break;
                        if ((device.Flags & 1) == 0 || (device.Flags & 8) != 0 ||
                            String.IsNullOrWhiteSpace(device.Id)) continue;
                        monitors.Add(new Monitor {
                            Id = device.Id, Connected = true,
                            Width = info.Bounds.Right - info.Bounds.Left,
                            Height = info.Bounds.Bottom - info.Bounds.Top
                        });
                    }
                    return true;
                }, IntPtr.Zero);
            if (!completed) throw new System.ComponentModel.Win32Exception(
                error != 0 ? error : Marshal.GetLastWin32Error());
            return monitors.ToArray();
        }

        public static Monitor[] GetMonitors() {
            // Read physical pixels even when monitors have different Windows scaling.
            IntPtr previousContext = IntPtr.Zero;
            try { previousContext = SetThreadDpiAwarenessContext(new IntPtr(-4)); }
            catch (EntryPointNotFoundException) { SetProcessDPIAware(); }
            IDesktopWallpaper desktop = null;
            try {
                desktop = (IDesktopWallpaper)new DesktopWallpaperClass();
                return ReadMonitors(desktop, ReadActiveMonitors());
            } finally {
                if (desktop != null) Marshal.ReleaseComObject(desktop);
                if (previousContext != IntPtr.Zero) SetThreadDpiAwarenessContext(previousContext);
            }
        }

        internal static Monitor[] ReadMonitors(IDesktopWallpaper desktop, Monitor[] activeMonitors) {
            var monitors = new List<Monitor>();
            var activeById = new Dictionary<string, Monitor>(StringComparer.OrdinalIgnoreCase);
            foreach (Monitor active in activeMonitors) {
                if (active.Connected && !String.IsNullOrWhiteSpace(active.Id) &&
                    active.Width > 0 && active.Height > 0 && !activeById.ContainsKey(active.Id))
                    activeById.Add(active.Id, active);
            }
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            uint count = desktop.GetMonitorDevicePathCount();
            for (uint i = 0; i < count; i++) {
                string id = desktop.GetMonitorDevicePathAt(i);
                var monitor = new Monitor { Index = i, Id = id };
                // Never pass a blank ID to SetWallpaper: NULL targets ALL monitors.
                if (!String.IsNullOrWhiteSpace(id) && seen.Add(id)) {
                    Monitor active;
                    if (activeById.TryGetValue(id, out active)) {
                        monitor.Connected = true;
                        monitor.Width = active.Width;
                        monitor.Height = active.Height;
                        monitor.Current = desktop.GetWallpaper(id);
                        monitors.Add(monitor);
                        continue;
                    }
                    Rect rect;
                    int result = desktop.GetMonitorRECT(id, out rect);
                    // Windows also returns E_FAIL for stale device paths after docking
                    // or reconnecting a display, rather than the documented S_FALSE.
                    // Do not let those saved entries abort discovery of active screens.
                    if (result == unchecked((int)0x80004005)) {
                        monitors.Add(monitor);
                        continue;
                    }
                    if (result < 0) Marshal.ThrowExceptionForHR(result);
                    monitor.Connected = result == 0 && rect.Right > rect.Left && rect.Bottom > rect.Top;
                    if (monitor.Connected) {
                        monitor.Width = rect.Right - rect.Left;
                        monitor.Height = rect.Bottom - rect.Top;
                    }
                    monitor.Current = desktop.GetWallpaper(id);
                }
                monitors.Add(monitor);
            }
            // The wallpaper API can return a blank ID for an active monitor, and
            // GetMonitorRECT may reject its real ID. Use the active desktop's
            // physical rectangle and explicit device ID instead of guessing which
            // saved/blank entry belongs to it. Keep existing indices intact.
            foreach (Monitor active in activeMonitors) {
                if (!String.IsNullOrWhiteSpace(active.Id) && activeById.ContainsKey(active.Id) && seen.Add(active.Id)) {
                    Monitor recovered = activeById[active.Id];
                    monitors.Add(new Monitor {
                        Index = (uint)monitors.Count, Id = recovered.Id, Connected = true,
                        Width = recovered.Width, Height = recovered.Height,
                        Current = desktop.GetWallpaper(recovered.Id)
                    });
                }
            }
            return monitors.ToArray();
        }

        public static void Set(string id, string path) {
            if (String.IsNullOrWhiteSpace(id)) throw new ArgumentException("A specific monitor ID is required.", "id");
            var desktop = (IDesktopWallpaper)new DesktopWallpaperClass();
            try { desktop.SetWallpaper(id, path); }
            finally { Marshal.ReleaseComObject(desktop); }
        }

        public static void Fit() {
            var desktop = (IDesktopWallpaper)new DesktopWallpaperClass();
            try { desktop.SetPosition(3); } // DWPOS_FIT: preserve proportions without cropping.
            finally { Marshal.ReleaseComObject(desktop); }
        }

        public static int GetPosition() {
            var desktop = (IDesktopWallpaper)new DesktopWallpaperClass();
            try { return desktop.GetPosition(); }
            finally { Marshal.ReleaseComObject(desktop); }
        }
    }
}
'@
}

$monitors = @([DeliberatePractice.DesktopWallpaper]::GetMonitors())
if ($List) {
    foreach ($monitor in $monitors) {
        $size = if ($monitor.Connected) { "$($monitor.Width)x$($monitor.Height)" } else { '? (disconnected)' }
        $name = if ($monitor.Id) { ($monitor.Id -split '#')[1] } else { '(unknown)' }
        Write-Output "$($monitor.Index) $name $size $($monitor.Current)"
    }
    return
}

$connected = @($monitors | Where-Object { $_.Connected -and -not [string]::IsNullOrWhiteSpace($_.Id) })
if ($connected.Count -eq 0) { throw 'No connected monitors were found. No wallpapers were changed.' }
$Dir = [System.IO.Path]::GetFullPath($Dir)
$ImageDirectory = [System.IO.Path]::GetFullPath($ImageDirectory)
Add-Type -AssemblyName System.Drawing
$images = @{}

function Get-WallpaperHash([string]$Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
    finally { $stream.Dispose(); $hasher.Dispose() }
}

# Prepare every resolution before changing the desktop. Missing or incorrectly sized
# images are rendered from the source instead of substituting a landscape fallback.
foreach ($monitor in $connected) {
    $width = $monitor.Width
    $height = $monitor.Height
    $size = "${width}x${height}"
    if ($images.ContainsKey($size)) { continue }
    $sourceImage = Join-Path $Dir "deliberate-practice-$Theme-$size.png"
    $valid = $false
    if (Test-Path -LiteralPath $sourceImage -PathType Leaf) {
        $image = [System.Drawing.Image]::FromFile($sourceImage)
        try { $valid = $image.Width -eq $width -and $image.Height -eq $height }
        finally { $image.Dispose() }
    }
    if (-not $valid) {
        & (Join-Path $PSScriptRoot 'render-wallpaper.ps1') -Width $width -Height $height -Theme $Theme -OutputDirectory $Dir
    }
    $image = [System.Drawing.Image]::FromFile($sourceImage)
    try {
        if ($image.Width -ne $width -or $image.Height -ne $height) {
            throw "Wallpaper $sourceImage must be ${width}x${height}. No wallpapers were changed."
        }
    } finally { $image.Dispose() }

    # Windows must retain a path outside a temporary Git worktree. A content hash
    # also prevents Windows from reusing a stale cached image after a design edit.
    $hash = Get-WallpaperHash $sourceImage
    $installedImage = Join-Path $ImageDirectory "deliberate-practice-$Theme-$size-$hash.png"
    New-Item -ItemType Directory -Path $ImageDirectory -Force | Out-Null
    if (-not (Test-Path -LiteralPath $installedImage -PathType Leaf) -or
        (Get-WallpaperHash $installedImage) -ine $hash) {
        Copy-Item -LiteralPath $sourceImage -Destination $installedImage -Force
    }
    $images[$size] = $installedImage
}

foreach ($monitor in $connected) {
    $size = "$($monitor.Width)x$($monitor.Height)"
    [DeliberatePractice.DesktopWallpaper]::Set($monitor.Id, $images[$size])
}
[DeliberatePractice.DesktopWallpaper]::Fit()

# Read Windows' assignments back; do not report success on a silent failure.
$currentMonitors = @([DeliberatePractice.DesktopWallpaper]::GetMonitors())
foreach ($monitor in $connected) {
    $size = "$($monitor.Width)x$($monitor.Height)"
    $current = $currentMonitors | Where-Object { $_.Id -eq $monitor.Id -and $_.Connected }
    if (-not $current -or $current.Current -ine $images[$size]) {
        throw "Windows did not retain the requested wallpaper for monitor $($monitor.Index)."
    }
    Write-Output "monitor $($monitor.Index) $size -> $(Split-Path -Path $images[$size] -Leaf)"
}
if ([DeliberatePractice.DesktopWallpaper]::GetPosition() -ne 3) {
    throw 'Windows did not retain the Fit wallpaper position.'
}
