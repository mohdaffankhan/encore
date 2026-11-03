<p align="center">
  <img src="assets/brand/icon_256.png" width="112" alt="Encore logo">
</p>

<h1 align="center">Encore</h1>

<p align="center">
  <b>An ad-free, open-source music player for YouTube Music.</b><br>
  No ads. No account. No tracking. For Android, Windows and Linux.
</p>

<p align="center">
  <a href="https://github.com/mohdaffankhan/encore/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/mohdaffankhan/encore?style=flat-square&color=ff8a4c"></a>
  <a href="https://github.com/mohdaffankhan/encore/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/mohdaffankhan/encore/total?style=flat-square&color=ff8a4c"></a>
  <a href="https://github.com/mohdaffankhan/encore/actions/workflows/test.yml"><img alt="Tests" src="https://img.shields.io/github/actions/workflow/status/mohdaffankhan/encore/test.yml?branch=main&label=tests&style=flat-square"></a>
  <a href="LICENSE"><img alt="License: GPL-3.0" src="https://img.shields.io/github/license/mohdaffankhan/encore?style=flat-square"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Android%20%7C%20Windows%20%7C%20Linux-informational?style=flat-square">
</p>

<p align="center">
  <a href="#download">Download</a> ·
  <a href="#features">Features</a> ·
  <a href="#install">Install</a> ·
  <a href="#faq">FAQ</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

<p align="center">
  <img src="docs/screenshots/desktop-player.png" width="100%" alt="The full player with synced lyrics">
</p>

<p align="center">
  <img src="docs/screenshots/desktop-home.png" width="49%" alt="Home">
  <img src="docs/screenshots/desktop-playlist.png" width="49%" alt="A playlist imported from Spotify">
  <img src="docs/screenshots/desktop-import.png" width="49%" alt="Importing a Spotify playlist">
  <img src="docs/screenshots/desktop-artist.png" width="49%" alt="An artist page">
</p>

## Download

**Android** 7.0 or later<br>
[**encore-android.apk**](https://github.com/mohdaffankhan/encore/releases/latest/download/encore-android.apk), for any phone · [How to install](#android)<br>
<sub>Smaller, for your phone's chip: [arm64-v8a](https://github.com/mohdaffankhan/encore/releases/latest/download/encore-android-arm64-v8a.apk) (most phones) · [armeabi-v7a](https://github.com/mohdaffankhan/encore/releases/latest/download/encore-android-armeabi-v7a.apk) (older phones) · [x86_64](https://github.com/mohdaffankhan/encore/releases/latest/download/encore-android-x86_64.apk). Not sure? Take the one above.</sub>

**Windows** 10 or 11<br>
[**Installer**](https://github.com/mohdaffankhan/encore/releases/latest/download/encore-windows-setup.exe) · [Portable zip](https://github.com/mohdaffankhan/encore/releases/latest/download/encore-windows-portable.zip) · [How to install](#windows)

**Linux** x64<br>
[**AppImage**](https://github.com/mohdaffankhan/encore/releases/latest/download/Encore-x86_64.AppImage), just run it · [tar.gz](https://github.com/mohdaffankhan/encore/releases/latest/download/encore-linux-x64.tar.gz), needs libmpv · [How to install](#linux)

Older versions and what changed in each: [Releases](https://github.com/mohdaffankhan/encore/releases).

## Features

**Listen**
- Everything on YouTube Music: songs, albums, artists, playlists, and
  videos such as covers and lyric videos
- Paste a YouTube or YouTube Music link into search to play that exact song
- Song radio, up next, shuffle and repeat; no gaps between songs
- Synced lyrics that follow the song; tap a line to jump there
- Equalizer with presets, and playback speed from 0.5× to 2×
- Sleep timer (15 minutes to an hour, or the end of the song) that fades out
- Swipe the player sideways for the next or previous song; on phones, swipe
  up for lyrics and down to close

**Your library, on your device**
- Likes, history and your own playlists (add, reorder, rename), each one
  searchable and sortable
- Import public playlists from **YouTube Music**, **YouTube** or **Spotify**
  by pasting their link
- Save the queue as a playlist; share songs, albums and playlists
- Downloads for offline listening (on Android they carry on after you close
  Encore)

**Everywhere**
- Six themes: Ember, Ocean, Forest, Orchid, Rose and Graphite
- Android: plays in the background, with controls (and a ♡) in the
  notification panel and on the lock screen
- Windows and Linux: your system's media controls and media keys, the song
  in the window title; on Windows, keeps playing from the tray
- Works with screen readers (TalkBack, Narrator, Orca)

## Install

### Android

1. Download **`encore-android.apk`** on your phone and open it. If asked,
   allow your browser or file manager to *install unknown apps*.
2. Open Encore and tap **Allow** when it asks to show notifications: that is
   what puts the player in your notification panel.

To update, install the new APK over the old one. Your library stays.

The per-chip APKs are about a third of the size. Not sure which chip your
phone has? Take `encore-android.apk`, which works on all of them; you can
switch between it and a per-chip one any time, keeping your library.

### Windows

Run **`encore-windows-setup.exe`**. It needs no admin rights and adds Encore
to the Start menu. If SmartScreen says it protected your PC, click
**More info → Run anyway** (the installer isn't code-signed).

Prefer no installer? Unzip **`encore-windows-portable.zip`** anywhere and run
`encore.exe`.

### Linux

**AppImage** (the simplest): download `Encore-x86_64.AppImage`, make it
runnable and open it. Everything it needs is inside; nothing to install.

```sh
chmod +x Encore-x86_64.AppImage
./Encore-x86_64.AppImage
```

It needs a 2024 or newer Linux (glibc 2.39: Ubuntu 24.04, Fedora 40,
Debian 13 and later). If it doesn't open, your system may lack FUSE,
which AppImages use: run it with `--appimage-extract-and-run` instead.

**tar.gz** (adds Encore to your app menu): Encore needs `libmpv` for sound:

```sh
sudo apt install libmpv2      # Debian, Ubuntu (libmpv1 on older releases)
sudo dnf install mpv-libs     # Fedora
sudo pacman -S mpv            # Arch
```

Then extract the download and run its installer, which needs no root and
adds Encore to your app menu:

```sh
mkdir encore && tar -xzf encore-linux-x64.tar.gz -C encore
./encore/install.sh           # ./encore/install.sh --uninstall to remove
```

To update, do the same with the new download.

Encore on Flathub (so GNOME Software and KDE Discover list it, and it
updates by itself) and an AUR package are on the way.

## Keyboard shortcuts

| Key | Action |
|---|---|
| Space or K | Play / pause |
| Ctrl + → / ← | Next / previous song |
| → / ← | Forward / back 10 seconds |
| Ctrl + ↑ / ↓ | Volume |
| M | Mute |
| Ctrl + S / Ctrl + R | Shuffle / repeat |
| L | Like the song |
| Ctrl + K or / | Search |
| Alt + ← | Back |
| Ctrl + , | Settings |
| Esc | Close the player |

Press **?** in Encore to see them all. Media keys work too.

## FAQ

**Is it free? Are there ads?**
Free, with no ads, ever. Encore is open source (GPL-3.0) and nobody makes
money from it.

**Do I need a Google or YouTube account?**
No. Encore doesn't sign in to anything.

**What does Encore know about me?**
Nothing leaves your device except the searches and songs you ask
YouTube Music for (and lyrics from [LRCLIB](https://lrclib.net)). There's no
analytics and no Encore server. Your likes, playlists, history and downloads
are kept in a file on your device.

**Can I import my private playlists or Liked songs?**
Not yet: importing works by link, which only reaches public playlists.
Make a playlist public (or *unlisted* on YouTube), import it, then make it
private again. Spotify shares only the first 100 songs of a playlist without
signing in.

**A song won't play.**
YouTube changes how it serves music now and then, and Encore has to follow.
If songs stop playing, check for a newer version, or
[open an issue](https://github.com/mohdaffankhan/encore/issues).

**Will there be an iPhone or Mac version?**
Not for now: they need a paid Apple developer account to install apps.

## Contributing

Bug reports, ideas and pull requests are welcome. See
[CONTRIBUTING.md](CONTRIBUTING.md) for building Encore, running the tests
and how releases are checked. [FEATURES.md](FEATURES.md) lists every feature
with the tests that cover it.

## Thanks to

[Flutter](https://flutter.dev),
[mpv](https://mpv.io) and [media_kit](https://github.com/media-kit/media-kit),
[just_audio](https://pub.dev/packages/just_audio),
[audio_service](https://pub.dev/packages/audio_service),
[LRCLIB](https://lrclib.net) for lyrics, and the
[yt-dlp](https://github.com/yt-dlp/yt-dlp) project, whose work on YouTube's
streams Encore follows.

## License

Encore is free software under the [GNU GPL v3.0](LICENSE).

Encore is unofficial. It isn't affiliated with, endorsed by or sponsored by
YouTube, Google or Spotify. It uses YouTube Music's internal API, which can
change at any time.
