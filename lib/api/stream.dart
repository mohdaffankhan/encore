import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'clients.dart';

// Audio comes from YouTube's player API, asked as one of [playerClients]
// (see clients.dart): few clients still serve full streams without a
// proof-of-origin token. When playback breaks, yt-dlp's youtube/_base.py
// shows the clients that work now; they go in config/youtube_clients.json.

String? _visitorData;

/// Where the player API is; a local server in tests.
@visibleForTesting
Uri playerEndpoint = Uri.parse(
  'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
);

/// YouTube throttles one long request to about real-time speed but serves
/// range requests at full speed, so streams are read in chunks this size.
const _chunkSize = 1 << 20;

/// How often one range request is tried again before reading fails.
const _retries = 3;

/// Doubled, tripled… for each retry of the same request.
@visibleForTesting
Duration retryDelay = const Duration(milliseconds: 400);

/// How long a range request may send nothing before it is dropped and tried
/// again. A connection can go silent without ever closing (e.g. the phone
/// changing networks), which left songs stuck for good.
@visibleForTesting
Duration readTimeout = const Duration(seconds: 10);

/// The e2e test makes renewing fail, so the song itself breaks off.
@visibleForTesting
var failRenewals = false;

class AudioStream {
  AudioStream(
    this.url,
    this.mimeType,
    this.length, {
    this.renew,
    this.userAgent = '',
  });

  /// The asking client's, sent with every range request.
  final String userAgent;

  /// Changes when the link is renewed.
  Uri url;

  /// Gets a new link to the same bytes. YouTube's links stop working after
  /// some hours, or when the device's IP address changes (Wi-Fi to mobile
  /// data), and then every request is refused.
  final Future<Uri> Function()? renew;
  Future<Uri>? _renewing;

  /// Reading gave up (the link or the connection failed for good). The
  /// desktop player takes that for the song's end, so it would move on.
  bool brokeOff = false;

  /// e.g. `audio/webm` (without codec parameters).
  final String mimeType;

  /// Size in bytes.
  final int length;

  /// Bytes from [start] (inclusive) to [end] (exclusive, default: the end),
  /// fetched one range request at a time as the consumer reads.
  ///
  /// A request that fails or breaks off is tried again (from where it
  /// stopped) a few times before giving up: YouTube occasionally refuses
  /// one, and the player has already been told how many bytes are coming.
  Stream<List<int>> read([int start = 0, int? end]) async* {
    end = min(end ?? length, length);
    var pos = start;
    var failures = 0;
    var renewed = false;
    while (pos < end) {
      final last = min(pos + _chunkSize, end) - 1;
      try {
        final req = await youtubeHttp.getUrl(url);
        req.headers
          ..set(HttpHeaders.userAgentHeader, userAgent)
          ..set(HttpHeaders.rangeHeader, 'bytes=$pos-$last');
        final res = await req.close().timeout(readTimeout);
        if (res.statusCode == HttpStatus.forbidden &&
            renew != null &&
            !renewed) {
          await res.drain<void>();
          renewed = true;
          await _renew();
          continue;
        }
        if (res.statusCode != HttpStatus.partialContent) {
          await res.drain<void>();
          throw HttpException('Audio stream: HTTP ${res.statusCode}', uri: url);
        }
        await for (final data in res.timeout(readTimeout)) {
          pos += data.length;
          yield data;
        }
        if (pos <= last) {
          throw HttpException('Audio stream: cut short', uri: url);
        }
        failures = 0;
        renewed = false;
      } on Exception catch (e) {
        if (e is! IOException && e is! TimeoutException) rethrow;
        if (++failures > _retries) {
          brokeOff = true;
          rethrow;
        }
        debugPrint('$e at byte $pos; trying again ($failures)');
        await Future<void>.delayed(retryDelay * failures);
      }
    }
  }

  /// One renewal at a time, shared by the requests waiting for it.
  Future<void> _renew() async {
    debugPrint('Audio stream refused; renewing its link');
    if (failRenewals) throw const HttpException('Renewal failed (test)');
    url = await (_renewing ??= renew!().whenComplete(() => _renewing = null));
  }
}

/// The audio stream of [videoId] at [quality]; with [itag] (and the
/// [client] that gave it), that format, to renew a link to the same bytes.
/// Each of [playerClients] is asked in turn until one can play the song.
Future<AudioStream> audioStream(
  String videoId, {
  int? itag,
  PlayerClient? client,
  AudioQuality quality = AudioQuality.high,
}) async {
  HttpException? refused;
  for (final c in client == null ? playerClients : [client]) {
    try {
      return await _streamFrom(c, videoId, itag, quality);
    } on HttpException catch (e) {
      // This client can't have it (YouTube said no): the next one might.
      // No connection is another matter, so that is thrown at once.
      debugPrint('${c.name}: $e');
      refused ??= e;
    }
  }
  throw refused!;
}

Future<AudioStream> _streamFrom(
  PlayerClient client,
  String videoId,
  int? itag,
  AudioQuality quality,
) async {
  var json = await _player(client, videoId);
  if (json['playabilityStatus']?['status'] == 'LOGIN_REQUIRED') {
    // YouTube asks anonymous clients to identify as a visitor first.
    _visitorData = json['responseContext']?['visitorData'];
    json = await _player(client, videoId);
  }
  final status = json['playabilityStatus'];
  if (status?['status'] != 'OK') {
    throw HttpException(
      status?['reason'] ?? 'Unplayable (${status?['status']})',
    );
  }
  final formats = [
    for (final f in json['streamingData']?['adaptiveFormats'] as List? ?? [])
      if (f['mimeType'] is String &&
          (f['mimeType'] as String).startsWith('audio/') &&
          f['url'] != null &&
          int.tryParse('${f['contentLength']}') != null &&
          (itag == null || f['itag'] == itag))
        f,
  ];
  if (formats.isEmpty) throw const HttpException('No audio stream');
  final best = pickFormat(formats, quality);
  final length = int.parse('${best['contentLength']}');
  final format = best['itag'] as int?;
  return AudioStream(
    Uri.parse(best['url']),
    (best['mimeType'] as String).split(';').first,
    length,
    userAgent: client.userAgent,
    renew: format == null
        ? null
        : () async {
            final again = await audioStream(
              videoId,
              itag: format,
              client: client,
            );
            if (again.length != length) {
              throw const HttpException('Audio stream changed');
            }
            return again.url;
          },
  );
}

/// The format for [quality] among [formats] (each with a `bitrate`): the
/// best for high, the lowest for low, and for normal the best at or under
/// 100 kbps (YouTube's ~70 kbps Opus), else the lowest.
@visibleForTesting
Map pickFormat(List formats, AudioQuality quality) {
  int rate(Map f) => f['averageBitrate'] as int? ?? f['bitrate'] as int? ?? 0;
  final sorted = [for (final f in formats) f as Map]
    ..sort((a, b) => rate(b).compareTo(rate(a)));
  return switch (quality) {
    AudioQuality.high => sorted.first,
    AudioQuality.low => sorted.last,
    AudioQuality.normal =>
      sorted.where((f) => rate(f) <= 100000).firstOrNull ?? sorted.last,
  };
}

/// Fails instead of waiting forever on a stalled connection.
Future<Map<String, dynamic>> _player(PlayerClient client, String videoId) =>
    _playerRequest(client, videoId).timeout(const Duration(seconds: 15));

Future<Map<String, dynamic>> _playerRequest(
  PlayerClient client,
  String videoId,
) async {
  final req = await youtubeHttp.postUrl(playerEndpoint);
  req.headers
    ..contentType = ContentType.json
    ..set(HttpHeaders.userAgentHeader, client.userAgent)
    ..set('X-YouTube-Client-Name', '${client.id}')
    ..set('X-YouTube-Client-Version', client.version);
  if (_visitorData != null) req.headers.set('X-Goog-Visitor-Id', _visitorData!);
  req.write(
    jsonEncode({
      'videoId': videoId,
      'contentCheckOk': true,
      'racyCheckOk': true,
      'context': {'client': client.context(_visitorData)},
    }),
  );
  final res = await req.close();
  return jsonDecode(await utf8.decodeStream(res));
}
