#!/bin/sh
# Builds the release APKs: the universal one (every phone) and one per chip
# type (about a third of the size), then checks each.
# Each chip's APK is its own build (--target-platform), not Flutter's
# --split-per-abi: that one raises the Android version code (build 17
# becomes 2017 for arm64), after which the universal APK, and every test
# build, would count as a downgrade and refuse to install over it. Here all
# four have the same version code, so people can switch between them.
# Usage: sh tool/android_apks.sh <out dir> [flutter build flags...]
set -u
out=$1
shift
mkdir -p "$out"
fail=0
log() { echo "[apks] $*"; }
aapt2=$(command -v aapt2 || ls "${ANDROID_HOME:-$LOCALAPPDATA/Android/Sdk}"/build-tools/*/aapt2* 2>/dev/null | tail -1)
built=build/app/outputs/flutter-apk/app-release.apk

build() { # <name> [--target-platform ...]
  name=$1
  shift
  flutter build apk --release "$@" > "build/apk_$name.log" 2>&1 ||
    { log "FAIL: $name build (see build/apk_$name.log)"; exit 1; }
  cp "$built" "$out/encore-android$name.apk"
}
build "" "$@"
build -arm64-v8a --target-platform android-arm64 "$@"
build -armeabi-v7a --target-platform android-arm "$@"
build -x86_64 --target-platform android-x64 "$@"

code() { "$aapt2" dump badging "$1" | grep -o "versionCode='[0-9]*'"; }
abis() { unzip -l "$1" | grep -o 'lib/[^/]*/libflutter\.so' | cut -d/ -f2 | sort | tr '\n' ' '; }
universal=$(code "$out/encore-android.apk")
for abi in "" arm64-v8a armeabi-v7a x86_64; do
  apk=$out/encore-android${abi:+-$abi}.apk
  sh "$(dirname "$0")/check_apk_resources.sh" "$apk" > /dev/null || { log "FAIL: $apk resources"; fail=1; }
  has=$(abis "$apk")
  want=${abi:-arm64-v8a armeabi-v7a x86_64}
  [ "$has" = "$want " ] || { log "FAIL: $apk has chips '$has', wants '$want'"; fail=1; }
  [ "$(code "$apk")" = "$universal" ] ||
    { log "FAIL: $apk has $(code "$apk"), the universal one $universal"; fail=1; }
  log "$(basename "$apk"): $(($(wc -c < "$apk") / 1048576)) MB, $has$(code "$apk")"
done
[ "$fail" = 0 ] && log "PASSED" || log "FAILED"
exit $fail
