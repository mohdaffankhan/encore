#!/bin/sh
# Checks that music keeps playing when the phone switches between mobile
# data and Wi-Fi, with the installed app (dev.encore.app; play something in
# it first, or it plays the last song). Needs mobile data on, Wi-Fi off and
# a saved Wi-Fi network in range; the phone unlocked. Leaves Wi-Fi off.
# Each way: a new song starts, the network switches 2 s in, and 25 s after
# the start it is paused, so the position Android reports shows whether it
# played on throughout (it only updates on events like pause).
# Usage: sh tool/android_network_switch_check.sh <device-id>
set -u
device=$1
fail=0
a() { adb -s "$device" "$@"; }
log() { echo "[network] $*"; }
session() { a shell dumpsys media_session | grep -A12 "package=dev.encore.app$"; }
position() { session | grep -oE "position=[0-9]+" | head -1 | cut -d= -f2; }

if a shell cmd wifi status | grep -q "Wifi is enabled"; then
  log "FAIL: turn Wi-Fi off first (the check starts on mobile data)"; exit 1
fi
if a shell dumpsys window | grep -q 'isKeyguardShowing=true'; then
  log "FAIL: the phone is locked; unlock it and run again"; exit 1
fi
a logcat -b crash -c
a shell input keyevent KEYCODE_MEDIA_PLAY
sleep 3
session | grep -q "state=PLAYING" || { log "FAIL: nothing plays; play a song in Encore first"; exit 1; }

trial() { # <enable|disable> <name>
  a shell input keyevent KEYCODE_MEDIA_NEXT
  sleep 2
  a shell svc wifi "$1"
  sleep 23
  a shell input keyevent KEYCODE_MEDIA_PAUSE
  sleep 1
  at=$(position)
  if [ "${at:-0}" -ge 20000 ]; then
    log "ok: $2: played on (paused at ${at} ms, ~25 s in)"
  else
    log "FAIL: $2: paused at ${at:-?} ms, ~25 s in"; fail=1
  fi
  a shell input keyevent KEYCODE_MEDIA_PLAY
  sleep 1
}
trial enable "mobile data to Wi-Fi"
for _ in $(seq 20); do a shell cmd wifi status | grep -q "connected to" && break; sleep 1; done
a shell cmd wifi status | grep -q "connected to" || { log "FAIL: Wi-Fi didn't connect"; fail=1; }
trial disable "Wi-Fi to mobile data"
a shell input keyevent KEYCODE_MEDIA_PAUSE
if a logcat -b crash -d | grep -q "Process: dev.encore.app"; then
  log "FAIL: app crashed"; fail=1
fi
[ "$fail" = 0 ] && log "PASSED" || log "FAILED"
exit $fail
