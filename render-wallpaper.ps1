[CmdletBinding()]
param(
    [ValidateRange(1, 16384)][int]$Width = 2560,
    [ValidateRange(1, 16384)][int]$Height = 1600,
    [ValidateSet('dark', 'light', 'both')][string]$Theme = 'both',
    [string]$BrowserPath
)

$ErrorActionPreference = 'Stop'
$sourcePath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'wallpaper.html')).Path
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'fonts\Inter-latin.woff2') -PathType Leaf)) {
    throw 'The bundled Inter font is missing: fonts\Inter-latin.woff2'
}

if (-not $BrowserPath) {
    $browserCandidates = foreach ($applicationDirectory in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:LOCALAPPDATA)) {
        if ($applicationDirectory) {
            Join-Path $applicationDirectory 'Microsoft\Edge\Application\msedge.exe'
            Join-Path $applicationDirectory 'Google\Chrome\Application\chrome.exe'
        }
    }
    $BrowserPath = $browserCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $BrowserPath -or -not (Test-Path -LiteralPath $BrowserPath -PathType Leaf)) {
    throw 'Install Microsoft Edge or Google Chrome, or specify its executable with -BrowserPath.'
}
$BrowserPath = (Resolve-Path -LiteralPath $BrowserPath).Path

Add-Type -AssemblyName System.Drawing
$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$renderDirectory = Join-Path $temporaryRoot ('wallpaper-render-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $renderDirectory | Out-Null
$themes = if ($Theme -eq 'both') { @('dark', 'light') } else { @($Theme.ToLowerInvariant()) }

try {
    foreach ($variant in $themes) {
        $temporaryImage = Join-Path $renderDirectory "$variant.png"
        $errorLog = Join-Path $renderDirectory 'browser-stderr.log'
        $sourceUrl = ([uri]$sourcePath).AbsoluteUri + "?theme=$variant"
        $browserArguments = @(
            '--headless', '--no-first-run', '--no-default-browser-check',
            '--force-device-scale-factor=1', '--hide-scrollbars',
            '--allow-file-access-from-files', '--virtual-time-budget=2000', '--timeout=10000',
            "--window-size=$Width,$Height",
            ('--user-data-dir="{0}"' -f (Join-Path $renderDirectory 'profile')),
            ('--screenshot="{0}"' -f $temporaryImage),
            $sourceUrl
        )
        $browserProcess = Start-Process -FilePath $BrowserPath -ArgumentList $browserArguments `
            -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput (Join-Path $renderDirectory 'browser-stdout.log') `
            -RedirectStandardError $errorLog
        # Retain the process handle so Windows PowerShell can read its exit code.
        $null = $browserProcess.Handle
        if (-not $browserProcess.WaitForExit(30000)) {
            Stop-Process -Id $browserProcess.Id -ErrorAction SilentlyContinue
            throw "Browser timed out rendering the $variant wallpaper."
        }
        if ($browserProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $temporaryImage -PathType Leaf)) {
            throw "Browser failed to render the $variant wallpaper: $(Get-Content -LiteralPath $errorLog -Tail 10 | Out-String)"
        }

        # Validate the actual PNG before replacing an existing wallpaper.
        $image = [System.Drawing.Image]::FromFile($temporaryImage)
        try {
            if ($image.Width -ne $Width -or $image.Height -ne $Height) {
                throw "Expected ${Width}x${Height}, but the browser rendered $($image.Width)x$($image.Height)."
            }
        } finally {
            $image.Dispose()
        }
        $outputPath = Join-Path $PSScriptRoot "deliberate-practice-$variant-${Width}x${Height}.png"
        Copy-Item -LiteralPath $temporaryImage -Destination $outputPath -Force
        Write-Output "Generated $(Split-Path -Path $outputPath -Leaf) (${Width}x${Height})"
    }
} finally {
    # Only remove the unique temporary directory created by this invocation.
    $cleanupPath = [System.IO.Path]::GetFullPath($renderDirectory)
    $expectedParent = $temporaryRoot.TrimEnd('\')
    if ([System.IO.Path]::GetDirectoryName($cleanupPath) -ne $expectedParent -or
        [System.IO.Path]::GetFileName($cleanupPath) -notmatch '^wallpaper-render-[0-9a-f]{32}$') {
        throw "Unexpected rendering cleanup path: $cleanupPath"
    }
    try {
        Remove-Item -LiteralPath $cleanupPath -Recurse -Force
    } catch {
        Write-Warning "Could not remove rendering temporary directory: $cleanupPath. $($_.Exception.Message)"
    }
}
