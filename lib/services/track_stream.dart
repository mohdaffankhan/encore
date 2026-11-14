import 'package:flutter/foundation.dart';

import '../api/innertube.dart' as yt;
import '../api/stream.dart';
import '../models.dart';

/// Song versions found for age-restricted songs, by their ids.
final _versions = <String, Track>{};

/// How a song version is found (tests answer themselves).
@visibleForTesting
var findSongVersion = yt.songVersion;

/// How a stream is opened (tests answer themselves).
@visibleForTesting
var openStream = audioStream;

@visibleForTesting
void forgetSongVersions() => _versions.clear();

/// [track]'s audio: its own stream, or, when YouTube won't play it because
/// it's age-restricted (a music video, usually: Encore streams signed out),
/// its song version's. [first] is a lookup already under way, if any.
/// [onVersion] is told when a song version stands in, the first time.
Future<AudioStream> trackStream(
  Track track, {
  required AudioQuality quality,
  Future<AudioStream>? first,
  void Function(Track version)? onVersion,
}) async {
  Future<AudioStream> own() =>
      openStream(_versions[track.id]?.id ?? track.id, quality: quality);
  try {
    return first == null
        ? await own()
        : await first.catchError((Object _) => own());
  } on AgeRestricted {
    if (_versions.containsKey(track.id)) rethrow;
    final version = await findSongVersion(track);
    if (version == null) rethrow;
    final stream = await openStream(version.id, quality: quality);
    _versions[track.id] = version;
    onVersion?.call(version);
    return stream;
  }
}
