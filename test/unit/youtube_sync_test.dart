import 'dart:async';
import 'dart:io';

import 'package:encore/api/innertube.dart' as yt;
import 'package:encore/models.dart';
import 'package:encore/services/account.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/youtube_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_youtube.dart';
import 'account_test.dart' show MemoryStore, goodCookies, settle;

Track song(String id, {Duration? duration}) => Track(
  id: id,
  title: 'Song $id',
  artist: 'A',
  artUrl: '',
  duration: duration,
);

void main() {
  late FakeYouTube youtube;
  late Directory dir;
  late Account acc;
  late UserLibrary lib;
  late YouTubeSync sync;

  Future<YouTubeSync> startSync({Duration spacing = Duration.zero}) async {
    final s = YouTubeSync(
      account: acc,
      library: lib,
      dir: dir,
      spacing: spacing,
      retryAfter: const Duration(milliseconds: 100),
      readSpacing: Duration.zero,
      firstSync: null,
    );
    await s.start();
    return s;
  }

  List<String> rated() => [
    for (final r in youtube.requests)
      if (r.endpoint.startsWith('like/'))
        '${r.endpoint} ${r.body['target']['videoId']}',
  ];

  setUp(() async {
    youtube = FakeYouTube();
    await youtube.start();
    dir = await Directory.systemTemp.createTemp('encore_sync');
    acc = Account(store: MemoryStore());
    yt.signIn = acc;
    lib = UserLibrary();
    expect(await acc.signInWith(goodCookies()), isNull);
    youtube.requests.clear();
    sync = await startSync();
  });

  tearDown(() async {
    sync.stop();
    await sync.idle;
    await sync.saved;
    yt.signIn = null;
    yt.statsBase = null;
    await youtube.stop();
    // Windows: a save another instance started may still hold a file.
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

  group('likes', () {
    test('a song liked in Encore is liked on the account, signed in', () async {
      lib.toggleLike(song('a'));
      await sync.idle;
      expect(rated(), ['like/like a']);
      expect(youtube.signedIn(youtube.to('like/like').single), isTrue);
      expect(sync.pending.value, isEmpty);
    });

    test('unliking removes the like there', () async {
      lib.liked.value = [song('a')];
      await sync.idle;
      youtube.requests.clear();
      lib.toggleLike(song('a'));
      await sync.idle;
      expect(rated(), ['like/removelike a']);
    });

    test('in the order they happened, one at a time', () async {
      sync.stop();
      sync = await startSync(spacing: const Duration(milliseconds: 150));
      final at = <DateTime>[];
      youtube.handlers['like/like'] = (r, s) {
        at.add(DateTime.now());
        return {};
      };
      for (final id in ['a', 'b', 'c']) {
        lib.toggleLike(song(id));
      }
      await sync.idle;
      expect(rated(), ['like/like a', 'like/like b', 'like/like c']);
      for (var i = 1; i < at.length; i++) {
        expect(
          at[i].difference(at[i - 1]),
          greaterThanOrEqualTo(const Duration(milliseconds: 140)),
          reason: 'spaced out, never a burst',
        );
      }
    });

    test('signed out, nothing is sent or kept to send', () async {
      await acc.signOut();
      youtube.requests.clear();
      lib.toggleLike(song('a'));
      await sync.idle;
      expect(rated(), isEmpty);
      expect(sync.pending.value, isEmpty);
    });

    test('a sign-in that ended: nothing more is sent', () async {
      youtube.sessionEnded = true;
      await yt.home();
      await settle();
      expect(acc.status.value, AccountStatus.ended);
      youtube.requests.clear();
      lib.toggleLike(song('a'));
      await sync.idle;
      expect(rated(), isEmpty);
    });

    test('offline: kept (on disk too) and sent once back online', () async {
      youtube.failWith = 503;
      lib.toggleLike(song('a'));
      await sync.idle;
      expect(sync.pending.value.map((o) => '$o'), ['like a']);
      await sync.saved;

      // Encore restarts while still offline: the like is still waiting.
      sync.stop();
      final again = await startSync();
      expect(again.pending.value.map((o) => '$o'), ['like a']);
      youtube
        ..failWith = null
        ..requests.clear();
      again.retryNow();
      await again.idle;
      expect(rated(), ['like/like a']);
      expect(again.pending.value, isEmpty);
      again.stop();
      await again.saved;
    });

    test(
      'after a failure it tries again by itself, waiting longer each time',
      () async {
        youtube.failWith = 500;
        lib.toggleLike(song('a'));
        await sync.idle;
        youtube.failWith = null;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await sync.idle;
        expect(rated().last, 'like/like a');
        expect(sync.pending.value, isEmpty);
      },
    );

    test('liked then unliked while offline: only the last word goes', () async {
      youtube.failWith = 503;
      lib.toggleLike(song('a'));
      await sync.idle;
      lib.toggleLike(song('a'));
      lib.toggleLike(song('b'));
      expect(sync.pending.value.map((o) => '$o'), ['unlike a', 'like b']);
      youtube
        ..failWith = null
        ..requests.clear();
      sync.retryNow();
      await sync.idle;
      expect(rated(), ['like/removelike a', 'like/like b']);
    });

    test('a song YouTube refuses is dropped; the rest still go', () async {
      youtube.handlers['like/like'] = (r, s) =>
          r.body['target']['videoId'] == 'bad' ? 400 : {};
      lib.toggleLike(song('bad'));
      lib.toggleLike(song('good'));
      await sync.idle;
      expect(rated(), ['like/like bad', 'like/like good']);
      expect(sync.pending.value, isEmpty);
    });

    test('changes that came from the account are not sent back', () async {
      sync.applyingRemote(() => lib.liked.value = [song('x'), song('y')]);
      await sync.idle;
      expect(rated(), isEmpty);
      // Later changes are, compared with what came from the account.
      lib.toggleLike(song('x'));
      await sync.idle;
      expect(rated(), ['like/removelike x']);
    });

    test(
      'signing out drops what was waiting (it was for that account)',
      () async {
        youtube.failWith = 503;
        lib.toggleLike(song('a'));
        await sync.idle;
        expect(sync.pending.value, isNotEmpty);
        await acc.signOut();
        expect(sync.pending.value, isEmpty);
        await sync.saved;
        sync.stop();
        final again = await startSync();
        expect(again.pending.value, isEmpty, reason: 'not on disk either');
        again.stop();
      },
    );

    test('signing out while sending stops it', () async {
      sync.stop();
      sync = await startSync(spacing: const Duration(milliseconds: 100));
      for (final id in ['a', 'b', 'c', 'd']) {
        lib.toggleLike(song(id));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await acc.signOut();
      await sync.idle;
      expect(rated().length, lessThan(4));
    });

    test('an unreadable outbox file starts empty', () async {
      sync.stop();
      File('${dir.path}/youtube_sync.json').writeAsStringSync('{oops');
      final again = await startSync();
      expect(again.pending.value, isEmpty);
      File('${dir.path}/youtube_sync.json').writeAsStringSync(
        '{"pending":[{"kind":"nonsense","id":"a"},{"kind":"like","id":""},'
        '{"kind":"like","id":"ok"}]}',
      );
      again.stop();
      final third = await startSync();
      expect(third.pending.value.map((o) => '$o'), ['like ok']);
      third.stop();
    });
  });

  group('plays', () {
    late ValueNotifier<Track?> now;
    late StreamController<Duration> positions;
    late PlayReporter reporter;
    late List<String> reported;
    var fail = 0;
    Object failure = Exception('offline');

    setUp(() {
      now = ValueNotifier(null);
      positions = StreamController();
      reported = [];
      fail = 0;
      reporter = PlayReporter(
        nowPlaying: now,
        positions: positions.stream,
        account: acc,
        retryAfter: const Duration(milliseconds: 20),
        report: (t) async {
          reported.add(t.id);
          if (fail > 0) {
            fail--;
            throw failure;
          }
        },
      );
    });

    tearDown(() async {
      reporter.dispose();
      await positions.close();
    });

    Future<void> play(Track t, List<int> seconds) async {
      now.value = t;
      for (final s in seconds) {
        positions.add(Duration(seconds: s));
      }
      await settle();
    }

    test('a song heard for 30 seconds counts once', () async {
      await play(song('a'), [1, 10, 29]);
      expect(reported, isEmpty);
      await play(song('a'), [30, 31, 90, 180]);
      expect(reported, ['a']);
      expect(reporter.sent, ['a']);
    });

    test('a song skipped before then does not count', () async {
      await play(song('a'), [1, 5, 12]);
      await play(song('b'), [1, 31]);
      expect(reported, ['b']);
    });

    test('a short song counts at half its length', () async {
      final short = song('s', duration: const Duration(seconds: 40));
      expect(PlayReporter.needed(short), const Duration(seconds: 20));
      expect(
        PlayReporter.needed(song('x', duration: const Duration(seconds: 4))),
        const Duration(seconds: 5),
      );
      await play(short, [19]);
      expect(reported, isEmpty);
      await play(short, [20]);
      expect(reported, ['s']);
    });

    test('signed out, nothing is counted', () async {
      await acc.signOut();
      await play(song('a'), [1, 40]);
      expect(reported, isEmpty);
    });

    test('a song played again (repeat one) counts again', () async {
      await play(song('a'), [30, 200]);
      await play(song('a'), [0, 1, 31]);
      expect(reported, ['a', 'a']);
    });

    test('the same song next in the queue counts again', () async {
      await play(song('a'), [31]);
      now.value = null;
      await play(song('a'), [1, 31]);
      expect(reported, ['a', 'a']);
    });

    test('seeking back within a song does not count it twice', () async {
      await play(song('a'), [31, 60, 40, 35]);
      expect(reported, ['a']);
    });

    test('a failed count is tried twice more, then given up', () async {
      fail = 5;
      await play(song('a'), [31]);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(reported, ['a', 'a', 'a']);
      expect(reporter.sent, isEmpty);
    });

    test('a count YouTube refuses is not tried again', () async {
      fail = 5;
      failure = yt.YouTubeError('player', 400);
      await play(song('a'), [31]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(reported, ['a']);
      failure = Exception('offline');
    });

    test('a retry after signing out is not sent', () async {
      fail = 1;
      now.value = song('a');
      positions.add(const Duration(seconds: 31));
      await Future<void>.delayed(Duration.zero);
      await acc.signOut();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(reported, ['a']);
    });
  });

  group('the play report itself', () {
    test('asks the player for the stats address, then calls it as the '
        'website does, signed in', () async {
      youtube.handlers['player'] = (r, s) => {
        'playbackTracking': {
          'videostatsPlaybackUrl': {
            'baseUrl':
                'https://s.youtube.com/api/stats/playback?docid=${r.body['videoId']}&ei=abc',
          },
        },
      };
      final stats = await yt.playbackStatsUrl('song0000001');
      expect(stats!.host, 's.youtube.com');
      expect(youtube.signedIn(youtube.to('player').single), isTrue);

      yt.statsBase = (u) =>
          Uri.parse(yt.musicApiBase)
              .replace(path: u.path, queryParameters: u.queryParameters);
      await yt.reportPlayback(stats);
      final r = youtube.requests.last;
      expect(r.endpoint, '/api/stats/playback');
      expect(r.query['docid'], 'song0000001');
      expect(r.query['ei'], 'abc');
      expect(r.query['ver'], '2');
      expect(r.query['c'], 'WEB_REMIX');
      expect(r.query['cpn'], matches(RegExp(r'^[\w-]{16}$')));
      expect(youtube.signedIn(r), isTrue);
    });

    test(
      "an address that isn't YouTube's never gets the account's cookies",
      () async {
        for (final url in [
          'https://evil.example/api/stats/playback',
          'http://s.youtube.com/api/stats/playback',
          'https://youtube.com.evil.example/x',
          'not a url',
        ]) {
          youtube.handlers['player'] = (r, s) => {
            'playbackTracking': {
              'videostatsPlaybackUrl': {'baseUrl': url},
            },
          };
          expect(await yt.playbackStatsUrl('a'), isNull, reason: url);
        }
        youtube.handlers['player'] = (r, s) => {};
        expect(await yt.playbackStatsUrl('a'), isNull);
      },
    );

    test('signed out, no report is sent', () async {
      await acc.signOut();
      youtube.requests.clear();
      await yt.reportPlayback(
        Uri.parse('https://s.youtube.com/api/stats/playback'),
      );
      expect(youtube.requests, isEmpty);
    });
  });
}
