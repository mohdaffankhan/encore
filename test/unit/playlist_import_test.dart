import 'dart:convert';
import 'dart:io';

import 'package:encore/api/innertube.dart';
import 'package:encore/api/spotify.dart';
import 'package:encore/models.dart';
import 'package:encore/services/playlist_import.dart';
import 'package:encore/ui/widgets/playlist_dialogs.dart';
import 'package:flutter_test/flutter_test.dart';

// Importing Spotify playlists: reading Spotify's page, finding each song on
// YouTube Music, and exporting playlists back out.

Track _yt(String title, String artist, [int? seconds, String? id]) => Track(
  id: id ?? '$title/$artist',
  title: title,
  artist: artist,
  duration: seconds == null ? null : Duration(seconds: seconds),
  artUrl: '',
);

/// A page like Spotify's embed page, holding [tracks].
String _embedPage(String name, List<Map<String, Object>> tracks) =>
    '<html><script id="__NEXT_DATA__" type="application/json">'
    '${jsonEncode({
      'props': {
        'pageProps': {
          'state': {
            'data': {
              'entity': {'name': name, 'trackList': tracks},
            },
          },
        },
      },
    })}'
    '</script></html>';

void main() {
  group('Spotify page', () {
    test('lists the songs with their artists and length', () {
      final list = parseSpotifyEmbed(
        _embedPage('Road trip', [
          {'title': 'Housewife', 'subtitle': 'Tate McRae', 'duration': 208810},
          {
            'title': 'BbY WOW',
            'subtitle': 'KAROL G, Judeline, rusowsky',
            'duration': 180000,
          },
          {'title': '', 'subtitle': 'Nobody'},
        ]),
      );
      expect(list.name, 'Road trip');
      expect(list.total, 2);
      expect(list.songs.map((s) => s.title), ['Housewife', 'BbY WOW']);
      expect(list.songs[1].artists, ['KAROL G', 'Judeline', 'rusowsky']);
      expect(list.songs[0].duration, const Duration(milliseconds: 208810));
    });

    test('a private or missing playlist says so', () {
      // What Spotify serves for a private playlist: a "Page not found" page.
      expect(
        () => parseSpotifyEmbed('<html><title>Page not found</title></html>'),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            contains('private'),
          ),
        ),
      );
    });
  });

  group('match score', () {
    const song = SourceSong('Get Lucky (feat. Pharrell Williams)', [
      'Daft Punk',
      'Pharrell Williams',
    ], Duration(seconds: 369));

    test('the same song is sure', () {
      expect(
        matchScore(
          song,
          _yt('Get Lucky', 'Daft Punk & Pharrell Williams', 369),
        ),
        greaterThanOrEqualTo(sureScore),
      );
      // A video with the artist in its title.
      expect(
        matchScore(
          song,
          _yt('Daft Punk - Get Lucky (Official Audio)', 'Daft Punk', 368),
        ),
        greaterThanOrEqualTo(sureScore),
      );
    });

    test('another artist, version or length is not sure', () {
      for (final other in [
        _yt('Get Lucky', 'Some Cover Band', 369),
        _yt('Get Lucky (Cover)', 'Random Singer', 369),
        _yt('Get Lucky (Live)', 'Daft Punk', 400),
        _yt('Get Lucky (Remix)', 'Daft Punk', 369),
        _yt('Get Lucky - Sped Up', 'Daft Punk', 250),
        _yt('Lose Yourself to Dance', 'Daft Punk', 353),
      ]) {
        expect(
          matchScore(song, other),
          lessThan(sureScore),
          reason: other.title,
        );
      }
    });

    test('a remix is sure when the original is that remix', () {
      const remix = SourceSong('KALYANI (Remix)', ['Artist'], null);
      expect(
        matchScore(remix, _yt('KALYANI (Remix)', 'Artist')),
        greaterThanOrEqualTo(sureScore),
      );
    });

    test('titles in other scripts and with accents match', () {
      const hindi = SourceSong('तुम ही हो', ['Arijit Singh'], null);
      expect(
        matchScore(hindi, _yt('तुम ही हो', 'Arijit Singh')),
        greaterThanOrEqualTo(sureScore),
      );
      const accents = SourceSong('Nicole Kidman', ['ADÉLA'], null);
      expect(
        matchScore(accents, _yt('Nicole Kidman', 'ADÉLA')),
        greaterThanOrEqualTo(sureScore),
      );
    });
  });

  group('finding songs', () {
    const song = SourceSong('Sammi Meri Waar', ['Shifa Qassim'], null);

    test('looks in videos when no song is sure (covers, uploads)', () async {
      final asked = <SearchFilter>[];
      final match = await findMatch(
        song,
        search: (query, filter) async {
          asked.add(filter);
          return filter == SearchFilter.songs
              ? [_yt('Sammi Meri Waar', 'Someone Else', null, 'other')]
              : [
                  _yt(
                    'Sammi Meri Waar (Lyrical Cover) Shifa Qassim',
                    'Times Mp3 Records',
                    null,
                    'YlycL6ky2Wc',
                  ),
                ];
        },
      );
      expect(asked, [SearchFilter.songs, SearchFilter.videos]);
      expect(match.chosen?.id, 'YlycL6ky2Wc');
      expect(match.sure, isTrue);
      expect(match.candidates.map((t) => t.id), contains('other'));
    });

    test('stops at songs when one is sure', () async {
      final asked = <SearchFilter>[];
      await findMatch(
        song,
        search: (query, filter) async {
          asked.add(filter);
          return [_yt('Sammi Meri Waar', 'Shifa Qassim')];
        },
      );
      expect(asked, [SearchFilter.songs]);
    });

    test('nothing found (or offline) leaves the song out', () async {
      final match = await findMatch(
        song,
        search: (query, filter) async => throw const SocketException('x'),
      );
      expect(match.candidates, isEmpty);
      expect(match.chosen, isNull);
      expect(match.sure, isFalse);
    });

    test('a whole list keeps its order and counts up', () async {
      final songs = [
        for (var i = 0; i < 9; i++) SourceSong('Song $i', ['Band'], null),
      ];
      final import = SpotifyImport(
        SpotifyList(name: 'Mix', songs: songs, total: 9),
      );
      final counts = <int>[];
      import.matched.addListener(() => counts.add(import.matched.value));
      await import.run(
        search: (query, filter) async {
          // Later songs answer sooner: the order must still hold.
          final i = int.parse(query.split(' ')[1]);
          await Future<void>.delayed(Duration(milliseconds: 20 - 2 * i));
          return [_yt('Song $i', 'Band', null, 'id$i')];
        },
      );
      expect(import.matches.map((m) => m.chosen?.id), [
        for (var i = 0; i < 9; i++) 'id$i',
      ]);
      expect(counts.last, 9);
    });
  });

  test('cancelling stops the searches', () async {
    final import = SpotifyImport(
      SpotifyList(
        name: 'Mix',
        songs: [
          for (var i = 0; i < 40; i++) SourceSong('Song $i', ['Band']),
        ],
        total: 40,
      ),
    );
    var searches = 0;
    await import.run(
      search: (query, filter) async {
        if (++searches == 6) import.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return [_yt(query, 'Band')];
      },
    );
    expect(searches, lessThan(12), reason: 'only those already started');
    expect(import.matches, hasLength(40));
  });

  group('export', () {
    final tracks = [for (var i = 0; i < 120; i++) _yt('S$i', 'A', null, 'v$i')];

    test('YouTube links hold 50 songs each, in order', () {
      final links = youTubeLinks(tracks);
      expect(links, hasLength(3));
      final ids = [
        for (final l in links) ...l.queryParameters['video_ids']!.split(','),
      ];
      expect(ids, [for (var i = 0; i < 120; i++) 'v$i']);
      expect(links.first.path, '/watch_videos');
      expect(
        links.last.queryParameters['video_ids']!.split(','),
        hasLength(20),
      );
    });

    test('the song list is one "Title - Artist" per line', () {
      final playlist = Playlist(
        id: '1',
        name: 'Mix',
        tracks: [_yt('Get Lucky', 'Daft Punk'), _yt('Khat', 'Navjot Ahuja')],
      );
      expect(songList(playlist), 'Get Lucky - Daft Punk\nKhat - Navjot Ahuja');
    });
  });
}
