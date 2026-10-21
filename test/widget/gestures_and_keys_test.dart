import 'package:encore/models.dart';
import 'package:encore/services/player.dart';
import 'package:encore/ui/pages/search_page.dart';
import 'package:encore/ui/player/player_ui.dart';
import 'package:encore/ui/shortcuts.dart';
import 'package:encore/ui/theme.dart';
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

    testWidgets('swipe up shows lyrics; Back returns to the song', (
      tester,
    ) async {
      await pumpPlayer(tester);
      expect(find.byType(LyricsView), findsNothing);
      expect(find.byType(SwipeToSkip), findsOneWidget);

      await tester.fling(find.text('A Song'), const Offset(0, -200), 1200);
      await tester.pumpAndSettle();
      expect(find.byType(LyricsView), findsOneWidget);
      // Offline in tests: an error with Retry, not "No lyrics".
      expect(find.text("Couldn't load lyrics."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Back goes to the song first, then closes the player.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(FullPlayer), findsOneWidget);
      expect(find.byType(LyricsView), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(FullPlayer), findsNothing);
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

    testWidgets('swipe up starting on the artwork shows lyrics', (
      tester,
    ) async {
      // The sideways swipe on the artwork gives way to the vertical one.
      await pumpPlayer(tester);
      await tester.fling(find.byType(SwipeToSkip), const Offset(0, -250), 1200);
      await tester.pumpAndSettle();
      expect(find.byType(LyricsView), findsOneWidget);
    });

    testWidgets('the Lyrics cue opens lyrics too', (tester) async {
      await pumpPlayer(tester);
      await tester.tap(find.text('Lyrics').last);
      await tester.pumpAndSettle();
      expect(find.byType(LyricsView), findsOneWidget);
    });

    testWidgets('swiping down on the song does not open lyrics', (
      tester,
    ) async {
      await pumpPlayer(tester);
      await tester.fling(find.text('A Song'), const Offset(0, 200), 1200);
      await tester.pumpAndSettle();
      expect(find.byType(LyricsView), findsNothing);
    });
  });
}

const _target = Key('swipe target');
