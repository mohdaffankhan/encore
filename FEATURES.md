# Features and their tests

Every feature (and every bug that was fixed) is listed here with the tests
that cover it. Add a row with each change, and run the matching tests before
calling it done. Releases also go through the owner's own testing.

**Test kinds**
- *unit / widget*: `flutter test test/unit test/widget` (offline, fast);
  GitHub Actions runs them, and the analyzer, on every push to main and
  every pull request (`.github/workflows/test.yml`)
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
| Streaming and download quality: High (best), Normal (about half the data), Low (least); Android streams at Low on mobile data unless turned off | all | unit `settings_test` |
| A song that can't play is skipped (max 3 in a row) when playback moves on by itself | all | e2e "unplayable song skipped" |
| No gap between songs: the next song is lined up in the player as one plays (swapped when the queue, repeat or sleep timer changes what is next), and the player moves on by itself; a song whose stream broke off goes on from where it stopped instead of skipping | all | unit `player_test` group "no gap between songs"; self-test "no gap" (release checks); e2e "no gap" (Windows, Android); Linux self-test "no gap" (`linux_media_check.sh`, `linux_appimage_check.sh`) |
| The next song's stream link is looked up while a song plays, so skipping doesn't wait for YouTube | all | unit `player_test` "the next song is prepared" |
| The app opens where it was left: the queue, the song (paused, where it was), shuffle and repeat; nothing loads until it is played, and seeking first moves where it plays from | all | unit `session_test` |
| Which YouTube apps Encore asks for songs comes from `config/youtube_clients.json` in the repo, read at start (last good copy kept): a fix there reaches every install without a release; only client names, versions and identities are taken; a client YouTube refuses makes way for the next, then the built-in one | all | unit `clients_test` (also checks the repo's file) |
| **Bug fixed:** a song stuck for good when its link stopped working (it expires, and changes with the IP address, e.g. Wi-Fi to mobile data), and dragging the seek bar did nothing: a refused link is renewed and the song goes on from there | all | unit `stream_test` "a refused link is renewed"; e2e "expired link renewed" |
| **Bug fixed:** a song that broke off anyway (no network for a moment) stayed stuck: it is loaded again from where it stopped (3 tries), Play or the seek bar loads it again, and the desktop player taking the break for the end no longer skips the song | all | unit `player_test`; e2e "seek works after a failure" |
| Music plays on when the phone switches between mobile data and Wi-Fi (both ways), and the next song loads on the new network | Android | `tool/android_network_switch_check.sh` (real switch on the phone) |
| **Bug fixed:** a connection that went silent without closing hung the song (and the download queue) forever: dropped after 10 s and tried again; YouTube requests time out instead of spinning | all | unit `stream_test` "a connection that goes silent" |
| Seeking while a song loads is kept for when it is ready; the seek bar shows the song's length while it loads | all | unit `player_test` "a seek while the song loads"; widget `now_playing_test` "the seek bar shows the song's length" |
| **Bug fixed (Android):** a seek the stream couldn't serve never finished, which left the song loading for good | android | unit `player_test` "a seek that never completes"; Android e2e "seek works after a failure" |
| Settings page (desktop sidebar, the gear on the phone's home, Ctrl+,): quality, save data on mobile, storage used by downloads and artwork (remove all / clear), version, source, shortcuts | all | widget "Ctrl + , opens settings", "the gear on home opens settings"; unit `downloads_test` "every download can be removed" |
| Album / playlist play buttons say so when offline | all | (manual) |

## Player screens

| Feature | Platforms | Tests |
|---|---|---|
| **Bug fixed:** a 2nd/3rd song from search showed the earlier song's art and title (players, notification, colour) | all | widget `now_playing_test`; e2e "search result N shown in the player" |
| Mini player: tap or swipe up opens the full player; swipe sideways skips | phones | widget "swipe up on the mini player", `swipe to skip` group |
| **Bug fixed:** the volume control disappeared when the full player opened (it covers the bar): a speaker beside like, whose slider slides out on hover; mute remembers the level across both. The art and the controls under it share one width | desktop | widget `now_playing_test` "the full player has the volume too" |
| **Bug fixed:** the desktop player bar overflowed in a window about 1000 px wide: the volume slider shortens and the full screen button goes when short of room | desktop | widget `now_playing_test` "it fits a window N px wide" |
| Desktop player bar: click anywhere that isn't a control opens the full player | desktop | widget `now_playing_test` group "desktop player bar"; e2e (opens it that way) |
| Full player: swipe the artwork left/right for next/previous | all | widget `swipe to skip`; e2e "swipe left", "swipe right" |
| Full player: pull down to close (follows the finger, springs back) | phones | widget "pulling the song down follows the finger" |
| Lyrics sheet: drag up/down with the finger, snaps, swipe down / ⌄ / Back closes, follows the song | phones | widget group "full player on a phone"; e2e "swipe up: lyrics" |
| Up next: drag the handle to reorder (desktop: shown on hover), "Remove from queue" in the song's menu (it stays out when shuffle is turned off) | all | unit `player_test` group "up next"; widget "a song can be taken out of up next" |
| Up next: "Save queue" saves the whole queue (the current song too) as a new playlist; "Clear queue" empties what's up next (the song plays on; it stays cleared when shuffle is turned off) | all | unit `player_test` "clearing up next…"; widget "up next saves the queue as a playlist, and clears" |
| Playback speed (0.5× to 2×, same pitch) in the player's ⋯ menu, shown there while not normal; kept for every song and the next time | all | unit `player_test` "the speed setting…", `settings_test`; widget "playback speed is in the ⋯ menu"; e2e "playback speed 1.5×" (Windows, Android) |
| Liked songs, History, Downloads and playlists: search (title, artist or album) and sort (their own order, title, artist, album); a song plays the list as shown; playlists are reordered by hand only in their own order | all | widget `song_lists_test` |
| Share a song (⋯ menu), an album or YouTube playlist (header), or one of your playlists (its options: links that play it on YouTube, 50 songs a link): Android's share sheet; desktop copies it and says "Link copied" | all | widget `share_test`; share sheet opened on the phone (ChooserActivity on top) |
| Named themes (Ember, Ocean, Forest, Orchid, Rose, Graphite; all dark) in Settings: accent, brand gradient and a tint in the background layers; switching redraws the app in place and is kept | all | widget `themes_test` |
| Equalizer (5 bands, ±12 dB; presets Flat, Bass boost, Treble boost, Vocal, Rock, Pop, Electronic, Acoustic) in Settings and the player's ⋯ menu, kept: Android's system equalizer; desktop FFmpeg's `equalizer` in mpv (a small patch to just_audio_media_kit, in third_party/); speed no longer uses mpv's filters, so the two don't undo each other | all | widget `equalizer_test`; e2e "equalizer" (mpv has the filter; the phone's bands have the gains) |
| **Screen readers (pass of every screen):** every button is named (the big Play, home's scroll arrows, the bar's artwork, search boxes, settings switches read with their row); tap targets at least 48 px on phones (mini player Play, the Song / Lyrics / Up next tabs, the artist under the song, sort and search in lists); header text readable on its colour | all | widget `accessibility_test` (Flutter's label, tap-size and contrast checks on 9 screens, phone and desktop) |
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
| Search: ↓ / ↑ go through the suggestions (or recent searches), Enter searches the picked one, Esc drops it then leaves the box; ↓ moves into the results | desktop | widget "↓ / ↑ pick a suggestion", "Esc first drops the picked suggestion" |
| More keys, as in Spotify: Esc closes the full player, Alt+← and the mouse's back button go back, Ctrl+K / Ctrl+F / / search from anywhere, Ctrl+S shuffle, Ctrl+R repeat, M mute, Ctrl+/ lists them all; the mouse wheel over the volume turns it | desktop | widget group "desktop keys"; unit `player_test` "unmuting goes back" |
| Windows media controls: the overlay (volume / media keys), lock screen and the keyboard's media keys work with Encore in the background (Windows sends them to it; no key is grabbed), showing the song, art, play state and position; seeking from the overlay | Windows | unit `windows_media_controls_test`; `windows_release_check.ps1` (Windows shows the song; the Next media key moves on exactly one, also with another app in front) |
| The window title shows the song while it plays ("Get Lucky – Daft Punk"), as in Spotify | desktop | unit `desktop_window_test`; `linux_media_check.sh` (Linux window title) |
| The window opens where it was left: size, place (Windows, and X11 on Linux), maximized; not off a screen that is gone | desktop | (checked by hand on Windows) |
| Tray icon: closing the window keeps the music playing (Settings can turn it off); click to bring Encore back, right-click for play / pause, next, previous, quit; opening Encore again shows the running one | Windows | unit `desktop_window_test` (tray menu, setting); (checked by hand: close hides, second start hands over) |
| Linux media controls (MPRIS): the desktop's player widget, playerctl and headset buttons show and control Encore | Linux | `linux_media_check.sh` (Docker: the desktop sees the song; playerctl next moves on one) |
| Background playback, screen off | Android | e2e "background playback" |
| Notification / lock screen player: previous, play/pause, next, and like (♡, filled when liked; a media-session button, drawn by Android 13+); no stop. The collapsed view's buttons stay valid on Android 12 and older | Android | unit `media_session_test`; e2e host checks; release check (media panel screenshot) |
| Swiping Encore away from the recent apps stops the music and its notification (as in Spotify) | Android | release check "swiping it from recents stops the music" |
| Release APK keeps the notification icons (v0.1.1 crash) | Android | `check_apk_resources.sh` (also in CI) |
| Downloads go on after Encore is closed (swiped away; the music stops as before), with a progress notification ("Downloading 2 of 5", the song, a bar; at most one update a second, shown at once) and "Downloaded 5 songs" at the end when Encore is off screen | Android | unit `download_notice_test`; `tool/android_downloads_check.sh` (real close on the phone) |
| APKs per chip type (arm64-v8a, armeabi-v7a, x86_64; ~17-21 MB) besides the universal one (54 MB), all with the same version code, so they install over each other and test builds | Android | `tool/android_apks.sh` (chips and version code of each; in CI); release check installs the phone's own one over the universal |
| APK without the desktop player (mpv): 73 → 54 MB | Android | `check_apk_resources.sh` (also in CI) |
| Tests never touch the real app on the phone | Android | `android_background_check.sh` fails if it goes missing |
| **Bug fixed:** a range request YouTube refuses or cuts short is tried again (from where it stopped) instead of stalling the song | all | unit `stream_test` |
| **Bug fixed:** "1 song", not "1 songs" | all | widget "one song is \"1 song\"" |
| Linux tar.gz: launcher, icons, app metadata, `install.sh` / `--uninstall` for the user; plugin libraries search only their own folder (no build-folder RUNPATH) | Linux | CI "Check plugin library paths"; `linux_release_check.sh` (Ubuntu: install, play, uninstall) |
| **Bug fixed:** the Linux packages carried package:jni's library (Android only), which CI linked to Java's `libjvm.so`: unused, but it stopped the AppImage build; it is left out | Linux | `make_tarball.sh`; `linux_media_check.sh`, `linux_appimage_check.sh` |
| Linux AppImage: one file with libmpv (and what it needs) inside: nothing to install on a desktop Linux; built from the tar.gz in CI (linuxdeploy, pinned) | Linux | `tool/linux_appimage_check.sh` (Fedora, built on Ubuntu, no libmpv: plays, media controls, window title, Next); in `release_check.sh` |
| Closing Encore's window on Linux while music plays ends it cleanly (no crash report); the self-test shuts the player down before it exits (it aborted on Linux, leaving a ~600 MB crash dump each check) | Linux | `tool/linux_quit_check.sh`; `linux_media_check.sh` "ended cleanly" |
| Flatpak (`io.github.mohdaffankhan.Encore`, GNOME 51 runtime) with libmpv built in, published through Flathub (not as a file on the release, which would never update); Flathub's manifest made for a published release (`tool/flathub_update.sh`) | Linux | CI flatpak job (every tag); `release_check.sh` builds it from the draft (`tool/flatpak_build.sh`) and plays it on Fedora with Flatpak (`linux_release_check.sh`); Flathub's linter (manifest, metainfo) |
| **Bug fixed (release check):** on Windows the packaging files were checked out with Windows line endings, so the AUR check asked pacman for "libglvnd"; and the local Flatpak build reused an older Encore build (cached by file name). Packaging files are always LF now (.gitattributes), and the build goes by the tar.gz's checksum | Linux | `release_check.sh` (AUR and Flatpak on the v0.2.0 draft: version 0.2.0, plays) |
| **Bug fixed (release check):** the Android check tapped the home feed's first "Title / Artist" item, which with a song restored at startup (or a feed without song rows) was the mini player, so nothing played; it now searches for a song and plays the top result. The self-test waited on player calls (mpv's seek can stall while a link is renewed) and hung with nothing said; it now waits up to 60 s for what is heard instead | Android, desktop | `android_release_check.sh` (draft APK: plays, background, notification, swipe-away); Windows release check |
| AUR `encore-music-bin` (command `encore-music`): ready, on hold until the owner can make an AUR account (registrations closed); then `tool/aur_update.sh` after each release | Linux | CI aur job (every tag: makepkg, namcap, install); `linux_release_check.sh` (Arch: install, play) |
| Linux app id is `io.github.mohdaffankhan.Encore`; the library moves over from the old `dev.encore.app` folder once, never over an existing one | Linux | unit `storage_test` |
| Package versions (PKGBUILD, metainfo) match `pubspec.yaml` | Linux | CI test job |
| **Bug fixed:** Settings opened on top of the current tab, which kept showing it, so Home or Library seemed stuck on Settings: on desktop Settings is a place of its own in the sidebar (highlighted while open), left by picking anything else there; the sidebar headings are readable (contrast 4.5:1) | desktop | widget `shell_test` "Settings is a place of its own", `accessibility_test` "desktop: settings" |

## YouTube Music account (branch youtube-account, not released)

| Feature | Platforms | Tests |
|---|---|---|
| Optional sign-in from Settings: Google's own page in the app (Android WebView, a WebView2 / WebKitGTK window on desktop); Encore never sees the password | all | widget `account_test` "signing in shows who is signed in"; manual: Windows sign-in check 2026-11-14 |
| Desktop: "Sign in with your browser": paste a Cookie header or cookies.txt; empty or wrong text is refused in the dialog | Windows, Linux | unit `account_test` "a pasted …"; widget `account_test` group "signing in with a browser" |
| Signed-in requests carry the cookies and a SAPISIDHASH Authorization (time + sha1 of time, SAPISID, origin), X-Origin and X-Goog-AuthUser; signed out, none of it | all | unit `account_test` "SAPISIDHASH …", "signing in checks with YouTube…", "signed out, requests carry no sign-in" |
| A sign-in is checked with YouTube first: refused, incomplete or offline sign-ins say so and keep what was before | all | unit + widget `account_test` "refused", "incomplete", "offline while signing in" |
| Cookies YouTube replaces in its replies are used from then on and saved (a malformed one doesn't lose the others) | all | unit `account_test` "cookies YouTube replaces…", "a malformed Set-Cookie…" |
| A sign-in that ended (signed out elsewhere, expired) is noticed, confirmed once with YouTube, said once, and Encore carries on signed out; server errors and one odd reply don't end it | all | unit `account_test` "a sign-in that ended…", "one signed-out reply alone…", "server errors…", "many signed-out replies make one check" |
| The sign-in is kept in the system's secret store (a private file where there is none), read back at start and checked; broken or unreadable: signed out | all | unit `account_test` "a saved sign-in is used after a restart", "a broken or unreadable store…" |
| Signing out asks first, keeps the library, forgets the sign-in, the sign-in page's cookies and the home feed made for the account; replies to requests made before can't bring it back | all | unit `account_test` "signing out forgets…", "a reply arriving after…"; widget "signing out asks first" |
| Brand channels: Switch channel lists the account's own and brand channels (not other Google accounts); requests then go as that channel (X-Goog-PageId, onBehalfOfUser), kept on restart | all | unit `account_test` "a brand channel…", "channels: own and brand…" |
| Home reloads for the new account when signing in or out; a feed loaded for the old account isn't saved | all | unit `account_test` "signing out forgets…"; widget `account_test` |
| Account rows, signed in, ended, and the paste dialog work with screen readers | all | widget `accessibility_test` "settings, signed in", "settings, sign-in ended", "sign in with a browser" |
| **Bug fixed:** Home's pull-to-refresh and the artist, album and Settings retry/re-measure handed setState a Future (a debug-build error) | all | widget `account_test` "signing in shows who is signed in" |
| Signed in, a song liked or unliked in Encore (anywhere: menu, player, keys) is liked or unliked on the account; signed out or ended, nothing is sent | all | unit `youtube_sync_test` group "likes" |
| Changes to the account wait in an outbox kept on disk: one at a time, in order, spaced out (no bursts); offline they wait and go later (also after a restart), retried with growing waits; a song YouTube refuses is dropped; only the last word per song goes; signing out drops them | all | unit `youtube_sync_test` "offline: kept…", "after a failure…", "only the last word…", "refuses…", "signing out drops…" |
| Plays count on the account (its history and recommendations) once a song is heard 30 s (half, if shorter): skips don't count, repeats do, seeking back doesn't count twice; failures are tried twice more | all | unit `youtube_sync_test` group "plays" |
| Play reports go only to YouTube's own https stats address, signed in, as the website sends them (ver, c, a random cpn) | all | unit `youtube_sync_test` group "the play report itself" |
| Two-way sync with the account: liked songs, the account's own playlists (made, renamed, songs added, removed, moved, deleted), saved albums and playlists, followed artists; Encore's changes go at once through the outbox, the account's come with each sync (on signing in, at start, every 30 min, Sync now) | all | unit `library_sync_test` group "syncing with the account" |
| Merging against what both last agreed: added on either side is kept, removed on either side goes; the first sync (and after signing in again) only combines; the agreed state is kept on disk, and updated as each change is accepted (a song liked in Encore and unliked on YouTube Music stays unliked) | all | unit `library_sync_test` group "merging", "the first sync combines…", "…stays unliked", "…stays removed", "…stays unfollowed", "what was agreed is kept on disk…" |
| Playlist order: the account's, unless only Encore's changed; moves sent as the fewest moves (songs not in the longest run already in order); a song removed takes all its duplicate entries | all | unit `library_sync_test` "moves: the fewest…", "songs added, removed, renamed and moved…", "a song removed takes all its entries…" |
| A playlist deleted on one side is deleted on the other only if unchanged there since; changed, it is kept (and made there again); one deleted before it was made there isn't made; songs added while it is being made follow it | all | unit `library_sync_test` "deleted in Encore…", "deleted on the account…", "a playlist deleted before…", "songs added while…" |
| A sync waits while changes are still to be sent, and changes nothing if offline, signed out meanwhile, or the library changed during it; others' playlists saved on the account are saved playlists in Encore, not Encore playlists; artists are followed by their channel | all | unit `library_sync_test` "while changes wait…", "offline…", "signed out meanwhile…", "someone else's playlist…", "an artist whose channel differs…" |
| Library: "Albums and playlists" (saved) and "Artists" (followed) sections, shown once there are any; signed in, the sync status ("Synced … 5 min ago", changes waiting, couldn't sync) and Sync now, also in Settings | all | widget `library_account_test` group "Library", "sync status says…", "Settings, signed in…"; `accessibility_test` "library, signed in, …" |
| Save to library (bookmark) on albums and others' playlists; Follow on artist pages (work signed out too, kept on the device) | all | widget `library_account_test` "Save to library…", "Follow…" |
| Add to playlist button next to like in the full player and the desktop player bar (filled once the song is in a playlist); a new playlist can be made from it | all | widget `library_account_test` group "Add to playlist in the player" |
| Play something on Home: a radio (made for the user when signed in) from a random song they like or played (twice as likely) or from the feed; hidden with nothing to start from | all | widget `library_account_test` group "Play something" |
| Brand channels: the channel list is the signed-in account's own section (YouTube lists other Google accounts as sections of their own, and every entry has a sign-in token) | all | unit `account_test` "channels: own and brand…" (fixture shaped as the real reply) |
| **Bug fixed (found by the live check):** an account's own playlist was read with YouTube's suggestions below it as its songs (#playsong: 37 for 30); only the playlist's own song shelf and its "load more" pages are read now | all | unit `library_sync_test` "the account's suggestions…", "long playlists and liked songs come in full…" |
| **Bug fixed (found by the live check):** play reports got no stats address ("The page needs to be reloaded"): the player is asked with a recent player version (a week before today, in days since 1970) | all | unit `youtube_sync_test` "the player is asked with a recent player version…" |
| Live check against a real test account (by hand, `test/live/account_sync_live_test.dart`): playlist made, added to, moved, removed from, renamed, deleted; a song liked and unliked; an album saved and removed; an artist followed and unfollowed; a play counted; a full sync into an empty library: everything taken, nothing sent; the account left as it was | all | live, passed 2026-11-14 |
| Linux signs in with "Sign in with your browser" only: the sign-in window would link WebKitGTK into Encore, so it wouldn't start without it (the plugin is a Windows-only copy in `third_party/desktop_webview_window`) | Linux | widget `account_test` "Linux (no sign-in window)…"; Docker Linux build (`tool/linux_build.sh`) |
| **Bug fixed (found by a new test):** a change sent while a sync was fetching the account could be undone by that sync (its copy of the account was from before); a sync that sees anything change or go out meanwhile now merges nothing and says so | all | unit `library_sync_test` "the library changed during a sync…" |
| A playlist made on the account from Encore (e.g. an import of 1000 songs) is made with its first 50 songs and linked at once; the rest are added 50 at a time through the outbox, so going offline part way never makes it twice | all | unit `library_sync_test` "a big playlist…", "offline part way through filling…" |
| **Bug fixed:** desktop sidebar places (Liked songs, Downloads, History, playlists) piled up on each other, so back went through all of them; each now opens over Library alone (back goes to Library), and the one showing isn't opened again | Windows, Linux | widget `shell_test` "desktop: sidebar places replace each other…" |
| Play something moved by the greeting: a button at the end of the greeting row on desktop, an icon by search and settings on phones (it was a large button under the greeting) | all | widget `library_account_test` "phone: an icon…", "desktop: a button at the end of the greeting row" |
| The first sync after signing in asks first: what goes to YouTube Music (liked songs, playlists and their songs, saved, artists), what comes into Encore, about how long sending takes; nothing is sent or changed until "Sync"; "Sign out instead" signs out with nothing sent; asked again if closed before answering; not asked when Encore has nothing to send | all | unit `library_sync_test` group "the first sync asks first", "nothing in Encore to send: not asked"; widget `library_account_test` group "the first sync question"; `accessibility_test` "first sync question" |
| Sending shows its progress: a bar and "Sending to YouTube Music: 10 of 40", that it carries on next time if Encore is closed (long runs), "Waiting for a connection" with Try now when offline; after a restart with changes waiting, says it carries on from where it left off | all | unit `library_sync_test` group "progress"; widget `library_account_test` group "sending, shown"; `accessibility_test` "library, sending to YouTube Music" |
| Age-restricted songs (music videos, nearly always: Encore streams signed out, and YouTube plays them only to signed-in adults in its own apps) play as their song version (same title without "(Official Video)" and the like, same artist, about as long), said once; downloads too; with none, "Couldn't play": "it's age-restricted, and YouTube plays it only in its own apps" instead of "Sign in to confirm your age" | all | unit `age_restricted_test`; live `test/live/age_restricted_live_test.dart` (passed 2026-11-14: two restricted videos played as their song versions) |
| Android, by hand on the owner's phone (build 23, 2026-11-14): in-app Google sign-in worked; first sync asked, then took the account's 712 liked songs and #playsong (30) in and sent the phone's 7 liked songs up (719 on both sides); personalised Home; signed in after a reinstall; Android e2e and release check passed signed in | Android | manual + `tool/android_background_check.sh`, `tool/android_release_check.sh` |
