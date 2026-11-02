#!/bin/sh
# Checks the AppImage on a Linux it wasn't built on (Fedora; it is built on
# Ubuntu), as a desktop has it (GTK, which every Linux desktop has) but
# without libmpv, which the AppImage brings with everything mpv needs;
# plus a screen (Xvfb), a silent sound server, a desktop session bus and
# the checking tools. The
# self-test plays a real song, the desktop's media controls (playerctl) see
# it, and Next moves on one song, as in tool/linux_media_check.sh.
# Usage: sh tool/linux_appimage_check.sh <folder with Encore-x86_64.AppImage> [image]
set -u
export MSYS_NO_PATHCONV=1
dir=$(cd "$1" && pwd)
image=${2:-fedora:41}
here=$(cd "$(dirname "$0")" && pwd)
host() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else echo "$1"; fi; }
out=$(docker run --rm -v "$(host "$dir"):/pkg:ro" \
  -v "$(host "$here/linux_test"):/check:ro" "$image" sh -c '
set -e
dnf install -y -q xorg-x11-server-Xvfb xorg-x11-xauth pulseaudio dbus-daemon \
  dbus-tools playerctl xdotool mesa-dri-drivers mesa-libEGL mesa-libGL \
  mesa-libGLES gtk3 shadow-utils util-linux procps-ng > /dev/null
if ldconfig -p | grep -q libmpv; then echo "[linux] FAIL: libmpv is installed"; fi
useradd -m user
su user -c "ENCORE_PKG=appimage sh /check/media_session.sh"
' 2>&1)
echo "$out" | grep -E '^\[linux\]|self-test|error while loading'
if echo "$out" | grep -q '\[linux\] FAIL' ||
  ! echo "$out" | grep -q 'media key: next song .*, 1 along'; then
  echo "[linux] FAILED (AppImage on $image)"
  exit 1
fi
echo "[linux] PASSED (AppImage on $image, no libmpv installed)"
