import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api/innertube.dart' as yt;
import 'models.dart';
import 'services/player.dart';
import 'services/youtube_audio_source.dart';

/// Where `encore --self-test` writes its report. Desktop release builds have
/// no console, so the release checks read this file.
final selfTestLog = File('${Directory.systemTemp.path}/encore_self_test.log');

/// With `--media-check`: written once a song plays, for the release check
/// to press the keyboard's Next media key (Windows routes it to us through
/// its media controls, whichever app is in front).
final mediaCheckFile = File(
  '${Directory.systemTemp.path}/encore_media_check.ready',
);

/// `encore --self-test` plays a real song in the build people install (no
/// debug build, no test harness) and exits with 0 if it played, 1 if not.
/// Used by tool/*_release_check and the release workflow. Runs with the UI
/// up, on test data (see storage.dart), so the user's library is untouched.
Future<void> runSelfTest({bool mediaKeys = false}) async {
  final report = StringBuffer();
  void log(String line) {
    report.writeln(line);
    debugPrint('[self-test] $line');
  }

  var ok = false;
  try {
    final results = await yt.search(
      'daft punk get lucky',
      yt.SearchFilter.songs,
    );
    final track = results.whereType<Track>().first;
    log('search: ${track.title} - ${track.artist}');

    await player.playRadio(track);
    await _until(
      () => player.audio.playing && player.audio.position.inSeconds >= 3,
    );
    log('plays: ${player.audio.position.inSeconds} s');

    await _until(() => player.upNext.isNotEmpty);
    await player.next();
    await _until(
      () =>
          player.current != track &&
          player.audio.playing &&
          player.audio.position.inSeconds >= 2,
    );
    log('next: ${player.current!.title}');

    // A link that stopped working (expired, or the IP address changed) is
    // renewed: break it as YouTube would, then seek to the middle.
    await _until(() => player.audio.audioSource is YouTubeAudioSource);
    final stream = (player.audio.audioSource! as YouTubeAudioSource).stream;
    stream.url = stream.url.replace(
      queryParameters: {...stream.url.queryParameters, 'expire': '1'},
    );
    final middle = player.audio.duration! ~/ 2;
    await player.seek(middle);
    await _until(
      () =>
          player.audio.playing &&
          player.audio.position >= middle + const Duration(seconds: 2),
    );
    final renewed = stream.url.queryParameters['expire'] != '1';
    log('expired link: plays on (${renewed ? 'renewed' : 'not needed'})');

    if (mediaKeys) {
      final before = player.current;
      final at = player.index.value;
      await mediaCheckFile.writeAsString(before!.title);
      await _until(() => player.current != before && player.audio.playing);
      // Once only: the app's own key handling and Windows' media controls
      // must not both act on one press.
      await Future<void>.delayed(const Duration(seconds: 3));
      final moved = player.index.value - at;
      log('media key: next song (${player.current!.title}), $moved along');
      if (moved != 1) throw StateError('one press moved $moved songs');
    }
    ok = true;
  } catch (e) {
    log('error: $e');
    log(
      'player: ${player.audio.processingState.name}, '
      'error: ${player.error.value}',
    );
  }
  if (await mediaCheckFile.exists()) await mediaCheckFile.delete();
  log(ok ? 'PASSED' : 'FAILED');
  await player.audio.stop();
  await selfTestLog.writeAsString(report.toString());
  exit(ok ? 0 : 1);
}

Future<void> _until(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException(
        'timed out (${player.audio.processingState.name}, '
        'playing: ${player.audio.playing})',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}
