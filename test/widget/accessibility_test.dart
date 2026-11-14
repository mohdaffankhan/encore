import 'package:encore/models.dart';
import 'package:encore/services/account.dart';
import 'package:encore/services/home_cache.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/player.dart';
import 'package:encore/services/youtube_sync.dart';
import 'package:encore/ui/pages/account_settings.dart';
import 'package:encore/ui/pages/collection_page.dart';
import 'package:encore/ui/pages/library_page.dart';
import 'package:encore/ui/player/player_ui.dart';
import 'package:encore/ui/shell.dart';
import 'package:encore/ui/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../unit/account_test.dart' show MemoryStore, goodCookies;
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
  'library, signed in, with saved albums and artists': (tester) async {
    account.reset(store: MemoryStore());
    account.whoIs = () async => const AccountInfo(name: 'Test Listener');
    await account.signInWith(goodCookies());
    userLibrary.savedMedia.value = const [
      MediaRef(
        kind: MediaKind.album,
        id: 'MPREa',
        title: 'An album',
        subtitle: 'An artist',
        artUrl: '',
      ),
    ];
    userLibrary.artists.value = const [
      MediaRef(
        kind: MediaKind.artist,
        id: 'UCa',
        title: 'An artist',
        subtitle: '',
        artUrl: '',
      ),
    ];
    await tester.tap(find.text('Library').first);
  },
  'settings': (tester) async => openSettings(),
  'settings, signed in': (tester) async {
    account.reset(store: MemoryStore());
    account.whoIs = () async =>
        const AccountInfo(name: 'Test Listener', handle: '@test');
    await account.signInWith(goodCookies());
    openSettings();
  },
  'settings, sign-in ended': (tester) async {
    account.reset(store: MemoryStore());
    account.whoIs = () async => const AccountInfo(name: 'Test Listener');
    await account.signInWith(goodCookies());
    account.whoIs = () async => null;
    account.replied(account.headers()!, const [], 401, null);
    openSettings();
    await tester.pumpAndSettle();
    ScaffoldMessenger.of(tester.element(find.byType(Shell))).clearSnackBars();
  },
  'many removals at once': (tester) async {
    youtubeSync.removals.value = const RemovalQuestion(songs: 228);
  },
  'first sync question': (tester) async {
    youtubeSync.question.value = const SyncPlan(
      likes: 450,
      playlists: 3,
      playlistSongs: 1240,
      requests: 500,
      newLikes: 712,
    );
  },
  'library, sending to YouTube Music': (tester) async {
    account.reset(store: MemoryStore());
    account.whoIs = () async => const AccountInfo(name: 'Test Listener');
    await account.signInWith(goodCookies());
    youtubeSync.pending.value = [
      for (var i = 0; i < 30; i++) SyncOp('like', 's$i'),
    ];
    youtubeSync.total.value = 40;
    await tester.tap(find.text('Library').first);
  },
  'sign in with a browser': (tester) async {
    openSettings();
    await tester.pumpAndSettle();
    // ignore: unawaited_futures
    pasteSignIn(tester.element(find.text('Settings').first));
  },
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
    account.reset(store: MemoryStore());
    youtubeSync.question.value = null;
    youtubeSync.removals.value = null;
    youtubeSync.pending.value = const [];
    youtubeSync.total.value = 0;
    userLibrary.savedMedia.value = [];
    userLibrary.artists.value = [];
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
