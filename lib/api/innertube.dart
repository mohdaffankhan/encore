import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'auth.dart';
import 'clients.dart';

// YouTube Music's internal API, as used by music.youtube.com. Unofficial:
// response shapes change occasionally, so parsing is defensive throughout.

/// Where requests go: YouTube Music, or a test's fake server.
@visibleForTesting
var musicApiBase = '$musicOrigin/youtubei/v1';

/// Signs requests in to the user's account (see services/account.dart);
/// null while signed out, when every request is anonymous.
abstract interface class YouTubeSignIn {
  /// The headers that sign a request in, or null to send it anonymously
  /// (signed out, or the sign-in has ended).
  Map<String, String>? headers();

  /// What a request signed in with [signed] got back: its new cookies, and
  /// whether YouTube still treated it as signed in.
  void replied(
    Map<String, String> signed,
    List<Cookie> cookies,
    int status,
    Map<String, dynamic>? json,
  );
}

YouTubeSignIn? signIn;

/// A reply that wasn't a usable answer, with its HTTP status.
class YouTubeError extends HttpException {
  YouTubeError(String endpoint, this.status)
    : super('YouTube Music $endpoint: HTTP $status');

  final int status;

  /// The request itself was wrong (a song that doesn't exist): sending it
  /// again won't help. Signed-out (401, 403) and busy (429) replies can.
  bool get rejected =>
      status >= 400 &&
      status < 500 &&
      status != 401 &&
      status != 403 &&
      status != 408 &&
      status != 429;
}

/// Development only (`--dart-define=ENCORE_DUMP=<folder>`, never in
/// release builds): every reply is saved there, to write tests from.
const _dump = kReleaseMode ? '' : String.fromEnvironment('ENCORE_DUMP');
var _dumped = 0;

/// Forgets the anonymous visitor (when the account changes).
void resetVisitor() => _visitorData = null;

enum SearchFilter {
  songs('Songs', 'EgWKAQIIAWoSEAUQDhADEAkQChAEEBUQEBAR'),
  // Covers, lyric videos and other uploads that aren't in the song catalog.
  videos('Videos', 'EgWKAQIQAWoSEAUQDhADEAkQChAEEBUQEBAR'),
  albums('Albums', 'EgWKAQIYAWoSEAUQDhADEAkQChAEEBUQEBAR'),
  artists('Artists', 'EgWKAQIgAWoSEAUQDhADEAkQChAEEBUQEBAR'),
  playlists('Playlists', 'EgeKAQQoADgBahIQBRAOEAMQCRAKEAQQFRAQEBE%3D');

  const SearchFilter(this.label, this.params);

  final String label;
  final String params;
}

/// The anonymous visitor id YouTube assigns; feed continuations only work
/// when it is sent back.
String? _visitorData;

/// Fails instead of spinning forever on a stalled connection.
Future<Map<String, dynamic>> _post(
  String endpoint,
  Map<String, dynamic> body, {
  String query = '',
}) => _send(endpoint, body, query: query).timeout(const Duration(seconds: 15));

Future<Map<String, dynamic>> _send(
  String endpoint,
  Map<String, dynamic> body, {
  String query = '',
}) async {
  final req = await youtubeHttp.postUrl(
    Uri.parse('$musicApiBase/$endpoint?prettyPrint=false$query'),
  );
  final signed = signIn?.headers();
  req.headers
    ..contentType = ContentType.json
    ..set('Origin', 'https://music.youtube.com')
    ..set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
    );
  if (_visitorData != null) req.headers.set('X-Goog-Visitor-Id', _visitorData!);
  if (signed != null) {
    signed.forEach(req.headers.set);
  }
  req.write(
    jsonEncode({
      ...body,
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          // Kept current through the online clients file (clients.dart).
          'clientVersion': musicClientVersion,
          'hl': 'en',
          'visitorData': ?_visitorData,
        },
        // A brand channel the account manages, when used as that.
        if (signed?['X-Goog-PageId'] case final page?)
          'user': {'onBehalfOfUser': page},
      },
    }),
  );
  final res = await req.close();
  final text = await utf8.decodeStream(res);
  Map<String, dynamic>? json;
  try {
    if (jsonDecode(text) case final Map<String, dynamic> map) json = map;
  } on FormatException {
    // An error page: said below.
  }
  if (signed != null) {
    // One by one: a cookie Dart can't parse mustn't lose the others.
    final cookies = <Cookie>[];
    for (final value in res.headers[HttpHeaders.setCookieHeader] ?? []) {
      try {
        cookies.add(Cookie.fromSetCookieValue(value));
      } catch (_) {}
    }
    signIn?.replied(signed, cookies, res.statusCode, json);
  }
  if (res.statusCode != HttpStatus.ok || json == null) {
    throw YouTubeError(endpoint, res.statusCode);
  }
  _visitorData ??= json['responseContext']?['visitorData'];
  if (_dump.isNotEmpty) {
    final what = '${body['browseId'] ?? body['videoId'] ?? body['query'] ?? ''}'
        .replaceAll(RegExp(r'[^\w-]'), '_');
    final name =
        '${(++_dumped).toString().padLeft(3, '0')}_'
        '${endpoint.replaceAll('/', '_')}_$what.json';
    try {
      File('$_dump${Platform.pathSeparator}$name')
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    } catch (_) {}
  }
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

/// The video id in a YouTube or YouTube Music link (youtu.be/…,
/// …/watch?v=…, /shorts/…, /embed/…, /live/…), or null if [text] isn't one.
String? videoIdFromLink(String text) {
  text = text.trim();
  if (text.contains(RegExp(r'\s'))) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www|m)\.'), '');
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final id = switch (host) {
    'youtu.be' => segments.firstOrNull,
    'youtube.com' || 'music.youtube.com' => switch (segments) {
      ['watch'] => uri.queryParameters['v'],
      ['shorts' || 'embed' || 'live' || 'v', final id, ...] => id,
      _ => null,
    },
    _ => null,
  };
  return id != null && RegExp(r'^[\w-]{11}$').hasMatch(id) ? id : null;
}

/// The playlist id in a YouTube or YouTube Music playlist link
/// (…/playlist?list=…, or a song link that also names a playlist), or null.
/// Mixes made for the viewer (`RD…`, `TL…`) aren't playlists anyone can
/// open, so they don't count; YouTube Music's own playlists (`RDCLAK…`) do.
String? playlistIdFromLink(String text) {
  text = text.trim();
  if (text.contains(RegExp(r'\s'))) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www|m)\.'), '');
  if (!{'youtube.com', 'music.youtube.com', 'youtu.be'}.contains(host)) {
    return null;
  }
  final id = uri.queryParameters['list'];
  if (id == null || !RegExp(r'^[\w-]{10,}$').hasMatch(id)) return null;
  if ((id.startsWith('RD') && !id.startsWith('RDCLAK')) ||
      id.startsWith('TL')) {
    return null;
  }
  return id;
}

/// One song by its video id, or null if YouTube doesn't know it.
Future<Track?> track(String videoId) async {
  final json = await _post('next', {'videoId': videoId, 'isAudioOnly': true});
  return [
    for (final item in _findAll(json, 'playlistPanelVideoRenderer'))
      ?_panelTrack(item),
  ].where((t) => t.id == videoId).firstOrNull;
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
  final subscribe = _findAll(json, 'subscribeButtonRenderer').firstOrNull;
  return Artist(
    channelId: subscribe?['channelId'] as String?,
    subscribed: signedInReply(json) == true && subscribe?['subscribed'] is bool
        ? subscribe['subscribed'] as bool
        : null,
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

/// An album (`MPRE…`) or playlist (`VL…`) with all its songs (up to
/// [maxPages] pages of 100).
Future<Collection> collection(String browseId, {int maxPages = 10}) async {
  var json = await browse(browseId);
  final signedIn = signedInReply(json) == true;
  final owned =
      signedIn &&
      _findAll(json, 'musicEditablePlaylistDetailHeaderRenderer').isNotEmpty;
  // The bookmark (save to library) button, and the playlist it saves.
  final bookmark = _findAll(json, 'toggleButtonRenderer')
      .whereType<Map>()
      .where((b) => b['defaultIcon']?['iconType'] == 'BOOKMARK_BORDER')
      .firstOrNull;
  final canonical = _findAll(json, 'urlCanonical').firstOrNull as String?;
  final playlistId =
      _findAll(bookmark?['defaultServiceEndpoint'], 'playlistId').firstOrNull
          as String? ??
      (canonical == null
          ? null
          : Uri.tryParse(canonical)?.queryParameters['list']) ??
      (browseId.startsWith('VL') ? browseId.substring(2) : null);
  final entryIds = <String, List<String>>{};
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
  // The songs are one shelf; the page also has others (an owned playlist's
  // suggestions, an album's other versions), which aren't its songs.
  final shelf =
      _findAll(json, 'musicPlaylistShelfRenderer').firstOrNull ??
      _findAll(json, 'musicShelfRenderer').firstOrNull;
  List items = shelf is Map ? shelf['contents'] as List? ?? const [] : const [];
  Object? holder = shelf;
  // Playlists arrive in pages of 100; up to [maxPages] of them.
  for (var page = 0; page < maxPages; page++) {
    for (final item in items) {
      final row = item is Map ? item['musicResponsiveListItemRenderer'] : null;
      if (row is! Map<String, dynamic>) continue;
      if (_listItem(row, defaults) case final Track t) {
        tracks.add(t);
        if (row['playlistItemData']?['playlistSetVideoId']
            case final String entry) {
          (entryIds[t.id] ??= []).add(entry);
        }
      }
    }
    final next = _shelfContinuation(items, holder);
    if (next == null) break;
    json = await next();
    final more =
        _findAll(json, 'appendContinuationItemsAction').firstOrNull ??
        _findAll(json, 'musicPlaylistShelfContinuation').firstOrNull ??
        _findAll(json, 'musicShelfContinuation').firstOrNull;
    if (more is! Map) break;
    items =
        (more['continuationItems'] ?? more['contents']) as List? ?? const [];
    holder = more;
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
    playlistId: playlistId,
    saved: signedIn && bookmark != null ? bookmark['isToggled'] == true : null,
    owned: owned,
    entryIds: entryIds,
  );
}

/// The next page of a shelf's songs: a "load more" item at the end of
/// [items], or (older pages) a continuation on the shelf itself.
Future<Map<String, dynamic>> Function()? _shelfContinuation(
  List items,
  Object? shelf,
) {
  final last = items.lastOrNull;
  final more = last is Map ? last['continuationItemRenderer'] : null;
  if (_findAll(more, 'token').firstOrNull case final String token) {
    return () => _post('browse', {'continuation': token});
  }
  final legacy = shelf is Map
      ? _findAll(shelf['continuations'], 'continuation').firstOrNull
      : null;
  if (legacy case final String token) {
    return () => _post(
      'browse',
      {},
      query: '&ctoken=$token&continuation=$token&type=next',
    );
  }
  return null;
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
      .where(
        (s) =>
            _parseDuration(s) == null &&
            !s.endsWith(' plays') &&
            !s.endsWith(' views'),
      )
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

/// The signed-in account, as YouTube Music's account menu shows it; null if
/// the request wasn't signed in.
Future<AccountInfo?> accountInfo() async {
  final json = await _post('account/account_menu', {});
  final header = _findAll(json, 'activeAccountHeaderRenderer').firstOrNull;
  if (header is! Map || signedInReply(json) == false) return null;
  final name = _text(header['accountName']);
  if (name.isEmpty) return null;
  return AccountInfo(
    name: name,
    handle: _text(header['channelHandle']),
    photoUrl: _smallest(header['accountPhoto']),
  );
}

/// The channels the account can use YouTube Music as: its own, and any
/// brand channels it manages (each with its page id).
Future<List<AccountChannel>> accountChannels() async {
  final json = await _post('account/accounts_list', {});
  // One section per Google account signed in on the page; the one in use
  // holds the selected item (its own channel, and its brand channels).
  final sections = _findAll(json, 'accountSectionListRenderer').toList();
  final mine =
      sections
          .where((s) => _findAll(s, 'isSelected').contains(true))
          .firstOrNull ??
      sections.firstOrNull;
  return [
    for (final item in _findAll(mine, 'accountItem'))
      if (item is Map && _text(item['accountName']).isNotEmpty)
        AccountChannel(
          name: _text(item['accountName']),
          handle: _text(item['channelHandle']).isNotEmpty
              ? _text(item['channelHandle'])
              : _text(item['accountByline']),
          photoUrl: _smallest(item['accountPhoto']),
          pageId: _findAll(item, 'pageId').whereType<String>().firstOrNull,
          selected: item['isSelected'] == true,
        ),
  ];
}

String _smallest(dynamic node) {
  final thumbs = _findAll(node, 'thumbnails').firstOrNull as List?;
  return (thumbs?.lastOrNull?['url'] as String?) ?? '';
}

enum Rating { like, none, dislike }

/// Likes a song (or removes the like) on the signed-in account.
Future<void> rateSong(String videoId, Rating rating) => _post(
  switch (rating) {
    Rating.like => 'like/like',
    Rating.none => 'like/removelike',
    Rating.dislike => 'like/dislike',
  },
  {
    'target': {'videoId': videoId},
  },
);

/// Where YouTube counts a play of [videoId] (and adds it to the account's
/// history), or null if it doesn't say.
///
/// YouTube Music only answers with it given its player's version (its
/// build day, counted from 1970: the `signatureTimestamp`); any from the
/// last months will do (tried 2026-11: 70 to 0 days old, and newer, all
/// work; a year old doesn't), so a week before today is used.
Future<Uri?> playbackStatsUrl(
  String videoId, {
  int? signatureTimestamp,
  DateTime? now,
}) async {
  signatureTimestamp ??=
      (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay -
      7;
  final json = await _post('player', {
    'videoId': videoId,
    'playbackContext': {
      'contentPlaybackContext': {
        'html5Preference': 'HTML5_PREF_WANTS',
        'signatureTimestamp': signatureTimestamp,
      },
    },
  });
  final url =
      json['playbackTracking']?['videostatsPlaybackUrl']?['baseUrl'] as String?;
  final uri = url == null ? null : Uri.tryParse(url);
  // Only YouTube's own stats address gets the account's cookies.
  if (uri == null ||
      uri.scheme != 'https' ||
      !(uri.host == 'youtube.com' || uri.host.endsWith('.youtube.com'))) {
    return null;
  }
  return uri;
}

/// Counts a play at [stats] (from [playbackStatsUrl]) as the website does.
Future<void> reportPlayback(Uri stats, {Random? random}) async {
  final signed = signIn?.headers();
  if (signed == null) return;
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_';
  final r = random ?? Random.secure();
  final cpn = String.fromCharCodes([
    for (var i = 0; i < 16; i++) chars.codeUnitAt(r.nextInt(64)),
  ]);
  final url = stats.replace(
    queryParameters: {
      ...stats.queryParameters,
      'ver': '2',
      'c': 'WEB_REMIX',
      'cpn': cpn,
    },
  );
  final req = await youtubeHttp.getUrl(
    statsBase == null ? url : statsBase!(url),
  );
  signed.forEach(req.headers.set);
  req.headers.set(
    HttpHeaders.userAgentHeader,
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
  );
  final res = await req.close().timeout(const Duration(seconds: 15));
  await res.drain<void>();
  if (res.statusCode >= 400) {
    throw YouTubeError('play report', res.statusCode);
  }
}

/// Tests send play reports to their fake server instead.
@visibleForTesting
Uri Function(Uri)? statsBase;

/// A playlist in the signed-in account's library (its own, or saved).
class LibraryPlaylist {
  const LibraryPlaylist(this.id, this.title, this.subtitle, this.artUrl);

  /// Without the `VL` of its page's id.
  final String id;
  final String title;
  final String subtitle;
  final String artUrl;
}

/// The account's playlists, its own and saved ones (not Liked Music or
/// Episodes for Later, which aren't playlists people make).
Future<List<LibraryPlaylist>> libraryPlaylists() async {
  final items = await _libraryItems('FEmusic_liked_playlists');
  return [
    for (final r in items)
      if (r['navigationEndpoint']?['browseEndpoint']?['browseId']
          case final String id
          when id.startsWith('VL') &&
              id != 'VLLM' &&
              id != 'VLSE' &&
              _pageType(r['navigationEndpoint']) == 'MUSIC_PAGE_TYPE_PLAYLIST')
        LibraryPlaylist(
          id.substring(2),
          _text(r['title']),
          _text(r['subtitle']),
          _art(r['thumbnailRenderer']),
        ),
  ];
}

/// Albums saved in the account's library.
Future<List<MediaRef>> savedAlbums() async => [
  for (final r in await _libraryItems('FEmusic_liked_albums'))
    if (_card(r) case final MediaRef ref when ref.kind == MediaKind.album) ref,
];

/// Artists the account follows (subscribed to), by channel id.
Future<List<MediaRef>> followedArtists() async {
  var json = await browse('FEmusic_library_corpus_artists');
  final artists = <MediaRef>[];
  for (var page = 0; page < 20; page++) {
    for (final item in _findAll(json, 'musicResponsiveListItemRenderer')) {
      if (_listItem(item) case final MediaRef ref
          when ref.kind == MediaKind.artist) {
        artists.add(ref.withId(channelOf(ref.id)));
      }
    }
    final next = _continuation(json);
    if (next == null) break;
    json = await next();
  }
  return artists;
}

/// Library pages name artists `MPLA` + their channel id.
String channelOf(String id) => id.startsWith('MPLA') ? id.substring(4) : id;

/// The grid items of a library page, all its pages.
Future<List<Map<String, dynamic>>> _libraryItems(String browseId) async {
  var json = await browse(browseId);
  final items = <Map<String, dynamic>>[];
  for (var page = 0; page < 20; page++) {
    items.addAll(
      _findAll(
        json,
        'musicTwoRowItemRenderer',
      ).whereType<Map<String, dynamic>>(),
    );
    final next = _continuation(json);
    if (next == null) break;
    json = await next();
  }
  return items;
}

/// Makes a private playlist on the account; its id.
Future<String> createPlaylist(String title, List<String> videoIds) async {
  final json = await _post('playlist/create', {
    'title': title,
    'description': '',
    'privacyStatus': 'PRIVATE',
    if (videoIds.isNotEmpty) 'videoIds': videoIds,
  });
  final id = json['playlistId'];
  if (id is! String || id.isEmpty) throw YouTubeError('playlist/create', 200);
  return id;
}

Future<void> deletePlaylist(String playlistId) =>
    _post('playlist/delete', {'playlistId': playlistId});

/// Changes a playlist of the account: [actions] as the website sends them
/// (see [addAction], [removeAction], [renameAction], [moveAction]).
Future<void> editPlaylist(
  String playlistId,
  List<Map<String, Object>> actions,
) async {
  if (actions.isEmpty) return;
  final json = await _post('browse/edit_playlist', {
    'playlistId': playlistId,
    'actions': actions,
  });
  if (json['status'] case final String status
      when status != 'STATUS_SUCCEEDED') {
    throw YouTubeError('browse/edit_playlist ($status)', 400);
  }
}

Map<String, Object> addAction(String videoId) => {
  'action': 'ACTION_ADD_VIDEO',
  'addedVideoId': videoId,
  'dedupeOption': 'DEDUPE_OPTION_SKIP',
};

Map<String, Object> removeAction(String videoId, String entryId) => {
  'action': 'ACTION_REMOVE_VIDEO',
  'removedVideoId': videoId,
  'setVideoId': entryId,
};

Map<String, Object> renameAction(String name) => {
  'action': 'ACTION_SET_PLAYLIST_NAME',
  'playlistName': name,
};

/// Moves the entry [entryId] before [beforeEntryId] (to the end if null).
Map<String, Object> moveAction(String entryId, String? beforeEntryId) => {
  'action': 'ACTION_MOVE_VIDEO_BEFORE',
  'setVideoId': entryId,
  'movedSetVideoIdSuccessor': ?beforeEntryId,
};

/// Saves a playlist or album (by its playlist id, `OLAK…` for albums) to
/// the account's library, or removes it.
Future<void> savePlaylist(String playlistId, bool save) =>
    _post(save ? 'like/like' : 'like/removelike', {
      'target': {'playlistId': playlistId},
    });

Future<void> followArtist(String channelId, bool follow) =>
    _post(follow ? 'subscription/subscribe' : 'subscription/unsubscribe', {
      'channelIds': [channelId],
    });
