#!/bin/sh
# Runs the integration test on an Android device and, when the test is
# ready, sends the app to the background and turns the screen off, then
# reports the media session state. Usage: tool/android_background_check.sh <device-id>
set -u
device=$1
log=build/e2e_android.log
mkdir -p build
flutter test integration_test/app_test.dart -d "$device" \
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
  echo "[host] media session while screen off:"
  adb -s "$device" shell dumpsys media_session | grep -A3 "dev.encore.app" | grep -E "package|state=" | head -4
  echo "[host] notification posted:"
  adb -s "$device" shell dumpsys notification --noredact | grep -c "pkg=dev.encore.app"
fi
wait $test_pid
status=$?
adb -s "$device" shell input keyevent KEYCODE_WAKEUP
grep -E '\[e2e\]|Expected:|Actual:|TestFailure|All tests|Some tests' "$log"
exit $status
