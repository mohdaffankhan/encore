# Design

Encore: an ad-free YouTube Music client. Flutter: Android, Windows, Linux.

## Principles
- Premium and calm: near-black layers, Apple-style greys, white pill buttons,
  one warm accent (amber → coral) used sparingly. Players take their colour
  from the artwork.
- One typeface: Plus Jakarta Sans (bundled, SIL OFL), heavy weights for titles.
- No backend, no tracking. The app talks only to YouTube Music, LRCLIB,
  Spotify (importing a playlist) and GitHub (new versions).
- Signing in is optional; without it everything works, with the library
  only on the device.
- Plain Flutter state (`ValueNotifier`/streams), few dependencies.

## Brand
The mark, "Echo play", is a play button with two fading echoes behind it
("play it again"), in the amber → coral gradient on a dark tile.
`tool/icons.py` renders every platform's icons; `lib/ui/widgets/logo.dart`
draws the same mark in-app.

## Layout
- Desktop (≥ 900 px): sidebar (logo, Home/Search/Library, library shortcuts),
  content in a rounded panel, and a full-width player bar along the bottom
  (song · transport + seek · lyrics/queue/volume).
- Phone: bottom navigation with a floating mini player tinted by the artwork.
- Full player: artwork-coloured backdrop, big art, Song / Lyrics / Up next
  tabs (side by side on wide screens).
- Cards lift and show a play button on hover; carousels scroll with arrow
  buttons or mouse drag on desktop.

## Behaviour
- Tap a song in search → plays it, then fills "Up next" with its radio
  (like YouTube Music). Tap a song in a list → plays that list from there.
- When the queue runs out, it is extended with the radio of the last song.
- Search suggests as you type; recent searches are kept (removable).
- Every played song goes to History / Recently played; songs can be liked.

## Structure

Three layers; each only depends on the ones above it.

```
lib/
  main.dart, app.dart        startup; the MaterialApp
  models.dart                Track, MediaRef, Shelf, Collection, Artist
  api/                       network only, no Flutter (testable with plain Dart)
    innertube.dart           YouTube Music: home, search, suggestions, radio,
                             artist, album/playlist pages; the account's
                             library and its edits; play reports
    auth.dart                sign-in cookies, SAPISIDHASH signed requests
    clients.dart             InnerTube client versions
    stream.dart              audio streams (VISIONOS client, ranged reads)
    lyrics.dart              synced lyrics from LRCLIB
    spotify.dart             public Spotify playlists, for importing
  services/                  app state, no widgets
    player.dart              queue, radio, shuffle/repeat, seek/volume
    library.dart             liked, history, searches, downloads (one JSON file)
    downloads.dart           offline files and download queue
    account.dart             the YouTube Music sign-in, kept on the device
                             (DPAPI on Windows, dpapi.dart)
    youtube_sync.dart        two-way library sync with the account; play
                             reports
    track_stream.dart        a song's audio (song version for age-restricted
                             videos)
    updates.dart             new versions from GitHub; Android/Windows
                             install them
    youtube_audio_source.dart  feeds the player via ranged reads
    storage.dart             data folder (separate one for test builds)
  ui/
    shell.dart               per-tab navigation, sidebar / bottom bar, openPage()
    shortcuts.dart           keyboard + media keys
    theme.dart, art_colors.dart
    pages/                   home, search, library, collection, artist,
                             settings, sign-in, sync questions
    player/                  player bar, mini player, full player, controls,
                             lyrics, up next
    widgets/                 artwork, track tile + menu, cards, shelves, logo
```

## Keyboard (desktop)
Space / K play-pause · ← → seek 10 s · Ctrl+← → previous/next ·
Ctrl+↑ ↓ volume · L like · media keys while the window is focused.

## Performance
Measured in profile mode with `integration_test/perf_test.dart`
(90th-percentile frame time, build / raster):

| | Galaxy F23 (120 Hz, 8.3 ms budget) | Windows (60 Hz, 16.7 ms) |
|---|---|---|
| Scroll home | 1.8 / 6.2 ms | 0.8 / 5.6 ms |
| Open a page | 8.7 / 8.1 ms | 5.7 / 9.5 ms |
| Full player | 8.8 / 7.7 ms | 13.4 / 9.9 ms |

Choices that keep it smooth: a cheap fade page transition (not the desktop
zoom), plain ripples (not InkSparkle), no per-image fade animations, artwork
colour from an 8×8 decode instead of palette quantizing, a tiny stretched
image instead of a blur filter for the player backdrop, and repaint
boundaries around everything that updates with playback position.

## Resource use
- Artwork is requested at the size shown (YouTube serves 60–544 px) and decoded
  at display size; image cache capped at 48 MB.
- mpv's read-ahead buffer is 8 MB instead of 32 MB.
- Stream URLs and radio are fetched lazily; lyrics and art colours are cached.
- Audio is read in 1 MB range requests: YouTube throttles one long request
  to ~real time (~35 KB/s) but serves ranges at 1–4 MB/s, so songs start
  and seek quickly and a download takes seconds, not minutes.
- Release build on Windows: ~140 MB RAM with the home feed loaded.

## YouTube access (unofficial — may break)
- Metadata comes from YouTube Music's internal API (`music.youtube.com/youtubei/v1`,
  client `WEB_REMIX`) — the same one the YouTube Music website uses.
- Audio comes from the `VISIONOS` client of the player API. Most other clients now
  need a PO token and stop serving audio after ~1 MB. Mirrors yt-dlp's current
  defaults; when YouTube changes something, check yt-dlp's `_base.py` first.
- Signed in, the `WEB_REMIX` requests carry the account's cookies and a
  `SAPISIDHASH` header, as the website's do: home, radio, up next, likes,
  the library and its edits are the account's. Audio stays anonymous; each
  play is reported to the account separately (its playback stats URL), so
  it counts in history and recommendations.
- Sync is a three-way merge against what Encore and the account last agreed
  on. Changes go out one at a time, spaced and backed off; more than 20
  removals at once wait for the user; a playlist is never deleted on the
  account because it is missing in Encore; a page cut short fails the sync.
  Test builds (`ENCORE_TEST`) never sign in.

## Platform notes
- Android allows plain HTTP only to 127.0.0.1 (`network_security_config.xml`):
  the player reads through just_audio's local proxy.
- Android builds disable Kotlin incremental compilation: the project and the
  pub cache are on different drives here, which breaks its caches.

## Dependencies
`just_audio`, `just_audio_media_kit` + `media_kit_libs_windows_audio` / `media_kit_libs_linux` (desktop backend),
`just_audio_background` (Android notification), `path_provider` (data folder).

## Done
Offline downloads · synced lyrics · artist and album pages · search filters ·
keyboard shortcuts · system media controls (Windows SMTC / Linux MPRIS) ·
YouTube Music sign-in and library sync · updates from inside the app ·
CI builds (`.github/workflows/build.yml`) · tests on Windows, Android and
Linux (see README).
