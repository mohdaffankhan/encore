import 'package:encore/main.dart' as app;
import 'package:encore/services/player.dart';
import 'package:encore/ui/player/player_ui.dart';
import 'package:encore/ui/shell.dart';
import 'package:encore/ui/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Frame timings for the interactions that felt laggy. Must run in profile
// mode to mean anything:
//   flutter drive --profile --no-dds --driver=test_driver/perf_driver.dart \
//     --target=integration_test/perf_test.dart -d windows

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scrolling and navigation stay smooth', (tester) async {
    await app.main();
    await _until(tester, () => find.byType(ShelfView).evaluate().isNotEmpty);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await binding.watchPerformance(() async {
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 4; i++) {
        await tester.fling(list, const Offset(0, -600), 2500);
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 4; i++) {
        await tester.fling(list, const Offset(0, 600), 2500);
        await tester.pumpAndSettle();
      }
    }, reportKey: 'home_scroll');

    // A playlist page: open, scroll, back.
    final card = find.byType(MediaCard).first;
    await binding.watchPerformance(() async {
      await tester.tap(card);
      await _until(
        tester,
        () => find.byType(PlayCircleButton).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(Scrollable).last,
        const Offset(0, -800),
        3000,
      );
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
    }, reportKey: 'open_page');

    // Full player open and close while a song (from quick picks) plays.
    await tester.tap(find.byType(TrackTile).first);
    await _until(tester, () => player.audio.playing);
    await binding.watchPerformance(() async {
      for (var i = 0; i < 3; i++) {
        openFullPlayer(shellKey.currentContext!);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
      }
    }, reportKey: 'full_player');
    await player.audio.stop();
  });
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('Timed out');
    await tester.pump(const Duration(milliseconds: 100));
  }
}
