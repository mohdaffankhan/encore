import 'dart:convert';
import 'dart:io';

import '../models.dart';

// YouTube Music's internal API, as used by music.youtube.com. Unofficial:
// response shapes change occasionally, so parsing is defensive throughout.

const _base = 'https://music.youtube.com/youtubei/v1';
const _context = {
  'client': {
    'clientName': 'WEB_REMIX',
    'clientVersion': '1.20261015.01.00',
    'hl': 'en',
  },
};

enum SearchFilter {
  songs('Songs', 'EgWKAQIIAWoSEAUQDhADEAkQChAEEBUQEBAR'),
  albums('Albums', 'EgWKAQIYAWoSEAUQDhADEAkQChAEEBUQEBAR'),
  artists('Artists', 'EgWKAQIgAWoSEAUQDhADEAkQChAEEBUQEBAR'),
  playlists('Playlists', 'EgeKAQQoADgBahIQBRAOEAMQCRAKEAQQFRAQEBE%3D');

  const SearchFilter(this.label, this.params);

  final String label;
  final String params;
}

final _http = HttpClient();

/// The anonymous visitor id YouTube assigns; feed continuations only work
/// when it is sent back.
String? _visitorData;

Future<Map<String, dynamic>> _post(
  String endpoint,
  Map<String, dynamic> body, {
  String query = '',
}) async {
  final req = await _http.postUrl(
    Uri.parse('$_base/$endpoint?prettyPrint=false$query'),
  );
  req.headers
    ..contentType = ContentType.json
    ..set('Origin', 'https://music.youtube.com')
    ..set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
    );
  if (_visitorData != null) req.headers.set('X-Goog-Visitor-Id', _visitorData!);
  req.write(
    jsonEncode({
      ...body,
      'context': {
        'client': {..._context['client']!, 'visitorData': ?_visitorData},
      },
    }),
  );
  final res = await req.close();
  final text = await utf8.decodeStream(res);
  if (res.statusCode != HttpStatus.ok) {
    throw HttpException('YouTube Music $endpoint: HTTP ${res.statusCode}');
  }
  final json = jsonDecode(text);
  _visitorData ??= json['responseContext']?['visitorData'];
  return json;
}

Future<Map<String, dynamic>> browse(String browseId) =>
    _post('browse', {'browseId': browseId});

/// Results are [Track]s for songs, [MediaRef]s otherwise.
Future<List<Object>> search(String query, SearchFilter filter) async {
  final json = await _post('search', {'query': query, 'params': filter.params});
  return [
    for (final item in _findAll(json, 'musicResponsiveListItemRenderer'))
      ?_listItem(item),
  ];
}

Future<List<String>> suggestions(String input) async {
  final json = await _post('music/get_search_suggestions', {'input': input});
  return [
    for (final s in _findAll(json, 'searchSuggestionRenderer'))
      _text(s['suggestion']),
  ];
}

/// A song's radio.
Future<List<Track>> radio(String videoId) async {
  final json = await _post('next', {
    'videoId': videoId,
    'playlistId': 'RDAMVM$videoId',
    'isAudioOnly': true,
  });
  return [
    for (final item in _findAll(json, 'playlistPanelVideoRenderer'))
      ?_panelTrack(item),
  ];
}

Future<List<Shelf>> home() async {
  final hadVisitor = _visitorData != null;
  var json = await browse('FEmusic_home');
  // Continuation tokens are tied to the visitor; refetch once we have one.
  if (!hadVisitor && _visitorData != null) json = await browse('FEmusic_home');
  final shelves = _shelves(json);
  // Each page holds only a few rows; a few more pages fill the feed.
  for (var page = 0; page < 3; page++) {
    final next = _continuation(json);
    if (next == null) break;
    try {
      json = await next();
    } catch (_) {
      break;
    }
    shelves.addAll(_shelves(json));
  }
  return shelves;
}

Future<Artist> artist(String browseId) async {
  final json = await browse(browseId);
  final header =
      _findAll(json, 'musicImmersiveHeaderRenderer').firstOrNull ??
      _findAll(json, 'musicVisualHeaderRenderer').firstOrNull;
  final topSongs = _findAll(json, 'musicShelfRenderer').firstOrNull;
  return Artist(
    name: _text(header?['title']),
    subtitle: _text(header?['monthlyListenerCount']),
    artUrl: _art(header?['thumbnail'], resize: false),
    topSongs: [
      for (final item in _findAll(topSongs, 'musicResponsiveListItemRenderer'))
        if (_listItem(item) case final Track t) t,
    ],
    shelves: _shelves(json),
  );
}

/// An album (`MPRE…`) or playlist (`VL…`) with all its songs.
Future<Collection> collection(String browseId) async {
  var json = await browse(browseId);
  final header =
      _findAll(json, 'musicResponsiveHeaderRenderer').firstOrNull ??
      _findAll(json, 'musicDetailHeaderRenderer').firstOrNull;
  final title = _text(header?['title']);
  final artUrl = _art(header?['thumbnail']);
  final strapline =
      (header?['straplineTextOne']?['runs'] as List?)?.firstOrNull;
  final artistName = _text(header?['straplineTextOne']);
  final artistId = _findAll(strapline, 'browseId').firstOrNull as String?;
  final isAlbum = browseId.startsWith('MPRE');
  final defaults = _Defaults(
    artUrl: artUrl,
    artist: artistName,
    artistId: artistId,
    album: isAlbum ? title : null,
    albumId: isAlbum ? browseId : null,
  );

  final tracks = <Track>[];
  // Playlists arrive in pages of 100; stop at 1000 songs.
  for (var page = 0; page < 10; page++) {
    for (final item in _findAll(json, 'musicResponsiveListItemRenderer')) {
      if (_listItem(item, defaults) case final Track t) tracks.add(t);
    }
    final next = _continuation(json);
    if (next == null) break;
    json = await next();
  }
  return Collection(
    title: title,
    subtitle: [
      _text(header?['subtitle']),
      _text(header?['secondSubtitle']),
    ].where((s) => s.isNotEmpty).join(' • '),
    artUrl: artUrl,
    tracks: tracks,
    artist: artistName.isEmpty ? null : artistName,
    artistId: artistId,
  );
}

/// The request for the next page of a browse result, if there is one.
Future<Map<String, dynamic>> Function()? _continuation(
  Map<String, dynamic> json,
) {
  final legacy = _findAll(json, 'nextContinuationData').firstOrNull;
  if (legacy?['continuation'] case final String token) {
    return () => _post(
      'browse',
      {},
      query: '&ctoken=$token&continuation=$token&type=next',
    );
  }
  final command = _findAll(json, 'continuationCommand').firstOrNull;
  if (command?['token'] case final String token) {
    return () => _post('browse', {'continuation': token});
  }
  return null;
}

List<Shelf> _shelves(Map<String, dynamic> json) {
  final shelves = <Shelf>[];
  for (final shelf in _findAll(json, 'musicCarouselShelfRenderer')) {
    final title = _text(_findAll(shelf['header'], 'title').firstOrNull);
    final items = shelf['contents'] as List? ?? [];
    final tracks = <Track>[];
    final cards = <Object>[];
    for (final i in items) {
      if (i['musicResponsiveListItemRenderer']
          case final Map<String, dynamic> r) {
        if (_listItem(r) case final Track t) tracks.add(t);
      } else if (i['musicTwoRowItemRenderer']
          case final Map<String, dynamic> r) {
        if (_card(r) case final card?) cards.add(card);
      }
    }
    if (title.isNotEmpty && (tracks.isNotEmpty || cards.isNotEmpty)) {
      shelves.add(Shelf(title, tracks: tracks, cards: cards));
    }
  }
  return shelves;
}

class _Defaults {
  const _Defaults({
    this.artUrl = '',
    this.artist = '',
    this.artistId,
    this.album,
    this.albumId,
  });

  final String artUrl;
  final String artist;
  final String? artistId;
  final String? album;
  final String? albumId;
}

/// Type labels YouTube Music prefixes to subtitles, e.g. "Song • Artist".
const _labels = {
  'Song',
  'Video',
  'Album',
  'Single',
  'EP',
  'Artist',
  'Playlist',
  'Episode',
  'Podcast',
  'Profile',
};

/// A row from a list: a [Track] when it plays a song, else a [MediaRef].
Object? _listItem(Map<String, dynamic> r, [_Defaults d = const _Defaults()]) {
  final columns = [
    for (final c in r['flexColumns'] as List? ?? [])
      c['musicResponsiveListItemFlexColumnRenderer']?['text'],
  ];
  if (columns.isEmpty) return null;
  final title = _text(columns.first);
  final art = _art(r['thumbnail']);
  final details = [for (final c in columns.skip(1)) ..._segments(c)];
  if (details.isNotEmpty && _labels.contains(details.first)) {
    details.removeAt(0);
  }

  final videoId =
      r['playlistItemData']?['videoId'] ??
      _findAll(columns.first, 'watchEndpoint').firstOrNull?['videoId'];
  if (videoId == null) {
    final ref = _ref(r['navigationEndpoint'], title, details.join(' • '), art);
    return ref;
  }

  final runs = [
    for (final c in columns.skip(1)) ...(c?['runs'] as List? ?? []),
  ];
  Map? runOf(String pageType) => runs
      .where((run) => _pageType(run['navigationEndpoint']) == pageType)
      .firstOrNull;
  final artistRun = runOf('MUSIC_PAGE_TYPE_ARTIST');
  final albumRun = runOf('MUSIC_PAGE_TYPE_ALBUM');
  final fixed = [
    for (final c in r['fixedColumns'] as List? ?? [])
      _text(c['musicResponsiveListItemFixedColumnRenderer']?['text']),
  ];
  final artist = details
      .where((s) => _parseDuration(s) == null && !s.endsWith(' plays'))
      .firstOrNull;
  return Track(
    id: videoId,
    title: title,
    artist: artist ?? d.artist,
    artistId: _browseId(artistRun) ?? d.artistId,
    album: albumRun?['text'] ?? d.album,
    albumId: _browseId(albumRun) ?? d.albumId,
    duration: [...fixed, ...details].map(_parseDuration).nonNulls.firstOrNull,
    artUrl: art.isEmpty ? d.artUrl : art,
  );
}

/// A card from a carousel: album/playlist/artist, or a video.
Object? _card(Map<String, dynamic> r) {
  final title = _text(r['title']);
  final subtitle = _segments(r['subtitle']);
  if (subtitle.isNotEmpty && _labels.contains(subtitle.first)) {
    subtitle.removeAt(0);
  }
  final art = _art(r['thumbnailRenderer']);
  final videoId = r['navigationEndpoint']?['watchEndpoint']?['videoId'];
  if (videoId != null) {
    return Track(
      id: videoId,
      title: title,
      artist: subtitle.firstOrNull ?? '',
      artUrl: art,
    );
  }
  return _ref(r['navigationEndpoint'], title, subtitle.join(' • '), art);
}

MediaRef? _ref(dynamic endpoint, String title, String subtitle, String art) {
  final id = endpoint?['browseEndpoint']?['browseId'] as String?;
  final kind = switch (_pageType(endpoint)) {
    'MUSIC_PAGE_TYPE_ALBUM' => MediaKind.album,
    'MUSIC_PAGE_TYPE_PLAYLIST' => MediaKind.playlist,
    'MUSIC_PAGE_TYPE_ARTIST' => MediaKind.artist,
    _ => null,
  };
  if (id == null || kind == null) return null;
  return MediaRef(
    kind: kind,
    id: id,
    title: title,
    subtitle: subtitle,
    artUrl: art,
  );
}

Track? _panelTrack(Map<String, dynamic> r) {
  final videoId = r['videoId'];
  if (videoId == null) return null;
  final byline = _segments(r['longBylineText']);
  final runs = r['longBylineText']?['runs'] as List? ?? [];
  Map? runOf(String pageType) => runs
      .where((run) => _pageType(run['navigationEndpoint']) == pageType)
      .firstOrNull;
  final artistRun =
      runOf('MUSIC_PAGE_TYPE_ARTIST') ??
      runs
          .where((run) => _browseId(run)?.startsWith('UC') ?? false)
          .firstOrNull;
  final albumRun = runOf('MUSIC_PAGE_TYPE_ALBUM');
  return Track(
    id: videoId,
    title: _text(r['title']),
    artist: byline.firstOrNull ?? '',
    artistId: _browseId(artistRun),
    album: albumRun?['text'],
    albumId: _browseId(albumRun),
    duration: _parseDuration(_text(r['lengthText'])),
    artUrl: _art(r['thumbnail']),
  );
}

String? _pageType(dynamic endpoint) =>
    endpoint?['browseEndpoint']?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType'];

String? _browseId(Map? run) =>
    run?['navigationEndpoint']?['browseEndpoint']?['browseId'];

/// The largest thumbnail. YouTube Music art URLs are resized via `=wN-hN`;
/// requested at 544 here and scaled down per use in the UI.
String _art(dynamic node, {bool resize = true}) {
  final thumbs = _findAll(node, 'thumbnails').firstOrNull as List?;
  final url = (thumbs?.lastOrNull?['url'] as String?) ?? '';
  return resize ? url.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w544-h544') : url;
}

String _text(dynamic node) =>
    [for (final run in node?['runs'] as List? ?? []) run['text']].join();

/// Splits "Artist • Album • 4:37" style text into its parts.
List<String> _segments(dynamic node) =>
    _text(node)
        .split(' • ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

Duration? _parseDuration(String text) {
  if (!RegExp(r'^\d+(:\d{2}){1,2}$').hasMatch(text)) return null;
  return Duration(
    seconds: text.split(':').fold(0, (sum, part) => sum * 60 + int.parse(part)),
  );
}

/// Every value stored under [key], at any depth.
Iterable<dynamic> _findAll(dynamic node, String key) sync* {
  if (node is Map) {
    for (final entry in node.entries) {
      if (entry.key == key) {
        yield entry.value;
      } else {
        yield* _findAll(entry.value, key);
      }
    }
  } else if (node is List) {
    for (final item in node) {
      yield* _findAll(item, key);
    }
  }
}
