import 'package:encore/api/innertube.dart';
import 'package:encore/api/lyrics.dart';
import 'package:encore/api/spotify.dart';
import 'package:encore/api/stream.dart';
import 'package:encore/models.dart';
import 'package:encore/services/playlist_import.dart';
import 'package:flutter_test/flutter_test.dart';

// Hits the real YouTube Music and LRCLIB APIs: catches breaking changes on
// their side.
void main() {
  test('search finds songs, albums, artists and playlists', () async {
    final songs = await search('daft punk', SearchFilter.songs);
    expect(songs.whereType<Track>(), isNotEmpty);
    final first = songs.first as Track;
    expect(first.title, isNotEmpty);
    expect(first.artist, isNotEmpty);
    expect(first.artistId, isNotNull);
    for (final (filter, kind) in [
      (SearchFilter.albums, MediaKind.album),
      (SearchFilter.artists, MediaKind.artist),
      (SearchFilter.playlists, MediaKind.playlist),
    ]) {
      final refs = (await search('daft punk', filter)).whereType<MediaRef>();
      expect(refs.map((r) => r.kind), contains(kind));
    }
  });

  // A cover upload, not in the song catalog: only Videos finds it.
  test('videos and pasted links find uploads that are not songs', () async {
    const id = 'YlycL6ky2Wc';
    final songs = await search(
      'Sammi Meri Waar Shifa Qassim',
      SearchFilter.songs,
    );
    expect(songs.whereType<Track>().map((t) => t.id), isNot(contains(id)));
    final videos = await search(
      'Sammi Meri Waar Shifa Qassim',
      SearchFilter.videos,
    );
    final video = videos.whereType<Track>().firstWhere((t) => t.id == id);
    expect(video.title, contains('Sammi Meri Waar'));
    expect(video.artist, 'Times Mp3 Records');
    expect(video.duration, isNotNull);
    final linked = await track(videoIdFromLink('https://youtu.be/$id?si=x')!);
    expect(linked?.id, id);
    expect(linked?.title, contains('Sammi Meri Waar'));
    expect(linked?.artUrl, isNotEmpty);
    expect((await audioStream(id)).length, greaterThan(500000));
  });

  test('a public Spotify playlist imports, a private one says so', () async {
    // Today's Top Hits (Spotify's own, public, 50 songs).
    final list = await spotifyList(
      SpotifyKind.playlist,
      '37i9dQZF1DXcBWIGoYBM5M',
    );
    expect(list.name, isNotEmpty);
    expect(list.songs.length, greaterThan(20));
    expect(list.songs.first.artists, isNotEmpty);
    expect(list.songs.first.duration, isNotNull);
    final import = SpotifyImport(
      SpotifyList(
        name: list.name,
        songs: list.songs.take(10).toList(),
        total: 10,
      ),
    );
    await import.run();
    expect(
      import.matches.where((m) => m.sure).length,
      greaterThanOrEqualTo(8),
      reason: 'chart hits are found for sure',
    );
    // The owner's private playlist (link as shared from Spotify).
    await expectLater(
      spotifyList(SpotifyKind.playlist, '6fGsXMDMl4nueTKDXxyKxt'),
      throwsA(isA<Exception>()),
    );
  });

  test('a big Spotify playlist says how many it really has', () async {
    // All Out 2010s: 150 songs, of which Spotify shares 100.
    final list = await spotifyList(
      SpotifyKind.playlist,
      '37i9dQZF1DX5Ejj0EkURtP',
    );
    expect(list.songs, hasLength(spotifyLimit));
    expect(list.total, greaterThan(spotifyLimit));
  });

  test('home, radio, artist, album and playlist load', () async {
    expect(await home(), hasLength(greaterThan(2)));
    expect(await radio('5NV6Rdv1a3I'), isNotEmpty);
    final artistPage = await artist('UCDxKh1gFWeYsqePvgVzmPoQ');
    expect(artistPage.name, isNotEmpty);
    expect(artistPage.topSongs, isNotEmpty);
    final album = await collection('MPREb_ruJS3kIaIDn');
    expect(album.tracks.first.albumId, 'MPREb_ruJS3kIaIDn');
    final playlist = await collection(
      'VLRDCLAK5uy_krbBs7P2iEb30IODyVbiOXWyhZtAIX9Uk',
    );
    expect(playlist.tracks, isNotEmpty);
  });

  test('audio streams past the first megabyte, quickly', () async {
    final stream = await audioStream('5NV6Rdv1a3I');
    expect(stream.length, greaterThan(2000000));
    final sw = Stopwatch()..start();
    var bytes = 0;
    await for (final chunk in stream.read(1000000, 3000000)) {
      bytes += chunk.length;
    }
    expect(bytes, 2000000);
    // Range requests avoid YouTube's ~real-time throttle on long requests.
    expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('synced lyrics are found', () async {
    final songs = await search('daft punk get lucky', SearchFilter.songs);
    final lyrics = await lyricsFor(songs.first as Track);
    expect(lyrics?.synced, isNotEmpty);
  });
}
