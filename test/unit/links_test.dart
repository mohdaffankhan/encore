import 'package:encore/api/innertube.dart';
import 'package:encore/api/spotify.dart';
import 'package:encore/services/playlist_import.dart';
import 'package:flutter_test/flutter_test.dart';

// Pasting a YouTube / YouTube Music link into search opens that song; a
// playlist link (YouTube, YouTube Music, Spotify) imports the playlist.
void main() {
  const id = 'YlycL6ky2Wc';

  test('links to a song give its id', () {
    for (final link in [
      'https://youtu.be/$id?si=GCLgmi9AL9I2bEZ_',
      'youtu.be/$id',
      'https://www.youtube.com/watch?v=$id',
      'https://youtube.com/watch?v=$id&list=RDMM&t=42s',
      'https://m.youtube.com/watch?v=$id',
      'https://music.youtube.com/watch?v=$id&si=abc',
      'https://www.youtube.com/shorts/$id',
      'https://www.youtube.com/embed/$id',
      'https://www.youtube.com/live/$id?feature=share',
      '  https://youtu.be/$id  ',
      'HTTPS://WWW.YOUTUBE.COM/watch?v=$id',
    ]) {
      expect(videoIdFromLink(link), id, reason: link);
    }
  });

  test('searches and other links are not', () {
    for (final text in [
      'sammi meri waar',
      'get lucky',
      id,
      'youtu.be',
      'https://youtube.com/',
      'https://www.youtube.com/watch?v=short',
      'https://www.youtube.com/playlist?list=PL123',
      'https://www.youtube.com/@TimesMp3Records',
      'https://example.com/watch?v=$id',
      'https://notyoutu.be/$id',
      'youtu.be/$id and more',
    ]) {
      expect(videoIdFromLink(text), isNull, reason: text);
    }
  });

  test('YouTube playlist links give the playlist id', () {
    const list = 'PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG';
    for (final link in [
      'https://www.youtube.com/playlist?list=$list',
      'https://music.youtube.com/playlist?list=$list&si=abc',
      'youtube.com/playlist?list=$list',
      'https://www.youtube.com/watch?v=$id&list=$list',
      'https://youtu.be/$id?list=$list',
    ]) {
      expect(playlistIdFromLink(link), list, reason: link);
    }
    // YouTube Music's own playlists start like a mix, but are playlists.
    const official = 'RDCLAK5uy_krbBs7P2iEb30IODyVbiOXWyhZtAIX9Uk';
    expect(
      playlistIdFromLink('https://music.youtube.com/playlist?list=$official'),
      official,
    );
    for (final text in [
      'https://www.youtube.com/watch?v=$id',
      'https://www.youtube.com/watch?v=$id&list=RDMM',
      'https://www.youtube.com/watch?v=$id&list=RDAMVM$id',
      'https://www.youtube.com/watch?v=$id&list=TLGGKUght8YCkmcy',
      'https://example.com/playlist?list=$list',
      'my playlist',
    ]) {
      expect(playlistIdFromLink(text), isNull, reason: text);
    }
  });

  test('Spotify links give the playlist or album', () {
    const sp = '6fGsXMDMl4nueTKDXxyKxt';
    for (final (link, kind) in [
      (
        'https://open.spotify.com/playlist/$sp?si=d65dd1ec8b094bad&pt=7972',
        SpotifyKind.playlist,
      ),
      ('open.spotify.com/playlist/$sp', SpotifyKind.playlist),
      ('https://open.spotify.com/intl-de/playlist/$sp', SpotifyKind.playlist),
      ('spotify:playlist:$sp', SpotifyKind.playlist),
      ('https://open.spotify.com/album/$sp', SpotifyKind.album),
    ]) {
      expect(spotifyIdFromLink(link), (kind, sp), reason: link);
    }
    for (final text in [
      'https://open.spotify.com/track/$sp',
      'https://open.spotify.com/artist/$sp',
      'https://open.spotify.com/playlist/short',
      'https://example.com/playlist/$sp',
      'spotify playlist',
    ]) {
      expect(spotifyIdFromLink(text), isNull, reason: text);
    }
  });

  test('a playlist link is told apart from a search', () {
    expect(
      PlaylistLink.parse(
        'https://open.spotify.com/playlist/6fGsXMDMl4nueTKDXxyKxt',
      ),
      isA<SpotifyLink>(),
    );
    expect(
      PlaylistLink.parse(
        'https://music.youtube.com/playlist?list=PLabcdefghijk',
      ),
      isA<YouTubeLink>(),
    );
    expect(PlaylistLink.parse('https://youtu.be/$id'), isNull);
    expect(PlaylistLink.parse('lofi playlist'), isNull);
  });
}
