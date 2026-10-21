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
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
'@
  $app = Get-Process encore | Where-Object MainWindowHandle -ne 0 |
    Sort-Object StartTime | Select-Object -Last 1
  # Windows only lets a background script bring a window to the front right
  # after a key press, so tap Alt first.
  foreach ($try in 1..5) {
    [Win]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
    [Win]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
    $null = [Win]::SetForegroundWindow($app.MainWindowHandle)
    Start-Sleep -Milliseconds 500
    if ([Win]::GetForegroundWindow() -eq $app.MainWindowHandle) { break }
  }
  if ([Win]::GetForegroundWindow() -ne $app.MainWindowHandle) {
    '[host] FAIL: could not bring the Encore window to the front'
  }
  (New-Object -ComObject WScript.Shell).SendKeys('get lucky kl{LEFT}{LEFT}x')
}
$test.WaitForExit()
Select-String '\[e2e\]|Typed |Expected|Actual|All tests|Some tests' $log | ForEach-Object { $_.Line }
exit $test.ExitCode
