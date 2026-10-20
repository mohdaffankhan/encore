import 'package:encore/api/innertube.dart';
import 'package:encore/api/lyrics.dart';
import 'package:encore/api/stream.dart';
import 'package:encore/models.dart';
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
