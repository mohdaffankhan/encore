#!/bin/sh
# Puts the latest build on the owner's devices, replacing the old one:
# this PC through the real Windows installer (an upgrade, keeping the
# library), and the phone with the release APK (adb install -r, keeping the
# library). Each is checked by playing music in the installed app.
# Usage: sh tool/install_latest.sh [android-device-id]
set -u
export MSYS_NO_PATHCONV=1
device=${1:-}
fail=0
log() { echo "[install] $*"; }
version=$(grep '^version:' pubspec.yaml | sed 's/version: //; s/+.*//')
build=$(grep '^version:' pubspec.yaml | sed 's/.*+//')
iscc="$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe"

log "--- Windows $version"
flutter build windows --release > build/install_windows.log 2>&1 || { log "FAIL: build"; exit 1; }
"$iscc" "/DAppVersion=$version" windows/installer.iss > build/install_iscc.log 2>&1 || { log "FAIL: installer"; exit 1; }
taskkill //IM encore.exe //F > /dev/null 2>&1
build/installer/encore-windows-setup.exe //VERYSILENT //SUPPRESSMSGBOXES //NORESTART || fail=1
installed="$LOCALAPPDATA/Programs/Encore"
powershell -ExecutionPolicy Bypass -File tool/windows_release_check.ps1 "$(cygpath -w "$installed")" || fail=1

if [ -n "$device" ]; then
  log "--- Android $version on $device"
  flutter build apk --release --build-name="$version" --build-number="$build" > build/install_android.log 2>&1 || { log "FAIL: build"; exit 1; }
  sh tool/android_release_check.sh build/app/outputs/flutter-apk/app-release.apk "$device" || fail=1
fi
[ "$fail" = 0 ] && log "PASSED: $version installed" || log "FAILED"
exit $fail
