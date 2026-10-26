import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api/innertube.dart' as yt;
import '../api/spotify.dart';
import '../models.dart';
import 'library.dart';

/// A playlist link someone can paste: YouTube / YouTube Music or Spotify.
sealed class PlaylistLink {
  const PlaylistLink();

  static PlaylistLink? parse(String text) {
    if (yt.playlistIdFromLink(text) case final id?) return YouTubeLink(id);
    if (spotifyIdFromLink(text) case (final kind, final id)) {
      return SpotifyLink(kind, id);
    }
    return null;
  }
}

class YouTubeLink extends PlaylistLink {
  const YouTubeLink(this.id);

  final String id;
}

class SpotifyLink extends PlaylistLink {
  const SpotifyLink(this.kind, this.id);

  final SpotifyKind kind;
  final String id;
}

/// One Spotify song and what it matched on YouTube Music.
class ImportMatch {
  ImportMatch(this.song, this.candidates, {required this.sure})
    : chosen = candidates.firstOrNull;

  final SourceSong song;

  /// Best first.
  final List<Track> candidates;

  /// The best candidate is clearly the same song.
  final bool sure;

  /// What gets saved; null leaves the song out.
  Track? chosen;
}

/// Finds Spotify songs on YouTube Music, a few at a time. [matched] counts
/// up as they come in.
class SpotifyImport {
  SpotifyImport(this.list);

  final SpotifyList list;
  final matched = ValueNotifier(0);
  late final List<ImportMatch> matches;
  var _cancelled = false;

  /// Stops looking (the page was left); [run] then ends early.
  void cancel() => _cancelled = true;

  Future<void> run({
    Future<List<Object>> Function(String, yt.SearchFilter) search = yt.search,
  }) async {
    final results = List<ImportMatch?>.filled(list.songs.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < list.songs.length && !_cancelled) {
        final i = next++;
        results[i] = await findMatch(list.songs[i], search: search);
        matched.value++;
      }
    }

    await Future.wait([for (var w = 0; w < 4; w++) worker()]);
    matches = [
      for (var i = 0; i < results.length; i++)
        results[i] ?? ImportMatch(list.songs[i], const [], sure: false),
    ];
  }

  /// The playlist from the chosen matches, each song once.
  Playlist save() => userLibrary.createPlaylist(
    list.name,
    tracks: [for (final m in matches) ?m.chosen],
    source: 'Spotify',
  );
}

/// Searches YouTube Music for [song]: songs first, then videos (covers,
/// uploads) when no song is clearly it.
Future<ImportMatch> findMatch(
  SourceSong song, {
  Future<List<Object>> Function(String, yt.SearchFilter) search = yt.search,
}) async {
  final query = '${song.title} ${song.artists.take(2).join(' ')}';
  final scored = <(Track, double)>[];
  for (final filter in [yt.SearchFilter.songs, yt.SearchFilter.videos]) {
    try {
      final results = await search(query, filter);
      for (final t in results.whereType<Track>().take(5)) {
        if (!scored.any((s) => s.$1 == t)) scored.add((t, matchScore(song, t)));
      }
    } catch (_) {
      // Try the other filter; a song with no candidates is left out.
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    if (scored.firstOrNull case (_, final best) when best >= sureScore) break;
  }
  return ImportMatch(song, [
    for (final (t, score) in scored)
      if (score >= 0.3) t,
  ], sure: (scored.firstOrNull?.$2 ?? 0) >= sureScore);
}

/// At or above this, a match is the same song.
const sureScore = 0.8;

/// Versions that are a different recording unless the original says so.
const _versionWords = {
  'live',
  'remix',
  'cover',
  'karaoke',
  'instrumental',
  'acoustic',
  'sped',
  'slowed',
  'reverb',
  'nightcore',
  '8d',
  'lofi',
  'reprise',
  'unplugged',
  'mashup',
};

/// How sure it is that [candidate] is [song], from 0 to 1: the title
/// counts most, then the artist, then the length.
@visibleForTesting
double matchScore(SourceSong song, Track candidate) {
  final title = _words(_baseTitle(song.title));
  // Videos often put the artist in the title ("Artist - Song (Video)").
  final candidateText = _words('${candidate.title} ${candidate.artist}');
  final candidateTitle = _words(_baseTitle(candidate.title));
  if (title.isEmpty) return 0;
  final titleScore = title.where(candidateText.contains).length / title.length;

  final artists = [for (final a in song.artists) _words(a)];
  final artistFound = artists.any(
    (a) => a.isNotEmpty && a.every(candidateText.contains),
  );

  var lengthScore = 0.5;
  if (song.duration case final d?) {
    if (candidate.duration case final c?) {
      final off = (d - c).inSeconds.abs();
      lengthScore = off <= 3
          ? 1
          : off <= 10
          ? 0.7
          : off <= 30
          ? 0.3
          : 0;
    }
  }

  // A remix, live or sped-up version, unless that's what the song is. A
  // "cover" by the song's own artist is their song.
  final original = _words(song.title);
  final otherVersion = candidateTitle
      .where(
        (w) =>
            _versionWords.contains(w) &&
            !original.contains(w) &&
            !(w == 'cover' && artistFound),
      )
      .isNotEmpty;

  final score =
      0.5 * titleScore +
      (artistFound ? 0.3 : 0) +
      0.2 * lengthScore -
      (otherVersion ? 0.4 : 0);
  return max(0, min(1, score));
}

/// "Song (feat. X) - Remastered 2011" → "Song".
String _baseTitle(String title) => title
    .replaceAll(
      RegExp(r'\((feat|ft|with)\.? [^)]*\)', caseSensitive: false),
      '',
    )
    .replaceAll(
      RegExp(r'\[(feat|ft|with)\.? [^\]]*\]', caseSensitive: false),
      '',
    )
    .replaceAll(
      RegExp(r' - (\d{4} )?remaster(ed)?( \d{4})?.*$', caseSensitive: false),
      '',
    )
    .replaceAll(
      RegExp(r' - (from|radio edit|single version).*$', caseSensitive: false),
      '',
    );

List<String> _words(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r"['’]"), '')
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((w) => w.isNotEmpty)
    .toList();
