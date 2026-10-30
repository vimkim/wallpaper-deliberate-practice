param([ValidateSet("dark","light")][string]$Theme = "dark", [string]$Dir = $PSScriptRoot, [switch]$List)
Add-Type @"
using System; using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDesktopWallpaper {
  void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
  [return: MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
  [return: MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint monitorIndex);
  uint GetMonitorDevicePathCount();
  RECT GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
  void SetBackgroundColor(uint color); uint GetBackgroundColor();
  void SetPosition(int position); int GetPosition();
}
[ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")] public class DesktopWallpaperClass {}
public static class WP {
  static IDesktopWallpaper D() { return (IDesktopWallpaper)new DesktopWallpaperClass(); }
  public static string[] Monitors() { var d = D(); var n = d.GetMonitorDevicePathCount(); var a = new System.Collections.Generic.List<string>();
    for (uint i = 0; i < n; i++) { var id = d.GetMonitorDevicePathAt(i);
      try { var r = d.GetMonitorRECT(id); a.Add(id + "|" + (r.Right - r.Left) + "|" + (r.Bottom - r.Top)); }
      catch (COMException) { a.Add(id + "|0|0"); } }  // inactive/disconnected monitor
    return a.ToArray(); }
  public static void Set(string id, string f) { D().SetWallpaper(id, f); }
  public static string Get(string id) { return D().GetWallpaper(id); }
  public static void SetById(uint i, string f) { var d = D(); d.SetWallpaper(d.GetMonitorDevicePathAt(i), f); }
  public static void Fill() { D().SetPosition(4); }
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
"@
[WP]::SetProcessDPIAware() | Out-Null
# Remember each monitor's size while it is connected (Windows reports 0x0 for disconnected ones)
$mapFile = Join-Path $Dir "monitors.json"
$sizes = @{}
if (Test-Path $mapFile) { (Get-Content $mapFile -Raw | ConvertFrom-Json).PSObject.Properties | % { $sizes[$_.Name] = $_.Value } }
$mons = [WP]::Monitors() | % { $id, $w, $h = $_ -split '\|'; [pscustomobject]@{ Id = $id; W = $w; H = $h; Cur = [WP]::Get($id) } }
foreach ($m in $mons) { if ($m.W -ne '0') { $sizes[$m.Id] = "$($m.W)x$($m.H)" } }
if (-not $List) {
  $sizes | ConvertTo-Json | Set-Content $mapFile
  # System-wide default first, so a monitor that later appears under a new ID gets it too
  [WP]::Set($null, (Join-Path $Dir "deliberate-practice-$Theme-2560x1440.png"))
}
$i = 0
foreach ($m in $mons) {
  $size = if ($m.W -ne '0') { "$($m.W)x$($m.H)" } else { $sizes[$m.Id] }
  $state = if ($m.W -ne '0') { "" } else { " (disconnected)" }
  if ($List) { "$i $($m.Id.Split('#')[1]) $(if ($size) { $size } else { '?' })$state $($m.Cur)"; $i++; continue }
  if ($size -and (Test-Path (Join-Path $Dir "deliberate-practice-$Theme-$size.png"))) {
    $f = Join-Path $Dir "deliberate-practice-$Theme-$size.png"
  } elseif (-not $size -and $m.Cur -like "*deliberate-practice-*") {  # size unknown: keep its existing image
    $f = $m.Cur -replace '-(dark|light)-', "-$Theme-"
  } else { $f = Join-Path $Dir "deliberate-practice-$Theme-2560x1440.png" }
  [WP]::Set($m.Id, $f); "monitor $i $(if ($size) { $size } else { '?' })$state -> $(Split-Path $f -Leaf)"; $i++
}
if (-not $List) { [WP]::Fill() }
