import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'player.dart';
import 'storage.dart';

final playbackSession = PlaybackSession(player);

/// What is playing (the queue, the song and how far in, shuffle and
/// repeat), kept in a file of its own, so the app opens where it was left
/// instead of with nothing playing.
class PlaybackSession {
  PlaybackSession(this.player);

  final Player player;

  File? _file;

  /// The queue's JSON as last saved: saving the position (every few
  /// seconds while playing) doesn't encode a long queue again.
  String? _queue;

  Timer? _ticker;
  Future<void> _lastWrite = Future.value();

  /// Completes when everything changed so far is saved.
  Future<void> get saved => _lastWrite;

  /// Puts back what was playing, then keeps the file up to date.
  Future<void> restore() async {
    final dir = await dataDir();
    final file = _file = File(
      '${dir.path}${Platform.pathSeparator}session.json',
    );
    try {
      final json = jsonDecode(await file.readAsString());
      player.restore(
        [for (final t in json['queue'] as List) Track.fromJson(t)],
        json['index'] as int,
        Duration(milliseconds: json['position'] as int? ?? 0),
        shuffled: json['shuffle'] == true,
        repeat: Repeat.values.asNameMap()[json['repeat']] ?? Repeat.off,
      );
    } on PathNotFoundException {
      // Nothing played yet.
    } catch (e) {
      // Not worth more than a fresh start.
      debugPrint('Playback session unreadable: $e');
    }
    player.queue.addListener(() {
      _queue = null;
      save();
    });
    player.index.addListener(save);
    player.shuffle.addListener(save);
    player.repeat.addListener(save);
    player.audio.playingStream.listen((playing) {
      _ticker?.cancel();
      save();
      if (playing) {
        // The app can be killed at any time (swiped away, or by Android).
        _ticker = Timer.periodic(const Duration(seconds: 10), (_) => save());
      }
    });
  }

  void save() {
    final file = _file;
    if (file == null) return;
    final json =
        '{"queue":${_queue ??= jsonEncode(player.queue.value)},'
        '"index":${player.index.value},'
        '"position":${player.position.inMilliseconds},'
        '"shuffle":${player.shuffle.value},'
        '"repeat":"${player.repeat.value.name}"}';
    // As for the library: in order, and swapped in whole.
    _lastWrite = _lastWrite.then((_) async {
      try {
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(json, flush: true);
        await temp.rename(file.path);
      } catch (e) {
        debugPrint('Saving the playback session failed: $e');
      }
    });
  }
}
