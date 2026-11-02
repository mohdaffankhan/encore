#!/bin/sh
# Inside the container, as a user (tool/linux_quit_check.sh): Encore plays
# a song, then its window is closed as a person closes it (the window
# manager's close), and Encore must end cleanly: exit code 0, not an abort
# (134), which desktops report as a crash.
mkdir -p ~/encore && tar -xzf /pkg/encore-linux-x64.tar.gz -C ~/encore
pulseaudio --start --exit-idle-time=-1 --load="module-null-sink sink_name=null" 2>/dev/null
exec dbus-run-session -- xvfb-run -a sh -c '
openbox > /dev/null 2>&1 &
sleep 1
~/encore/encore > /tmp/out 2>&1 &
app=$!
for _ in $(seq 30); do
  wmctrl -l 2>/dev/null | grep -q Encore && break
  sleep 1
done
sleep 4
# Play (the song left from last time, or the first on home): the media key.
name=$(playerctl -l 2>/dev/null | grep -i encore | head -1)
playerctl -p "$name" play 2>/dev/null
sleep 6
echo "[quit] playing: $(playerctl -p "$name" status 2>/dev/null)"
wmctrl -c Encore
for _ in $(seq 20); do
  kill -0 $app 2>/dev/null || break
  sleep 1
done
if kill -0 $app 2>/dev/null; then
  echo "[quit] FAIL: still running 20 s after its window was closed"
  kill -9 $app
else
  wait $app
  code=$?
  if [ $code = 0 ]; then
    echo "[quit] ok: closed cleanly (exit 0)"
  else
    echo "[quit] FAIL: exit code $code after its window was closed"
    tail -5 /tmp/out
  fi
fi
'
