import 'package:encore/models.dart';
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

  Future<void> pumpButton(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: const Scaffold(body: Center(child: SleepTimerButton())),
    ),
  );

  Color iconColor(WidgetTester tester) => tester
      .widget<Icon>(
        find.descendant(
          of: find.byType(SleepTimerButton),
          matching: find.byType(Icon),
        ),
      )
      .color!;

  testWidgets('sleep timer: set a time, see it, turn it off', (tester) async {
    await pumpButton(tester);
    expect(find.byTooltip('Sleep timer'), findsOneWidget);
    expect(iconColor(tester), isNot(EncoreColors.accent));

    await tester.tap(find.byType(SleepTimerButton));
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
    expect(find.text('Turn off'), findsNothing, reason: 'nothing to turn off');
    await tester.tap(find.text('30 minutes'));
    await tester.pumpAndSettle();

    expect(sleepTimer.remaining!.inMinutes, 29);
    expect(iconColor(tester), EncoreColors.accent, reason: 'highlighted');

    await tester.tap(find.byType(SleepTimerButton));
    await tester.pumpAndSettle();
    expect(find.text('Pausing in 30 min'), findsOneWidget);
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(sleepTimer.setting.value, isNull);
    expect(iconColor(tester), isNot(EncoreColors.accent));
  });

  testWidgets('sleep timer: end of song is shown as selected', (tester) async {
    await pumpButton(tester);
    await tester.tap(find.byType(SleepTimerButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End of song'));
    await tester.pumpAndSettle();
    expect(sleepTimer.setting.value!.endOfSong, isTrue);

    await tester.tap(find.byType(SleepTimerButton));
    await tester.pumpAndSettle();
    expect(find.text('Pausing at the end of this song'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
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
