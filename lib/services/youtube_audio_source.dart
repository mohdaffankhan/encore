// StreamAudioSource is marked experimental in just_audio but is stable in
// practice; it is the supported way to feed the player custom bytes.
// ignore_for_file: experimental_member_use

import 'package:just_audio/just_audio.dart';

import '../api/stream.dart';

/// Feeds the player through [AudioStream.read], so audio arrives in fast
/// range requests instead of one throttled download. Seeking requests only
/// the bytes needed from the new position.
class YouTubeAudioSource extends StreamAudioSource {
  YouTubeAudioSource(this.stream, {super.tag});

  final AudioStream stream;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end = end == null || end > stream.length ? stream.length : end;
    return StreamAudioResponse(
      sourceLength: stream.length,
      contentLength: end - start,
      offset: start,
      contentType: stream.mimeType,
      stream: stream.read(start, end),
    );
  }
}
