import 'package:encore/models.dart';
import 'package:encore/services/player.dart';
import 'package:encore/ui/player/player_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test.dart' show pumpApp;

// Bug: playing a second and third song from search left the players on
// the earlier song. Each search result replaces the queue, so the new song
// is at index 0 again and nothing that watched the index updated.

Track _song(String id) =>
    Track(id: id, title: 'Song $id', artist: 'Artist $id', artUrl: '');

/// What playing a search result does to the queue (without real audio).
void _playFromSearch(Track track) {
  player.queue.value = [track];
  player.index.value = 0;
}

void main() {
  tearDown(() {
    player.queue.value = [];
    player.index.value = -1;
  });

  for (final (name, size, bar) in [
    ('phone mini player', const Size(400, 860), MiniPlayer),
    ('desktop player bar', const Size(1400, 900), NowPlayingBar),
  ]) {
    testWidgets('$name shows each new song played from search', (tester) async {
      await pumpApp(tester, size);
      for (final id in ['one', 'two', 'three']) {
        _playFromSearch(_song(id));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(bar),
            matching: find.text('Song $id'),
          ),
          findsOneWidget,
          reason: 'after playing song $id',
        );
      }
    });
  }

  testWidgets('the full player follows too', (tester) async {
    await pumpApp(tester, const Size(400, 860));
    _playFromSearch(_song('one'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    _playFromSearch(_song('two'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(FullPlayer),
        matching: find.text('Song two'),
      ),
      findsOneWidget,
    );
  });

  // The player only knows the length once the song has loaded; until then
  // the seek bar read 0:00 and ignored drags.
  testWidgets('the seek bar shows the song\'s length while it loads', (
    tester,
  ) async {
    await pumpApp(tester, const Size(400, 860));
    _playFromSearch(
      const Track(
        id: 'long',
        title: 'Long song',
        artist: 'Artist',
        artUrl: '',
        duration: Duration(minutes: 3, seconds: 35),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(SeekBar), matching: find.text('3:35')),
      findsOneWidget,
    );
  });

  testWidgets('on phones the full player slides up from the bottom', (
    tester,
  ) async {
    await pumpApp(tester, const Size(400, 860));
    _playFromSearch(_song('one'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MiniPlayer));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      tester.getTopLeft(find.byType(FullPlayer)).dy,
      greaterThan(200),
      reason: 'on its way up, not fading in place',
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(FullPlayer)).dy, 0);
  });

  group('desktop player bar', () {
    Future<Finder> pumpBar(WidgetTester tester) async {
      await pumpApp(tester, const Size(1400, 900));
      _playFromSearch(_song('one'));
      await tester.pumpAndSettle();
      return find.byType(NowPlayingBar);
    }

    testWidgets('clicking empty space on it opens the full player', (
      tester,
    ) async {
      final bar = await pumpBar(tester);
      // Its left edge, beside the artwork.
      await tester.tapAt(tester.getTopLeft(bar) + const Offset(6, 44));
      await tester.pumpAndSettle();
      expect(find.byType(FullPlayer), findsOneWidget);
    });

    // Opening the full player covered the bar's volume control, and the
    // full player had none.
    testWidgets('the full player has the volume too', (tester) async {
      final bar = await pumpBar(tester);
      await tester.tapAt(tester.getTopLeft(bar) + const Offset(6, 44));
      await tester.pumpAndSettle();
      final volume = find.descendant(
        of: find.byType(FullPlayer),
        matching: find.byType(VolumeButton),
      );
      expect(volume, findsOneWidget);
      // A speaker icon whose slider slides out on hover.
      final slider = find.descendant(
        of: volume,
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(slider).width, 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(
          find.descendant(of: volume, matching: find.byTooltip('Mute')),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(slider).width, greaterThan(50));
    });

    for (final control in ['Like', 'More']) {
      testWidgets('its $control button does its own job only', (tester) async {
        final bar = await pumpBar(tester);
        await tester.tap(
          find.descendant(of: bar, matching: find.byTooltip(control)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(FullPlayer), findsNothing);
        if (control == 'More') {
          expect(find.text('Sleep timer'), findsOneWidget, reason: 'menu');
        }
      });
    }
  });

  test('nowPlaying changes with the song, even at the same index', () {
    final seen = <String?>[];
    void listener() => seen.add(player.nowPlaying.value?.id);
    player.nowPlaying.addListener(listener);
    addTearDown(() => player.nowPlaying.removeListener(listener));
    _playFromSearch(_song('a'));
    _playFromSearch(_song('b'));
    expect(seen, ['a', 'b']);
  });
}
