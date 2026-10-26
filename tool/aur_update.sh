#!/bin/sh
# Updates the AUR package (encore-music-bin) to a PUBLISHED release: sets
# the version and the tarball's checksum in linux/packaging/aur/PKGBUILD,
# writes .SRCINFO, and copies both into a clone of the AUR repository.
# With --push it also commits and pushes there, which publishes the update.
#
# One-time setup (needs an AUR account with your SSH key added):
#   git clone ssh://aur@aur.archlinux.org/encore-music-bin.git ../aur-encore-music-bin
# Usage: sh tool/aur_update.sh 0.1.5 [--push]
set -eu
export MSYS_NO_PATHCONV=1
version=$1
push=${2:-}
repo=$(cd "$(dirname "$0")/.." && pwd)
aur=${AUR_REPO:-$repo/../aur-encore-music-bin}
pkgbuild=$repo/linux/packaging/aur/PKGBUILD
host() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else echo "$1"; fi; }

tmp=$(mktemp -d)
gh release download "v$version" -p encore-linux-x64.tar.gz -D "$tmp"
sum=$(sha256sum "$tmp/encore-linux-x64.tar.gz" | cut -d' ' -f1)
rm -rf "$tmp"

sed -i -e "s/^pkgver=.*/pkgver=$version/" -e "s/^pkgrel=.*/pkgrel=1/" \
  -e "s/^sha256sums=.*/sha256sums=('$sum')/" "$pkgbuild"
docker run --rm -v "$(host "$repo/linux/packaging/aur"):/aur" archlinux:latest sh -c '
  pacman -Sy --noconfirm --needed base-devel > /dev/null 2>&1
  useradd -m builder && cp /aur/PKGBUILD /home/builder/ && cd /home/builder
  su builder -c "makepkg --printsrcinfo" > /aur/.SRCINFO'
echo "PKGBUILD and .SRCINFO updated to $version ($sum)"

if [ -d "$aur/.git" ]; then
  cp "$pkgbuild" "$repo/linux/packaging/aur/.SRCINFO" "$aur/"
  if [ "$push" = --push ]; then
    git -C "$aur" add PKGBUILD .SRCINFO
    git -C "$aur" commit -m "Update to $version"
    git -C "$aur" push
    echo "Published encore-music-bin $version on the AUR"
  else
    echo "Copied into $aur. Run again with --push to publish."
  fi
else
  echo "No AUR clone at $aur (see the setup at the top of this script)."
fi
