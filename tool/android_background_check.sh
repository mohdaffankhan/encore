#!/bin/sh
# Runs the integration test on an Android device and, when the test is
# ready, sends the app to the background and turns the screen off, then
# reports the media session state. Debug builds are dev.encore.app.test, so
# the real app on the phone is left alone. Usage: tool/android_background_check.sh <device-id>
set -u
device=$1
host_fail=0
log=build/e2e_android.log
mkdir -p build
# --no-uninstall: flutter would otherwise uninstall by the project's app id,
# which is the REAL app (dev.encore.app), wiping the user's library. The test
# app is removed below by its exact id instead.
real_app() { adb -s "$device" shell pm list packages dev.encore.app | grep -cx 'package:dev.encore.app'; }
real_app_before=$(real_app)
# Keep the screen from timing out during the install and the UI steps (put
# back at the end); the background step turns it off on purpose.
adb -s "$device" shell svc power stayon usb
adb -s "$device" shell input keyevent KEYCODE_WAKEUP
flutter test integration_test/app_test.dart -d "$device" --no-uninstall \
  --dart-define=ENCORE_TEST=true --dart-define=ENCORE_BACKGROUND_CHECK=true \
  > "$log" 2>&1 &
test_pid=$!
until grep -q 'background: ready' "$log" 2>/dev/null; do
  kill -0 $test_pid 2>/dev/null || break
  sleep 1
done
if grep -q 'background: ready' "$log"; then
  adb -s "$device" shell input keyevent KEYCODE_HOME
  sleep 2
  adb -s "$device" shell input keyevent KEYCODE_SLEEP
  sleep 8
  # The player must be visible to the system: an active media session that
  # is PLAYING (lock screen / panel controls) and a media notification.
  session=$(adb -s "$device" shell dumpsys media_session | grep -A12 "package=dev.encore.app.test")
  echo "$session" | grep -E "active=|state=PlaybackState" | sed 's/^ */[host] /'
  echo "$session" | grep -q "active=true" || { echo "[host] FAIL: media session not active"; host_fail=1; }
  echo "$session" | grep -q "state=PLAYING" || { echo "[host] FAIL: media session not PLAYING"; host_fail=1; }
  # Keep only Encore's own notification record (the full dump includes
  # other apps' notifications).
  adb -s "$device" shell dumpsys notification --noredact     | awk '/NotificationRecord\(.*pkg=dev.encore.app.test /{n=45} n&&n--' > build/encore_notification.txt
  grep -E "android.template|^ *\[[0-9]\] " build/encore_notification.txt | sed 's/^ */[host] /'
  # Exactly previous / play-pause / next, and no stop button anywhere.
  buttons=$(grep -cE '^ *\[[0-9]\] "' build/encore_notification.txt)
  [ "$buttons" = 3 ] || { echo "[host] FAIL: expected 3 notification buttons, got $buttons"; host_fail=1; }
  if grep -qiE '"Stop"' build/encore_notification.txt || echo "$session" | grep -q "mName='Stop"; then
    echo "[host] FAIL: stop button present"; host_fail=1
  fi
  # Next via the media session (same path as the notification's button).
  title() { adb -s "$device" shell dumpsys media_session | grep -A12 "package=dev.encore.app.test" | grep -o "description=[^,]*" | head -1; }
  until grep -q 'background playback' "$log" 2>/dev/null; do
    kill -0 $test_pid 2>/dev/null || break
    sleep 1
  done
  before=$(title)
  adb -s "$device" shell input keyevent KEYCODE_MEDIA_NEXT
  sleep 6
  after=$(title)
  echo "[host] next: '$before' -> '$after'"
  [ -n "$after" ] && [ "$before" != "$after" ] || { echo "[host] FAIL: next did not change the song"; host_fail=1; }
  if grep -q "MediaStyle" build/encore_notification.txt; then
    echo "[host] media notification: shown"
  else
    echo "[host] FAIL: no media notification"; host_fail=1
  fi
fi
wait $test_pid
status=$?
adb -s "$device" shell input keyevent KEYCODE_WAKEUP
adb -s "$device" shell svc power stayon false
adb -s "$device" uninstall dev.encore.app.test > /dev/null
if [ "$real_app_before" != "$(real_app)" ]; then
  echo "[host] FAIL: the real Encore app was removed from the phone"; host_fail=1
fi
grep -E '\[e2e\]|Expected:|Actual:|TestFailure|All tests|Some tests' "$log"
[ "$host_fail" = 0 ] || status=1
exit $status
