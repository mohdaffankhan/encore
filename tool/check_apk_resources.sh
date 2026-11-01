#!/bin/sh
# Fails if a release APK is missing resources that are only looked up by
# name at runtime, which the resource shrinker can silently remove (see
# android/app/src/main/res/raw/keep.xml). Without the notification icons,
# Android kills the app as soon as a song starts.
# Usage: tool/check_apk_resources.sh <apk>
set -u
apk=$1
aapt2=$(command -v aapt2 || ls "${ANDROID_HOME:-$LOCALAPPDATA/Android/Sdk}"/build-tools/*/aapt2* 2>/dev/null | tail -1)
resources=$("$aapt2" dump resources "$apk") || exit 1
missing=0
for name in ic_stat_encore audio_service_play_arrow audio_service_pause \
  audio_service_skip_next audio_service_skip_previous; do
  if ! echo "$resources" | grep -q "drawable/$name\$"; then
    echo "[apk] FAIL: missing drawable/$name"
    missing=1
  fi
done
[ "$missing" = 0 ] && echo "[apk] ok: notification icons present"
# The desktop player (mpv) isn't used on Android: ~19 MB for nothing.
if unzip -l "$apk" | grep -q 'libmpv\.so'; then
  echo "[apk] FAIL: libmpv.so is in the APK"
  missing=1
else
  echo "[apk] ok: no desktop player libraries"
fi
exit $missing
