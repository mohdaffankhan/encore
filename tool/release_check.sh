#!/bin/sh
# The last step of every release: nothing is public until this passes.
# Pushing a tag makes GitHub Actions build a DRAFT release. This downloads
# that draft's files (the exact ones people will install), plays music with
# them on a real Android phone and on this Windows PC, and only then
# publishes the release.
# Usage: sh tool/release_check.sh v0.2.0 <android-device-id>
set -u
tag=$1
device=$2
dir=build/release_check/$tag
fail=0
log() { echo "[release] $*"; }

rm -rf "$dir"
mkdir -p "$dir"
gh release download "$tag" -D "$dir" || { log "FAIL: no draft release $tag"; exit 1; }
ls "$dir"

log "--- Android: $dir/encore-android.apk on $device"
sh tool/android_release_check.sh "$dir/encore-android.apk" "$device" || fail=1

log "--- Windows: portable zip"
unzip -q "$dir/encore-windows-portable.zip" -d "$dir/portable" || fail=1
[ -f "$dir/portable/data/app.so" ] || { log "FAIL: zip layout"; fail=1; }
powershell -ExecutionPolicy Bypass -File tool/windows_release_check.ps1 \
  "$(cygpath -w "$dir/portable")" || fail=1

log "--- Windows: installer"
# Like a user updating: run it over the Encore installed on this PC and
# play a song in it. With none installed, install into a test folder and
# remove it after.
if reg query 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{6F1E2A57-3C8B-4E7D-9A41-2B5C0D8E9F13}_is1' > /dev/null 2>&1; then
  taskkill //IM encore.exe //F > /dev/null 2>&1
  "$dir/encore-windows-setup.exe" //VERYSILENT //SUPPRESSMSGBOXES //NORESTART || fail=1
  powershell -ExecutionPolicy Bypass -File tool/windows_release_check.ps1 \
    "$(cygpath -w "$LOCALAPPDATA/Programs/Encore")" || fail=1
else
  installed=$(cygpath -w "$PWD/$dir/installed")
  "$dir/encore-windows-setup.exe" //VERYSILENT //SUPPRESSMSGBOXES //NORESTART \
    //NOICONS "//DIR=$installed" || fail=1
  powershell -ExecutionPolicy Bypass -File tool/windows_release_check.ps1 \
    "$installed" || fail=1
  "$dir/installed/unins000.exe" //VERYSILENT //SUPPRESSMSGBOXES
  sleep 3
fi

log "--- Linux: archive (GitHub Actions checked its libraries)"
tar -tzf "$dir/encore-linux-x64.tar.gz" | grep -qx './encore' &&
  tar -tzf "$dir/encore-linux-x64.tar.gz" | grep -qx './lib/libapp.so' ||
  { log "FAIL: linux archive layout"; fail=1; }

if [ "$fail" != 0 ]; then
  log "FAILED: $tag stays a draft. Fix, delete the draft and tag, and retag."
  exit 1
fi
gh release edit "$tag" --draft=false --latest
log "PASSED: $tag is published"
