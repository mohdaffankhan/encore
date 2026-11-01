#!/bin/sh
# Inside the container, as a user (tool/linux_media_check.sh): the app's
# self-test plays a song; playerctl checks the desktop sees it, then
# presses Next, which the self-test waits for. The window title shows the
# song meanwhile.
mkdir -p ~/encore && tar -xzf /pkg/encore-linux-x64.tar.gz -C ~/encore
pulseaudio --start --exit-idle-time=-1 --load="module-null-sink sink_name=null" 2>/dev/null
exec dbus-run-session -- xvfb-run -a sh -c '
rm -f /tmp/encore_media_check.ready
timeout 180 ~/encore/encore --self-test --media-check > /tmp/out 2>&1 &
app=$!
for _ in $(seq 150); do
  [ -f /tmp/encore_media_check.ready ] && break
  sleep 1
done
playing=$(cat /tmp/encore_media_check.ready)
name=$(playerctl -l 2>/dev/null | grep -i encore | head -1)
echo "[linux] media player: $name"
title=$(playerctl -p "$name" metadata title 2>/dev/null)
echo "[linux] playing: $title ($(playerctl -p "$name" status 2>/dev/null))"
if [ -n "$title" ] && [ "$title" = "$playing" ]; then
  echo "[linux] ok: the desktop sees the song"
else
  echo "[linux] FAIL: the desktop does not see the song"
fi
window=$(xdotool search --onlyvisible --class encore getwindowname 2>/dev/null | head -1)
echo "[linux] window title: $window"
case "$window" in
  "$playing – "*) echo "[linux] ok: the window title shows the song" ;;
  *) echo "[linux] FAIL: the window title does not show the song" ;;
esac
playerctl -p "$name" next
wait $app
grep self-test /tmp/out
'
