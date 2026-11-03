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
# The app can't be seen (or tapped) behind the lock screen.
if a shell dumpsys window | grep -q 'isKeyguardShowing=true'; then
  log "FAIL: the phone is locked; unlock it and run again"
  exit 1
fi
# No screen timeout during the check (put back at the end).
a shell svc power stayon usb
trap 'a shell svc power stayon false' EXIT
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

# Taps the middle of a node from ui()/nodes() (its bounds="[x1,y1][x2,y2]").
tap() {
  set -- $(echo "$1" | sed 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/')
  a shell input tap $((($1 + $3) / 2)) $((($2 + $4) / 2))
}
# Every node with its class, text and label (for the search box).
nodes() {
  a shell uiautomator dump /sdcard/encore_ui.xml > /dev/null 2>&1
  a shell cat /sdcard/encore_ui.xml | grep -oE '<node [^>]*>'
  a shell rm -f /sdcard/encore_ui.xml
}

# A song from a search, the same every time: the home feed changes (and
# its first row can be the mini player, which Encore restores paused).
tab=""
for _ in $(seq 30); do
  tab=$(ui | grep 'Search&#10;Tab' | head -1)
  [ -n "$tab" ] && break
  sleep 1
done
check "app starts" '[ -n "$tab" ]'
[ -n "$tab" ] || exit 1
tap "$tab"
sleep 2
box=$(nodes | grep 'class="android.widget.EditText"' | head -1)
check "search box shown" '[ -n "$box" ]'
[ -n "$box" ] || exit 1
tap "$box"
sleep 1
a shell input text "daft%spunk%sget%slucky"
a shell input keyevent KEYCODE_ENTER
# The topmost "Get Lucky" row (the mini player, if it shows that song too,
# is at the bottom).
tile=""
for _ in $(seq 30); do
  tile=$(ui | grep -i 'content-desc="Get Lucky[^"]*&#10;' |
    sed 's/\(.*bounds="\[[0-9]*,\([0-9]*\)\].*\)/\2 \1/' | sort -n | head -1 | cut -d' ' -f2-)
  [ -n "$tile" ] && break
  sleep 1
done
check "search finds the song" '[ -n "$tile" ]'
[ -n "$tile" ] || exit 1
log "playing: $(echo "$tile" | sed 's/content-desc="\([^&]*\).*/\1/')"
# The topmost row is above the keyboard (Back would leave the search).
tap "$tile"

for _ in $(seq 40); do
  session | grep -q "state=PLAYING" && break
  crashed && break
  sleep 1
done
check "playback starts" 'session | grep -q "state=PLAYING"'
# Why not, from the app's own log (cleared at the start of this check).
session | grep -q "state=PLAYING" ||
  a logcat -d -v time | grep -E "flutter|$pkg|AndroidRuntime" | tail -25
sleep 10
check "app still running after 10 s" 'alive && ! crashed'

# Background with the screen off: playback continues.
a shell input keyevent KEYCODE_HOME
sleep 2
a shell input keyevent KEYCODE_SLEEP
sleep 15
check "plays in background, screen off" 'alive && session | grep -q "state=PLAYING"'

# The player in the notification panel / lock screen: previous,
# play/pause and next as the notification's buttons, and like as the media
# session's custom button (Android 13+ draws it next to them). Keep only
# Encore's notification record.
# adb sometimes drops a command (v0.1.5's first check got nothing back), and
# a real dump always has other apps' records, so an empty one is retried.
for _ in 1 2 3; do
  : > build/encore_notification.txt
  records=$(a shell dumpsys notification --noredact | awk "
    /NotificationRecord\(/ { all++ }
    /NotificationRecord\(.*pkg=$pkg/ { n=45 }
    n && n-- { print > \"build/encore_notification.txt\" }
    END { print all + 0 }")
  [ "$records" -gt 0 ] && break
  log "notification dump came back empty; trying again"
  sleep 2
done
check "media notification shown" 'grep -q MediaStyle build/encore_notification.txt'
buttons=$(grep -cE '^ *\[[0-9]\] "' build/encore_notification.txt)
check "3 notification buttons (got $buttons)" '[ "$buttons" = 3 ]'
check "like button" 'session | grep -qE "mName=.(Like|Unlike)"'
check "no stop button" '! grep -qiE "\"Stop\"" build/encore_notification.txt'

title() { session | grep -o "description=[^,]*" | head -1; }
before=$(title)
a shell input keyevent KEYCODE_MEDIA_NEXT
sleep 8
after=$(title)
check "next changes the song" '[ -n "$after" ] && [ "$before" != "$after" ]'
check "still playing after next" 'alive && session | grep -q "state=PLAYING"'

# A picture of the media player in the panel, to look at (the like button
# among the others).
a shell input keyevent KEYCODE_WAKEUP
sleep 1
if ! a shell dumpsys window | grep -q 'isKeyguardShowing=true'; then
  a shell cmd statusbar expand-notifications
  sleep 2
  a exec-out screencap -p > build/release_media_panel.png
  log "media panel: build/release_media_panel.png"
  a shell cmd statusbar collapse
  sleep 1
fi

# Swiped away from the recent apps: the music stops (as in Spotify).
a shell input keyevent KEYCODE_WAKEUP
sleep 1
if a shell dumpsys window | grep -q 'isKeyguardShowing=true'; then
  log "skipped: swipe from recents (the phone locked itself)"
else
  a shell input keyevent KEYCODE_APP_SWITCH
  sleep 2
  # Encore's card is the most recent, in the middle; flick it up.
  a shell input swipe 540 1300 540 150 150
  sleep 5
  check "swiping it from recents stops the music" '! session | grep -q "state=PLAYING"'
  a shell input keyevent KEYCODE_HOME
fi

a shell input keyevent KEYCODE_MEDIA_PAUSE
a shell input keyevent KEYCODE_WAKEUP
if crashed; then
  log "FAIL: app crashed:"
  a logcat -b crash -d | grep -A6 "Process: $pkg" | head -14
  fail=1
fi
[ "$fail" = 0 ] && log "PASSED" || log "FAILED"
exit $fail
