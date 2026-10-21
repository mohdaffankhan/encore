# Runs the end-to-end test on Windows and, when it is ready, types into the
# search box with real key presses (through Windows, like a keyboard), so
# keys the app intercepts by mistake are caught.
# Usage: powershell -File tool/windows_keyboard_check.ps1
$log = 'build\e2e_windows_keys.log'
New-Item -ItemType Directory -Force build | Out-Null
$test = Start-Process cmd -ArgumentList '/c', 'flutter test integration_test/app_test.dart -d windows --dart-define=ENCORE_TEST=true --dart-define=ENCORE_KEYBOARD_CHECK=true' `
  -RedirectStandardOutput $log -NoNewWindow -PassThru
while (-not $test.HasExited -and -not (Select-String -Quiet 'keyboard: ready' $log)) {
  Start-Sleep -Milliseconds 500
}
if (-not $test.HasExited) {
  Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Win {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  // Windows only lets the foreground window's thread hand over the
  // foreground, so borrow its input queue for a moment. (Not tapping Alt:
  // a lone Alt press puts the window in menu mode, which takes keyboard
  // focus away from the app.)
  public static bool Bring(IntPtr h) {
    var fg = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero);
    var me = GetCurrentThreadId();
    AttachThreadInput(me, fg, true);
    SetForegroundWindow(h);
    AttachThreadInput(me, fg, false);
    return GetForegroundWindow() == h;
  }
}
'@
  $app = Get-Process encore | Where-Object MainWindowHandle -ne 0 |
    Sort-Object StartTime | Select-Object -Last 1
  $front = $false
  foreach ($try in 1..5) {
    if ([Win]::Bring($app.MainWindowHandle)) { $front = $true; break }
    Start-Sleep -Milliseconds 300
  }
  if (-not $front) { '[host] FAIL: could not bring the Encore window to the front' }
  Start-Sleep -Milliseconds 500
  (New-Object -ComObject WScript.Shell).SendKeys('get lucky kl{LEFT}{LEFT}x')
}
$test.WaitForExit()
Select-String '\[e2e\]|Typed |Expected|Actual|All tests|Some tests' $log | ForEach-Object { $_.Line }
exit $test.ExitCode
