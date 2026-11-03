#!/bin/sh
# Checks the Linux downloads of a release the way people install them, each
# in a clean Linux container (Docker), playing a real song with
# `--self-test`:
#   - the tar.gz on Ubuntu 24.04: install.sh, play, install.sh --uninstall
#   - the AUR package on Arch: makepkg from the tar.gz, pacman -U, play
#   - the Flatpak: flatpak install of the bundle, play
# Usage: sh tool/linux_release_check.sh <folder with encore-linux-x64.tar.gz
#        and encore-linux-x64.flatpak> [packages, default: "tar aur flatpak"]
set -u
export MSYS_NO_PATHCONV=1
dir=$(cd "$1" && pwd)
packages=${2:-tar aur flatpak}
wanted() { case " $packages " in *" $1 "*) return 0 ;; esac; return 1; }
repo=$(cd "$(dirname "$0")/.." && pwd)
fail=0
log() { echo "[linux] $*"; }
check() { if [ "$2" = 0 ]; then log "ok: $1"; else log "FAIL: $1"; fail=1; fi; }
# Docker on Windows takes Windows paths.
host() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else echo "$1"; fi; }
version=$(sed -n 's/^pkgver=//p' "$repo/linux/packaging/aur/PKGBUILD")

# A user session with a (silent) sound card, then the self-test.
play='pulseaudio --start --exit-idle-time=-1 --load="module-null-sink sink_name=null" 2>/dev/null
timeout 180 xvfb-run -a'

if wanted tar; then
log "--- tar.gz on Ubuntu 24.04"
docker run --rm -v "$(host "$dir"):/pkg:ro" ubuntu:24.04 sh -c "
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends libgtk-3-0t64 libmpv2 libgles2 \
  libgl1-mesa-dri libegl1 xvfb xauth pulseaudio ca-certificates > /dev/null
useradd -m user
su user -c '
set -e
mkdir -p ~/Downloads/encore
tar -xzf /pkg/encore-linux-x64.tar.gz -C ~/Downloads/encore
~/Downloads/encore/install.sh
test -f ~/.local/share/applications/io.github.mohdaffankhan.Encore.desktop
$play ~/.local/bin/encore --self-test > /tmp/out 2>&1 || { cat /tmp/out; exit 1; }
grep self-test /tmp/out
~/Downloads/encore/install.sh --uninstall
test ! -e ~/.local/bin/encore
'"
check "tar.gz installs, plays and uninstalls" $?
fi

if wanted aur; then
log "--- AUR package on Arch Linux"
docker run --rm -v "$(host "$dir"):/pkg:ro" \
  -v "$(host "$repo/linux/packaging/aur"):/aur:ro" archlinux:latest sh -c "
set -e
pacman -Syu --noconfirm --needed base-devel namcap xorg-server-xvfb xorg-xauth \
  pulseaudio > /dev/null 2>&1
useradd -m builder
mkdir /build
cp /aur/PKGBUILD /build/
cp /pkg/encore-linux-x64.tar.gz /build/encore-linux-x64-$version.tar.gz
chown -R builder /build
cd /build
pacman -S --noconfirm --needed \$(sed -n \"s/^depends=(\\(.*\\))/\\1/p\" PKGBUILD | tr -d \"'\") > /dev/null
su builder -c 'makepkg -f --noconfirm' > /dev/null
pacman -U --noconfirm encore-music-bin-*.pkg.tar.zst > /dev/null
su builder -c '$play encore-music --self-test > /tmp/out 2>&1 || { cat /tmp/out; exit 1; }'
grep self-test /tmp/out
"
check "AUR package builds, installs and plays" $?
fi

if wanted flatpak; then
log "--- Flatpak"
# As people have it: a desktop Linux (Fedora) with Flatpak, the bundle
# installed from the file (its runtime from Flathub).
docker run --rm --privileged -v "$(host "$dir"):/pkg:ro" \
  -v encore-flatpak-runtime:/root/.local/share/flatpak \
  fedora:41 sh -c "
set -e
dnf install -y -q flatpak xorg-x11-server-Xvfb xorg-x11-xauth pulseaudio dbus-daemon > /dev/null
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
# The runtime is kept between checks (a Docker volume); Encore is not.
flatpak uninstall --user -y --noninteractive io.github.mohdaffankhan.Encore > /dev/null 2>&1 || true
flatpak install --user -y --noninteractive /pkg/encore-linux-x64.flatpak > /dev/null
flatpak info --user io.github.mohdaffankhan.Encore | grep -E 'Version|Runtime'
export XDG_RUNTIME_DIR=/tmp/runtime && mkdir -p -m 700 \$XDG_RUNTIME_DIR
$play dbus-run-session flatpak run --user io.github.mohdaffankhan.Encore --self-test \
  > /tmp/out 2>&1 || { code=\$?; tail -20 /tmp/out; echo \"exit code \$code\"; exit 1; }
grep self-test /tmp/out
"
check "Flatpak installs and plays" $?
fi

[ "$fail" = 0 ] && log "PASSED" || log "FAILED"
exit $fail
