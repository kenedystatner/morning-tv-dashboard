# Remembers and restores where your open windows are, so switching the picture to the TV
# and back doesn't leave windows cut off or off-centre.
#   windows.ps1 save      -> remembers every open window's size and position
#   windows.ps1 restore   -> puts them back
param([string]$Action = "restore")
$File = Join-Path $PSScriptRoot "window-positions.json"

if (-not ("DashWin.W" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
namespace DashWin {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L; public int T; public int R; public int B; }
  [StructLayout(LayoutKind.Sequential)] public struct PLACEMENT {
    public int length; public int flags; public int showCmd; public POINT minPos; public POINT maxPos; public RECT normal; }
  public static class W {
    delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] static extern bool GetWindowPlacement(IntPtr h, ref PLACEMENT p);
    [DllImport("user32.dll")] static extern bool SetWindowPlacement(IntPtr h, ref PLACEMENT p);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    public static List<string> Save() {
      List<string> r = new List<string>();
      EnumWindows(delegate(IntPtr h, IntPtr p) {
        if (IsWindowVisible(h) && GetWindowTextLength(h) > 0) {
          PLACEMENT w = new PLACEMENT(); w.length = Marshal.SizeOf(w);
          if (GetWindowPlacement(h, ref w))
            r.Add(string.Join(",", new string[] { h.ToInt64().ToString(), w.showCmd.ToString(),
              w.normal.L.ToString(), w.normal.T.ToString(), w.normal.R.ToString(), w.normal.B.ToString() }));
        }
        return true; }, IntPtr.Zero);
      return r;
    }
    public static bool Restore(long handle, int showCmd, int l, int t, int r, int b) {
      IntPtr h = new IntPtr(handle); if (!IsWindow(h)) return false;
      PLACEMENT w = new PLACEMENT(); w.length = Marshal.SizeOf(w); GetWindowPlacement(h, ref w);
      w.normal.L = l; w.normal.T = t; w.normal.R = r; w.normal.B = b;
      w.showCmd = (showCmd == 2) ? 7 : (showCmd == 3 ? 3 : 4);   // keep minimised/maximised, don't steal focus
      return SetWindowPlacement(h, ref w);
    }
    public static void Maximize(IntPtr h) { ShowWindow(h, 3); }
  }
}
"@
}

if ($Action -eq "save") {
  # keep an existing recent save (e.g. the dashboard was started twice while already on the TV)
  if ((Test-Path $File) -and ((Get-Date) - (Get-Item $File).LastWriteTime).TotalHours -lt 12) { exit 0 }
  [DashWin.W]::Save() | Set-Content $File
} else {
  if (Test-Path $File) {
    foreach ($line in Get-Content $File) {
      $v = $line.Split(","); if ($v.Count -lt 6) { continue }
      [void][DashWin.W]::Restore([long]$v[0], [int]$v[1], [int]$v[2], [int]$v[3], [int]$v[4], [int]$v[5])
    }
    Remove-Item $File -Force
  }
}
