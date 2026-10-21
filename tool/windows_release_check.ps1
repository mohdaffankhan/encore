# Checks a real Windows release build (the files people install, not a
# debug build): runs `encore.exe --self-test`, which plays a real song and
# exits 0 if it played, and also checks sound actually leaves the app.
# Usage: powershell -File tool/windows_release_check.ps1 <folder with encore.exe>
param([Parameter(Mandatory)] [string] $Dir)

$fail = 0
function Check($name, [bool] $ok) {
  if ($ok) { "[release] ok: $name" } else { "[release] FAIL: $name"; $script:fail = 1 }
}

# Sound leaving the app: the peak level of its audio sessions.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class Peak {
  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class Enumerator {}
  [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceEnumerator { int NotImpl(); int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice d); }
  [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDevice { int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
  [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionManager2 { int a(); int b(); int GetSessionEnumerator(out IAudioSessionEnumerator e); }
  [Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionEnumerator { int GetCount(out int n); int GetSession(int i, [MarshalAs(UnmanagedType.IUnknown)] out object s); }
  [Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionControl2 { int a(); int b(); int c(); int d(); int e(); int f(); int g(); int h(); int i(); int j(); int k(); int GetProcessId(out uint pid); }
  [Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioMeterInformation { int GetPeakValue(out float v); }
  public static float Of(int pid) {
    IMMDevice dev; ((IMMDeviceEnumerator)new Enumerator()).GetDefaultAudioEndpoint(0, 1, out dev);
    object o; var iid = typeof(IAudioSessionManager2).GUID; dev.Activate(ref iid, 23, IntPtr.Zero, out o);
    IAudioSessionEnumerator en; ((IAudioSessionManager2)o).GetSessionEnumerator(out en);
    int n; en.GetCount(out n); float max = 0;
    for (int i = 0; i < n; i++) {
      object s; en.GetSession(i, out s); uint p; ((IAudioSessionControl2)s).GetProcessId(out p);
      if (p != pid) continue;
      float v; ((IAudioMeterInformation)s).GetPeakValue(out v); max = Math.Max(max, v);
    }
    return max;
  }
}
'@

$log = Join-Path $env:TEMP 'encore_self_test.log'
Remove-Item $log -ErrorAction SilentlyContinue
Get-Process encore -ErrorAction SilentlyContinue | Stop-Process -Force
$proc = Start-Process (Join-Path $Dir 'encore.exe') '--self-test' -PassThru
$peak = 0
while (-not $proc.WaitForExit(500)) {
  if ((Get-Date) - $proc.StartTime -gt [TimeSpan]::FromMinutes(3)) {
    $proc | Stop-Process -Force
    break
  }
  $peak = [Math]::Max($peak, [Peak]::Of($proc.Id))
}
if (Test-Path $log) { Get-Content $log | ForEach-Object { "[self-test] $_" } }
Check 'self-test passes' ($proc.ExitCode -eq 0)
Check "sound plays (peak $([Math]::Round($peak, 3)))" ($peak -gt 0.01)
if ($fail) { '[release] FAILED' } else { '[release] PASSED' }
exit $fail
