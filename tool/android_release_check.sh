#!/bin/sh
# Checks a real release APK on an Android device: the exact file people
# install, not a debug build. Release builds shrink code and resources, which
# debug builds don't, so only this catches what the shrinker breaks.
# Usage: tool/android_release_check.sh <apk> <device-id>
# Plays the first song on the home feed, so it adds one entry to history.
set -u
export MSYS_NO_PATHCONV=1
apk=$1
device=$2
pkg=dev.encore.app
fail=0
log() { echo "[release] $*"; }
check() { if eval "$2"; then log "ok: $1"; else log "FAIL: $1"; fail=1; fi; }
a() { adb -s "$device" "$@"; }

sh "$(dirname "$0")/check_apk_resources.sh" "$apk" || exit 1

a install -r "$apk" > /dev/null || { log "FAIL: install"; exit 1; }
a logcat -c
a logcat -b crash -c
a shell input keyevent KEYCODE_WAKEUP
a shell am force-stop $pkg
a shell am start -n $pkg/.MainActivity > /dev/null

# Reads the on-screen text through the accessibility tree (no screenshots).
ui() {
  a shell uiautomator dump /sdcard/encore_ui.xml > /dev/null 2>&1
  a shell cat /sdcard/encore_ui.xml | grep -oE 'content-desc="[^"]+"[^>]*bounds="[^"]+"'
  a shell rm -f /sdcard/encore_ui.xml
}
session() { a shell dumpsys media_session | grep -A12 "package=$pkg"; }
alive() { [ -n "$(a shell pidof $pkg)" ]; }
crashed() { a logcat -b crash -d | grep -q "Process: $pkg"; }

# A song tile on the home feed: "Title&#10;Artist", not a playlist card.
tile=""
for _ in $(seq 30); do
  tile=$(ui | grep '&#10;' | grep -v -e 'views' -e 'Tab [0-9]' | head -1)
  [ -n "$tile" ] && break
  sleep 1
done
check "home feed loads" '[ -n "$tile" ]'
[ -n "$tile" ] || exit 1
log "playing: $(echo "$tile" | sed 's/content-desc="\([^&]*\).*/\1/')"
set -- $(echo "$tile" | sed 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]"/\1 \2 \3 \4/')
a shell input tap $((($1 + $3) / 2)) $((($2 + $4) / 2))

for _ in $(seq 40); do
  session | grep -q "state=PLAYING" && break
  crashed && break
  sleep 1
done
check "playback starts" 'session | grep -q "state=PLAYING"'
sleep 10
check "app still running after 10 s" 'alive && ! crashed'

# Background with the screen off: playback continues.
a shell input keyevent KEYCODE_HOME
sleep 2
a shell input keyevent KEYCODE_SLEEP
sleep 15
check "plays in background, screen off" 'alive && session | grep -q "state=PLAYING"'

# The player in the notification panel / lock screen: exactly
# previous, play/pause, next. Keep only Encore's notification record.
a shell dumpsys notification --noredact \
  | awk "/NotificationRecord\(.*pkg=$pkg/{n=45} n&&n--" > build/encore_notification.txt
check "media notification shown" 'grep -q MediaStyle build/encore_notification.txt'
buttons=$(grep -cE '^ *\[[0-9]\] "' build/encore_notification.txt)
check "3 notification buttons (got $buttons)" '[ "$buttons" = 3 ]'
check "no stop button" '! grep -qiE "\"Stop\"" build/encore_notification.txt'

title() { session | grep -o "description=[^,]*" | head -1; }
before=$(title)
a shell input keyevent KEYCODE_MEDIA_NEXT
sleep 8
after=$(title)
check "next changes the song" '[ -n "$after" ] && [ "$before" != "$after" ]'
check "still playing after next" 'alive && session | grep -q "state=PLAYING"'

a shell input keyevent KEYCODE_MEDIA_PAUSE
a shell input keyevent KEYCODE_WAKEUP
if crashed; then
  log "FAIL: app crashed:"
  a logcat -b crash -d | grep -A6 "Process: $pkg" | head -14
  fail=1
fi
[ "$fail" = 0 ] && log "PASSED" || log "FAILED"
exit $fail
