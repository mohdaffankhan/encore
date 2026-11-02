#!/bin/sh
# Makes the AppImage from the Linux tar.gz: one file to download and run,
# with libmpv (sound) and the libraries it and Encore need inside, so
# nothing has to be installed. linuxdeploy picks those libraries, leaving
# out the ones every system has and must use its own of (glibc, graphics
# drivers, X11/Wayland basics). Needs libmpv installed where it runs (the
# build machine), patchelf, and network access for linuxdeploy (pinned).
# Usage: sh linux/packaging/make_appimage.sh <encore-linux-x64.tar.gz> <out.AppImage>
set -eu
tarball=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
out=$2
id=io.github.mohdaffankhan.Encore
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tools=https://github.com/linuxdeploy
linuxdeploy=$work/linuxdeploy-x86_64.AppImage
plugin=$work/linuxdeploy-plugin-appimage-x86_64.AppImage
curl -fsSL -o "$linuxdeploy" \
  "$tools/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage"
curl -fsSL -o "$plugin" \
  "$tools/linuxdeploy-plugin-appimage/releases/download/1-alpha-20250213-1/linuxdeploy-plugin-appimage-x86_64.AppImage"
chmod +x "$linuxdeploy" "$plugin"
# No FUSE in containers and CI: the tools unpack themselves instead.
export APPIMAGE_EXTRACT_AND_RUN=1

# The app as in the tar.gz, under usr/lib/encore (its lib/ and data/ next
# to the executable, as Flutter expects).
app=$work/AppDir
mkdir -p "$app/usr/lib/encore"
tar -xzf "$tarball" -C "$app/usr/lib/encore"
rm -rf "$app/usr/lib/encore/install.sh" "$app/usr/lib/encore/share"

# mpv is loaded by name at run time (not linked), so it is named here.
libmpv=$(ldconfig -p | sed -n 's/.*libmpv\.so\.2 .*=> //p' | head -1)
[ -n "$libmpv" ] || { echo "libmpv.so.2 is needed to build the AppImage" >&2; exit 1; }

cp "$here/icons/256.png" "$work/$id.png"
cat > "$work/AppRun" <<'EOF'
#!/bin/sh
# Encore's libraries (mpv's among them) before the system's.
here=$(dirname "$(readlink -f "$0")")
export LD_LIBRARY_PATH="$here/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$here/usr/lib/encore/encore" "$@"
EOF
chmod +x "$work/AppRun"

cd "$work"
LDAI_OUTPUT=Encore.AppImage "$linuxdeploy" --appdir "$app" \
  --executable "$app/usr/lib/encore/encore" \
  --deploy-deps-only "$app/usr/lib/encore/lib" \
  --library "$libmpv" \
  --desktop-file "$here/$id.desktop" \
  --icon-file "$work/$id.png" \
  --custom-apprun "$work/AppRun" \
  --output appimage > "$work/linuxdeploy.log" 2>&1 ||
  { tail -40 "$work/linuxdeploy.log" >&2; exit 1; }
cd - > /dev/null
mkdir -p "$(dirname "$out")"
mv "$work/Encore.AppImage" "$out"
echo "made $out ($(($(wc -c < "$out") / 1048576)) MB)"
