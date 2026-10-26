import 'dart:convert';
import 'dart:io';

// Public Spotify playlists and albums, read without signing in from the
// page Spotify serves for embedding them in other sites. It lists up to 100
// songs; Spotify doesn't share more without a login.

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The most songs Spotify shares without a login.
const spotifyLimit = 100;

final _http = HttpClient();

enum SpotifyKind { playlist, album }

/// A song as Spotify lists it.
class SourceSong {
  const SourceSong(this.title, this.artists, [this.duration]);

  final String title;
  final List<String> artists;
  final Duration? duration;

  String get artist => artists.join(', ');
}

class SpotifyList {
  const SpotifyList({
    required this.name,
    required this.songs,
    required this.total,
  });

  final String name;
  final List<SourceSong> songs;

  /// How many songs it really has (more than [songs] past the limit).
  final int total;
}

/// The playlist or album in a Spotify link (open.spotify.com/…, with or
/// without a language part, or a spotify: URI), or null.
(SpotifyKind, String)? spotifyIdFromLink(String text) {
  text = text.trim();
  if (text.contains(RegExp(r'\s'))) return null;
  final List<String> parts;
  if (text.startsWith('spotify:')) {
    parts = text.split(':').skip(1).toList();
  } else {
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host != 'open.spotify.com' && host != 'play.spotify.com') return null;
    parts = uri.pathSegments
        .where((s) => s.isNotEmpty && !s.startsWith('intl-'))
        .toList();
  }
  if (parts case [final kind, final id, ...]
      when RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(id)) {
    return switch (kind) {
      'playlist' => (SpotifyKind.playlist, id),
      'album' => (SpotifyKind.album, id),
      _ => null,
    };
  }
  return null;
}

Future<SpotifyList> spotifyList(SpotifyKind kind, String id) async {
  final page = await _get('https://open.spotify.com/embed/${kind.name}/$id');
  final list = parseSpotifyEmbed(page);
  if (list.songs.length < spotifyLimit) return list;
  // At the limit: the full page says how many there really are.
  try {
    // (Served to plain HTTP clients; browsers get an empty app shell.)
    final full = await _get(
      'https://open.spotify.com/${kind.name}/$id',
      browser: false,
    );
    final count = RegExp(r'music:song_count" content="(\d+)"')
        .firstMatch(full)
        ?.group(1);
    return SpotifyList(
      name: list.name,
      songs: list.songs,
      total: int.tryParse(count ?? '') ?? list.total,
    );
  } catch (_) {
    return list;
  }
}

/// Reads the embed page's data. Throws when it has none (private, deleted).
SpotifyList parseSpotifyEmbed(String page) {
  final data = RegExp(
    r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
    dotAll: true,
  ).firstMatch(page)?.group(1);
  final entity = data == null
      ? null
      : jsonDecode(data)['props']?['pageProps']?['state']?['data']?['entity'];
  if (entity is! Map || entity['trackList'] is! List) {
    throw const HttpException(
      "Couldn't open it on Spotify. It may be private: only public "
      'playlists can be imported.',
    );
  }
  final songs = [
    for (final t in entity['trackList'] as List)
      if (t['title'] case final String title when title.isNotEmpty)
        SourceSong(title, [
          for (final a in (t['subtitle'] as String? ?? '').split(','))
            if (a.trim().isNotEmpty) a.trim(),
        ], t['duration'] is int ? Duration(milliseconds: t['duration']) : null),
  ];
  return SpotifyList(
    name: entity['name'] ?? entity['title'] ?? 'Spotify playlist',
    songs: songs,
    total: songs.length,
  );
}

Future<String> _get(String url, {bool browser = true}) async {
  final req = await _http.getUrl(Uri.parse(url));
  if (browser) req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
  final res = await req.close();
  final text = await utf8.decodeStream(res);
  if (res.statusCode != HttpStatus.ok) {
    throw const HttpException(
      "Couldn't open it on Spotify. It may be private: only public "
      'playlists can be imported.',
    );
  }
  return text;
}
