# Switches Windows' sound output.  Usage:
#   audio.ps1 names     -> prints the names of the playback devices (used by install.ps1)
#   audio.ps1 list      -> writes the playback devices to audio-log.txt
#   audio.ps1 tv        -> remembers the current output, then plays sound through the TV
#   audio.ps1 restore   -> goes back to the output that was in use before
param([string]$Action = "list")
. (Join-Path $PSScriptRoot "common.ps1")
$Log = Join-Path $Dir "audio-log.txt"
$Prev = Join-Path $Dir "audio-previous.txt"
# how the TV's sound device is recognised: "tv.soundDevice" in config.json (a regular expression)
$TvMatch = ""
try { $TvMatch = [string](Get-DashConfig).tv.soundDevice } catch {}

if (-not ("DashAudio.Audio" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace DashAudio {
  [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
  }
  [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceCollection { int GetCount(out int count); int Item(int index, out IMMDevice device); }
  [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDevice {
    int Activate(ref Guid iid, int clsCtx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
    int OpenPropertyStore(int access, out IPropertyStore store);
    int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
  }
  [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPropertyStore {
    int GetCount(out int c); int GetAt(int i, out PROPERTYKEY k);
    int GetValue(ref PROPERTYKEY k, out PROPVARIANT v);
  }
  [StructLayout(LayoutKind.Sequential)] struct PROPERTYKEY { public Guid fmtid; public int pid; }
  [StructLayout(LayoutKind.Explicit)] struct PROPVARIANT { [FieldOffset(0)] public short vt; [FieldOffset(8)] public IntPtr p; [FieldOffset(16)] public IntPtr pad; }
  [ComImport, Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPolicyConfig {
    int GetMixFormat(); int GetDeviceFormat(); int ResetDeviceFormat(); int SetDeviceFormat();
    int GetProcessingPeriod(); int SetProcessingPeriod(); int GetShareMode(); int SetShareMode();
    int GetPropertyValue(); int SetPropertyValue();
    int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id, int role);
  }
  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCo {}
  [ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")] class PolicyConfigClient {}
  public static class Audio {
    static string Name(IMMDevice d) {
      IPropertyStore s; d.OpenPropertyStore(0, out s);
      PROPERTYKEY k = new PROPERTYKEY(); k.fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"); k.pid = 14;
      PROPVARIANT v; s.GetValue(ref k, out v);
      return Marshal.PtrToStringUni(v.p);
    }
    public static string DefaultId() {
      IMMDeviceEnumerator e = (IMMDeviceEnumerator)new MMDeviceEnumeratorCo(); IMMDevice d;
      e.GetDefaultAudioEndpoint(0, 1, out d); string id; d.GetId(out id); return id;
    }
    public static List<string[]> List() {
      List<string[]> r = new List<string[]>();
      IMMDeviceEnumerator e = (IMMDeviceEnumerator)new MMDeviceEnumeratorCo(); IMMDeviceCollection c;
      e.EnumAudioEndpoints(0, 1, out c); int n; c.GetCount(out n);
      for (int i = 0; i < n; i++) { IMMDevice d; c.Item(i, out d); string id; d.GetId(out id); r.Add(new string[] { id, Name(d) }); }
      return r;
    }
    public static void SetDefault(string id) {
      IPolicyConfig p = (IPolicyConfig)new PolicyConfigClient();
      p.SetDefaultEndpoint(id, 0); p.SetDefaultEndpoint(id, 1); p.SetDefaultEndpoint(id, 2);
    }
  }
}
"@
}

function L($m) { "$(Get-Date -Format 's')  $m" | Add-Content $Log }
$devices = [DashAudio.Audio]::List()
$current = [DashAudio.Audio]::DefaultId()

switch ($Action) {
  "names" { foreach ($d in $devices) { $d[1] } }
  "list" {
    L "--- playback devices ---"
    foreach ($d in $devices) { L ("{0}{1}" -f $(if ($d[0] -eq $current) { "[current] " } else { "" }), $d[1]) }
  }
  "tv" {
    if (-not $TvMatch) { L "no TV sound device set in config.json (tv.soundDevice); leaving sound as is"; exit 0 }
    $tv = $devices | Where-Object { $_[1] -match $TvMatch } | Select-Object -First 1
    if (-not $tv) { L "no TV sound device found (is the TV on and showing the PC?)"; exit 1 }
    if ($current -ne $tv[0]) { Set-Content $Prev $current }
    [DashAudio.Audio]::SetDefault($tv[0]); L "sound -> $($tv[1])"
  }
  "restore" {
    if (Test-Path $Prev) {
      $id = (Get-Content $Prev -Raw).Trim()
      if ($devices | Where-Object { $_[0] -eq $id }) { [DashAudio.Audio]::SetDefault($id); L "sound restored" } else { L "previous sound device not available" }
      Remove-Item $Prev -Force
    }
  }
}
