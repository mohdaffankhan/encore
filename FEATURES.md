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
| A song that can't play is skipped (max 3 in a row) when playback moves on by itself | all | e2e "unplayable song skipped" |
| Album / playlist play buttons say so when offline | all | (manual) |

## Player screens

| Feature | Platforms | Tests |
|---|---|---|
| **Bug fixed:** a 2nd/3rd song from search showed the earlier song's art and title (players, notification, colour) | all | widget `now_playing_test`; e2e "search result N shown in the player" |
| Mini player: tap or swipe up opens the full player; swipe sideways skips | phones | widget "swipe up on the mini player", `swipe to skip` group |
| Desktop player bar: click anywhere that isn't a control opens the full player | desktop | widget `now_playing_test` group "desktop player bar"; e2e (opens it that way) |
| Full player: swipe the artwork left/right for next/previous | all | widget `swipe to skip`; e2e "swipe left", "swipe right" |
| Full player: pull down to close (follows the finger, springs back) | phones | widget "pulling the song down follows the finger" |
| Lyrics sheet: drag up/down with the finger, snaps, swipe down / ⌄ / Back closes, follows the song | phones | widget group "full player on a phone"; e2e "swipe up: lyrics" |
| Lyrics / Up next side panel | desktop | e2e "lyrics load" |
| Lyrics: synced, tap a line to seek; "couldn't load" + Retry when offline | all | widget (offline Retry); e2e "lyrics load" |
| Seek bar stays enabled while a song loads (accessibility tree fix) | all | widget "the seek bar stays enabled" |
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
| Suggestions, recent searches, filters; suggestion ↖ keeps typing | all | e2e "search results"; widget `shell_test` |
| Home feed, quick picks; Retry when offline | all | e2e "home feed loads"; widget `shell_test` |
| Artist and album pages | all | e2e "artist page", "album page", "album playback" |
| Liked songs, history, downloads; saving can't be wiped by a crash | all | unit `library_test` group "saving" |
| Downloads play offline; failures say so and leave no files; removing a playing download works | all | e2e "download", "offline playback"; widget `downloads_test` |

## Desktop and Android specifics

| Feature | Platforms | Tests |
|---|---|---|
| Keyboard: Space/K play-pause, ←/→ seek, Ctrl+←/→ songs, Ctrl+↑/↓ volume, L like, media keys | desktop | e2e "keyboard shortcuts" |
| Background playback, screen off | Android | e2e "background playback" |
| Notification / lock screen player: exactly previous, play/pause, next; no stop | Android | e2e host checks; release check |
| Release APK keeps the notification icons (v0.1.1 crash) | Android | `check_apk_resources.sh` (also in CI) |
| Tests never touch the real app on the phone | Android | `android_background_check.sh` fails if it goes missing |
