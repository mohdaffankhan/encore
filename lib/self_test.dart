import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api/innertube.dart' as yt;
import 'models.dart';
import 'services/player.dart';

/// Where `encore --self-test` writes its report. Desktop release builds have
/// no console, so the release checks read this file.
final selfTestLog = File('${Directory.systemTemp.path}/encore_self_test.log');

/// `encore --self-test` plays a real song in the build people install (no
/// debug build, no test harness) and exits with 0 if it played, 1 if not.
/// Used by tool/*_release_check and the release workflow. Runs with the UI
/// up, on test data (see storage.dart), so the user's library is untouched.
Future<void> runSelfTest() async {
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
    ok = true;
  } catch (e) {
    log('error: $e');
    log(
      'player: ${player.audio.processingState.name}, '
      'error: ${player.error.value}',
    );
  }
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
