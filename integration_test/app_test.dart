import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:encore/api/stream.dart';
import 'package:encore/main.dart' as app;
import 'package:encore/models.dart';
import 'package:encore/services/downloads.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/player.dart';
import 'package:encore/services/sleep_timer.dart';
import 'package:encore/services/youtube_audio_source.dart';
import 'package:encore/ui/pages/collection_page.dart';
import 'package:encore/ui/pages/home_page.dart';
import 'package:encore/ui/pages/import_page.dart';
import 'package:encore/ui/player/player_ui.dart';
import 'package:encore/ui/shell.dart';
import 'package:encore/ui/shortcuts.dart';
import 'package:encore/ui/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

// End-to-end journey through the real app: real network, real audio.
// Run on each platform with:
//   flutter test integration_test --dart-define=ENCORE_TEST=true -d <device>
// ENCORE_TEST keeps the test's likes/history/downloads apart from the user's.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('listen journey', (tester) async {
    await app.main();
    await tester.pump();
    // Start from an empty test library (ENCORE_TEST keeps it separate from
    // the user's), so earlier runs can't affect this one.
    for (final t in [...userLibrary.downloads.value]) {
      await downloads.remove(t);
    }
    userLibrary
      ..liked.value = []
      ..history.value = []
      ..playlists.value = [];
    final shots = await _Screenshots.create();

    // Home feed loads.
    await _step(
      'home feed loads',
      () => _until(tester, find.byType(ShelfView)),
    );
    await shots.take(tester, '1_home');

    // A song from a home section queues the rest of that section after it.
    // The feed differs per visit: a section of songs may be further down,
    // and sections are only built once scrolled to.
    final songShelf = find.byWidgetPredicate(
      (w) => w is ShelfView && w.shelf.tracks.length >= 3,
    );
    await tester.scrollUntilVisible(
      songShelf.first, // Several may be on screen.
      300,
      scrollable: find
          .descendant(
            of: find.byType(HomePage),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 60,
    );
    final section = tester.widget<ShelfView>(songShelf.first).shelf.tracks;
    await tester.tap(
      find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w is ShelfView && identical(w.shelf.tracks, section),
            ),
            matching: find.byType(TrackTile),
          )
          .at(1),
    );
    await _step(
      'section song plays',
      () => _untilTrue(
        tester,
        () => player.audio.playing && player.current == section[1],
        timeout: const Duration(seconds: 60),
      ),
    );
    // The whole section is queued, starting at the tapped song.
    expect(player.queue.value.take(section.length).toList(), section);
    expect(player.index.value, 1);
    await player.audio.pause();

    // Search for a song.
    await tester.tap(find.text('Search').first);
    await tester.pumpAndSettle();
    if (_keyboardCheck) await _checkRealTyping(tester);
    await tester.enterText(find.byType(TextField), 'daft punk get lucky');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _step('search results', () => _until(tester, find.byType(TrackTile)));
    await shots.take(tester, '2_search');

    // Play it: the position must actually advance.
    await tester.tap(find.byType(TrackTile).first);
    await _step(
      'audio starts',
      () => _untilTrue(
        tester,
        () => player.audio.playing && player.audio.position.inSeconds >= 2,
        timeout: const Duration(seconds: 60),
      ),
    );
    final track = player.current!;
    await _step(
      'radio fills up next',
      () => _untilTrue(tester, () => player.upNext.isNotEmpty),
    );
    await shots.take(tester, '3_playing');

    // More songs from the same search: each replaces the queue (at index 0
    // again), and the player must show each one (it used to keep showing
    // the earlier song). Then back to the first.
    final wide = isWideLayout(tester);
    final bar = find.byType(wide ? NowPlayingBar : MiniPlayer);
    final results = tester
        .widgetList<TrackTile>(find.byType(TrackTile))
        .map((t) => t.track)
        .toList();
    for (final i in [1, 2, 0]) {
      await tester.tap(find.byType(TrackTile).at(i));
      await _step(
        'search result ${i + 1} shown in the player',
        () => _untilTrue(
          tester,
          () =>
              player.current == results[i] &&
              player.audio.playing &&
              find
                  .descendant(of: bar, matching: find.text(results[i].title))
                  .evaluate()
                  .isNotEmpty,
          timeout: const Duration(seconds: 60),
        ),
      );
    }
    expect(player.current, track);

    // Covers, lyric videos and other uploads aren't songs: they're under
    // Videos (this one couldn't be found before), and plays like a song.
    const videoId = 'YlycL6ky2Wc';
    Finder tileOf(String id) =>
        find.byWidgetPredicate((w) => w is TrackTile && w.track.id == id);
    await _typeSearch(tester, 'Sammi Meri Waar Shifa Qassim');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _until(tester, find.widgetWithText(ChoiceChip, 'Videos'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Videos'));
    await _step(
      'videos filter finds it',
      () => _until(tester, tileOf(videoId)),
    );
    await tester.tap(tileOf(videoId).first);
    await _step(
      'video result plays',
      () => _untilTrue(
        tester,
        () =>
            player.current?.id == videoId &&
            player.audio.playing &&
            player.audio.position.inSeconds >= 2,
        timeout: const Duration(seconds: 60),
      ),
    );

    // A pasted YouTube link opens that exact song.
    await player.audio.pause();
    await _typeSearch(tester, 'https://youtu.be/$videoId?si=GCLgmi9AL9I2bEZ_');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _step(
      'pasted link finds the song',
      () => _until(tester, tileOf(videoId)),
    );
    expect(find.byType(TrackTile), findsOneWidget, reason: 'only that song');
    expect(find.byType(ChoiceChip), findsNothing, reason: 'no filters');
    await tester.tap(tileOf(videoId));
    await _step(
      'pasted link plays',
      () => _untilTrue(
        tester,
        () =>
            player.current?.id == videoId &&
            player.audio.playing &&
            player.audio.position.inSeconds >= 2,
        timeout: const Duration(seconds: 60),
      ),
    );

    // Import playlists by link, from Library: YouTube Music's as they are,
    // Spotify's by finding each song on YouTube Music.
    Future<void> importLink(String link) async {
      await tester.tap(find.text('Library').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import playlist'));
      await tester.pumpAndSettle();
      final linkField = find.descendant(
        of: find.byType(ImportPage),
        matching: find.byType(TextField),
      );
      await tester.tap(linkField);
      await tester.pump();
      await tester.enterText(linkField, link);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    }

    Finder playlistTiles() => find.descendant(
      of: find.byType(CollectionPage),
      matching: find.byType(TrackTile),
    );

    await importLink(
      'https://music.youtube.com/playlist?list='
      'RDCLAK5uy_krbBs7P2iEb30IODyVbiOXWyhZtAIX9Uk',
    );
    await _step(
      'youtube music playlist imported',
      () => _until(tester, playlistTiles()),
    );
    final ytPlaylist = userLibrary.playlists.value.first;
    expect(ytPlaylist.source, 'YouTube Music');
    expect(ytPlaylist.tracks, isNotEmpty);

    // Today's Top Hits.
    await importLink(
      'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
    );
    final save = find.textContaining('Save playlist');
    await _step(
      'spotify playlist matched',
      () => _until(tester, save, timeout: const Duration(seconds: 120)),
    );
    await shots.take(tester, '2b_spotify_import');
    await tester.tap(save);
    await _until(tester, playlistTiles());
    final spPlaylist = userLibrary.playlists.value.first;
    expect(spPlaylist.source, 'Spotify');
    expect(spPlaylist.tracks.length, greaterThan(40), reason: 'of 50');
    await tester.tap(playlistTiles().first);
    await _step(
      'imported playlist plays',
      () => _untilTrue(
        tester,
        () =>
            player.current == spPlaylist.tracks.first &&
            player.audio.playing &&
            player.audio.position.inSeconds >= 2,
        timeout: const Duration(seconds: 60),
      ),
    );
    expect(player.queue.value, spPlaylist.tracks, reason: 'queued in order');
    for (final p in [ytPlaylist, spPlaylist]) {
      userLibrary.deletePlaylist(p.id);
    }

    // Back to the first song for the rest of the journey.
    unawaited(player.playRadio(track));
    await _untilTrue(
      tester,
      () =>
          player.current == track &&
          player.audio.playing &&
          player.upNext.isNotEmpty,
      timeout: const Duration(seconds: 60),
    );

    // Keyboard: space toggles, arrows seek, L likes.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _untilTrue(tester, () => !player.audio.playing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _untilTrue(tester, () => player.audio.playing);
    final before = player.audio.position;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _untilTrue(
      tester,
      () => player.audio.position - before >= const Duration(seconds: 8),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(userLibrary.isLiked(track), isTrue, reason: 'L likes the song');
    _log('keyboard shortcuts', 'ok');

    // Full player with lyrics and up next.
    // Desktop: clicking empty space on the player bar opens it; phones:
    // tapping the mini player.
    await tester.tapAt(
      wide
          ? tester.getTopLeft(bar) + const Offset(6, 44)
          : tester.getCenter(
              find.descendant(of: bar, matching: find.byType(Artwork)).first,
            ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FullPlayer), findsOneWidget);
    await shots.take(tester, '4_full_player');

    // Swiping the artwork left plays the next song, right the previous one.
    final art = find.descendant(
      of: find.byType(FullPlayer),
      matching: find.byType(SwipeToSkip),
    );
    final swipedFrom = player.index.value;
    await tester.drag(art, const Offset(-300, 0));
    await _step(
      'swipe left: next song',
      () => _untilTrue(
        tester,
        () => player.index.value == swipedFrom + 1 && player.audio.playing,
      ),
    );
    await tester.drag(art, const Offset(300, 0));
    await _step(
      'swipe right: previous song',
      () => _untilTrue(
        tester,
        () => player.index.value == swipedFrom && player.audio.playing,
      ),
    );

    // Phones: swiping up on the song shows its lyrics.
    if (!wide) {
      await tester.fling(art, const Offset(0, -300), 1500);
      await tester.pumpAndSettle();
      expect(find.byType(LyricsView), findsOneWidget, reason: 'swipe up');
      _log('swipe up: lyrics', 'ok');
    }
    await tester.tap(find.text('Lyrics').last);
    await _step(
      'lyrics load',
      () => _untilTrue(
        tester,
        () =>
            find.byType(LyricsView).evaluate().isNotEmpty &&
            find
                .descendant(
                  of: find.byType(LyricsView),
                  matching: find.byType(CircularProgressIndicator),
                )
                .evaluate()
                .isEmpty,
      ),
    );
    await shots.take(tester, '5_lyrics');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // Artist and album pages.
    openArtist(track.artistId!);
    await _step('artist page', () => _until(tester, find.text('Popular')));
    await shots.take(tester, '6_artist');
    openCollection(track.albumId!);
    await _step('album page', () => _until(tester, find.text('ALBUM')));
    await tester.pumpAndSettle();
    await shots.take(tester, '7_album');
    await tester.tap(find.byType(PlayCircleButton).first);
    await _untilTrue(
      tester,
      () => player.current?.albumId == track.albumId && player.audio.playing,
    );
    _log('album playback', 'ok');

    // Next song from the queue.
    final index = player.index.value;
    await player.next();
    await _untilTrue(
      tester,
      () => player.index.value == index + 1 && player.audio.playing,
    );
    _log('next track', 'ok');

    // Sleep timer, end of song: pauses there with the next song lined up.
    final ending = player.index.value;
    sleepTimer.untilEndOfSong();
    await _untilTrue(tester, () => player.audio.duration != null);
    await player.audio.seek(
      player.audio.duration! - const Duration(seconds: 3),
    );
    await _step(
      'sleep timer: end of song',
      () => _untilTrue(
        tester,
        () =>
            player.index.value == ending + 1 &&
            !player.loading.value &&
            player.audio.processingState == ProcessingState.ready,
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(player.audio.playing, isFalse, reason: 'paused at the song end');
    expect(sleepTimer.setting.value, isNull, reason: 'timer turned off');

    // Sleep timer, timed: fades out, pauses, then gives the volume back.
    player.audio.play();
    await _untilTrue(tester, () => player.audio.playing);
    final volume = player.audio.volume;
    sleepTimer.set(const Duration(seconds: 12));
    await tester.pump(const Duration(seconds: 6));
    expect(player.audio.playing, isTrue);
    await _step(
      'sleep timer: fades and pauses',
      () => _untilTrue(tester, () => !player.audio.playing),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(player.audio.volume, volume, reason: 'volume restored');
    expect(sleepTimer.setting.value, isNull);
    player.audio.play();

    // A song that can't play is skipped when playback moves on by itself.
    const unplayable = Track(
      id: 'encoretest0',
      title: 'Unplayable',
      artist: 'Nobody',
      artUrl: '',
    );
    await player.playList([player.current!, unplayable, track], 0);
    await _untilTrue(
      tester,
      () => player.audio.playing && player.audio.duration != null,
    );
    await player.audio.seek(
      player.audio.duration! - const Duration(seconds: 2),
    );
    await _step(
      'unplayable song skipped',
      () => _untilTrue(
        tester,
        () =>
            player.index.value == 2 &&
            player.audio.playing &&
            player.audio.position.inSeconds >= 1,
      ),
    );

    // Bug: a song whose link stopped working (it expires, and changes with
    // the IP address, e.g. Wi-Fi to mobile data) stuck, and dragging the
    // seek bar to the middle did nothing. Its link is broken here as YouTube
    // would, then the song is dragged to the middle.
    AudioStream breakLink() {
      final stream = (player.audio.audioSource! as YouTubeAudioSource).stream;
      return stream
        ..url = stream.url.replace(
          queryParameters: {...stream.url.queryParameters, 'expire': '1'},
        );
    }

    Future<void> playsFrom(Duration at) => _untilTrue(
      tester,
      () =>
          player.audio.playing &&
          player.audio.position >= at + const Duration(seconds: 2),
    );

    final broken = breakLink();
    var middle = player.audio.duration! ~/ 2;
    await player.seek(middle);
    await _step('expired link renewed', () => playsFrom(middle));
    // Not if the player already had those bytes.
    _log('link renewed', '${broken.url.queryParameters['expire'] != '1'}');
    expect(player.current, track, reason: 'the same song');

    // Renewing fails too (e.g. no network for a moment): the song breaks
    // off. Dragging the seek bar again, once it can be renewed, plays from
    // there (Android's player stops on the failure and the song is loaded
    // again; the desktop player carries on and asks again).
    breakLink();
    failRenewals = true;
    middle = player.audio.duration! ~/ 3;
    try {
      await player.seek(middle);
      final failed = DateTime.now().add(const Duration(seconds: 8));
      await _untilTrue(tester, () => DateTime.now().isAfter(failed));
    } finally {
      failRenewals = false;
    }
    _log('after the failure', player.audio.processingState.name);
    await player.seek(middle);
    await _step('seek works after a failure', () => playsFrom(middle));
    expect(player.current, track, reason: 'the same song');

    // Download, then play offline from the file.
    downloads.download([track]);
    await _step(
      'download',
      () => _untilTrue(
        tester,
        () => downloads.isDownloaded(track),
        timeout: const Duration(seconds: 120),
      ),
    );
    expect(await downloads.fileFor(track), isNotNull);
    await player.playList([track], 0);
    await _untilTrue(
      tester,
      () => player.audio.playing && player.audio.position.inSeconds >= 1,
    );
    _log('offline playback', 'ok');

    if (_backgroundCheck) await _checkBackgroundPlayback();

    // Clean up the test library.
    await downloads.remove(track);
    userLibrary.toggleLike(track);
    await player.audio.stop();
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// Set by tool/android_background_check.sh, which presses Home and turns
/// the screen off when this test says it is ready.
const _backgroundCheck = bool.fromEnvironment('ENCORE_BACKGROUND_CHECK');

/// Playback must continue with the app in the background and the screen
/// off. No frames are drawn then, so this waits with timers, not pumps.
Future<void> _checkBackgroundPlayback() async {
  _log('background', 'ready');
  // Give the host script time to press Home and turn the screen off.
  await Future<void>.delayed(const Duration(seconds: 8));
  final start = player.audio.position;
  await Future<void>.delayed(const Duration(seconds: 15));
  final advanced = player.audio.position - start;
  expect(player.audio.playing, isTrue, reason: 'still playing in background');
  expect(
    advanced,
    greaterThan(const Duration(seconds: 12)),
    reason: 'position advances in background',
  );
  _log('background playback', 'ok (+${advanced.inSeconds}s with screen off)');
  // Stay alive while the host presses the media "next" key.
  await Future<void>.delayed(const Duration(seconds: 20));

  // The sleep timer still fires with the screen off.
  expect(player.audio.playing, isTrue);
  sleepTimer.set(const Duration(seconds: 12));
  await Future<void>.delayed(const Duration(seconds: 16));
  expect(player.audio.playing, isFalse, reason: 'sleep timer, screen off');
  _log('sleep timer in background', 'ok');
}

/// Set by tool/windows_keyboard_check.ps1, which types into the search box
/// with real key presses from Windows when this test says it is ready.
const _keyboardCheck = bool.fromEnvironment('ENCORE_KEYBOARD_CHECK');

/// Real keystrokes reach the search box: Space, K and L are typed (not
/// play/pause and like) and the arrows move the cursor (not seek).
Future<void> _checkRealTyping(WidgetTester tester) async {
  await tester.tap(find.byType(TextField));
  await tester.pump();
  final wasPlaying = player.audio.playing;
  final likes = userLibrary.liked.value.length;
  _log('keyboard', 'ready');
  // The host types "get lucky kl", Left, Left, "x".
  String text() =>
      tester.widget<EditableText>(find.byType(EditableText)).controller.text;
  await _untilTrue(
    tester,
    () => text() == 'get lucky xkl',
    timeout: const Duration(seconds: 60),
  ).catchError((Object e) {
    throw TestFailure('Typed "${text()}", expected "get lucky xkl"');
  });
  expect(player.audio.playing, wasPlaying, reason: 'Space/K did not toggle');
  expect(userLibrary.liked.value.length, likes, reason: 'L did not like');
  _log('real typing', 'ok');
}

/// Clicks the search box, then types: on desktop, text typed into a box
/// that a search left unfocused doesn't arrive.
Future<void> _typeSearch(WidgetTester tester, String text) async {
  await tester.tap(find.byType(TextField));
  await tester.pump();
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

bool isWideLayout(WidgetTester tester) =>
    find.byType(NowPlayingBar).evaluate().isNotEmpty &&
    tester.view.physicalSize.width / tester.view.devicePixelRatio >= 900;

Future<void> _step(String name, Future<void> Function() body) async {
  final sw = Stopwatch()..start();
  await body();
  _log(name, '${sw.elapsedMilliseconds} ms');
}

void _log(String name, String result) =>
    // ignore: avoid_print
    print('[e2e] ${Platform.operatingSystem} · $name: $result');

Future<void> _until(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) => _untilTrue(tester, () => finder.evaluate().isNotEmpty, timeout: timeout);

/// Pumps frames until [condition] holds, failing after [timeout].
Future<void> _untilTrue(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure(
        'Timed out after $timeout '
        '(player: ${player.audio.processingState.name}, '
        'playing: ${player.audio.playing}, '
        'position: ${player.audio.position}, '
        'error: ${player.error.value}, '
        'typing: ${PlayerShortcuts.isTyping}, '
        'keys down: ${HardwareKeyboard.instance.logicalKeysPressed}, '
        'focus: ${FocusManager.instance.primaryFocus})',
      );
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Saves PNGs of the screen, for reviewing the design on each platform.
class _Screenshots {
  _Screenshots(this.dir);

  final Directory dir;

  static Future<_Screenshots> create() async {
    final base = Platform.isAndroid
        ? (await getTemporaryDirectory()).path
        : '${Directory.current.path}/build';
    final dir = Directory('$base/screenshots/${Platform.operatingSystem}');
    await dir.create(recursive: true);
    _log('screenshots', dir.path);
    return _Screenshots(dir);
  }

  Future<void> take(WidgetTester tester, String name) async {
    // Let images arrive and animations finish first.
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    // The root layer already scales by the device pixel ratio, so capture
    // its full physical size at 1:1.
    final image = await layer.toImage(
      Offset.zero & (view.size * tester.view.devicePixelRatio),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = png!.buffer.asUint8List();
    await File('${dir.path}/$name.png').writeAsBytes(bytes);
    if (Platform.isAndroid) {
      // The app (and its files) is uninstalled after the run, so also print
      // the PNG for tool/collect_screenshots.py to rebuild from the log.
      final data = base64Encode(bytes);
      for (var i = 0; i < data.length; i += 1000) {
        // ignore: avoid_print
        print('[shot:$name] ${data.substring(i, min(i + 1000, data.length))}');
      }
    }
  }
}
