# Run in a fresh PowerShell process. This replaces only the Windows API boundary;
# image validation, rendering, installation, and read-back checks run unchanged.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
if ('DeliberatePractice.DesktopWallpaper' -as [type]) {
    throw 'Run this test in a fresh PowerShell process.'
}
# Exercise the real discovery code in its own process before mocking installation.
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-monitor-discovery.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Monitor discovery regression tests failed.' }
Add-Type @'
using System;
using System.Collections.Generic;
namespace DeliberatePractice {
    public sealed class Monitor {
        public uint Index;
        public string Id, Current;
        public int Width, Height;
        public bool Connected;
    }
    public static class DesktopWallpaper {
        public static Monitor[] Screens;
        public static List<string> Calls = new List<string>();
        public static bool IgnoreSet;
        public static int Position = 4;
        public static Monitor[] GetMonitors() { return Screens; }
        public static void Set(string id, string path) {
            Calls.Add(id);
            var monitor = Array.Find(Screens, m => m.Id == id);
            if (String.IsNullOrWhiteSpace(id) || monitor == null || !monitor.Connected)
                throw new Exception("Only connected, explicitly identified monitors may be changed.");
            if (!IgnoreSet) monitor.Current = path;
        }
        public static void Fit() { Position = 3; }
        public static int GetPosition() { return Position; }
    }
}
'@
Add-Type -AssemblyName System.Drawing
$projectDirectory = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $projectDirectory 'set-wallpaper.ps1'
$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testDirectory = Join-Path $temporaryRoot ('wallpaper-tests-' + [guid]::NewGuid().ToString('N'))
$cache = Join-Path $testDirectory 'installed images'
$sources = Join-Path $testDirectory 'source images'

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

function New-Monitor([uint32]$Index, [string]$Id, [int]$Width, [int]$Height, [bool]$Connected = $true) {
    $monitor = New-Object DeliberatePractice.Monitor
    $monitor.Index = $Index
    $monitor.Id = $Id
    $monitor.Width = $Width
    $monitor.Height = $Height
    $monitor.Connected = $Connected
    $monitor.Current = 'original.png'
    return $monitor
}

try {
    [DeliberatePractice.DesktopWallpaper]::Screens = @(
        (New-Monitor 0 'display#laptop' 2880 1800),
        (New-Monitor 1 'display#portrait' 1440 2560),
        (New-Monitor 2 'display#landscape' 2560 1440),
        (New-Monitor 3 'display#duplicate' 2560 1440),
        (New-Monitor 4 'display#disconnected' 0 0 $false),
        (New-Monitor 5 '' 0 0 $false)
    )
    & $installer -List -Dir $sources -ImageDirectory $cache | Out-Null
    Assert ([DeliberatePractice.DesktopWallpaper]::Calls.Count -eq 0) 'Listing must not set wallpaper.'
    Assert (-not (Test-Path -LiteralPath $testDirectory)) 'Listing must not write files.'
    Write-Output 'PASS: listing has no side effects, including blank/disconnected IDs'

    foreach ($theme in @('dark', 'light', 'light')) {
        [DeliberatePractice.DesktopWallpaper]::Calls.Clear()
        & $installer -Theme $theme -Dir $projectDirectory -ImageDirectory $cache | Out-Null
        Assert ([DeliberatePractice.DesktopWallpaper]::Calls.Count -eq 4) 'Every connected monitor must be set exactly once.'
        Assert ([DeliberatePractice.DesktopWallpaper]::Position -eq 3) 'Fit must be used.'
        foreach ($monitor in [DeliberatePractice.DesktopWallpaper]::Screens) {
            if (-not $monitor.Connected) {
                Assert ($monitor.Current -eq 'original.png') 'Disconnected monitors must remain unchanged.'
                continue
            }
            Assert ($monitor.Current.StartsWith($cache)) 'Installed files must outlive the repository.'
            $expectedImage = Join-Path $projectDirectory "deliberate-practice-$theme-$($monitor.Width)x$($monitor.Height).png"
            Assert ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($monitor.Current)) -ceq
                [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($expectedImage))) 'Installed bytes must match the requested theme and resolution.'
            $image = [System.Drawing.Image]::FromFile($monitor.Current)
            try {
                Assert ($image.Width -eq $monitor.Width -and $image.Height -eq $monitor.Height) 'Image dimensions must match each screen.'
            } finally { $image.Dispose() }
        }
    }
    Assert (@(Get-ChildItem -LiteralPath $cache -File).Count -eq 6) 'Duplicate resolutions and repeated runs must reuse cached images.'
    Write-Output 'PASS: both themes, three aspect ratios, duplicate resolutions, persistent copies, and repeat runs'

    # Real browser rendering: one missing landscape image and a portrait file
    # whose filename claims the right dimensions but whose contents are wrong.
    New-Item -ItemType Directory -Path $sources -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectDirectory 'deliberate-practice-dark-2560x1440.png') -Destination (Join-Path $sources 'deliberate-practice-dark-800x1280.png')
    [DeliberatePractice.DesktopWallpaper]::Screens = @(
        (New-Monitor 0 'display#new-landscape' 1280 800),
        (New-Monitor 1 'display#new-portrait' 800 1280)
    )
    [DeliberatePractice.DesktopWallpaper]::Calls.Clear()
    & $installer -Dir $sources -ImageDirectory $cache | Out-Null
    foreach ($monitor in [DeliberatePractice.DesktopWallpaper]::Screens) {
        $image = [System.Drawing.Image]::FromFile($monitor.Current)
        try { Assert ($image.Width -eq $monitor.Width -and $image.Height -eq $monitor.Height) 'Generated image must match the display.' }
        finally { $image.Dispose() }
    }
    Write-Output 'PASS: actual browser generates missing and incorrectly sized images in paths with spaces'

    [DeliberatePractice.DesktopWallpaper]::Screens = @(
        (New-Monitor 0 'display#valid' 1280 800),
        (New-Monitor 1 'display#unsupported' 20000 1000)
    )
    [DeliberatePractice.DesktopWallpaper]::Calls.Clear()
    $failed = $false
    try { & $installer -Dir $sources -ImageDirectory $cache | Out-Null }
    catch { $failed = $true }
    Assert $failed 'Unsupported rendering dimensions must fail.'
    Assert ([DeliberatePractice.DesktopWallpaper]::Calls.Count -eq 0) 'Preparation failures must not change any wallpaper.'
    Write-Output 'PASS: all images are prepared before any wallpaper is changed'

    [DeliberatePractice.DesktopWallpaper]::Screens = @((New-Monitor 0 'display#silent-failure' 1280 800))
    [DeliberatePractice.DesktopWallpaper]::IgnoreSet = $true
    $failed = $false
    try { & $installer -Dir $sources -ImageDirectory $cache | Out-Null }
    catch { $failed = $_.Exception.Message -like '*did not retain*' }
    Assert $failed 'A silent Windows assignment failure must be detected.'
    Write-Output 'PASS: assignment verification detects silent failures'

    [DeliberatePractice.DesktopWallpaper]::Screens = @((New-Monitor 0 '' 0 0 $false))
    [DeliberatePractice.DesktopWallpaper]::Calls.Clear()
    $failed = $false
    try { & $installer -Dir $sources -ImageDirectory $cache | Out-Null }
    catch { $failed = $_.Exception.Message -like '*No connected monitors*' }
    Assert $failed 'No connected monitors must produce a clear error.'
    Assert ([DeliberatePractice.DesktopWallpaper]::Calls.Count -eq 0) 'No monitors must not set a global wallpaper.'
    Write-Output 'PASS: no connected monitors fails without changing wallpaper'
} finally {
    $cleanupPath = [System.IO.Path]::GetFullPath($testDirectory)
    if ([System.IO.Path]::GetDirectoryName($cleanupPath) -ne $temporaryRoot.TrimEnd('\') -or
        [System.IO.Path]::GetFileName($cleanupPath) -notmatch '^wallpaper-tests-[0-9a-f]{32}$') {
        throw "Unexpected test cleanup path: $cleanupPath"
    }
    if (Test-Path -LiteralPath $cleanupPath) { Remove-Item -LiteralPath $cleanupPath -Recurse -Force }
}
