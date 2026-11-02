#!/bin/sh
# Checks that Encore on Linux ends cleanly when its window is closed while
# music plays (an abort there shows people a crash report), in Docker.
# Usage: sh tool/linux_quit_check.sh <folder with encore-linux-x64.tar.gz>
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
  playerctl openbox wmctrl > /dev/null
useradd -m user
su user -c "sh /check/quit.sh"
' 2>&1)
echo "$out" | grep -E '^\[quit\]|^[A-Za-z].*(abort|Abort|error)' | head -20
if echo "$out" | grep -q '\[quit\] ok:'; then
  echo "[quit] PASSED"
else
  echo "[quit] FAILED"
  exit 1
fi
