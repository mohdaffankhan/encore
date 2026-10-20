import 'dart:convert';
import 'dart:io';
import 'dart:math';

// Audio comes from the player API with the VISIONOS client: unlike most
// clients it still serves full streams without a PO token (other clients cut
// off after ~1 MB). This mirrors yt-dlp's defaults; when playback breaks,
// check yt-dlp's youtube/_base.py for the current client details.

const _clientVersion = '1.02';
const userAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';

final _http = HttpClient();
String? _visitorData;

/// YouTube throttles one long request to about real-time speed but serves
/// range requests at full speed, so streams are read in chunks this size.
const _chunkSize = 1 << 20;

class AudioStream {
  const AudioStream(this.url, this.mimeType, this.length);

  final Uri url;

  /// e.g. `audio/webm` (without codec parameters).
  final String mimeType;

  /// Size in bytes.
  final int length;

  /// Bytes from [start] (inclusive) to [end] (exclusive, default: the end),
  /// fetched one range request at a time as the consumer reads.
  Stream<List<int>> read([int start = 0, int? end]) async* {
    end = min(end ?? length, length);
    for (var pos = start; pos < end; pos += _chunkSize) {
      final last = min(pos + _chunkSize, end) - 1;
      final req = await _http.getUrl(url);
      req.headers
        ..set(HttpHeaders.userAgentHeader, userAgent)
        ..set(HttpHeaders.rangeHeader, 'bytes=$pos-$last');
      final res = await req.close();
      if (res.statusCode != HttpStatus.partialContent) {
        await res.drain<void>();
        throw HttpException('Audio stream: HTTP ${res.statusCode}', uri: url);
      }
      yield* res;
    }
  }
}

Future<AudioStream> audioStream(String videoId) async {
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
      if ((f['mimeType'] as String).startsWith('audio/') && f['url'] != null) f,
  ]..sort((a, b) => (b['bitrate'] as int).compareTo(a['bitrate'] as int));
  if (formats.isEmpty) throw const HttpException('No audio stream');
  final best = formats.first;
  return AudioStream(
    Uri.parse(best['url']),
    (best['mimeType'] as String).split(';').first,
    int.parse(best['contentLength']),
  );
}

Future<Map<String, dynamic>> _player(String videoId) async {
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
