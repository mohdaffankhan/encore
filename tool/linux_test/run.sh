#!/bin/sh
# Runs inside the container. The project is mounted at /src; it is copied so
# the host's build folders are left alone, and screenshots are copied back.
set -e
rsync -a --delete --exclude build --exclude .dart_tool --exclude android/.gradle /src/ /work/
cd /work

# Dummy sound card so the audio backend can open an output.
pulseaudio --start --exit-idle-time=-1 --load="module-null-sink sink_name=null"

flutter pub get
flutter analyze
flutter test test/unit test/widget
status=0
xvfb-run -a -s "-screen 0 1440x900x24" \
  flutter test integration_test --dart-define=ENCORE_TEST=true -d linux || status=$?

mkdir -p /src/build/screenshots
cp -r build/screenshots/linux /src/build/screenshots/ 2>/dev/null || true
exit $status
