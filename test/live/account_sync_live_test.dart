// Run by hand only (never in CI), against a signed-in TEST account:
//   flutter test test/live/account_sync_live_test.dart \
//     --dart-define=ENCORE_ACCOUNT_DIR=<test_data folder>
// Checks each request the sync sends against YouTube Music itself, and
// leaves the account as it was: a playlist it makes is deleted, a song,
// album and artist it likes, saves or follows (only ones that weren't) are
// unliked, unsaved, unfollowed. One play is counted (it shows in history).
import 'dart:io';

import 'package:encore/api/innertube.dart' as yt;
import 'package:encore/services/account.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/youtube_sync.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = String.fromEnvironment('ENCORE_ACCOUNT_DIR');

/// Songs, an album and an artist to try with (not in the test library).
const _songs = ['cQq6iLF66Gc', 'ebZj_nrmH-c', 'DA3GyfDY0Aw', '2nK6WBcGPOw'];
const _album = 'MPREb_2IPsncXPdzh';
const _artist = 'UC-kVv2dTX6UD68r3wUmExKw';

Future<void> pause() => Future<void>.delayed(const Duration(seconds: 2));

/// YouTube takes a few seconds to show a change: checks [check] until it
/// holds (up to 30 s).
Future<void> eventually(Future<void> Function() check) async {
  for (var i = 0; ; i++) {
    try {
      return await check();
    } on TestFailure {
      if (i == 10) rethrow;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }
}

Future<List<String>> songsOf(String playlistId) async => [
  for (final t in (await yt.collection('VL$playlistId')).tracks) t.id,
];

void main() {
  late Account acc;

  setUpAll(() async {
    acc = Account(store: DeviceSecretStore(Directory(_dir)));
    await acc.load();
    expect(acc.status.value, AccountStatus.signedIn);
    yt.signIn = acc;
  });

  tearDownAll(() async {
    await acc.saved;
    yt.signIn = null;
  });

  test(
    'a playlist: made, songs added, moved, removed, renamed, deleted',
    () async {
      final id = await yt.createPlaylist(
        'Encore sync check',
        _songs.take(2).toList(),
      );
      try {
        await pause();
        final made = await yt.collection('VL$id');
        expect(made.owned, isTrue);
        expect(made.title, 'Encore sync check');
        expect([for (final t in made.tracks) t.id], _songs.take(2));

        await yt.editPlaylist(id, [yt.addAction(_songs[2])]);
        await pause();
        expect(await songsOf(id), _songs.take(3));

        // Move the third song to the front.
        final entries = (await yt.collection('VL$id')).entryIds;
        await yt.editPlaylist(id, [
          yt.moveAction(entries[_songs[2]]!.first, entries[_songs[0]]!.first),
        ]);
        await pause();
        expect(await songsOf(id), [_songs[2], _songs[0], _songs[1]]);

        await yt.editPlaylist(id, [
          yt.removeAction(_songs[0], entries[_songs[0]]!.first),
          yt.renameAction('Encore sync check 2'),
        ]);
        await pause();
        final after = await yt.collection('VL$id');
        expect([for (final t in after.tracks) t.id], [_songs[2], _songs[1]]);
        expect(after.title, 'Encore sync check 2');
        expect((await yt.libraryPlaylists()).map((p) => p.id), contains(id));
      } finally {
        await yt.deletePlaylist(id);
      }
      await pause();
      expect(
        (await yt.libraryPlaylists()).map((p) => p.id),
        isNot(contains(id)),
      );
    },
    skip: _dir.isEmpty,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'a song liked, then unliked',
    () async {
      final song = _songs[3];
      final before = await yt.collection('VLLM', maxPages: 50);
      expect(
        before.tracks.map((t) => t.id),
        isNot(contains(song)),
        reason: "only a song the account hadn't liked",
      );
      await yt.rateSong(song, yt.Rating.like);
      await pause();
      try {
        await eventually(() async {
          final liked = await yt.collection('VLLM', maxPages: 50);
          expect(liked.tracks.map((t) => t.id), contains(song));
        });
      } finally {
        await yt.rateSong(song, yt.Rating.none);
      }
      await eventually(() async {
        final after = await yt.collection('VLLM', maxPages: 50);
        expect(after.tracks.map((t) => t.id), isNot(contains(song)));
      });
    },
    skip: _dir.isEmpty,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'an album saved, then removed',
    () async {
      final album = await yt.collection(_album, maxPages: 0);
      expect(album.playlistId, startsWith('OLAK5uy_'));
      expect(album.saved, isFalse, reason: "only an album the account hadn't");
      await yt.savePlaylist(album.playlistId!, true);
      await pause();
      try {
        await eventually(() async {
          expect((await yt.savedAlbums()).map((r) => r.id), contains(_album));
          expect((await yt.collection(_album, maxPages: 0)).saved, isTrue);
        });
      } finally {
        await yt.savePlaylist(album.playlistId!, false);
      }
      await eventually(
        () async => expect(
          (await yt.savedAlbums()).map((r) => r.id),
          isNot(contains(_album)),
        ),
      );
    },
    skip: _dir.isEmpty,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'an artist followed, then unfollowed',
    () async {
      final artist = await yt.artist(_artist);
      expect(artist.channelId, isNotNull);
      expect(artist.subscribed, isFalse, reason: "only one it didn't follow");
      await yt.followArtist(artist.channelId!, true);
      await pause();
      try {
        await eventually(() async {
          expect((await yt.artist(_artist)).subscribed, isTrue);
          // Listed by the artist's page id (what Encore follows by).
          final followed = await yt.followedArtists();
          expect(followed.map((r) => r.id), contains(_artist));
        });
      } finally {
        await yt.followArtist(artist.channelId!, false);
      }
      await eventually(
        () async => expect((await yt.artist(_artist)).subscribed, isFalse),
      );
    },
    skip: _dir.isEmpty,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('a play is counted', () async {
    // Without a player version YouTube Music gives no stats address.
    final stats = await yt.playbackStatsUrl(_songs[0]);
    expect(stats, isNotNull);
    await yt.reportPlayback(stats!);
  }, skip: _dir.isEmpty);

  test(
    'a full sync into an empty library takes everything, changes '
    'nothing on the account',
    () async {
      final dir = await Directory.systemTemp.createTemp('encore_live_sync');
      final lib = UserLibrary();
      final sync = YouTubeSync(
        account: acc,
        library: lib,
        dir: dir,
        firstSync: null,
      );
      await sync.start();
      expect(await sync.sync(), isNull);
      expect(sync.pending.value, isEmpty, reason: 'nothing to send back');
      expect(lib.liked.value, isNotEmpty);
      expect(
        lib.playlists.value.map((p) => p.remoteId),
        everyElement(isNotNull),
      );
      // #playsong has 30 songs (not its suggestions too).
      final remote = await yt.libraryPlaylists();
      for (final p in lib.playlists.value) {
        final page = await yt.collection('VL${p.remoteId}', maxPages: 50);
        expect(p.tracks.length, page.tracks.toSet().length, reason: p.name);
      }
      expect(remote, isNotEmpty);
      final likedPage = await yt.collection('VLLM', maxPages: 50);
      expect(lib.liked.value.length, likedPage.tracks.toSet().length);
      // ignore: avoid_print
      print(
        'liked ${lib.liked.value.length}, playlists '
        '${lib.playlists.value.map((p) => '${p.name} (${p.tracks.length})')}, '
        'saved ${lib.savedMedia.value.length}, artists ${lib.artists.value.length}',
      );
      sync.stop();
      await sync.saved;
      await dir.delete(recursive: true);
    },
    skip: _dir.isEmpty,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
