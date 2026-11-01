# Features and their tests

Every feature (and every bug that was fixed) is listed here with the tests
that cover it. Add a row with each change, and run the matching tests before
calling it done. Releases also go through the owner's own testing.

**Test kinds**
- *unit / widget*: `flutter test test/unit test/widget` (offline, fast)
- *e2e*: the real app with real audio, the "listen journey" in
  `integration_test/app_test.dart`, step names shown in quotes:
  - Windows, with real key presses: `powershell -File tool/windows_keyboard_check.ps1`
  - Android phone, with background, lock screen and notification:
    `sh tool/android_background_check.sh <device>`
- *release*: the built release apps: `tool/android_release_check.sh`,
  `tool/windows_release_check.ps1`, `tool/check_apk_resources.sh`

## Playing music

| Feature | Platforms | Tests |
|---|---|---|
| Search result plays, then its radio | all | e2e "audio starts", "radio fills up next" |
| A song from a home section queues the rest of the section | all | e2e "section song plays" |
| Section "View all" lists every song | all | widget `player_features_test` "View all" |
| Next / previous; swipe right always goes to the previous song (button restarts after 3 s) | all | e2e "next track", "swipe right" |
| Shuffle is a mode: shuffles what's next, off restores the order, stays on for new songs, Play next stays next | all | widget `gestures_and_keys_test` group "shuffle" |
| Shuffle / repeat buttons show their state (orange + dot, pop, haptic on phones) | all | widget "the button shows its state" |
| "Couldn't play" says why when that helps: no connection, too slow, or YouTube's own reason (e.g. "This video is unavailable") | all | unit `player_test` "a song that can't play says why" |
| A song that can't play is skipped (max 3 in a row) when playback moves on by itself | all | e2e "unplayable song skipped" |
| The next song's stream link is looked up while a song plays, so skipping doesn't wait for YouTube | all | unit `player_test` "the next song is prepared" |
| The app opens where it was left: the queue, the song (paused, where it was), shuffle and repeat; nothing loads until it is played, and seeking first moves where it plays from | all | unit `session_test` |
| **Bug fixed:** a song stuck for good when its link stopped working (it expires, and changes with the IP address, e.g. Wi-Fi to mobile data), and dragging the seek bar did nothing: a refused link is renewed and the song goes on from there | all | unit `stream_test` "a refused link is renewed"; e2e "expired link renewed" |
| **Bug fixed:** a song that broke off anyway (no network for a moment) stayed stuck: it is loaded again from where it stopped (3 tries), Play or the seek bar loads it again, and the desktop player taking the break for the end no longer skips the song | all | unit `player_test`; e2e "seek works after a failure" |
| **Bug fixed:** a connection that went silent without closing hung the song (and the download queue) forever: dropped after 10 s and tried again; YouTube requests time out instead of spinning | all | unit `stream_test` "a connection that goes silent" |
| Seeking while a song loads is kept for when it is ready; the seek bar shows the song's length while it loads | all | unit `player_test` "a seek while the song loads"; widget `now_playing_test` "the seek bar shows the song's length" |
| **Bug fixed (Android):** a seek the stream couldn't serve never finished, which left the song loading for good | android | unit `player_test` "a seek that never completes"; Android e2e "seek works after a failure" |
| Album / playlist play buttons say so when offline | all | (manual) |

## Player screens

| Feature | Platforms | Tests |
|---|---|---|
| **Bug fixed:** a 2nd/3rd song from search showed the earlier song's art and title (players, notification, colour) | all | widget `now_playing_test`; e2e "search result N shown in the player" |
| Mini player: tap or swipe up opens the full player; swipe sideways skips | phones | widget "swipe up on the mini player", `swipe to skip` group |
| **Bug fixed:** the volume control disappeared when the full player opened (it covers the bar): a speaker beside like, whose slider slides out on hover; mute remembers the level across both. The art and the controls under it share one width | desktop | widget `now_playing_test` "the full player has the volume too" |
| Desktop player bar: click anywhere that isn't a control opens the full player | desktop | widget `now_playing_test` group "desktop player bar"; e2e (opens it that way) |
| Full player: swipe the artwork left/right for next/previous | all | widget `swipe to skip`; e2e "swipe left", "swipe right" |
| Full player: pull down to close (follows the finger, springs back) | phones | widget "pulling the song down follows the finger" |
| Lyrics sheet: drag up/down with the finger, snaps, swipe down / ⌄ / Back closes, follows the song | phones | widget group "full player on a phone"; e2e "swipe up: lyrics" |
| Lyrics / Up next side panel | desktop | e2e "lyrics load" |
| Lyrics: synced, tap a line to seek; "couldn't load" + Retry when offline | all | widget (offline Retry); e2e "lyrics load" |
| Seek bar stays enabled while a song loads (accessibility tree fix) | all | widget "the seek bar stays enabled" |
| **Bug fixed:** every song change flashed the placeholder before the new art: the old art stays until the new is ready; art shown for the first time fades in | all | widget `artwork_test` |
| Art is kept on disk (100 MB, least recently used goes first), so it shows at once after a restart; the next song's art is fetched ahead | all | unit `art_cache_test` |
| Swipe to skip turns pages: the next and previous songs sit beside the art (and the mini player) and follow the finger, so the new song is there at once (drawn only while it moves, and on desktop only inside the art's frame); at the end of the queue the song leaves and comes back; drags while it settles are ignored | all | widget `gestures_and_keys_test` "the next song slides into place", "a swipe carries the song off", "a drag while the song leaves" |
| Phones: the full player slides up from the bottom like a sheet (and back down) | phones | widget `now_playing_test` "slides up from the bottom" |
| **Bug fixed:** home cards overflowed with a larger system font size or a title in a taller script: the card grows with the font size and its lines keep their height | all | widget `media_card_test` |
| **Bug fixed (Android):** on 120 Hz phones (e.g. Samsung's adaptive refresh) animations ran at 60 fps once the finger lifted: the app asks for the screen's highest rate while it draws | android | measured on the phone (frame times, SurfaceFlinger) |
| **Bug fixed:** the app behind the full player was drawn with every frame of it (and of the swipe): once open, and until pulled down, the player covers it | all | widget `gestures_and_keys_test` "the app behind the open player is drawn only when pulled" |
| Full player draws cheaply: the backdrop has no offscreen layer, and the art no blurred shadow (a third of each frame while it moves) | all | measured on the phone (frame times) |
| **Bug fixed:** screen readers couldn't use the player's Song / Lyrics / Up next tabs or open home cards (bare gestures): they are buttons (tabs say which is selected); the desktop bar says it opens the player | all | widget "screen readers can use the player tabs", "screen readers can open a card" |
| Tabs fit narrow phones | phones | widget (no overflow in full player tests) |

## Song menu and sleep timer

| Feature | Platforms | Tests |
|---|---|---|
| Song menu: bottom sheet with the song on top (phones), pop-up under ⋯ (desktop) | all | widget `player_features_test` "song menu"; "⋯ on the last row opens a sheet" |
| Long-press (phones) / right-click (desktop) a song for its menu | all | widget group "song menu from the song itself" |
| Confirmations: Playing next, Added to Liked songs, Downloading… | all | widget "Liking says so" |
| Sleep timer in the ⋯ menu of the playing song; moon shows while on | all | widget "sleep timer is in the ⋯ menu" (phone + desktop) |
| Sleep timer: 15/30/45 min, 1 h, end of song; fades out, restores volume | all | unit `sleep_timer_test`; e2e "sleep timer: end of song", "fades and pauses" |
| Sleep timer works with the screen off | Android | e2e "sleep timer in background" |

## Search, home, library

| Feature | Platforms | Tests |
|---|---|---|
| **Bug fixed:** Space, K, L and arrows type in the search box (were taken as shortcuts) | desktop | e2e "real typing" (real key presses); widget "is typed, not a shortcut" |
| Esc or clicking elsewhere leaves the search box | desktop | widget "Esc leaves", "clicking elsewhere leaves" |
| Search box spans the page | all | widget "spans the page on desktop / phones" |
| **Bug fixed:** covers, lyric videos and other uploads couldn't be found (only official songs were searched): a Videos filter, like YouTube Music | all | widget `search_test` "narrowed to Videos"; live "videos and pasted links"; e2e "videos filter finds it", "video result plays" |
| Paste a YouTube / YouTube Music link (youtu.be, watch, shorts, music…) into search: that exact song | all | unit `links_test`; widget "a pasted link looks up its song"; e2e "pasted link finds the song", "pasted link plays" |
| A failed search shows Retry without an unhandled error | all | widget `search_test` (offline) |
| Suggestions, recent searches, filters; suggestion ↖ keeps typing | all | e2e "search results"; widget `shell_test` |
| Home feed, quick picks; Retry when offline | all | e2e "home feed loads"; widget `shell_test` |
| The home feed from last time shows at once while the new one loads, and offline (with Retry) | all | unit `home_cache_test`; widget `shell_test` "offline, home shows the feed from last time" |
| Artist and album pages | all | e2e "artist page", "album page", "album playback" |
| **Bug fixed:** an unreadable library came up empty with nothing said: the app says so, and the old file is kept (beside any kept before) | all | unit `library_test` "an unreadable file is reported"; widget `shell_test` "a problem found before the app shows" |
| Liked songs, history, downloads; saving can't be wiped by a crash | all | unit `library_test` group "saving" |
| **Bug fixed:** each song played re-encoded the whole library (~20 ms with big imported playlists, a dropped frame): only the changed part is encoded | all | unit `library_test` "a played song encodes only the history" |
| **Bug fixed:** closing the app lost the downloads not done yet (e.g. most of an album), with nothing said: they carry on the next time it opens | all | unit `downloads_test` |
| Downloads play offline; failures say so and leave no files; removing a playing download works | all | e2e "download", "offline playback"; widget `downloads_test` |

## Playlists

| Feature | Platforms | Tests |
|---|---|---|
| Make playlists (Library, desktop sidebar ＋), named on the spot | all | widget `playlists_test` "New playlist", "the sidebar lists playlists" |
| Add to playlist from any song's ⋯ / long-press / right-click menu (or a new one); "Already in" when it is | all | widget "Add to playlist from a song's menu" (phone + desktop); unit `library_test` group "playlists" |
| Remove a song; drag the handle to reorder (holding first works: no tooltip/menu takes the long-press) | all | widget "removed from the playlist", "reordered by dragging the handle" (phone + desktop) |
| Rename; delete after asking | all | widget "rename, then delete" |
| Playlists are saved with their songs, order and source | all | unit `library_test` "playlists are saved" |
| Import a public YouTube Music / YouTube playlist by link (exact songs, up to 1000; YouTube Music's own `RDCLAK…` playlists too) | all | unit `links_test`; e2e "youtube music playlist imported" |
| Import a public Spotify playlist or album by link: each song found on YouTube Music (songs, then videos for covers), unsure ones shown for a look and changeable; Spotify shares up to 100 songs without a login, and the page says when there are more | all | unit `playlist_import_test`; live "a public Spotify playlist imports", "a big Spotify playlist"; e2e "spotify playlist matched", "imported playlist plays" |
| A private playlist (or bad link) says so and keeps the link to fix | all | widget group "import page"; live (the owner's private playlist) |
| Pasting a playlist link into search opens the import | all | widget "pasting a playlist link into search" |
| Save a YouTube Music album or playlist page to your playlists | all | (manual) |
| Export: Open in YouTube (50 songs per link, saved there as a playlist); Copy song list ("Title - Artist" lines, for TuneMyMusic / Soundiiz) | all | unit `playlist_import_test` group "export"; widget "Copy song list" |

## Desktop and Android specifics

| Feature | Platforms | Tests |
|---|---|---|
| Keyboard: Space/K play-pause, ←/→ seek, Ctrl+←/→ songs, Ctrl+↑/↓ volume, L like, media keys | desktop | e2e "keyboard shortcuts" |
| Background playback, screen off | Android | e2e "background playback" |
| Notification / lock screen player: exactly previous, play/pause, next; no stop | Android | e2e host checks; release check |
| Release APK keeps the notification icons (v0.1.1 crash) | Android | `check_apk_resources.sh` (also in CI) |
| APK without the desktop player (mpv): 73 → 54 MB | Android | `check_apk_resources.sh` (also in CI) |
| Tests never touch the real app on the phone | Android | `android_background_check.sh` fails if it goes missing |
| **Bug fixed:** a range request YouTube refuses or cuts short is tried again (from where it stopped) instead of stalling the song | all | unit `stream_test` |
| **Bug fixed:** "1 song", not "1 songs" | all | widget "one song is \"1 song\"" |
| Linux tar.gz: launcher, icons, app metadata, `install.sh` / `--uninstall` for the user; plugin libraries search only their own folder (no build-folder RUNPATH) | Linux | CI "Check plugin library paths"; `linux_release_check.sh` (Ubuntu: install, play, uninstall) |
| Flatpak (`io.github.mohdaffankhan.Encore`) with libmpv built in (not released yet) | Linux | CI flatpak job (manual runs); `linux_release_check.sh` (install the bundle, play) |
| AUR `encore-music-bin` (command `encore-music`) (not released yet) | Linux | CI aur job, manual runs (makepkg, namcap, install); `linux_release_check.sh` (Arch: install, play) |
| Linux app id is `io.github.mohdaffankhan.Encore`; the library moves over from the old `dev.encore.app` folder once, never over an existing one | Linux | unit `storage_test` |
| Package versions (PKGBUILD, metainfo) match `pubspec.yaml` | Linux | CI test job |
