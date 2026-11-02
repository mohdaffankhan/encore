#!/bin/sh
# Checks that downloads go on after Encore is closed on Android: the test
# app starts 12 downloads, its progress notification shows, its task is
# removed (what swiping it from the recent apps does), and the downloads
# finish with a "Downloaded 12 songs" notification. Once they are done,
# Encore shuts down (nothing keeps it), so the notifications are what is
# checked, not the test's own result. Uses the test app
# (dev.encore.app.test), never the real one. The phone must be unlocked.
# Usage: sh tool/android_downloads_check.sh <device-id>
set -u
device=$1
log=build/downloads_check.log
fail=0
a() { adb -s "$device" "$@"; }
say() { echo "[downloads] $*"; }
real_app() { a shell pm list packages dev.encore.app | grep -cx 'package:dev.encore.app'; }
real_before=$(real_app)
if a shell dumpsys window | grep -q 'isKeyguardShowing=true'; then
  say "FAIL: the phone is locked; unlock it and run again"; exit 1
fi
a shell svc power stayon usb
mkdir -p build
# --no-uninstall: flutter would otherwise uninstall the REAL app.
flutter test integration_test/downloads_test.dart -d "$device" --no-uninstall \
  --dart-define=ENCORE_TEST=true > "$log" 2>&1 &
test_pid=$!
# A fresh install asks before showing notifications: allow them for the
# test app, as a person would.
for _ in $(seq 300); do
  a shell pm list packages dev.encore.app.test | grep -q test && break
  sleep 1
done
a shell pm grant dev.encore.app.test android.permission.POST_NOTIFICATIONS
# Each wait has a limit: past it the test app is stopped, so the phone is
# never left on the test's screen.
wait_for() { # <log line> <seconds>
  n=0
  until grep -q "$1" "$log" 2>/dev/null; do
    kill -0 $test_pid 2>/dev/null || return 1
    n=$((n + 1))
    if [ $n -gt "$2" ]; then
      say "FAIL: no '$1' after $2 s; stopping the test"
      a shell am force-stop dev.encore.app.test
      fail=1
      return 1
    fi
    sleep 1
  done
}
# The titles of the test app's notifications (from their full records).
notices() { a shell dumpsys notification --noredact | awk '/NotificationRecord\(.*pkg=dev.encore.app.test /{n=60} n&&n--' | grep -oE "android.title=String \([^)]*\)"; }
if ! wait_for '\[downloads\] ready' 400; then
  say "FAIL: the test didn't start the downloads"; fail=1
  grep -E 'Expected|Actual|Exception' "$log" | head -4
else
  sleep 2
  progress=$(notices | grep -o 'Downloading [0-9]* of 12' | head -1)
  [ -n "$progress" ] && say "ok: progress shown when closing ($progress)" ||
    { say "FAIL: no progress notification (or done before closing): $(notices | tr '
' ' ')"; a shell dumpsys notification --noredact > build/downloads_notifications.txt; fail=1; }
  task=$(a shell am stack list | grep -o "taskId=[0-9]*: dev.encore.app.test/" | grep -o "[0-9]*")
  [ -n "$task" ] && a shell am stack remove "$task"
  sleep 3
  a shell am stack list | grep -q "dev.encore.app.test/" &&
    { say "FAIL: Encore's task is still there"; fail=1; }
  a shell pidof dev.encore.app.test > /dev/null && say "ok: closed Encore; its process runs on" ||
    { say "FAIL: Encore's process ended"; fail=1; }
  n=0
  until notices | grep -q "Downloaded 12 songs"; do
    n=$((n + 1))
    [ $n -gt 90 ] && break
    sleep 2
  done
  if notices | grep -q "Downloaded 12 songs"; then
    say "ok: finished after Encore was closed ('Downloaded 12 songs')"
  else
    say "FAIL: no 'Downloaded 12 songs' ($(notices | tr '
' ' '))"; fail=1
  fi
fi
a shell am force-stop dev.encore.app.test
wait $test_pid
a shell svc power stayon false
a uninstall dev.encore.app.test > /dev/null
if [ "$(a get-state 2>/dev/null)" != device ]; then
  say "FAIL: the phone disconnected during the check"; fail=1
elif [ "$real_before" != "$(real_app)" ]; then
  say "FAIL: the real Encore app was removed from the phone"; fail=1
fi
[ "$fail" = 0 ] && say "PASSED" || say "FAILED"
exit $fail
