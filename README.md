# Deliberate practice wallpaper

The design lives in `wallpaper.html`, with a bundled Inter font in `fonts/`.
Render it at the display's native resolution to keep the text sharp and avoid cropping.

## Generate wallpapers

Requires Windows and an installed Microsoft Edge or Google Chrome.

```powershell
just generate                   # Dark and light at 2560x1600 (16:10)
just generate 2880 1800          # Dark and light at another resolution
just generate 2560 1600 dark     # Dark only
```

The renderer creates `deliberate-practice-<theme>-<width>x<height>.png` beside
the source. It checks the PNG dimensions before replacing an existing image.
It uses the browser's [headless screenshot mode](https://developer.chrome.com/docs/automation-and-testing/headless-cli)
with a separate temporary profile; your normal browser profile is not used.

You can also invoke the renderer directly or specify a browser executable:

```powershell
.\render-wallpaper.ps1 -Width 2560 -Height 1600 -Theme both
.\render-wallpaper.ps1 -BrowserPath 'C:\Program Files\Google\Chrome\Application\chrome.exe'
```

## Apply wallpapers

```powershell
just install        # Apply dark to the desktop and lock screen
just light          # Apply light to the desktop and lock screen
just wallpaper      # Apply only the desktop wallpaper
just lock-screen    # Apply only the lock-screen image
just monitors       # List monitor resolutions and current wallpaper files
just                # Show all commands
```

Run `just install` after generating a new size. Displays without an exact-size
image use the existing fallback image.

Desktop wallpaper uses each monitor's resolution. The lock screen uses the primary
monitor's resolution and keeps a persistent image copy in
`%LOCALAPPDATA%\DeliberatePracticeWallpaper`. It uses the current account's
[Windows lock-screen API](https://learn.microsoft.com/en-us/uwp/api/windows.system.userprofile.lockscreen.setimagefileasync)
through Windows PowerShell; no administrator rights are needed.
