import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models.dart';

// Audio comes from the player API with the VISIONOS client: unlike most
// clients it still serves full streams without a PO token (other clients cut
// off after ~1 MB). This mirrors yt-dlp's defaults; when playback breaks,
// check yt-dlp's youtube/_base.py for the current client details.

const _clientVersion = '1.02';
const userAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';

final _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
String? _visitorData;

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
  AudioStream(this.url, this.mimeType, this.length, {this.renew});

  /// Changes when the link is renewed.
  Uri url;

  /// Gets a new link to the same bytes. YouTube's links stop working after
  /// some hours, or when the device's IP address changes (Wi-Fi to mobile
  /// data), and then every request is refused.
  final Future<Uri> Function()? renew;
  Future<Uri>? _renewing;

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
        final req = await _http.getUrl(url);
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
        if (++failures > _retries) rethrow;
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

/// The audio stream of [videoId] at [quality]; with [itag], that format
/// (to renew a link to the same bytes).
Future<AudioStream> audioStream(
  String videoId, {
  int? itag,
  AudioQuality quality = AudioQuality.high,
}) async {
  var json = await _player(videoId);
  if (json['playabilityStatus']?['status'] == 'LOGIN_REQUIRED') {
    // YouTube asks anonymous clients to identify as a visitor first.
    _visitorData = json['responseContext']?['visitorData'];
    json = await _player(videoId);
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
    renew: format == null
        ? null
        : () async {
            final again = await audioStream(videoId, itag: format);
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
Future<Map<String, dynamic>> _player(String videoId) =>
    _playerRequest(videoId).timeout(const Duration(seconds: 15));

Future<Map<String, dynamic>> _playerRequest(String videoId) async {
  final req = await _http.postUrl(
    Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
  );
  req.headers
    ..contentType = ContentType.json
    ..set(HttpHeaders.userAgentHeader, userAgent)
    ..set('X-YouTube-Client-Name', '101')
    ..set('X-YouTube-Client-Version', _clientVersion);
  if (_visitorData != null) req.headers.set('X-Goog-Visitor-Id', _visitorData!);
  req.write(
    jsonEncode({
      'videoId': videoId,
      'contentCheckOk': true,
      'racyCheckOk': true,
      'context': {
        'client': {
          'clientName': 'VISIONOS',
          'clientVersion': _clientVersion,
          'deviceMake': 'Apple',
          'deviceModel': 'RealityDevice17,1',
          'userAgent': userAgent,
          'osName': 'visionOS',
          'osVersion': '26.5.23O471',
          'hl': 'en',
          'visitorData': ?_visitorData,
        },
      },
    }),
  );
  final res = await req.close();
  return jsonDecode(await utf8.decodeStream(res));
}
