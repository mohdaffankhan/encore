import 'dart:async';

import 'package:encore/models.dart';
import 'package:encore/services/account.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/player.dart';
import 'package:encore/services/youtube_sync.dart';
import 'package:encore/ui/pages/artist_page.dart';
import 'package:encore/ui/pages/collection_page.dart';
import 'package:encore/ui/pages/home_page.dart';
import 'package:encore/ui/pages/library_page.dart';
import 'package:encore/ui/pages/sync_question.dart';
import 'package:encore/ui/player/player_ui.dart';
import 'package:encore/ui/shell.dart';
import 'package:encore/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/account_test.dart' show MemoryStore, goodCookies;
import 'shell_test.dart' show pumpApp;

const _song = Track(
  id: 'abc',
  title: 'A Song',
  artist: 'An Artist',
  artUrl: '',
);

const _album = MediaRef(
  kind: MediaKind.album,
  id: 'MPREa',
  title: 'An Album',
  subtitle: 'Some Artist',
  artUrl: '',
);
const _artist = MediaRef(
  kind: MediaKind.artist,
  id: 'UCa',
  title: 'Some Artist',
  subtitle: '2M listeners',
  artUrl: '',
);

Future<void> openLibrary(WidgetTester tester) async {
  await pumpApp(tester, const Size(400, 860));
  await tester.tap(find.text('Library').last);
  await tester.pumpAndSettle();
}

Future<void> signIn() async {
  account.reset(store: MemoryStore());
  account.whoIs = () async => const AccountInfo(name: 'Test Listener');
  expect(await account.signInWith(goodCookies()), isNull);
}

Widget _app(Widget child) => MaterialApp(
  theme: appTheme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  tearDown(() {
    userLibrary.savedMedia.value = [];
    userLibrary.artists.value = [];
    userLibrary.playlists.value = [];
    userLibrary.liked.value = [];
    userLibrary.history.value = [];
    account.reset(store: MemoryStore());
    player.queue.value = [];
    player.index.value = -1;
  });

  group('Library', () {
    testWidgets('saved albums and followed artists have sections of their '
        'own, shown once there are any', (tester) async {
      await openLibrary(tester);
      expect(find.text('Albums and playlists'), findsNothing);
      expect(find.text('Artists'), findsNothing);
      userLibrary.savedMedia.value = [_album];
      userLibrary.artists.value = [_artist];
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Some Artist').last, 200);
      expect(find.text('Albums and playlists'), findsOneWidget);
      expect(find.text('An Album'), findsOneWidget);
      expect(find.text('Album • Some Artist'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget, reason: 'no listener count');
    });

    testWidgets('a saved album opens its page', (tester) async {
      userLibrary.savedMedia.value = [_album];
      await openLibrary(tester);
      await tester.scrollUntilVisible(find.text('An Album'), 200);
      await tester.tap(find.text('An Album'));
      await tester.pumpAndSettle();
      expect(find.byType(CollectionPage), findsOneWidget);
    });

    testWidgets('a followed artist opens their page', (tester) async {
      userLibrary.artists.value = [_artist];
      await openLibrary(tester);
      await tester.scrollUntilVisible(find.text('Some Artist'), 200);
      await tester.tap(find.text('Some Artist'));
      await tester.pumpAndSettle();
      expect(find.byType(ArtistPage), findsOneWidget);
    });

    testWidgets('signed out: no sync status', (tester) async {
      await openLibrary(tester);
      expect(find.text('Sync now'), findsNothing);
    });

    testWidgets('signed in: sync status and Sync now', (tester) async {
      await signIn();
      await openLibrary(tester);
      expect(find.text('Not synced with YouTube Music yet'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
    });

    testWidgets('a long album name fits on a phone', (tester) async {
      userLibrary.savedMedia.value = [
        MediaRef(
          kind: MediaKind.album,
          id: 'MPREl',
          title: 'A very long album name ' * 6,
          subtitle: 'An artist with a long name ' * 4,
          artUrl: '',
        ),
      ];
      await openLibrary(tester);
      expect(tester.takeException(), isNull);
    });
  });

  test('sync status says what is going on', () {
    final now = DateTime.now();
    String d(SyncState s, DateTime? at, int n) => SyncStatus.describe(s, at, n);
    String p(int left, int total, {bool offline = false}) =>
        SyncStatus.describe(
          SyncState.idle,
          now,
          left,
          total: total,
          offline: offline,
        );
    expect(d(SyncState.syncing, null, 0), 'Syncing with YouTube Music…');
    expect(p(3, 5), 'Sending to YouTube Music: 2 of 5');
    expect(p(5, 0), 'Sending to YouTube Music: 0 of 5');
    expect(
      p(3, 5, offline: true),
      'Waiting for a connection: 3 to send to YouTube Music',
    );
    expect(d(SyncState.idle, null, 0), 'Not synced with YouTube Music yet');
    expect(d(SyncState.idle, now, 0), 'Synced with YouTube Music just now');
    expect(
      d(SyncState.idle, now.subtract(const Duration(minutes: 5)), 0),
      'Synced with YouTube Music 5 min ago',
    );
    expect(
      d(SyncState.idle, now.subtract(const Duration(hours: 3)), 0),
      'Synced with YouTube Music 3 h ago',
    );
    expect(
      d(SyncState.idle, now.subtract(const Duration(days: 2)), 0),
      'Synced with YouTube Music 2 d ago',
    );
    expect(d(SyncState.idle, now, 1), 'Sending to YouTube Music: 0 of 1');
    expect(d(SyncState.failed, now, 0), "Couldn't sync with YouTube Music");
    expect(
      d(SyncState.failed, now, 2),
      "Couldn't sync: 2 changes wait to be sent",
    );
  });

  group('sending, shown', () {
    tearDown(() {
      youtubeSync.pending.value = const [];
      youtubeSync.total.value = 0;
      youtubeSync.waiting.value = false;
    });

    testWidgets('a progress bar, how far, and that it carries on later', (
      tester,
    ) async {
      await signIn();
      await openLibrary(tester);
      youtubeSync.pending.value = [
        for (var i = 0; i < 30; i++) SyncOp('like', 's$i'),
      ];
      youtubeSync.total.value = 40;
      await tester.pump();
      expect(find.text('Sending to YouTube Music: 10 of 40'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.25);
      expect(find.textContaining('carries on next time'), findsOneWidget);
    });

    testWidgets('a few: no note', (tester) async {
      await signIn();
      await openLibrary(tester);
      youtubeSync.pending.value = [SyncOp('like', 'a')];
      youtubeSync.total.value = 2;
      await tester.pump();
      expect(find.text('Sending to YouTube Music: 1 of 2'), findsOneWidget);
      expect(find.textContaining('carries on next time'), findsNothing);
    });

    testWidgets('offline: waiting for a connection, and Try now', (
      tester,
    ) async {
      await signIn();
      await openLibrary(tester);
      youtubeSync.pending.value = [SyncOp('like', 'a')];
      youtubeSync.total.value = 1;
      youtubeSync.waiting.value = true;
      await tester.pump();
      expect(find.textContaining('Waiting for a connection'), findsOneWidget);
      expect(find.text('Try now'), findsOneWidget);
    });
  });

  group('the first sync question', () {
    const plan = SyncPlan(
      likes: 450,
      playlists: 3,
      playlistSongs: 1240,
      saved: 2,
      artists: 1,
      requests: 500,
      newLikes: 712,
      newPlaylists: 1,
    );

    test('says what goes, what comes, and how long', () {
      expect(
        SyncQuestion.sending(plan),
        '450 liked songs, 3 playlists (1240 songs), 2 saved albums and '
        'playlists and 1 followed artist',
      );
      expect(SyncQuestion.bringing(plan), '712 liked songs and 1 playlist');
      expect(SyncQuestion.bringing(const SyncPlan(requests: 1)), 'nothing');
      expect(
        SyncQuestion.sending(const SyncPlan(playlistSongs: 3, requests: 1)),
        '3 songs in playlists',
      );
      expect(
        SyncQuestion.duration(const Duration(seconds: 40)),
        'under a minute',
      );
      expect(
        SyncQuestion.duration(const Duration(seconds: 500)),
        'about 9 minutes',
      );
    });

    Future<void> ask(WidgetTester tester) async {
      await pumpApp(tester, const Size(400, 860));
      youtubeSync.question.value = plan;
      await tester.pumpAndSettle();
      expect(find.byType(SyncQuestion), findsOneWidget);
      expect(find.textContaining('450 liked songs'), findsOneWidget);
      expect(find.textContaining('Nothing is removed'), findsOneWidget);
    }

    testWidgets('asked over the app; Sync answers yes', (tester) async {
      bool? said;
      final answer = youtubeSync.question;
      addTearDown(() => answer.value = null);
      youtubeSync.question.addListener(() {});
      await ask(tester);
      // The answer goes to the sync service.
      final done = Completer<void>();
      answer.addListener(() {
        if (answer.value == null && !done.isCompleted) done.complete();
      });
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();
      said = answer.value == null;
      expect(said, isTrue);
      expect(find.byType(SyncQuestion), findsNothing);
    });

    testWidgets("it can't be dismissed by tapping outside", (tester) async {
      addTearDown(() => youtubeSync.question.value = null);
      await ask(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(SyncQuestion), findsOneWidget);
      await tester.tap(find.text('Sign out instead'));
      await tester.pumpAndSettle();
      expect(find.byType(SyncQuestion), findsNothing);
      expect(youtubeSync.question.value, isNull);
    });
  });

  testWidgets('Settings, signed in, shows the sync status', (tester) async {
    await signIn();
    await pumpApp(tester, const Size(1400, 900));
    openSettings();
    await tester.pumpAndSettle();
    expect(find.text('Not synced with YouTube Music yet'), findsOneWidget);
  });

  testWidgets('Save to library on an album saves it, and again removes it', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const SaveToLibraryButton(_album)));
    expect(find.byTooltip('Save to library'), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(userLibrary.isSaved('MPREa'), isTrue);
    expect(find.text('Saved to library'), findsOneWidget);
    expect(find.byTooltip('Remove from library'), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(userLibrary.isSaved('MPREa'), isFalse);
  });

  testWidgets('Follow on an artist follows, and again unfollows', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const FollowButton(_artist)));
    await tester.tap(find.text('Follow'));
    await tester.pump();
    expect(userLibrary.isFollowed('UCa'), isTrue);
    expect(find.text('Following'), findsOneWidget);
    await tester.tap(find.text('Following'));
    await tester.pump();
    expect(userLibrary.isFollowed('UCa'), isFalse);
  });

  group('Add to playlist in the player', () {
    Future<void> openPlayer(WidgetTester tester, Size size) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      player.queue.value = [_song];
      player.index.value = 0;
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

    final inPlayer = find.descendant(
      of: find.byType(FullPlayer),
      matching: find.byTooltip('Add to playlist'),
    );

    testWidgets('next to like: picks a playlist, then shows it is in one', (
      tester,
    ) async {
      userLibrary.createPlaylist('Road trip');
      await openPlayer(tester, const Size(400, 860));
      expect(inPlayer, findsOneWidget);
      await tester.tap(inPlayer);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Road trip'));
      await tester.pumpAndSettle();
      expect(userLibrary.playlists.value.single.tracks, [_song]);
      final button = tester.widget<IconButton>(
        find.ancestor(of: inPlayer, matching: find.byType(IconButton)).first,
      );
      expect((button.icon as Icon).icon, Icons.playlist_add_check_rounded);
    });

    testWidgets('a new playlist can be made from it', (tester) async {
      await openPlayer(tester, const Size(400, 860));
      await tester.tap(inPlayer);
      await tester.pumpAndSettle();
      await tester.tap(find.text('New playlist'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Fresh');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(userLibrary.playlists.value.single.name, 'Fresh');
      expect(userLibrary.playlists.value.single.tracks, [_song]);
    });

    testWidgets('desktop: in the player bar and the full player', (
      tester,
    ) async {
      player.queue.value = [_song];
      player.index.value = 0;
      await pumpApp(tester, const Size(1400, 900));
      expect(
        find.descendant(
          of: find.byType(NowPlayingBar),
          matching: find.byTooltip('Add to playlist'),
        ),
        findsOneWidget,
      );
    });
  });

  group('Play something', () {
    testWidgets('nothing to start from: not shown', (tester) async {
      await tester.pumpWidget(_app(const PlaySomething(feed: [])));
      expect(find.text('Play something'), findsNothing);
    });

    testWidgets('starts a radio from a song the user likes or played', (
      tester,
    ) async {
      userLibrary.history.value = [_song];
      await tester.pumpWidget(_app(const PlaySomething(feed: [])));
      await tester.tap(find.text('Play something'));
      await tester.pump();
      expect(player.queue.value.first, _song);
    });

    testWidgets("a new user: from the home feed's songs", (tester) async {
      await tester.pumpWidget(
        _app(
          const PlaySomething(
            feed: [
              Shelf('Quick picks', tracks: [_song]),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Play something'));
      await tester.pump();
      expect(player.queue.value.first, _song);
    });

    test("the user's own songs are more likely than the feed's", () {
      userLibrary.liked.value = [_song];
      final seeds = PlaySomething.seeds([
        const Shelf(
          'Feed',
          tracks: [Track(id: 'f', title: 'F', artist: 'x', artUrl: '')],
        ),
      ]);
      expect(seeds.where((t) => t == _song).length, 2);
      expect(seeds.length, 3);
    });

    testWidgets('phone: an icon by search and settings in the greeting row', (
      tester,
    ) async {
      userLibrary.history.value = [_song];
      await pumpApp(tester, const Size(400, 860));
      final button = find.byTooltip('Play something');
      expect(button, findsOneWidget);
      expect(find.text('Play something'), findsNothing, reason: 'an icon');
      final row = tester.getCenter(find.byTooltip('Settings')).dy;
      expect(tester.getCenter(button).dy, row);
      // Level with the greeting's letters, which sit low in their line.
      final greeting = tester.getCenter(find.textContaining(RegExp(r'^Good ')));
      expect(row - greeting.dy, inInclusiveRange(1, 4));
    });

    testWidgets('desktop: a button at the end of the greeting row', (
      tester,
    ) async {
      userLibrary.history.value = [_song];
      await pumpApp(tester, const Size(1400, 900));
      // Quiet (not a filled button) and shorter than the greeting.
      final button = find.widgetWithText(TextButton, 'Play something');
      expect(button, findsOneWidget);
      final greeting = find.textContaining(RegExp(r'^Good '));
      // (Its pill, that is: clicking it reaches a little further.)
      final pill = find.descendant(of: button, matching: find.byType(Material));
      expect(
        tester.getSize(pill.first).height,
        lessThan(tester.getSize(greeting).height),
      );
      expect(
        (tester.getCenter(button).dy - tester.getCenter(greeting).dy).abs(),
        lessThan(8),
      );
      expect(
        tester.getCenter(button).dx,
        greaterThan(tester.getCenter(greeting).dx),
      );
    });
  });
}
