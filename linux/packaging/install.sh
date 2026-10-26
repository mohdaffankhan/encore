#!/bin/sh
# Installs Encore from this folder for the current user (no root needed):
# the app into ~/.local/opt/encore, the `encore` command into ~/.local/bin,
# and a launcher with its icon into the app menu.
#   ./install.sh              install (or update)
#   ./install.sh --uninstall  remove it (your library stays)
set -eu
id=io.github.mohdaffankhan.Encore
here=$(cd "$(dirname "$0")" && pwd)
data=${XDG_DATA_HOME:-$HOME/.local/share}
app=$HOME/.local/opt/encore
bin=$HOME/.local/bin

remove() {
  rm -rf "$app"
  rm -f "$bin/encore" "$data/applications/$id.desktop" \
    "$data/metainfo/$id.metainfo.xml"
  for size in 128 256 512; do
    rm -f "$data/icons/hicolor/${size}x$size/apps/$id.png"
  done
}

if [ "${1:-}" = --uninstall ]; then
  remove
  echo "Encore removed. Your library is still in $data/$id."
  exit 0
fi

if [ ! -x "$here/encore" ]; then
  echo "Run this from the extracted Encore folder." >&2
  exit 1
fi
if ! ldconfig -p 2>/dev/null | grep -q 'libmpv\.so'; then
  echo "Note: Encore needs libmpv for sound. Install it with one of:"
  echo "  sudo apt install libmpv2     (Debian, Ubuntu)"
  echo "  sudo dnf install mpv-libs    (Fedora)"
  echo "  sudo pacman -S mpv           (Arch)"
fi

if [ "$here" != "$app" ]; then
  remove
  mkdir -p "$app"
  cp -r "$here"/. "$app"/
fi
mkdir -p "$bin" "$data/applications" "$data/metainfo"
ln -sf "$app/encore" "$bin/encore"
sed "s|^Exec=.*|Exec=$app/encore|" \
  "$app/share/applications/$id.desktop" > "$data/applications/$id.desktop"
cp "$app/share/metainfo/$id.metainfo.xml" "$data/metainfo/"
for size in 128 256 512; do
  mkdir -p "$data/icons/hicolor/${size}x$size/apps"
  cp "$app/share/icons/hicolor/${size}x$size/apps/$id.png" \
    "$data/icons/hicolor/${size}x$size/apps/"
done
update-desktop-database "$data/applications" 2>/dev/null || true
gtk-update-icon-cache -q "$data/icons/hicolor" 2>/dev/null || true
echo "Encore installed: find it in your app menu, or run 'encore'."
