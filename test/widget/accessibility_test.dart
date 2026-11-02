import 'package:encore/models.dart';
import 'package:encore/services/home_cache.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/player.dart';
import 'package:encore/ui/pages/collection_page.dart';
import 'package:encore/ui/pages/library_page.dart';
import 'package:encore/ui/player/player_ui.dart';
import 'package:encore/ui/shell.dart';
import 'package:encore/ui/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'shell_test.dart' show pumpApp;

// Screen readers (TalkBack, Narrator, Orca): every screen is checked for
// buttons without a name, tap targets too small to hit, and text too
// faint to read.

const _songs = [
  Track(
    id: 'a',
    title: 'First song',
    artist: 'An artist',
    album: 'An album',
    artistId: 'UCa',
    albumId: 'MPREa',
    artUrl: '',
    duration: Duration(minutes: 3),
  ),
  Track(id: 'b', title: 'Second song', artist: 'Someone', artUrl: ''),
  Track(id: 'c', title: 'Third song', artist: 'Another', artUrl: ''),
];

/// The screens to check, each opened from the app as it starts.
final _screens = <String, Future<void> Function(WidgetTester)>{
  'home': (tester) async {},
  'search': (tester) => tester.tap(find.text('Search').first),
  'library': (tester) => tester.tap(find.text('Library').first),
  'settings': (tester) async => openSettings(),
  'liked songs': (tester) async =>
      openPage(libraryCollections.first.page(), tab: AppTab.library),
  'a playlist': (tester) async {
    final p = userLibrary.playlists.value.first;
    openPage(CollectionPage.playlist(p.id), tab: AppTab.library);
  },
  'full player': (tester) async =>
      openFullPlayer(tester.element(find.byType(Shell))),
  'up next': (tester) async => openFullPlayer(
    tester.element(find.byType(Shell)),
    view: PlayerView.queue,
  ),
  'equalizer': (tester) async {
    openSettings();
    await tester.pumpAndSettle();
    // ignore: unawaited_futures
    showEqualizer(tester.element(find.text('Settings').first));
  },
};

/// Each node's problem, without text fields' size: what is typed into
/// sits inside the search box, and the whole box (56 px) is tapped.
List<String> _problems(String reason) => [
  for (final node in reason.split(RegExp(r'(?=SemanticsNode#)')))
    if (node.trim().isNotEmpty &&
        !(node.contains('isTextField') && node.contains('tap target size')))
      node.trim(),
];

void main() {
  setUp(() {
    // The version Settings shows.
    PackageInfo.setMockInitialValues(
      appName: 'Encore',
      packageName: 'dev.encore.app',
      version: '0.1.5',
      buildNumber: '18',
      buildSignature: '',
    );
    lastHome = [
      Shelf('Quick picks', tracks: [..._songs, ..._songs.reversed]),
    ];
    userLibrary.liked.value = [..._songs];
    userLibrary.history.value = [..._songs];
    userLibrary.createPlaylist('Road trip', tracks: [..._songs]);
    player.queue.value = [..._songs];
    player.index.value = 0;
  });

  tearDown(() {
    lastHome = null;
    userLibrary.liked.value = [];
    userLibrary.history.value = [];
    userLibrary.playlists.value = [];
    player.queue.value = [];
    player.index.value = -1;
  });

  for (final (device, size) in [
    ('phone', const Size(400, 860)),
    ('desktop', const Size(1400, 900)),
  ]) {
    for (final MapEntry(key: name, value: open) in _screens.entries) {
      testWidgets('$device: $name works with a screen reader', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpApp(tester, size);
        await open(tester);
        await tester.pumpAndSettle();
        final problems = [
          for (final guideline in [
            labeledTapTargetGuideline,
            if (device == 'phone') androidTapTargetGuideline,
            textContrastGuideline,
          ])
            if (await guideline.evaluate(tester) case final e when !e.passed)
              ..._problems(e.reason!),
        ];
        semantics.dispose();
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }
  }
}
