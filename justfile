# Use Windows PowerShell regardless of the terminal used to invoke just.
set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "$ErrorActionPreference = 'Stop';"]

# Show available commands.
@default:
    just --list

# Generate PNGs: just generate [width height theme] (defaults to 2560x1600, both themes).
@generate width="2560" height="1600" theme="both":
    & '.\render-wallpaper.ps1' -Width '{{ width }}' -Height '{{ height }}' -Theme '{{ theme }}'

# Apply desktop and lock screen: just install [dark|light] (defaults to dark).
install theme="dark": (wallpaper theme) (lock-screen theme)

# Apply only the desktop wallpaper, choosing each monitor's resolution.
@wallpaper theme="dark":
    & '.\set-wallpaper.ps1' -Theme '{{ theme }}'

# Apply only the lock screen, using the primary monitor's resolution.
@lock-screen theme="dark":
    & '.\set-lock-screen.ps1' -Theme '{{ theme }}'

# Apply the dark desktop and lock screen.
dark: (install "dark")

# Apply the light desktop and lock screen.
light: (install "light")

# List monitors and their current wallpapers.
@monitors:
    & '.\set-wallpaper.ps1' -List
