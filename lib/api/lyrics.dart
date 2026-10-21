import 'dart:convert';
import 'dart:io';

import '../models.dart';

// Lyrics from LRCLIB (lrclib.net): a free, open lyrics database with a
// public API and no key.

class LyricLine {
  const LyricLine(this.time, this.text);

  final Duration time;
  final String text;
}

class Lyrics {
  const Lyrics({this.synced = const [], this.plain = ''});

  /// Time-stamped lines; empty when only plain lyrics exist.
  final List<LyricLine> synced;
  final String plain;
}

// LRCLIB asks clients to identify themselves.
final _http = HttpClient()..userAgent = 'Encore music player';
final _cache = <String, Lyrics?>{};

/// Lyrics for [track], or null when LRCLIB has none.
Future<Lyrics?> lyricsFor(Track track) async {
  if (_cache.containsKey(track.id)) return _cache[track.id];
  final title = _clean(track.title);
  final artist = track.artist.split(RegExp(r',| & ')).first.trim();
  Map<String, dynamic>? match;
  if (track.duration case final d?) {
    match = await _get('/api/get', {
      'track_name': title,
      'artist_name': artist,
      if (track.album != null) 'album_name': track.album!,
      'duration': '${d.inSeconds}',
    });
  }
  if (match == null) {
    final results = await _get('/api/search', {
      'track_name': title,
      'artist_name': artist,
    });
    final list = (results?['results'] as List?) ?? [];
    match = list.cast<Map<String, dynamic>>().where(_hasLyrics).firstOrNull;
  }
  final lyrics = match == null || !_hasLyrics(match)
      ? null
      : Lyrics(
          synced: parseLrc(match['syncedLyrics'] ?? ''),
          plain: match['plainLyrics'] ?? '',
        );
  if (_cache.length > 50) _cache.remove(_cache.keys.first);
  return _cache[track.id] = lyrics;
}

bool _hasLyrics(Map<String, dynamic> m) =>
    (m['syncedLyrics'] ?? m['plainLyrics']) != null;

Future<Map<String, dynamic>?> _get(
  String path,
  Map<String, String> query,
) async {
  Future<(int, String)> request() async {
    final req = await _http.getUrl(Uri.https('lrclib.net', path, query));
    final res = await req.close();
    return (res.statusCode, await utf8.decodeStream(res));
  }

  // A stalled connection fails instead of spinning forever.
  final (status, body) = await request().timeout(const Duration(seconds: 15));
  if (status == HttpStatus.notFound) return null;
  // Anything else (server trouble) is an error, not "no lyrics", so it
  // isn't cached and can be retried.
  if (status != HttpStatus.ok) throw HttpException('Lyrics: HTTP $status');
  final json = jsonDecode(body);
  // /api/search returns a list; wrap it to keep one return type.
  return json is List ? {'results': json} : json;
}

/// Drops decorations that stop lyric matches, e.g. `(From "Movie")`.
String _clean(String title) => title
    .replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), '')
    .split(' - ')
    .first
    .trim();

/// Parses LRC text (`[mm:ss.xx] line`) into time-sorted lines.
List<LyricLine> parseLrc(String lrc) {
  final tag = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');
  return [
    for (final line in const LineSplitter().convert(lrc))
      for (final m in tag.allMatches(line))
        LyricLine(
          Duration(
            milliseconds:
                (int.parse(m[1]!) * 60000 + double.parse(m[2]!) * 1000).round(),
          ),
          line.replaceAll(tag, '').trim(),
        ),
  ]..sort((a, b) => a.time.compareTo(b.time));
}
