#!/bin/sh
# Checks Linux's media controls (MPRIS) with a Linux tar.gz, in Docker: a
# desktop session bus, a silent sound card, the self-test playing a real
# song, and playerctl (what desktops and headset buttons use) reading what
# plays and pressing Next.
# Usage: sh tool/linux_media_check.sh <folder with encore-linux-x64.tar.gz>
set -u
export MSYS_NO_PATHCONV=1
dir=$(cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
host() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else echo "$1"; fi; }
out=$(docker run --rm -v "$(host "$dir"):/pkg:ro" \
  -v "$(host "$here/linux_test"):/check:ro" ubuntu:24.04 sh -c '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends libgtk-3-0t64 libmpv2 libgles2 \
  libgl1-mesa-dri libegl1 xvfb xauth pulseaudio ca-certificates dbus dbus-x11 \
  playerctl xdotool > /dev/null
useradd -m user
su user -c "sh /check/media_session.sh"
' 2>&1)
echo "$out" | grep -E '^\[linux\]|self-test'
if echo "$out" | grep -q '\[linux\] FAIL' ||
  ! echo "$out" | grep -q 'media key: next song .*, 1 along'; then
  echo "[linux] FAILED"
  exit 1
fi
echo "[linux] PASSED"
