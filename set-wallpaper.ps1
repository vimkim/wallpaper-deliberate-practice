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

        public static Monitor[] GetMonitors() {
            // Read physical pixels even when monitors have different Windows scaling.
            IntPtr previousContext = IntPtr.Zero;
            try { previousContext = SetThreadDpiAwarenessContext(new IntPtr(-4)); }
            catch (EntryPointNotFoundException) { SetProcessDPIAware(); }
            var desktop = (IDesktopWallpaper)new DesktopWallpaperClass();
            try {
                var monitors = new List<Monitor>();
                uint count = desktop.GetMonitorDevicePathCount();
                for (uint i = 0; i < count; i++) {
                    string id = desktop.GetMonitorDevicePathAt(i);
                    var monitor = new Monitor { Index = i, Id = id };
                    // Never pass a blank ID to SetWallpaper: NULL targets ALL monitors.
                    if (!String.IsNullOrWhiteSpace(id)) {
                        Rect rect;
                        int result = desktop.GetMonitorRECT(id, out rect);
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
                return monitors.ToArray();
            } finally {
                Marshal.ReleaseComObject(desktop);
                if (previousContext != IntPtr.Zero) SetThreadDpiAwarenessContext(previousContext);
            }
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
