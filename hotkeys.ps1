# Morning TV Dashboard - keyboard shortcuts.
# Runs quietly in the background (the installer starts it at every sign-in) and listens for:
#   Ctrl+Alt+D  dashboard on       Ctrl+Alt+X  dashboard off
#   Ctrl+Alt+N  news briefing      Ctrl+Alt+S  stop the news
# Windows' own desktop-shortcut keys proved unreliable, so this registers the keys itself.
# The key handling is done entirely in C# so a key press can never crash the listener.
$Dir = $PSScriptRoot
$Log = Join-Path $Dir "hotkeys-log.txt"
if ((Test-Path $Log) -and (Get-Item $Log).Length -gt 100kb) { Remove-Item $Log -Force }

# only one copy at a time
$mutex = New-Object Threading.Mutex($false, "MorningDashboardHotkeys")
$got = $false
try { $got = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $got = $true }
if (-not $got) { exit 0 }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @"
using System;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class DashHotkeyListener : NativeWindow {
  [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
  string dir, log;
  string[] keys = {"", "D", "X", "N", "S"};
  string[] scripts = {"", "start.ps1", "stop.ps1", "news.ps1", "news-stop.ps1"};
  public DashHotkeyListener(string d) { dir = d; log = Path.Combine(d, "hotkeys-log.txt"); CreateHandle(new CreateParams()); }
  public void Log(string m) { try { File.AppendAllText(log, DateTime.Now.ToString("s") + "  " + m + "\r\n"); } catch {} }
  public void RegisterAll() {
    for (int i = 1; i <= 4; i++) {
      bool ok = RegisterHotKey(Handle, i, 0x4003, (uint)keys[i][0]);   // Ctrl+Alt, no auto-repeat
      Log("Ctrl+Alt+" + keys[i] + ": " + (ok ? "ready" : "NOT available - another program is using it"));
    }
  }
  protected override void WndProc(ref Message m) {
    if (m.Msg == 0x0312) {   // WM_HOTKEY
      int id = m.WParam.ToInt32();
      if (id >= 1 && id <= 4) {
        try {
          Log("Ctrl+Alt+" + keys[id] + " pressed -> " + scripts[id]);
          var psi = new ProcessStartInfo("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + Path.Combine(dir, scripts[id]) + "\"");
          psi.UseShellExecute = false; psi.CreateNoWindow = true;
          Process.Start(psi);
        } catch (Exception e) { Log("launch failed: " + e.Message); }
      }
    }
    base.WndProc(ref m);
  }
}
"@
$hk = New-Object DashHotkeyListener($Dir)
$hk.RegisterAll()
$hk.Log("listening")
[System.Windows.Forms.Application]::Run()
