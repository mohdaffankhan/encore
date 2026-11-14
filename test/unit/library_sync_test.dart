import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:encore/api/innertube.dart' as yt;
import 'package:encore/models.dart';
import 'package:encore/services/account.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/youtube_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_youtube.dart';
import '../fake_youtube_library.dart';
import 'account_test.dart' show MemoryStore, goodCookies;

Track song(String id) => Track(id: id, title: 'Song $id', artist: 'A', artUrl: '');

MediaRef album(String id) => MediaRef(
  kind: MediaKind.album,
  id: id,
  title: 'Album $id',
  subtitle: '',
  artUrl: '',
);

MediaRef artistRef(String id) => MediaRef(
  kind: MediaKind.artist,
  id: id,
  title: 'Artist $id',
  subtitle: '',
  artUrl: '',
);

List<String> ids(List<Track> tracks) => [for (final t in tracks) t.id];

void main() {
  group('merging', () {
    test('never synced: both sides are combined, nothing removed', () {
      expect(mergeSets({'a', 'b'}, {'b', 'c'}, null), {'a', 'b', 'c'});
    });

    test('added on either side is kept; removed on either side goes', () {
      final base = {'a', 'b', 'c'};
      // Encore: removed a, added d. Account: removed b, added e.
      expect(
        mergeSets({'b', 'c', 'd'}, {'a', 'c', 'e'}, base),
        {'c', 'd', 'e'},
      );
    });

    test("the account's order, unless only Encore's changed", () {
      final keep = {'a', 'b', 'c'};
      expect(mergeOrder(['a', 'b', 'c'], ['c', 'b', 'a'], ['a', 'b', 'c'], keep),
          ['c', 'b', 'a']);
      expect(mergeOrder(['c', 'a', 'b'], ['a', 'b', 'c'], ['a', 'b', 'c'], keep),
          ['c', 'a', 'b']);
      // Both moved: the account's.
      expect(mergeOrder(['c', 'a', 'b'], ['b', 'a', 'c'], ['a', 'b', 'c'], keep),
          ['b', 'a', 'c']);
    });

    test('songs new in Encore go at the end, new on the account in place', () {
      expect(
        mergeOrder(['a', 'b', 'x'], ['a', 'y', 'b'], ['a', 'b'], {'a', 'b', 'x', 'y'}),
        ['a', 'y', 'b', 'x'],
      );
    });

    test('moves: the fewest, and they give the wanted order', () {
      final random = Random(7);
      for (var n = 0; n < 200; n++) {
        final from = [for (var i = 0; i < random.nextInt(30); i++) 's$i'];
        final to = [...from]..shuffle(random);
        final moves = movesFor(from, to);
        final list = [...from];
        for (final (id, before) in moves) {
          list.remove(id);
          list.insert(before == null ? list.length : list.indexOf(before), id);
        }
        expect(list, to);
      }
      expect(movesFor(['a', 'b', 'c', 'd'], ['a', 'b', 'c', 'd']), isEmpty);
      expect(movesFor(['a', 'b', 'c', 'd'], ['d', 'a', 'b', 'c']).length, 1);
    });
  });

  group('syncing with the account', () {
    late FakeYouTube youtube;
    late FakeLibrary remote;
    late Directory dir;
    late Account acc;
    late UserLibrary lib;
    late YouTubeSync sync;

    /// What the user answers the first sync's question (null: nothing yet).
    bool? answer = true;
    final asked = <SyncPlan>[];

    Future<YouTubeSync> startSync() async {
      final s = YouTubeSync(
        account: acc,
        library: lib,
        dir: dir,
        spacing: Duration.zero,
        readSpacing: Duration.zero,
        retryAfter: const Duration(milliseconds: 50),
        firstSync: null,
      );
      s.question.addListener(() {
        final plan = s.question.value;
        if (plan == null) return;
        asked.add(plan);
        if (answer case final a?) s.answer(a);
      });
      await s.start();
      return s;
    }

    /// A sync, then everything it queued sent.
    Future<String?> syncNow() async {
      final result = await sync.sync();
      await sync.idle;
      return result;
    }

    setUp(() async {
      youtube = FakeYouTube();
      await youtube.start();
      remote = FakeLibrary(youtube);
      dir = await Directory.systemTemp.createTemp('encore_libsync');
      acc = Account(store: MemoryStore());
      yt.signIn = acc;
      lib = UserLibrary();
      expect(await acc.signInWith(goodCookies()), isNull);
      answer = true;
      asked.clear();
      sync = await startSync();
    });

    tearDown(() async {
      sync.stop();
      await sync.idle;
      await sync.saved;
      await acc.signOut();
      yt.signIn = null;
      await youtube.stop();
      for (var i = 0; ; i++) {
        try {
          await dir.delete(recursive: true);
          break;
        } on FileSystemException {
          if (i == 20) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    });

    test('the first sync combines both libraries, removing nothing', () async {
      remote.liked.addAll(['r1', 'both']);
      remote.playlists['PLr'] = FakePlaylist('PLr', 'Road trip', ['a', 'b']);
      remote.savedAlbums.add('MPREr');
      remote.followed.add('UCr');
      sync.applyingRemote(() {
        lib.liked.value = [song('l1'), song('both')];
        lib.createPlaylist('Mine', tracks: [song('m')]);
        lib.savedMedia.value = [album('MPREl')];
        lib.artists.value = [artistRef('UCl')];
      });

      expect(await syncNow(), isNull);

      // Encore now has both.
      expect(ids(lib.liked.value), ['l1', 'r1', 'both']);
      final road = lib.playlists.value.firstWhere((p) => p.name == 'Road trip');
      expect(road.remoteId, 'PLr');
      expect(ids(road.tracks), ['a', 'b']);
      expect(road.source, 'YouTube Music');
      expect(lib.savedMedia.value.map((r) => r.id), ['MPREl', 'MPREr']);
      expect(lib.artists.value.map((r) => r.id), ['UCl', 'UCr']);

      // And the account too.
      expect(remote.liked, containsAll(['l1', 'r1', 'both']));
      final mine = lib.playlists.value.firstWhere((p) => p.name == 'Mine');
      expect(mine.remoteId, isNotNull, reason: 'made on the account, linked');
      expect(remote.playlists[mine.remoteId]!.songs, ['m']);
      expect(remote.savedAlbums, containsAll(['MPREl', 'MPREr']));
      expect(remote.followed, containsAll(['UCl', 'UCr']));
      expect(remote.writes.where((w) => w.startsWith('unlike')), isEmpty);
      expect(sync.lastSynced.value, isNotNull);
    });

    group('the first sync asks first', () {
      setUp(() {
        remote.liked.addAll(['r1', 'r2']);
        remote.playlists['PLr'] = FakePlaylist('PLr', 'Theirs', ['x']);
        sync.applyingRemote(() {
          lib.liked.value = [song('l1'), song('l2'), song('r1')];
          lib.createPlaylist(
            'Mine',
            tracks: [for (var i = 0; i < 120; i++) song('m$i')],
          );
          lib.savedMedia.value = [album('MPREa')];
          lib.artists.value = [artistRef('UCa')];
        });
      });

      test('what goes, what comes, and how many requests', () async {
        await syncNow();
        final plan = asked.single;
        expect(plan.likes, 2);
        expect(plan.playlists, 1);
        expect(plan.playlistSongs, 120);
        expect(plan.saved, 1);
        expect(plan.artists, 1);
        // 2 likes, the playlist (made, then 2 x 50 songs), the album
        // (looked up, saved), the artist (looked up, followed).
        expect(plan.requests, 2 + 3 + 2 + 2);
        expect(plan.newLikes, 1);
        expect(plan.newPlaylists, 1);
        expect(plan.estimate(const Duration(seconds: 1)),
            const Duration(milliseconds: 1400) * 9);
      });

      test('nothing is sent or changed until the user agrees', () async {
        answer = null;
        final result = sync.sync();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(sync.question.value, isNotNull);
        expect(remote.writes, isEmpty);
        expect(ids(lib.liked.value), ['l1', 'l2', 'r1']);
        sync.answer(true);
        expect(await result, isNull);
        await sync.idle;
        expect(remote.liked.toSet(), {'r1', 'r2', 'l1', 'l2'});
        expect(sync.question.value, isNull);
      });

      test('"Sign out instead": signed out, nothing sent or changed', () async {
        answer = false;
        expect(await sync.sync(), contains('Nothing was sent'));
        expect(acc.status.value, AccountStatus.signedOut);
        expect(remote.writes, isEmpty);
        expect(ids(lib.liked.value), ['l1', 'l2', 'r1']);
        expect(lib.playlists.value.single.remoteId, isNull);
      });

      test('signed out while it asks: the question goes, nothing is sent',
          () async {
        answer = null;
        final result = sync.sync();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await acc.signOut();
        expect(sync.question.value, isNull);
        expect(await result, isNotNull);
        expect(remote.writes, isEmpty);
      });

      test('closed before answering: asked again next time', () async {
        answer = null;
        unawaited(sync.sync());
        await Future<void>.delayed(const Duration(milliseconds: 100));
        sync.stop();
        sync = await startSync();
        answer = true;
        expect(await syncNow(), isNull);
        expect(asked, hasLength(2));
      });

      test('asked once: later syncs just sync', () async {
        await syncNow();
        lib.toggleLike(song('new'));
        await sync.idle;
        await syncNow();
        expect(asked, hasLength(1));
      });
    });

    test('nothing in Encore to send: not asked', () async {
      remote.liked.add('r');
      await syncNow();
      expect(asked, isEmpty);
      expect(ids(lib.liked.value), ['r']);
    });

    group('progress', () {
      test('how far sending has got, then nothing once done', () async {
        await syncNow();
        youtube.failWith = 503;
        for (var i = 0; i < 5; i++) {
          lib.toggleLike(song('p$i'));
        }
        await sync.idle;
        expect(sync.pending.value, hasLength(5));
        expect(sync.total.value, 5);
        expect(sync.waiting.value, isTrue, reason: 'offline');
        // Two go, then it fails again.
        var sent = 0;
        youtube.failWith = null;
        final like = youtube.handlers['like/like']!;
        youtube.handlers['like/like'] = (r, s) => ++sent > 2 ? 503 : like(r, s);
        sync.retryNow();
        await sync.idle;
        expect(sync.pending.value, hasLength(3));
        expect(sync.total.value, 5, reason: '2 of 5 done');
        youtube.handlers['like/like'] = like;
        sync.retryNow();
        await sync.idle;
        expect(sync.pending.value, isEmpty);
        expect(sync.total.value, 0);
        expect(sync.waiting.value, isFalse);
      });

      test('a change replacing one waiting does not count twice', () async {
        await syncNow();
        youtube.failWith = 503;
        lib.toggleLike(song('a'));
        await sync.idle;
        lib.toggleLike(song('a'));
        expect(sync.pending.value, hasLength(1));
        expect(sync.total.value, 1);
      });

      test('after a restart with changes waiting: says it carries on',
          () async {
        await syncNow();
        youtube.failWith = 503;
        lib.toggleLike(song('a'));
        lib.toggleLike(song('b'));
        await sync.idle;
        await sync.saved;
        sync.stop();
        sync = await startSync();
        expect(sync.notice.value, contains('Sending 2 changes'));
        expect(sync.notice.value, contains('where it left off'));
        expect(sync.total.value, 2);
      });
    });

    test('stopped mid-send, a failure does not start sending again', () async {
      await syncNow();
      final hold = youtube.hold = Completer();
      youtube.failWith = 503;
      lib.toggleLike(song('a'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      sync.stop();
      youtube.hold = null;
      hold.complete();
      await sync.idle;
      youtube.failWith = null;
      youtube.requests.clear();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(youtube.requests, isEmpty, reason: 'no retry after stopping');
    });

    test('a second sync brings removals across, both ways', () async {
      remote.liked.addAll(['a', 'b', 'c']);
      await syncNow();
      remote.liked.remove('a'); // unliked on YouTube Music
      lib.toggleLike(song('b')); // unliked in Encore (sent at once)
      await sync.idle;
      expect(remote.liked, isNot(contains('b')));
      await syncNow();
      expect(ids(lib.liked.value), ['c']);
      expect(remote.liked, ['c']);
    });

    test('songs liked on YouTube Music show in Encore, newest first', () async {
      await syncNow();
      remote.liked.insertAll(0, ['new2', 'new1']);
      await syncNow();
      expect(ids(lib.liked.value), ['new2', 'new1']);
      expect(remote.writes, isEmpty, reason: 'nothing sent back');
    });

    group('playlists', () {
      late Playlist linked;

      setUp(() async {
        remote.playlists['PL1'] = FakePlaylist('PL1', 'Chill', ['a', 'b', 'c']);
        await syncNow();
        linked = lib.playlists.value.single;
        remote.writes.clear();
      });

      test('changes on the account show in Encore', () async {
        final p = remote.playlists['PL1']!;
        p.title = 'Chill evenings';
        p.entries.removeAt(0);
        await syncNow();
        await syncNow();
        expect(remote.writes, isEmpty);
        final now = lib.playlist(linked.id)!;
        expect(now.name, 'Chill evenings');
        expect(ids(now.tracks), ['b', 'c']);
      });

      test('songs added, removed, renamed and moved in Encore go at once',
          () async {
        lib.addToPlaylist(linked.id, [song('d')]);
        lib.removeFromPlaylist(linked.id, song('a'));
        lib.renamePlaylist(linked.id, 'Calm');
        lib.moveInPlaylist(linked.id, 2, 0); // d first
        await sync.idle;
        final p = remote.playlists['PL1']!;
        expect(p.title, 'Calm');
        expect(p.songs, ['d', 'b', 'c']);
        // And a sync after agrees, changing nothing.
        remote.writes.clear();
        await syncNow();
        expect(remote.writes, isEmpty);
        expect(ids(lib.playlist(linked.id)!.tracks), ['d', 'b', 'c']);
      });

      test('a song removed takes all its entries (duplicates) away', () async {
        remote.playlists['PL1']!.entries.add(FakePlaylist('x', '', ['a']).entries.first);
        await syncNow();
        expect(ids(lib.playlist(linked.id)!.tracks), ['a', 'b', 'c'],
            reason: 'Encore keeps each song once');
        lib.removeFromPlaylist(linked.id, song('a'));
        await sync.idle;
        expect(remote.playlists['PL1']!.songs, ['b', 'c']);
      });

      test('deleted in Encore: deleted on the account', () async {
        lib.deletePlaylist(linked.id);
        await sync.idle;
        expect(remote.playlists, isNot(contains('PL1')));
      });

      test('deleted on the account, unchanged in Encore: deleted here', () async {
        remote.playlists.remove('PL1');
        await syncNow();
        expect(lib.playlists.value, isEmpty);
      });

      test('deleted on the account but changed in Encore since: kept, and '
          'made there again', () async {
        await sync.sync();
        remote.playlists.remove('PL1');
        // Changed while signed out (not sent).
        await acc.signOut();
        lib.addToPlaylist(linked.id, [song('z')]);
        expect(await acc.signInWith(goodCookies()), isNull);
        await sync.idle;
        // Signing in again forgets what was agreed: nothing is deleted.
        expect(lib.playlist(linked.id), isNotNull);
        expect(ids(lib.playlist(linked.id)!.tracks), contains('z'));
        expect(lib.playlist(linked.id)!.remoteId, isNot('PL1'));
        expect(
          remote.playlists.values.where((p) => p.songs.contains('z')),
          hasLength(1),
        );
      });

      test('both sides changed: both kept', () async {
        remote.playlists['PL1']!.entries.add(FakePlaylist('x', '', ['r']).entries.first);
        youtube.failWith = 503; // Encore's change waits (offline)
        lib.addToPlaylist(linked.id, [song('l')]);
        await sync.idle;
        youtube.failWith = null;
        expect(await syncNow(), isNull);
        expect(ids(lib.playlist(linked.id)!.tracks), ['a', 'b', 'c', 'r', 'l']);
        expect(remote.playlists['PL1']!.songs, ['a', 'b', 'c', 'r', 'l']);
      });

      test("someone else's playlist saved on the account is a saved "
          'playlist here, not one of Encore\'s', () async {
        remote.playlists['PLother'] =
            FakePlaylist('PLother', 'Hits', ['h'], owned: false);
        await syncNow();
        expect(lib.playlists.value.map((p) => p.name), ['Chill']);
        expect(lib.savedMedia.value.map((r) => r.id), ['VLPLother']);
      });
    });

    test("the account's suggestions under its own playlist aren't songs "
        'of it (found on YouTube Music: they were taken in)', () async {
      remote.playlists['PL1'] = FakePlaylist('PL1', 'Mine', ['a', 'b']);
      await syncNow();
      expect(ids(lib.playlists.value.single.tracks), ['a', 'b']);
      expect(remote.writes, isEmpty);
    });

    test('long playlists and liked songs come in full, page by page', () async {
      remote.pageSize = 3;
      remote.liked.addAll([for (var i = 0; i < 8; i++) 'l$i']);
      remote.playlists['PL1'] =
          FakePlaylist('PL1', 'Long', [for (var i = 0; i < 10; i++) 's$i']);
      await syncNow();
      expect(ids(lib.liked.value), [for (var i = 0; i < 8; i++) 'l$i']);
      expect(ids(lib.playlists.value.single.tracks), [
        for (var i = 0; i < 10; i++) 's$i',
      ]);
      // Removing the last song finds its entry on the last page.
      lib.removeFromPlaylist(lib.playlists.value.single.id, song('s9'));
      await sync.idle;
      expect(remote.playlists['PL1']!.songs, hasLength(9));
    });

    test('a playlist made in Encore is made on the account, with its songs',
        () async {
      await syncNow();
      final p = lib.createPlaylist('New one', tracks: [song('a'), song('b')]);
      await sync.idle;
      final made = lib.playlist(p.id)!.remoteId!;
      expect(remote.playlists[made]!.title, 'New one');
      expect(remote.playlists[made]!.songs, ['a', 'b']);
      remote.writes.clear();
      await syncNow();
      expect(remote.writes, isEmpty, reason: 'not made twice');
      expect(lib.playlists.value, hasLength(1));
    });

    test('a big playlist (an import of 1000 songs) is made, then filled 50 '
        'songs at a time, all of them in order', () async {
      await syncNow();
      final songs = [for (var i = 0; i < 1000; i++) song('s$i')];
      final p = lib.createPlaylist('Imported', tracks: songs);
      await sync.idle;
      final made = lib.playlist(p.id)!.remoteId!;
      expect(remote.playlists[made]!.songs, ids(songs));
      final edits = youtube.to('browse/edit_playlist');
      expect(edits, hasLength(19));
      expect(edits.every((r) => (r.body['actions'] as List).length <= 50), isTrue);
    });

    test('offline part way through filling a big playlist: not made twice, '
        'filled when back online', () async {
      await syncNow();
      final edit = youtube.handlers['browse/edit_playlist']!;
      var fail = true;
      youtube.handlers['browse/edit_playlist'] = (r, s) {
        if (fail) return 503;
        return edit(r, s);
      };
      final songs = [for (var i = 0; i < 120; i++) song('s$i')];
      final p = lib.createPlaylist('Imported', tracks: songs);
      await sync.idle;
      final made = lib.playlist(p.id)!.remoteId;
      expect(made, isNotNull, reason: 'linked as soon as it was made');
      expect(remote.playlists[made]!.songs, hasLength(50));
      fail = false;
      sync.retryNow();
      await sync.idle;
      expect(remote.playlists, hasLength(1));
      expect(remote.playlists[made]!.songs, ids(songs));
    });

    test('a playlist deleted before it was made there is not made', () async {
      await syncNow();
      youtube.failWith = 503;
      final p = lib.createPlaylist('Gone');
      await sync.idle;
      lib.deletePlaylist(p.id);
      youtube.failWith = null;
      sync.retryNow();
      await sync.idle;
      expect(remote.playlists, isEmpty);
      expect(sync.pending.value, isEmpty);
    });

    test('songs added while a playlist is being made follow it', () async {
      await syncNow();
      final hold = youtube.hold = Completer();
      final p = lib.createPlaylist('Growing', tracks: [song('a')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      lib.addToPlaylist(p.id, [song('b')]);
      youtube.hold = null;
      hold.complete();
      await sync.idle;
      final made = lib.playlist(p.id)!.remoteId!;
      expect(remote.playlists[made]!.songs, ['a', 'b']);
    });

    test('saving albums and following artists, both ways', () async {
      await syncNow();
      lib.toggleSaved(album('MPREx'));
      lib.toggleFollow(artistRef('UCx'));
      await sync.idle;
      expect(remote.savedAlbums, ['MPREx']);
      expect(remote.followed, ['UCx']);
      remote.savedAlbums.clear();
      remote.followed.add('UCy');
      await syncNow();
      expect(lib.savedMedia.value, isEmpty);
      expect(lib.artists.value.map((r) => r.id), ['UCx', 'UCy']);
      lib.toggleFollow(artistRef('UCx'));
      await sync.idle;
      expect(remote.followed, ['UCy']);
    });

    test('liked in Encore, then unliked on YouTube Music: stays unliked',
        () async {
      await syncNow();
      lib.toggleLike(song('x'));
      await sync.idle;
      remote.liked.remove('x');
      await syncNow();
      expect(lib.liked.value, isEmpty);
      expect(remote.liked, isEmpty);
    });

    test('added to a playlist in Encore, then removed on YouTube Music: '
        'stays removed', () async {
      remote.playlists['PL1'] = FakePlaylist('PL1', 'P', ['a']);
      await syncNow();
      final p = lib.playlists.value.single;
      lib.addToPlaylist(p.id, [song('x')]);
      await sync.idle;
      remote.playlists['PL1']!.entries.removeWhere((e) => e.videoId == 'x');
      await syncNow();
      expect(ids(lib.playlist(p.id)!.tracks), ['a']);
      expect(remote.playlists['PL1']!.songs, ['a']);
    });

    test('followed in Encore, then unfollowed on YouTube Music: stays '
        'unfollowed', () async {
      await syncNow();
      lib.toggleFollow(artistRef('UCx'));
      await sync.idle;
      remote.followed.clear();
      await syncNow();
      expect(lib.artists.value, isEmpty);
    });

    test('an artist whose channel differs from its page is followed by '
        'its channel', () async {
      final channels = {'UCpage': 'UCchannel'};
      final original = remote.channelOf;
      expect(original('UCa'), 'UCa');
      youtube.handlers['browse'] = (r, s) {
        if (r.body['browseId'] == 'UCpage') {
          return {
            'header': {
              'subscribeButtonRenderer': {
                'channelId': channels['UCpage'],
                'subscribed': false,
              },
            },
          };
        }
        return {};
      };
      lib.toggleFollow(artistRef('UCpage'));
      await sync.idle;
      expect(remote.followed, ['UCchannel']);
    });

    test('while changes wait (offline), a sync waits too, changing nothing',
        () async {
      remote.liked.add('a');
      await syncNow();
      youtube.failWith = 503;
      lib.toggleLike(song('b'));
      await sync.idle;
      remote.liked.remove('a');
      expect(await sync.sync(), isNotNull);
      expect(ids(lib.liked.value), ['b', 'a'], reason: 'untouched');
      expect(sync.state.value, SyncState.failed);
    });

    test('offline, a sync fails and changes nothing', () async {
      lib.liked.value = [song('a')];
      await sync.idle;
      youtube.failWith = 503;
      expect(await sync.sync(), "Couldn't sync with YouTube Music");
      expect(ids(lib.liked.value), ['a']);
    });

    test('the library changed during a sync: that sync changes nothing, '
        'the change goes, the next sync merges', () async {
      remote.liked.add('r');
      final hold = youtube.hold = Completer();
      final result = sync.sync();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      lib.toggleLike(song('mine'));
      youtube.hold = null;
      hold.complete();
      expect(await result, contains('changed while syncing'));
      expect(ids(lib.liked.value), ['mine'], reason: 'not merged');
      await sync.idle;
      expect(remote.liked, contains('mine'));
      expect(await syncNow(), isNull);
      expect(ids(lib.liked.value).toSet(), {'mine', 'r'});
    });

    test('signed out meanwhile: the sync changes nothing', () async {
      remote.liked.add('r');
      final hold = youtube.hold = Completer();
      final result = sync.sync();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      youtube.hold = null;
      await acc.signOut();
      hold.complete();
      expect(await result, isNotNull);
      expect(lib.liked.value, isEmpty);
    });

    test('what was agreed is kept on disk: removals are still noticed after '
        'a restart', () async {
      remote.liked.addAll(['a', 'b']);
      await syncNow();
      await sync.saved;
      sync.stop();
      sync = await startSync();
      remote.liked.remove('a');
      await syncNow();
      expect(ids(lib.liked.value), ['b']);
    });

    test('an unreadable sync file starts over (combines, removes nothing)',
        () async {
      remote.liked.addAll(['a']);
      await syncNow();
      await sync.saved;
      sync.stop();
      File('${dir.path}/youtube_sync.json').writeAsStringSync('nonsense');
      sync = await startSync();
      remote.liked.clear();
      await syncNow();
      expect(ids(lib.liked.value), ['a']);
      expect(remote.liked, ['a'], reason: 'sent back, not removed here');
    });

    test('changes made signed out are merged at the next sign-in, nothing '
        'removed', () async {
      remote.liked.add('r');
      await syncNow();
      await acc.signOut();
      lib.toggleLike(song('r')); // unliked while signed out
      lib.toggleLike(song('n'));
      expect(await acc.signInWith(goodCookies()), isNull);
      await sync.idle;
      // Signing in syncs by itself; first sync again: combined.
      expect(ids(lib.liked.value).toSet(), {'n', 'r'});
      expect(remote.liked.toSet(), {'n', 'r'});
    });

    test('signing in starts a sync by itself', () async {
      await acc.signOut();
      remote.liked.add('r');
      expect(await acc.signInWith(goodCookies()), isNull);
      await sync.idle;
      expect(ids(lib.liked.value), ['r']);
    });

    test('everything sent is signed in and spaced: never two at once',
        () async {
      for (var i = 0; i < 5; i++) {
        lib.toggleLike(song('s$i'));
      }
      lib.createPlaylist('P', tracks: [song('a')]);
      await sync.idle;
      expect(remote.writes, hasLength(6));
      for (final r in youtube.requests) {
        expect(youtube.signedIn(r), isTrue, reason: r.endpoint);
      }
    });
  });
}
