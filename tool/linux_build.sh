#!/bin/sh
# Builds the Linux tar.gz on this PC, in Docker, the way CI does (Ubuntu,
# the same packages and Flutter version), for checking Linux changes before
# they reach CI. The Flutter SDK is kept in a Docker volume between builds.
# Usage: sh tool/linux_build.sh  ->  build/linux-docker/encore-linux-x64.tar.gz
set -eu
export MSYS_NO_PATHCONV=1
repo=$(cd "$(dirname "$0")/.." && pwd)
flutter_version=$(sed -n 's/^ *FLUTTER_VERSION: *//p' "$repo/.github/workflows/build.yml" | tr -d "'\"" | head -1)
host() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else echo "$1"; fi; }
mkdir -p "$repo/build/linux-docker"
docker run --rm \
  -v "$(host "$repo"):/repo:ro" \
  -v "$(host "$repo/build/linux-docker"):/out" \
  -v encore-flutter-sdk:/flutter \
  ubuntu:24.04 sh -c "
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends git curl unzip xz-utils ca-certificates \
  build-essential clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev patchelf rsync > /dev/null
if [ ! -x /flutter/bin/flutter ]; then
  git clone -q --depth 1 --branch $flutter_version https://github.com/flutter/flutter.git /flutter
fi
git config --global --add safe.directory /flutter
export PATH=/flutter/bin:\$PATH
flutter --version | head -1
# A copy without this PC's build output (and Windows line endings fixed).
rsync -a --exclude build --exclude .dart_tool /repo/ /src/
cd /src
flutter pub get > /dev/null
flutter build linux --release
if ldd build/linux/x64/release/bundle/encore build/linux/x64/release/bundle/lib/*.so | grep 'not found'; then
  exit 1
fi
sh linux/packaging/make_tarball.sh build/linux/x64/release/bundle /out/encore-linux-x64.tar.gz
"
echo "[linux] built build/linux-docker/encore-linux-x64.tar.gz"
