import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/storage.dart';

/// One connection pool and one timeout policy for every YouTube request
/// (the player, YouTube Music, the audio itself). Separate clients each had
/// their own rules, and one with no timeout left songs stuck for good.
final youtubeHttp = HttpClient()
  ..connectionTimeout = const Duration(seconds: 10)
  ..idleTimeout = const Duration(seconds: 30);

/// Which YouTube app Encore says it is when it asks for a song's audio.
/// YouTube changes which apps it serves full songs to, so this can be
/// updated without a release: see [loadClients].
@immutable
class PlayerClient {
  const PlayerClient({
    required this.name,
    required this.id,
    required this.version,
    required this.userAgent,
    this.device = const {},
  });

  /// e.g. VISIONOS, and the number YouTube knows it by (the
  /// X-YouTube-Client-Name header).
  final String name;
  final int id;
  final String version;
  final String userAgent;

  /// deviceMake, deviceModel, osName, osVersion.
  final Map<String, String> device;

  static final _name = RegExp(r'^[A-Z0-9_]{2,40}$');
  static const _deviceKeys = [
    'deviceMake',
    'deviceModel',
    'osName',
    'osVersion',
  ];

  /// Only the fields above, each checked; null if anything is off.
  static PlayerClient? fromJson(Object? json) {
    if (json is! Map) return null;
    String? text(String key, {int max = 300}) => switch (json[key]) {
      final String s when s.isNotEmpty && s.length <= max && !_control(s) => s,
      _ => null,
    };
    final name = text('clientName', max: 40);
    final id = json['clientId'];
    final version = text('clientVersion', max: 40);
    final agent = text('userAgent');
    if (name == null ||
        !_name.hasMatch(name) ||
        id is! int ||
        id < 1 ||
        id > 1000 ||
        version == null ||
        agent == null) {
      return null;
    }
    return PlayerClient(
      name: name,
      id: id,
      version: version,
      userAgent: agent,
      device: {for (final key in _deviceKeys) key: ?text(key, max: 60)},
    );
  }

  static bool _control(String s) => s.codeUnits.any((c) => c < 0x20);

  /// The `context.client` YouTube's player API takes.
  Map<String, Object> context(String? visitorData) => {
    'clientName': name,
    'clientVersion': version,
    ...device,
    'userAgent': userAgent,
    'hl': 'en',
    'visitorData': ?visitorData,
  };

  @override
  bool operator ==(Object other) =>
      other is PlayerClient && other.name == name && other.version == version;

  @override
  int get hashCode => Object.hash(name, version);
}

/// Built in, as yt-dlp uses it: unlike most clients it serves full songs
/// without a proof-of-origin token (others cut off after ~1 MB).
const visionOs = PlayerClient(
  name: 'VISIONOS',
  id: 101,
  version: '1.02',
  userAgent:
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/26.0 Safari/605.1.15',
  device: {
    'deviceMake': 'Apple',
    'deviceModel': 'RealityDevice17,1',
    'osName': 'visionOS',
    'osVersion': '26.5.23O471',
  },
);

/// The YouTube Music web app's version, for home, search and pages.
const builtInMusicVersion = '1.20261015.01.00';

/// From the online file (or its last good copy), if any.
List<PlayerClient> _remote = const [];
String? _remoteMusicVersion;

/// The clients to ask, in order: the online file's, then the built-in one.
List<PlayerClient> get playerClients => [
  ..._remote,
  if (!_remote.contains(visionOs)) visionOs,
];

String get musicClientVersion => _remoteMusicVersion ?? builtInMusicVersion;

/// The file in Encore's (public) repo: edited when YouTube stops serving a
/// client, it reaches every installed app on its next start, no release
/// needed. Only client names, versions and identities are taken from it.
final clientsUrl = Uri.https(
  'raw.githubusercontent.com',
  '/mohdaffankhan/encore/main/config/youtube_clients.json',
);

/// Applies [json] (the file's contents); false if it isn't usable.
@visibleForTesting
bool applyClients(String json) {
  try {
    final data = jsonDecode(json);
    if (data is! Map) return false;
    final players = [
      for (final p in (data['player'] as List? ?? const []).take(4))
        ?PlayerClient.fromJson(p),
    ];
    final music = data['musicClientVersion'];
    final musicOk =
        music is String && RegExp(r'^1\.\d{8}\.\d{2}\.\d{2}$').hasMatch(music);
    if (players.isEmpty && !musicOk) return false;
    _remote = players;
    _remoteMusicVersion = musicOk ? music : null;
    return true;
  } catch (_) {
    return false;
  }
}

@visibleForTesting
void resetClients() {
  _remote = const [];
  _remoteMusicVersion = null;
}

/// Uses the last good copy at once, then fetches the file in the background
/// (startup doesn't wait for the network) for this run and the next.
Future<void> loadClients({Future<String?> Function()? fetch}) async {
  File? cache;
  try {
    cache = File(
      '${(await dataDir()).path}${Platform.pathSeparator}youtube_clients.json',
    );
    if (await cache.exists()) applyClients(await cache.readAsString());
  } catch (e) {
    debugPrint('Saved YouTube clients unreadable: $e');
  }
  unawaited(() async {
    final text = await (fetch ?? _fetch)();
    if (text == null || !applyClients(text)) return;
    try {
      await cache?.writeAsString(text);
    } catch (_) {}
  }());
}

Future<String?> _fetch() async {
  try {
    final req = await youtubeHttp.getUrl(clientsUrl);
    final res = await req.close().timeout(const Duration(seconds: 10));
    final text = await utf8
        .decodeStream(res)
        .timeout(const Duration(seconds: 10));
    return res.statusCode == HttpStatus.ok && text.length < 20000 ? text : null;
  } catch (e) {
    debugPrint('YouTube clients file: $e');
    return null;
  }
}
