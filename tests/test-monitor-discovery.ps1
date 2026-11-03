# Compile the actual Windows API boundary with a fake COM implementation, so
# discovery failures can be reproduced without changing the real desktop.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'set-wallpaper.ps1'
$source = Get-Content -LiteralPath $installer -Raw
$typeDefinition = [regex]::Match($source, "(?s)Add-Type @'\r?\n(.*?)\r?\n'@").Groups[1].Value
if (-not $typeDefinition) { throw 'Could not find the desktop wallpaper API definition.' }
$fixture = @'
namespace DeliberatePractice {
    public static class MonitorDiscoveryTests {
        private sealed class FakeDesktop : IDesktopWallpaper {
            public string[] Ids;
            public readonly List<string> RectangleReads = new List<string>();
            public readonly List<string> WallpaperReads = new List<string>();
            public uint GetMonitorDevicePathCount() { return (uint)Ids.Length; }
            public string GetMonitorDevicePathAt(uint index) { return Ids[index]; }
            public int GetMonitorRECT(string id, out Rect rect) {
                RectangleReads.Add(id);
                rect = new Rect();
                if (id.StartsWith("stale")) return unchecked((int)0x80004005);
                if (id == "denied") return unchecked((int)0x80070005);
                if (id == "detached") return 1;
                if (id == "empty") return 0;
                if (id == "portrait") {
                    rect.Left = 5440; rect.Top = -479; rect.Right = 6880; rect.Bottom = 2081;
                } else {
                    rect.Right = 2880; rect.Bottom = 1800;
                }
                return 0;
            }
            public string GetWallpaper(string id) {
                if (id.StartsWith("stale")) throw new System.Exception("A stale monitor must not be queried again.");
                WallpaperReads.Add(id);
                return id + ".png";
            }
            public void SetWallpaper(string id, string path) { throw new System.Exception("Discovery must not change wallpaper."); }
            public void SetBackgroundColor(uint color) { throw new System.Exception("Discovery must not change color."); }
            public uint GetBackgroundColor() { throw new System.NotSupportedException(); }
            public void SetPosition(int position) { throw new System.Exception("Discovery must not change position."); }
            public int GetPosition() { throw new System.NotSupportedException(); }
        }

        private static void Assert(bool condition, string message) {
            if (!condition) throw new System.Exception("FAIL: " + message);
        }

        public static void Run() {
            // Keep active displays on both sides of the stale entries: discovery
            // must continue, preserve device identities, and retain physical sizes.
            var desktop = new FakeDesktop {
                Ids = new [] { "landscape", "stale-old-port", "portrait", "stale-dock", "detached", "", "empty" }
            };
            Monitor[] monitors = DesktopWallpaper.ReadMonitors(desktop);
            Assert(monitors.Length == 7, "Monitor indices must stay stable.");
            Assert(monitors[0].Connected && monitors[0].Width == 2880 && monitors[0].Height == 1800,
                "Landscape pixels must be retained.");
            Assert(monitors[2].Connected && monitors[2].Id == "portrait" && monitors[2].Index == 2 &&
                monitors[2].Width == 1440 && monitors[2].Height == 2560 && monitors[2].Current == "portrait.png",
                "A portrait display after a stale entry must still be discovered correctly.");
            foreach (int index in new [] { 1, 3, 4, 5, 6 }) {
                Assert(!monitors[index].Connected && monitors[index].Width == 0 && monitors[index].Height == 0,
                    "Stale, detached, blank, and empty displays must not become connected targets.");
            }
            Assert(!desktop.RectangleReads.Contains("") && !desktop.WallpaperReads.Contains(""),
                "A blank device ID must never be queried.");
            Assert(monitors[1].Current == null && monitors[3].Current == null,
                "Stale monitor wallpaper reads must be skipped.");
            Assert(monitors[4].Current == "detached.png", "Normal detached assignments must still be listed.");

            desktop = new FakeDesktop { Ids = new [] { "stale-only" } };
            monitors = DesktopWallpaper.ReadMonitors(desktop);
            Assert(monitors.Length == 1 && !monitors[0].Connected, "Only stale entries must not produce an active target.");

            desktop = new FakeDesktop { Ids = new [] { "denied" } };
            bool failed = false;
            try { DesktopWallpaper.ReadMonitors(desktop); }
            catch (System.UnauthorizedAccessException) { failed = true; }
            Assert(failed, "Other Windows failures must still propagate.");
        }
    }
}
'@
Add-Type -TypeDefinition ($typeDefinition + [Environment]::NewLine + $fixture)
[DeliberatePractice.MonitorDiscoveryTests]::Run()
Write-Output 'PASS: real monitor discovery handles stale E_FAIL IDs, portrait pixels, detached/blank entries, and other API failures'
