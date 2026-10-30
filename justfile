# Use Windows PowerShell regardless of the terminal used to invoke just.
set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "$ErrorActionPreference = 'Stop';"]

# Show available commands.
@default:
    just --list

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
