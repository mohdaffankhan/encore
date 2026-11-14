import 'dart:convert';
import 'dart:io';

import 'package:encore/api/innertube.dart' as yt;
import 'package:encore/api/stream.dart';
import 'package:encore/models.dart';
import 'package:encore/services/player.dart';
import 'package:encore/services/track_stream.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_youtube.dart';

// Encore streams signed out (so signing in can never stop music playing),
// and YouTube plays age-restricted songs (music videos, nearly always) only
// to signed-in adults in its own apps. Such a song plays as its song
// version instead, which isn't restricted.

const _video = Track(
  id: 'B3eAMGXFw1o',
  title: 'Bitch Better Have My Money (Explicit)',
  artist: 'Rihanna',
  artUrl: '',
  duration: Duration(minutes: 4, seconds: 30),
);

Map<String, Object> _songRow(
  String id,
  String title,
  String artist,
  String length,
) => {
  'musicResponsiveListItemRenderer': {
    'playlistItemData': {'videoId': id},
    'flexColumns': [
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [
              {'text': title},
            ],
          },
        },
      },
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [
              {'text': 'Song'},
              {'text': ' • '},
              {'text': artist},
              {'text': ' • '},
              {'text': length},
            ],
          },
        },
      },
    ],
  },
};

AudioStream _stream(String id) =>
    AudioStream(Uri.parse('https://example.invalid/$id'), 'audio/webm', 100);

void main() {
  group('titles without what videos add', () {
    for (final (title, artist, base) in [
      (
        'Bitch Better Have My Money (Explicit)',
        'Rihanna',
        'Bitch Better Have My Money',
      ),
      (
        "Rammstein - ''Pussy'' - (OFFICIAL VIDEO) -  [FIXED AUDIO] - (English CC)",
        'Rammstein',
        'Pussy',
      ),
      ('Anaconda | Official Music Video', 'Nicki Minaj', 'Anaconda'),
      ('Kill You - Official Audio', 'Eminem', 'Kill You'),
      ('"Blinding Lights" [4K]', 'The Weeknd', 'Blinding Lights'),
      ('Levitating (Lyrics)', 'Dua Lipa', 'Levitating'),
      // What belongs to the song stays.
      ('Levitating (feat. DaBaby)', 'Dua Lipa', 'Levitating (feat. DaBaby)'),
      ('Shadows (Remix)', 'X', 'Shadows (Remix)'),
      // Words inside words don't count ("hd" in "Adhd").
      ('Shadows (Adhd Mix)', 'X', 'Shadows (Adhd Mix)'),
      ('Audiotopia', 'X', 'Audiotopia'),
      ('Videotape', 'Radiohead', 'Videotape'),
    ]) {
      test(title, () => expect(yt.baseTitle(title, artist: artist), base));
    }
  });

  group('finding the song version', () {
    late FakeYouTube youtube;
    late List<Object> results;

    setUp(() async {
      youtube = FakeYouTube();
      await youtube.start();
      results = [];
      youtube.handlers['search'] = (r, s) => {'contents': results};
    });
    tearDown(() => youtube.stop());

    test('same title and artist, about as long', () async {
      results = [
        _songRow('other1', 'Money', 'Rihanna', '4:30'),
        _songRow('song1', 'Bitch Better Have My Money', 'Rihanna', '4:29'),
      ];
      expect((await yt.songVersion(_video))?.id, 'song1');
      expect(
        youtube.to('search').single.body['query'],
        'Bitch Better Have My Money Rihanna',
      );
    });

    test('another artist, a much longer one, or itself: none', () async {
      results = [
        _songRow('cover', 'Bitch Better Have My Money', 'Someone Else', '4:30'),
        _songRow('extended', 'Bitch Better Have My Money', 'Rihanna', '9:00'),
        _songRow(_video.id, 'Bitch Better Have My Money', 'Rihanna', '4:30'),
      ];
      expect(await yt.songVersion(_video), isNull);
    });

    test('nothing found: none', () async {
      expect(await yt.songVersion(_video), isNull);
    });
  });

  test('YouTube asking to confirm the age is told apart', () {
    expect(AgeRestricted.means('Sign in to confirm your age'), isTrue);
    expect(
      AgeRestricted.means('This video may be inappropriate for some users.'),
      isTrue,
    );
    expect(AgeRestricted.means('This video is unavailable'), isFalse);
  });

  test("every client refusing for the age: it's age-restricted", () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await req.drain<void>();
      req.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'playabilityStatus': {
              'status': 'LOGIN_REQUIRED',
              'reason': 'Sign in to confirm your age',
            },
          }),
        );
      await req.response.close();
    });
    final was = playerEndpoint;
    playerEndpoint = Uri.parse('http://127.0.0.1:${server.port}/player');
    addTearDown(() async {
      playerEndpoint = was;
      await server.close(force: true);
    });
    await expectLater(
      audioStream('B3eAMGXFw1o'),
      throwsA(isA<AgeRestricted>()),
    );
  });

  group('playing it', () {
    late List<String> opened;
    late List<String> looked;
    Track? version;

    setUp(() {
      opened = [];
      looked = [];
      version = const Track(
        id: 'song1',
        title: 'BBHMM',
        artist: 'Rihanna',
        artUrl: '',
      );
      forgetSongVersions();
      openStream = (id, {itag, client, quality = AudioQuality.high}) async {
        opened.add(id);
        if (id == _video.id) throw const AgeRestricted();
        if (id == 'restricted-too') throw const AgeRestricted();
        return _stream(id);
      };
      findSongVersion = (track) async {
        looked.add(track.id);
        return version;
      };
    });
    tearDown(() {
      openStream = audioStream;
      findSongVersion = yt.songVersion;
    });

    test('the song version plays instead, said once', () async {
      final told = <String>[];
      final s = await trackStream(
        _video,
        quality: AudioQuality.high,
        onVersion: (v) => told.add(v.id),
      );
      expect(s.url.path, '/song1');
      expect(told, ['song1']);
      // Next time: straight to the song version, no search, nothing said.
      final again = await trackStream(
        _video,
        quality: AudioQuality.high,
        onVersion: (v) => told.add(v.id),
      );
      expect(again.url.path, '/song1');
      expect(looked, [_video.id]);
      expect(told, ['song1']);
    });

    test('no song version: age-restricted, said so', () async {
      version = null;
      await expectLater(
        trackStream(_video, quality: AudioQuality.high),
        throwsA(isA<AgeRestricted>()),
      );
    });

    test('the song version restricted too: age-restricted', () async {
      version = const Track(
        id: 'restricted-too',
        title: 'x',
        artist: 'y',
        artUrl: '',
      );
      await expectLater(
        trackStream(_video, quality: AudioQuality.high),
        throwsA(isA<AgeRestricted>()),
      );
    });

    test('other problems are not looked into', () async {
      openStream = (id, {itag, client, quality = AudioQuality.high}) async =>
          throw const HttpException('This video is unavailable');
      await expectLater(
        trackStream(_video, quality: AudioQuality.high),
        throwsA(isA<HttpException>()),
      );
      expect(looked, isEmpty);
    });

    test(
      'a lookup ahead that failed is tried again, then falls back',
      () async {
        final s = await trackStream(
          _video,
          quality: AudioQuality.high,
          first: Future.error(const AgeRestricted()),
        );
        expect(s.url.path, '/song1');
      },
    );
  });

  test(
    '"Couldn\'t play" says it plainly, not "Sign in to confirm your age"',
    () {
      expect(
        couldNotPlay(_video, const AgeRestricted()),
        'Couldn\'t play "${_video.title}": it\'s age-restricted, and YouTube '
        'plays it only in its own apps',
      );
    },
  );
}
