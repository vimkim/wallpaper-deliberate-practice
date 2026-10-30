# Use Windows PowerShell regardless of the terminal used to invoke just.
set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "$ErrorActionPreference = 'Stop';"]

# Show available commands.
@default:
    just --list

# Generate PNGs: just generate [width height theme] (defaults to 2560x1600, both themes).
@generate width="2560" height="1600" theme="both":
    & '.\render-wallpaper.ps1' -Width '{{ width }}' -Height '{{ height }}' -Theme '{{ theme }}'

# Apply the wallpaper: just install [dark|light] (defaults to dark).
@install theme="dark":
    & '.\set-wallpaper.ps1' -Theme '{{ theme }}'

# Apply the dark wallpaper.
dark: (install "dark")

# Apply the light wallpaper.
light: (install "light")

# List monitors and their current wallpapers.
@monitors:
    & '.\set-wallpaper.ps1' -List
