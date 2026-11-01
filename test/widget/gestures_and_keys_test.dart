import 'package:encore/models.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/player.dart';
import 'package:encore/services/settings.dart';
import 'package:encore/ui/pages/search_page.dart';
import 'package:encore/ui/pages/settings_page.dart';
import 'package:encore/ui/player/player_ui.dart';
import 'package:encore/ui/shortcuts.dart';
import 'package:encore/ui/theme.dart';
import 'package:encore/ui/widgets/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test.dart' show pumpApp;

void main() {
  group('keyboard while typing in search', () {
    Future<void> focusSearch(WidgetTester tester) async {
      await pumpApp(tester, const Size(1400, 900));
      await tester.tap(find.text('Search').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(PlayerShortcuts.isTyping, isTrue);
    }

    // On desktop, a key the app marks as handled is never typed: these must
    // be left alone for the text field.
    for (final key in [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyL,
    ]) {
      testWidgets('${key.keyLabel} is typed, not a shortcut', (tester) async {
        await focusSearch(tester);
        expect(await simulateKeyDownEvent(key), isFalse);
        await simulateKeyUpEvent(key);
      });
    }

    int cursor(WidgetTester tester) => tester
        .widget<EditableText>(find.byType(EditableText))
        .controller
        .selection
        .baseOffset;

    testWidgets('arrows move the cursor instead of seeking', (tester) async {
      await focusSearch(tester);
      await tester.enterText(find.byType(TextField), 'get lucky');
      expect(cursor(tester), 9);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(cursor(tester), 7);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(cursor(tester), 8);
      // Ctrl+Left jumps a word, rather than going to the previous song.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(cursor(tester), lessThan(8));
    });

    testWidgets('the search box spans the page on desktop', (tester) async {
      await focusSearch(tester);
      final page = tester.getSize(find.byType(SearchPage));
      final box = tester.getSize(find.byType(SearchBar));
      // Only the page's side padding is left over.
      expect(box.width, greaterThan(page.width - 2 * 48));
    });

    testWidgets('the search box spans the page on phones', (tester) async {
      await pumpApp(tester, const Size(400, 860));
      await tester.tap(find.text('Search').last);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SearchBar)).width, 400 - 2 * 16);
    });

    testWidgets('Esc leaves the search box', (tester) async {
      await focusSearch(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(PlayerShortcuts.isTyping, isFalse);
    });

    // Up / down did nothing in the suggestions (they moved the cursor).
    testWidgets('↓ / ↑ pick a suggestion and Enter searches it', (
      tester,
    ) async {
      userLibrary.searches.value = ['first', 'second', 'third'];
      addTearDown(() => userLibrary.searches.value = []);
      await focusSearch(tester);
      for (final key in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.pump();
      expect(PlayerShortcuts.isTyping, isTrue, reason: 'still in the box');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(
        tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
        'second',
      );
    });

    testWidgets('Esc first drops the picked suggestion, then leaves', (
      tester,
    ) async {
      userLibrary.searches.value = ['first'];
      addTearDown(() => userLibrary.searches.value = []);
      await focusSearch(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(PlayerShortcuts.isTyping, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(PlayerShortcuts.isTyping, isFalse);
    });

    testWidgets('clicking elsewhere leaves the search box', (tester) async {
      await focusSearch(tester);
      await tester.tapAt(const Offset(1000, 600));
      await tester.pump();
      expect(PlayerShortcuts.isTyping, isFalse);
    });

    testWidgets('not typing once the field loses focus', (tester) async {
      await focusSearch(tester);
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      expect(PlayerShortcuts.isTyping, isFalse);
    });
  });

  group('desktop keys', () {
    setUp(() {
      player.queue.value = [
        const Track(id: 'k', title: 'Keys song', artist: 'X', artUrl: ''),
      ];
      player.index.value = 0;
    });
    tearDown(() {
      player.queue.value = [];
      player.index.value = -1;
    });

    Future<void> openPlayer(WidgetTester tester) async {
      await pumpApp(tester, const Size(1400, 900));
      await tester.tapAt(
        tester.getTopLeft(find.byType(NowPlayingBar)) + const Offset(6, 44),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FullPlayer), findsOneWidget);
    }

    Future<void> press(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      LogicalKeyboardKey? holding,
    }) async {
      if (holding != null) await tester.sendKeyDownEvent(holding);
      await tester.sendKeyEvent(key);
      if (holding != null) await tester.sendKeyUpEvent(holding);
      await tester.pumpAndSettle();
    }

    // Closing the full player took a trip to the ⌄ in the top corner.
    testWidgets('Esc closes the full player', (tester) async {
      await openPlayer(tester);
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(FullPlayer), findsNothing);
    });

    testWidgets('Alt + ← goes back: the player, then the page', (tester) async {
      await openPlayer(tester);
      await press(
        tester,
        LogicalKeyboardKey.arrowLeft,
        holding: LogicalKeyboardKey.altLeft,
      );
      expect(find.byType(FullPlayer), findsNothing);
      await tester.tap(find.text('Liked songs').first);
      await tester.pumpAndSettle();
      expect(find.text('No songs here yet'), findsOneWidget);
      await press(
        tester,
        LogicalKeyboardKey.arrowLeft,
        holding: LogicalKeyboardKey.altLeft,
      );
      expect(find.text('No songs here yet'), findsNothing);
    });

    testWidgets("the mouse's back button closes the player", (tester) async {
      await openPlayer(tester);
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      );
      await mouse.down(const Offset(700, 450));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.byType(FullPlayer), findsNothing);
    });

    testWidgets('Ctrl + K puts the cursor in search from anywhere', (
      tester,
    ) async {
      await openPlayer(tester);
      await press(
        tester,
        LogicalKeyboardKey.keyK,
        holding: LogicalKeyboardKey.controlLeft,
      );
      expect(find.byType(FullPlayer), findsNothing);
      expect(find.byType(SearchPage), findsOneWidget);
      expect(PlayerShortcuts.isTyping, isTrue);
    });

    testWidgets('Ctrl + / lists the shortcuts', (tester) async {
      await pumpApp(tester, const Size(1400, 900));
      await press(
        tester,
        LogicalKeyboardKey.slash,
        holding: LogicalKeyboardKey.controlLeft,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Ctrl + S'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Ctrl + , opens settings, where quality can be picked', (
      tester,
    ) async {
      addTearDown(() => settings.streamQuality.value = AudioQuality.high);
      await pumpApp(tester, const Size(1400, 900));
      await press(
        tester,
        LogicalKeyboardKey.comma,
        holding: LogicalKeyboardKey.controlLeft,
      );
      expect(find.byType(SettingsPage), findsOneWidget);
      await tester.tap(find.text('Streaming quality'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Low'));
      await tester.pumpAndSettle();
      expect(settings.streamQuality.value, AudioQuality.low);
      expect(find.text('Low · Least data'), findsOneWidget);
    });

    testWidgets('Ctrl + S and Ctrl + R: shuffle and repeat', (tester) async {
      await pumpApp(tester, const Size(1400, 900));
      addTearDown(() {
        if (player.shuffle.value) player.toggleShuffle();
        player.repeat.value = Repeat.off;
      });
      await press(
        tester,
        LogicalKeyboardKey.keyS,
        holding: LogicalKeyboardKey.controlLeft,
      );
      expect(player.shuffle.value, isTrue);
      await press(
        tester,
        LogicalKeyboardKey.keyR,
        holding: LogicalKeyboardKey.controlLeft,
      );
      expect(player.repeat.value, Repeat.all);
    });
  });

  group('swipe to skip', () {
    late List<String> calls;

    Future<void> pumpSwipe(WidgetTester tester) async {
      calls = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: SwipeToSkip(
                onNext: () => calls.add('next'),
                onPrevious: () => calls.add('previous'),
                child: const ColoredBox(key: _target, color: Colors.orange),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('left is next, right is previous', (tester) async {
      await pumpSwipe(tester);
      await tester.drag(find.byKey(_target), const Offset(-150, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(_target), const Offset(150, 0));
      await tester.pumpAndSettle();
      expect(calls, ['next', 'previous']);
    });

    testWidgets('a quick flick counts, a short slow drag does not', (
      tester,
    ) async {
      await pumpSwipe(tester);
      await tester.fling(find.byKey(_target), const Offset(-70, 0), 1500);
      await tester.pumpAndSettle();
      expect(calls, ['next']);
      await tester.timedDrag(
        find.byKey(_target),
        const Offset(40, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(calls, ['next'], reason: 'too short and slow');
    });

    testWidgets('springs back after a swipe', (tester) async {
      await pumpSwipe(tester);
      final start = tester.getTopLeft(find.byKey(_target));
      await tester.drag(find.byKey(_target), const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_target)), start);
    });

    // It snapped back and then changed, which felt abrupt next to other
    // players: now the song is carried off, and the next comes in from the
    // other side.
    testWidgets('a swipe carries the song off and brings the next in', (
      tester,
    ) async {
      await pumpSwipe(tester);
      final start = tester.getTopLeft(find.byKey(_target)).dx;
      await tester.drag(find.byKey(_target), const Offset(-100, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getTopLeft(find.byKey(_target)).dx,
        lessThan(start - 150),
        reason: 'on its way off to the left',
      );
      expect(calls, isEmpty, reason: 'not yet');
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, ['next']);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getTopLeft(find.byKey(_target)).dx,
        greaterThan(start + 50),
        reason: 'the next one comes in from the right',
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_target)).dx, start);
    });

    // Seen on a phone: the old song's art came back in from the other
    // side before the new art showed. With the songs either side shown
    // beside it, the next one slides into place and the song changes there.
    testWidgets('the next song slides into place, like a page', (tester) async {
      calls = [];
      const next = Key('next');
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: SwipeToSkip(
                onNext: () => calls.add('next'),
                onPrevious: () => calls.add('previous'),
                next: const ColoredBox(key: next, color: Colors.blue),
                child: const ColoredBox(key: _target, color: Colors.orange),
              ),
            ),
          ),
        ),
      );
      final start = tester.getTopLeft(find.byKey(_target)).dx;
      // At rest an edge of it showed beside the art (phones, and over the
      // up next panel on desktop).
      expect(find.byKey(next), findsNothing, reason: 'not drawn at rest');
      expect(
        find.byKey(next, skipOffstage: false),
        findsOneWidget,
        reason: 'built, so its art is loaded',
      );
      await tester.drag(find.byKey(_target), const Offset(-100, 0));
      final seen = <double>[];
      var nextAt = double.infinity;
      for (var i = 0; i < 30 && calls.isEmpty; i++) {
        nextAt = tester.getTopLeft(find.byKey(next, skipOffstage: false)).dx;
        await tester.pump(const Duration(milliseconds: 16));
        seen.add(tester.getTopLeft(find.byKey(_target)).dx);
      }
      expect(calls, ['next']);
      expect(
        nextAt - start,
        lessThan(10),
        reason: 'the next page all but in place when the song changed',
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_target)).dx, start);
      expect(
        seen.every((dx) => dx <= start),
        isTrue,
        reason: 'never back in from the right',
      );
    });

    testWidgets('a drag while the song leaves changes it only once', (
      tester,
    ) async {
      await pumpSwipe(tester);
      await tester.drag(find.byKey(_target), const Offset(-100, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Slow and short: not a swipe of its own.
      await tester.timedDrag(
        find.byKey(_target),
        const Offset(-20, 0),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();
      expect(calls, ['next']);
    });

    testWidgets('vertical drags are not swipes', (tester) async {
      await pumpSwipe(tester);
      await tester.drag(find.byKey(_target), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    });
  });

  group('full player on a phone', () {
    const track = Track(
      id: 'abc',
      title: 'A Song',
      artist: 'An Artist',
      artUrl: '',
      duration: Duration(minutes: 3),
    );

    Future<void> pumpPlayer(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(400, 860)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      player.queue.value = [track];
      player.index.value = 0;
      addTearDown(() {
        player.queue.value = [];
        player.index.value = -1;
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => openFullPlayer(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    final sheet = find.descendant(
      of: find.byType(LyricsSheet),
      matching: find.byType(Material),
    );
    double sheetTop(WidgetTester tester) => tester.getTopLeft(sheet.first).dy;
    bool isOpen(WidgetTester tester) =>
        find.byTooltip('Close lyrics').evaluate().isNotEmpty;

    testWidgets('closed: a Lyrics bar along the bottom, no Lyrics tab', (
      tester,
    ) async {
      await pumpPlayer(tester);
      expect(sheetTop(tester), 860 - LyricsSheet.barHeight);
      expect(find.text('Lyrics'), findsOneWidget, reason: 'the bar only');
      expect(find.text('Up next'), findsOneWidget);
      expect(isOpen(tester), isFalse);
    });

    testWidgets('the sheet follows the finger up and back down', (
      tester,
    ) async {
      await pumpPlayer(tester);
      final closedTop = sheetTop(tester);
      final drag = await tester.startGesture(
        tester.getCenter(find.byType(SwipeToSkip)),
      );
      for (var i = 0; i < 10; i++) {
        await drag.moveBy(const Offset(0, -20));
        await tester.pump();
      }
      final raised = sheetTop(tester);
      expect(closedTop - raised, greaterThan(150), reason: 'follows up');
      for (var i = 0; i < 5; i++) {
        await drag.moveBy(const Offset(0, 20));
        await tester.pump();
      }
      expect(sheetTop(tester), greaterThan(raised + 80), reason: 'and down');
      // Let go a little way up, slowly: it settles closed again.
      await tester.pump(const Duration(seconds: 1));
      await drag.up();
      await tester.pumpAndSettle();
      expect(sheetTop(tester), closedTop);
    });

    testWidgets('a flick up on the song opens it; swipe down closes it', (
      tester,
    ) async {
      await pumpPlayer(tester);
      await tester.fling(find.byType(SwipeToSkip), const Offset(0, -200), 1500);
      await tester.pumpAndSettle();
      expect(isOpen(tester), isTrue);
      expect(sheetTop(tester), lessThan(100), reason: 'covers the player');
      // Offline in tests: an error with Retry, not "No lyrics".
      expect(find.text("Couldn't load lyrics."), findsOneWidget);

      await tester.fling(find.text('Lyrics'), const Offset(0, 400), 1500);
      await tester.pumpAndSettle();
      expect(isOpen(tester), isFalse);
      expect(sheetTop(tester), 860 - LyricsSheet.barHeight);
    });

    testWidgets('dragging the bar itself opens it', (tester) async {
      await pumpPlayer(tester);
      await tester.fling(find.text('Lyrics'), const Offset(0, -300), 1500);
      await tester.pumpAndSettle();
      expect(isOpen(tester), isTrue);
    });

    testWidgets('tap the bar to open, the close button to close', (
      tester,
    ) async {
      await pumpPlayer(tester);
      await tester.tap(find.text('Lyrics'));
      await tester.pumpAndSettle();
      expect(isOpen(tester), isTrue);
      await tester.tap(find.byTooltip('Close lyrics'));
      await tester.pumpAndSettle();
      expect(isOpen(tester), isFalse);
    });

    testWidgets('Back closes the lyrics first, then the player', (
      tester,
    ) async {
      await pumpPlayer(tester);
      await tester.tap(find.text('Lyrics'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(FullPlayer), findsOneWidget);
      expect(isOpen(tester), isFalse);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(FullPlayer), findsNothing);
    });

    testWidgets('pulling the song down follows the finger, then closes', (
      tester,
    ) async {
      await pumpPlayer(tester);
      final top = tester.getTopLeft(find.byType(FullPlayer)).dy;
      final drag = await tester.startGesture(
        tester.getCenter(find.byType(SwipeToSkip)),
      );
      for (var i = 0; i < 5; i++) {
        await drag.moveBy(const Offset(0, 20));
        await tester.pump();
      }
      final pulled = tester.getTopLeft(find.byType(Scaffold).last).dy;
      expect(pulled - top, greaterThan(60), reason: 'follows the finger');
      // A short, slow pull springs back.
      await tester.pump(const Duration(seconds: 1));
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.byType(FullPlayer), findsOneWidget);
      expect(tester.getTopLeft(find.byType(Scaffold).last).dy, top);
      // A flick down closes the player.
      await tester.fling(find.byType(SwipeToSkip), const Offset(0, 300), 1500);
      await tester.pumpAndSettle();
      expect(find.byType(FullPlayer), findsNothing);
    });

    // The app behind the player was drawn with every frame of it, which
    // made the player's frames cost about twice as much on phones.
    testWidgets('the app behind the open player is drawn only when pulled', (
      tester,
    ) async {
      await pumpPlayer(tester);
      final behind = find.text('open');
      expect(behind, findsNothing, reason: 'covered');
      final drag = await tester.startGesture(
        tester.getCenter(find.byType(SwipeToSkip)),
      );
      for (var i = 0; i < 5; i++) {
        await drag.moveBy(const Offset(0, 20));
        await tester.pump();
      }
      expect(behind, findsOneWidget, reason: 'pulled down');
      await tester.pump(const Duration(seconds: 1));
      await drag.up();
      await tester.pumpAndSettle();
      expect(behind, findsNothing, reason: 'sprang back');
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(behind, findsOneWidget, reason: 'closing');
    });

    testWidgets('up next has no lyrics sheet; Back returns to the song', (
      tester,
    ) async {
      await pumpPlayer(tester);
      await tester.tap(find.text('Up next'));
      await tester.pumpAndSettle();
      expect(find.byType(LyricsSheet), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LyricsSheet), findsOneWidget);
    });

    // The Song / Lyrics / Up next tabs were bare gestures: a screen reader
    // couldn't tell they were there, or use them.
    testWidgets('screen readers can use the player tabs', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpPlayer(tester);
      expect(
        tester.getSemantics(find.text('Up next')),
        isSemantics(
          label: 'Up next',
          isButton: true,
          hasTapAction: true,
          isSelected: false,
        ),
      );
      semantics.dispose();
    });

    // Up next was read-only: nothing could be taken out or moved.
    testWidgets('a song can be taken out of up next', (tester) async {
      await pumpPlayer(tester);
      Track song(String id) =>
          Track(id: id, title: 'Queued $id', artist: 'X', artUrl: '');
      player.queue.value = [track, song('1'), song('2')];
      await tester.tap(find.text('Up next'));
      await tester.pumpAndSettle();
      // From the song's menu, like Spotify (a × on every row was clutter).
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(TrackTile, 'Queued 1'),
          matching: find.byTooltip('More'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from queue'));
      await tester.pumpAndSettle();
      expect(find.text('Queued 1'), findsNothing);
      expect(find.text('Queued 2'), findsOneWidget);
      expect(player.queue.value, [track, song('2')]);
    });

    testWidgets('the seek bar stays enabled while a song loads', (
      tester,
    ) async {
      // No length known yet (nothing loaded): flipping the slider to
      // disabled and back on every song change broke the accessibility
      // tree of the player bar hidden under the full player.
      await pumpPlayer(tester);
      final slider = tester.widget<Slider>(
        find.descendant(
          of: find.byType(SeekBar),
          matching: find.byType(Slider),
        ),
      );
      expect(slider.onChanged, isNotNull);
    });
  });

  group('shuffle', () {
    final songs = [
      for (var i = 0; i < 30; i++)
        Track(id: 's$i', title: 'Song $i', artist: 'X', artUrl: ''),
    ];
    setUp(() {
      player.queue.value = List.of(songs);
      player.index.value = 4;
      player.shuffle.value = false;
    });
    tearDown(() {
      if (player.shuffle.value) player.toggleShuffle();
      player.queue.value = [];
      player.index.value = -1;
    });

    testWidgets('on: the rest is shuffled, what played stays put', (
      tester,
    ) async {
      player.toggleShuffle();
      expect(player.shuffle.value, isTrue);
      final q = player.queue.value;
      expect(q.take(5), songs.take(5), reason: 'played and current');
      expect(q.skip(5).toSet(), songs.skip(5).toSet(), reason: 'same songs');
      expect(q.skip(5), isNot(songs.skip(5)), reason: 'new order');
    });

    testWidgets('off: back to the original order, from the same song', (
      tester,
    ) async {
      player.toggleShuffle();
      player.index.value = 9; // played a few shuffled songs
      final now = player.current;
      player.toggleShuffle();
      expect(player.queue.value, songs);
      expect(player.current, now, reason: 'keeps playing the same song');
      expect(player.index.value, songs.indexOf(now!));
    });

    testWidgets('a song added with Play next stays next when turned off', (
      tester,
    ) async {
      player.toggleShuffle();
      const extra = Track(id: 'new', title: 'New', artist: 'X', artUrl: '');
      player.playNext(extra);
      expect(player.upNext.first, extra);
      player.toggleShuffle();
      expect(player.upNext.first, extra);
    });

    testWidgets('the button shows its state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: const Scaffold(body: Center(child: TransportControls())),
        ),
      );
      expect(find.byTooltip('Shuffle off'), findsOneWidget);
      await tester.tap(find.byTooltip('Shuffle off'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Shuffle on'), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.shuffle_rounded));
      expect(icon.color, EncoreColors.accent);
    });
  });

  group('song menu from the song itself', () {
    const song = Track(id: 'm', title: 'Menu Song', artist: 'X', artUrl: '');

    Future<void> pumpTile(WidgetTester tester, Size size) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: TrackTile(track: song, onTap: () {}),
            ),
          ),
        ),
      );
    }

    testWidgets('phone: long-press opens the sheet', (tester) async {
      await pumpTile(tester, const Size(400, 860));
      await tester.longPress(find.text('Menu Song'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Play next'), findsOneWidget);
    });

    testWidgets('phone: ⋯ on the last row opens a sheet, not a pop-up', (
      tester,
    ) async {
      await pumpTile(tester, const Size(400, 860));
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('desktop: right-click opens the menu where clicked', (
      tester,
    ) async {
      await pumpTile(tester, const Size(1400, 900));
      final click = tester.getCenter(find.text('Menu Song'));
      await tester.tapAt(click, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Play next'), findsOneWidget);
      // At the pointer (shifted up only as far as it must to fit).
      final item = tester.getRect(find.text('Play next'));
      expect((item.left - click.dx).abs(), lessThan(80));
      expect(click.dy - item.top, lessThan(400));
    });
  });

  testWidgets('phone: swipe up on the mini player opens the full player', (
    tester,
  ) async {
    player.queue.value = [
      const Track(id: 'p', title: 'Mini', artist: 'X', artUrl: ''),
    ];
    player.index.value = 0;
    addTearDown(() {
      player.queue.value = [];
      player.index.value = -1;
    });
    await pumpApp(tester, const Size(400, 860));
    await tester.fling(find.byType(MiniPlayer), const Offset(0, -150), 1200);
    await tester.pumpAndSettle();
    expect(find.byType(FullPlayer), findsOneWidget);
  });
}

const _target = Key('swipe target');
