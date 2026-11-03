#!/bin/sh
# Builds the Flatpak bundle on this PC the way CI does (Flathub's builder
# image, the manifest in linux/packaging/flatpak/, the Linux tar.gz), for
# checking Flatpak changes before they reach CI. mpv and what it needs are
# compiled the first time; a Docker volume keeps that for the next build.
# Usage: sh tool/flatpak_build.sh <folder with encore-linux-x64.tar.gz>
#        -> encore-linux-x64.flatpak in that folder
set -eu
export MSYS_NO_PATHCONV=1
dir=$(cd "$1" && pwd)
repo=$(cd "$(dirname "$0")/.." && pwd)
host() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else echo "$1"; fi; }
image=$(sed -n 's/^ *image: \(ghcr.io\/flathub-infra\/flatpak-github-actions:.*\)/\1/p' \
  "$repo/.github/workflows/build.yml" | head -1)
docker run --rm --privileged \
  -v "$(host "$repo/linux/packaging/flatpak"):/manifest:ro" \
  -v "$(host "$dir"):/pkg" \
  -v encore-flatpak-builder:/build \
  "$image" sh -c '
set -e
mkdir -p /build/work && cd /build/work
cp /manifest/*.yml . && cp /pkg/encore-linux-x64.tar.gz .
# The tar.gz by its checksum: flatpak-builder caches a module by its
# sources, and a local file by name alone would reuse an older build.
sum=$(sha256sum encore-linux-x64.tar.gz | cut -d" " -f1)
sed -i "s|^        path: encore-linux-x64.tar.gz\$|&\n        sha256: $sum|" io.github.mohdaffankhan.Encore.yml
grep -q "sha256: $sum" io.github.mohdaffankhan.Encore.yml ||
  { echo "[flatpak] FAIL: could not add the tar.gz checksum to the manifest"; exit 1; }
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak-builder --user --install-deps-from=flathub --disable-rofiles-fuse \
  --repo=repo --force-clean build io.github.mohdaffankhan.Encore.yml > /build/log 2>&1 ||
  { tail -40 /build/log; exit 1; }
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  repo /pkg/encore-linux-x64.flatpak io.github.mohdaffankhan.Encore
'
echo "[flatpak] built $dir/encore-linux-x64.flatpak ($(($(wc -c < "$dir/encore-linux-x64.flatpak") / 1048576)) MB)"
