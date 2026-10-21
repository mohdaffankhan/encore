import 'package:encore/models.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/player.dart';
import 'package:encore/services/sleep_timer.dart';
import 'package:encore/ui/player/player_ui.dart';
import 'package:encore/ui/shell.dart';
import 'package:encore/ui/theme.dart';
import 'package:encore/ui/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test.dart' show pumpApp;

void main() {
  tearDown(sleepTimer.cancel);

  const song = Track(
    id: 'abc',
    title: 'A Song',
    artist: 'An Artist',
    artUrl: '',
    artistId: 'UCx',
    albumId: 'MPREx',
  );

  /// The full player for [song], on a phone or a desktop window.
  Future<void> pumpPlayer(WidgetTester tester, {bool desktop = false}) async {
    tester.view
      ..physicalSize = desktop ? const Size(1400, 900) : const Size(400, 860)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    player.queue.value = [song];
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

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(FullPlayer),
        matching: find.byTooltip('More'),
      ),
    );
    await tester.pumpAndSettle();
  }

  final moon = find.byType(SleepTimerIndicator);
  final moonIcon = find.byIcon(Icons.bedtime_rounded);

  for (final desktop in [false, true]) {
    final where = desktop ? 'desktop' : 'phone';

    testWidgets('$where: sleep timer is in the ⋯ menu', (tester) async {
      await pumpPlayer(tester, desktop: desktop);
      expect(moonIcon, findsNothing, reason: 'no moon while off');

      await openMenu(tester);
      await tester.tap(find.text('Sleep timer'));
      await tester.pumpAndSettle();
      for (final option in [
        '15 minutes',
        '30 minutes',
        '45 minutes',
        '1 hour',
        'End of song',
      ]) {
        expect(find.text(option), findsOneWidget);
      }
      expect(
        find.text('Turn off'),
        findsNothing,
        reason: 'nothing to turn off',
      );
      await tester.tap(find.text('30 minutes'));
      await tester.pumpAndSettle();
      expect(sleepTimer.remaining!.inMinutes, 29);
      expect(find.text('Pausing in 30 min'), findsOneWidget, reason: 'toast');
      expect(
        find.descendant(of: moon, matching: moonIcon),
        findsOneWidget,
        reason: 'a moon shows while it is on',
      );

      // The menu shows the time left.
      await openMenu(tester);
      expect(find.text('30 min'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5)); // close it
      await tester.pumpAndSettle();

      // The moon opens the timer too, to turn it off.
      await tester.tap(moonIcon);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      expect(sleepTimer.setting.value, isNull);
      expect(moonIcon, findsNothing);
    });
  }

  testWidgets('sleep timer: end of song is shown as selected', (tester) async {
    await pumpPlayer(tester);
    await openMenu(tester);
    await tester.tap(find.text('Sleep timer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End of song'));
    await tester.pumpAndSettle();
    expect(sleepTimer.setting.value!.endOfSong, isTrue);

    await tester.tap(moonIcon);
    await tester.pumpAndSettle();
    final picker = find.byType(BottomSheet);
    expect(
      find.descendant(
        of: picker,
        matching: find.text('Pausing at the end of this song'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: picker, matching: find.byIcon(Icons.check_rounded)),
      findsOneWidget,
    );
  });

  testWidgets('phone: the song menu is a bottom sheet with the song on top', (
    tester,
  ) async {
    await pumpPlayer(tester);
    await openMenu(tester);
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('A Song')),
      findsOneWidget,
    );
    for (final action in [
      'Start radio',
      'Like',
      'Download',
      'Go to artist',
      'Go to album',
      'Sleep timer',
    ]) {
      expect(
        find.descendant(of: sheet, matching: find.text(action)),
        findsOneWidget,
      );
    }
    // Liking says so.
    await tester.tap(find.text('Like'));
    await tester.pumpAndSettle();
    expect(find.text('Added to Liked songs'), findsOneWidget);
    expect(userLibrary.isLiked(song), isTrue);
    userLibrary.toggleLike(song);
  });

  testWidgets('desktop: the song menu opens under the ⋯ button', (
    tester,
  ) async {
    await pumpPlayer(tester, desktop: true);
    final button = tester.getRect(
      find.descendant(
        of: find.byType(FullPlayer),
        matching: find.byTooltip('More'),
      ),
    );
    await openMenu(tester);
    expect(find.byType(BottomSheet), findsNothing);
    final menuTop = tester.getTopLeft(find.text('Start radio')).dy;
    expect(menuTop, greaterThan(button.bottom), reason: 'below, not over it');
  });

  testWidgets('song sections offer View all, which lists every song', (
    tester,
  ) async {
    final tracks = [
      for (var i = 1; i <= 10; i++)
        Track(id: 'id$i', title: 'Song $i', artist: 'Artist', artUrl: ''),
    ];
    await pumpApp(tester, const Size(400, 860));
    openPage(Scaffold(body: ShelfView(Shelf('Quick picks', tracks: tracks))));
    await tester.pumpAndSettle();
    expect(find.text('Play all'), findsNothing);

    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();
    expect(find.text('10 songs'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Song 10'), 200);
    expect(find.text('Song 10'), findsOneWidget);
    // The phone frame stays, with Back to the section.
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('View all'), findsOneWidget);
  });
}
