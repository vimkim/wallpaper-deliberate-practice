[CmdletBinding()]
param(
    [ValidateSet('dark', 'light')][string]$Theme = 'dark',
    [string]$ImagePath
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -eq 'Core' -or
    ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess)) {
    throw 'Run this script with 64-bit Windows PowerShell (powershell.exe), or use just lock-screen.'
}

if (-not $ImagePath) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type @'
using System.Runtime.InteropServices;
public static class LockScreenDisplay {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
    [LockScreenDisplay]::SetProcessDPIAware() | Out-Null
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $ImagePath = Join-Path $PSScriptRoot "deliberate-practice-$Theme-$($bounds.Width)x$($bounds.Height).png"
    if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
        $ImagePath = Join-Path $PSScriptRoot "deliberate-practice-$Theme-2560x1440.png"
    }
}
$ImagePath = (Resolve-Path -LiteralPath $ImagePath).Path

# Keep a persistent copy whose name changes when the rendered image changes.
$imageStream = [System.IO.File]::OpenRead($ImagePath)
$hasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $imageHash = [BitConverter]::ToString($hasher.ComputeHash($imageStream)).Replace('-', '').ToLowerInvariant()
} finally {
    $imageStream.Dispose()
    $hasher.Dispose()
}
$imageDirectory = Join-Path $env:LOCALAPPDATA 'DeliberatePracticeWallpaper'
New-Item -ItemType Directory -Path $imageDirectory -Force | Out-Null
$installedImage = Join-Path $imageDirectory "lock-screen-$imageHash.png"
if (-not (Test-Path -LiteralPath $installedImage -PathType Leaf)) {
    Copy-Item -LiteralPath $ImagePath -Destination $installedImage
}

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$storageFileType = [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime]
[Windows.System.UserProfile.LockScreen, Windows.System.UserProfile, ContentType=WindowsRuntime] | Out-Null
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and
    $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1

$fileOperation = [Windows.Storage.StorageFile]::GetFileFromPathAsync($installedImage)
$fileTask = $asTask.MakeGenericMethod($storageFileType).Invoke($null, @($fileOperation))
if (-not $fileTask.Wait(10000)) { throw 'Timed out opening the lock-screen image.' }
$file = $fileTask.GetAwaiter().GetResult()
$setOperation = [Windows.System.UserProfile.LockScreen]::SetImageFileAsync($file)
$actionAsTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and -not $_.IsGenericMethod -and
    $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction'
} | Select-Object -First 1
$setTask = $actionAsTask.Invoke($null, @($setOperation))
if (-not $setTask.Wait(10000)) { throw 'Timed out setting the lock-screen image.' }
$setTask.GetAwaiter().GetResult() | Out-Null
$currentImage = [Windows.System.UserProfile.LockScreen]::OriginalImageFile
if (-not $currentImage -or -not $currentImage.IsFile -or $currentImage.LocalPath -ine $installedImage) {
    throw 'Windows did not retain the requested lock-screen image.'
}
Write-Output "Lock screen -> $(Split-Path -Path $ImagePath -Leaf)"
