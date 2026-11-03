#!/bin/sh
# Packs the Linux release build into the tar.gz people download (and the
# AUR and Flatpak packages are made from): the Flutter bundle plus the
# launcher, icons, app metadata and install.sh.
# Usage: sh linux/packaging/make_tarball.sh <bundle dir> <out.tar.gz>
set -eu
bundle=$1
out=$2
id=io.github.mohdaffankhan.Encore
here=$(cd "$(dirname "$0")" && pwd)

# Flutter's plugin libraries keep the build folder as a library search
# path (RUNPATH): point them at their own folder (where the Flutter
# library is) instead, so nothing is loaded from a path someone else could
# create on the user's machine.
command -v patchelf > /dev/null || { echo "patchelf is needed" >&2; exit 1; }
for lib in "$bundle"/lib/*.so; do
  if [ -n "$(patchelf --print-rpath "$lib")" ]; then
    patchelf --set-rpath '$ORIGIN' "$lib"
  fi
done

# package:jni's library (pulled in by Android plugins) is only used on
# Android; built where Java is installed (CI), it needs Java's libjvm.so,
# which people's systems don't have (and the AppImage can't bundle). Encore
# never loads it on Linux.
rm -f "$bundle/lib/libdartjni.so"

mkdir -p "$bundle/share/applications" "$bundle/share/metainfo"
cp "$here/$id.desktop" "$bundle/share/applications/"
cp "$here/$id.metainfo.xml" "$bundle/share/metainfo/"
for size in 128 256 512; do
  mkdir -p "$bundle/share/icons/hicolor/${size}x$size/apps"
  cp "$here/icons/$size.png" "$bundle/share/icons/hicolor/${size}x$size/apps/$id.png"
done
cp "$here/install.sh" "$bundle/install.sh"
chmod +x "$bundle/install.sh" "$bundle/encore"
mkdir -p "$(dirname "$out")"
tar -czf "$out" -C "$bundle" .
