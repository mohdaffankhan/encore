import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:encore/main.dart' as app;
import 'package:encore/services/library.dart';
import 'package:encore/services/player.dart';
import 'package:encore/ui/pages/collection_page.dart';
import 'package:encore/ui/pages/import_page.dart';
import 'package:encore/ui/player/player_ui.dart';
import 'package:encore/ui/shell.dart';
import 'package:encore/ui/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

// The screenshots in the README and the app stores: the real app with real
// content, one screen at a time. Not a test of behaviour (app_test.dart is).
//   flutter test integration_test/screenshots_test.dart \
//     --dart-define=ENCORE_TEST=true -d windows
// Desktop shots land in build/screenshots/<os>/readme; on Android they are
// printed for tool/collect_screenshots.py (see README, "Screenshots").

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screenshots', (tester) async {
    await app.main();
    await tester.pump();
    userLibrary
      ..liked.value = []
      ..history.value = []
      ..playlists.value = [];
    final shots = await _Shots.create();
    final wide =
        MediaQuery.sizeOf(tester.element(find.byType(Shell))).width >= 900;

    // Home.
    await _until(tester, find.byType(ShelfView));
    await shots.take(tester, 'home');

    // Search.
    await tester.tap(find.text('Search').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.enterText(
      find.byType(TextField),
      'the weeknd blinding lights',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _until(tester, find.byType(TrackTile));
    FocusManager.instance.primaryFocus?.unfocus();
    await shots.take(tester, 'search');

    // The player, with synced lyrics.
    await tester.tap(find.byType(TrackTile).first);
    await _untilTrue(
      tester,
      () => player.audio.playing && player.audio.position.inSeconds >= 1,
    );
    // Into the song, where the lyrics have started.
    await player.audio.seek(const Duration(seconds: 62));
    openFullPlayer(
      tester.element(find.byType(Shell)),
      view: wide ? PlayerView.lyrics : PlayerView.song,
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await shots.take(tester, 'player');
    if (!wide) {
      await tester.fling(
        find.descendant(
          of: find.byType(FullPlayer),
          matching: find.byType(SwipeToSkip),
        ),
        const Offset(0, -300),
        1500,
      );
    }
    await _until(tester, find.byType(LyricsView));
    await _untilTrue(
      tester,
      () => find
          .descendant(
            of: find.byType(LyricsView),
            matching: find.byType(CircularProgressIndicator),
          )
          .evaluate()
          .isEmpty,
    );
    await shots.take(tester, 'lyrics');
    await player.audio.pause();
    Navigator.of(tester.element(find.byType(FullPlayer))).pop();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Importing a Spotify playlist, then the playlist.
    await tester.tap(find.text('Library').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import playlist'));
    await tester.pumpAndSettle();
    final linkField = find.descendant(
      of: find.byType(ImportPage),
      matching: find.byType(TextField),
    );
    await tester.tap(linkField);
    await tester.enterText(
      linkField,
      'https://open.spotify.com/playlist/37i9dQZF1DX0XUfTFmNBRM', // Hot Hits Hindi
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    final save = find.textContaining('Save playlist');
    await _until(tester, save, timeout: const Duration(seconds: 120));
    FocusManager.instance.primaryFocus?.unfocus();
    await shots.take(tester, 'import');
    await tester.tap(save);
    await _until(
      tester,
      find.descendant(
        of: find.byType(CollectionPage),
        matching: find.byType(TrackTile),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await shots.take(tester, 'playlist');

    // Library with it.
    openPage(const _Empty(), tab: AppTab.library);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(_Empty)))
        .popUntil((r) => r.isFirst);
    await tester.pumpAndSettle();
    await shots.take(tester, 'library');

    // An artist.
    openArtist('UCDxKh1gFWeYsqePvgVzmPoQ'); // Arijit Singh
    await _until(tester, find.text('Popular'));
    await shots.take(tester, 'artist');

    userLibrary.playlists.value = [];
    await player.audio.stop();
  }, timeout: const Timeout(Duration(minutes: 6)));
}

/// A blank page, to get the Library tab's navigator.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

Future<void> _until(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) => _untilTrue(tester, () => finder.evaluate().isNotEmpty, timeout: timeout);

Future<void> _untilTrue(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('Timed out');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Shots {
  _Shots(this.dir);

  final Directory dir;

  static Future<_Shots> create() async {
    final base = Platform.isAndroid
        ? (await getTemporaryDirectory()).path
        : '${Directory.current.path}/build';
    final dir = Directory(
      '$base/screenshots/${Platform.operatingSystem}/readme',
    );
    await dir.create(recursive: true);
    return _Shots(dir);
  }

  Future<void> take(WidgetTester tester, String name) async {
    // Let artwork arrive and animations settle.
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(
      Offset.zero & (view.size * tester.view.devicePixelRatio),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = png!.buffer.asUint8List();
    await File('${dir.path}/$name.png').writeAsBytes(bytes);
    // ignore: avoid_print
    print('[screenshot] $name');
    if (Platform.isAndroid) {
      final data = base64Encode(bytes);
      for (var i = 0; i < data.length; i += 1000) {
        // ignore: avoid_print
        print('[shot:$name] ${data.substring(i, min(i + 1000, data.length))}');
      }
    }
  }
}
