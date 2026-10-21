import 'dart:io';

import 'package:flutter/foundation.dart';

import '../api/stream.dart';
import '../models.dart';
import 'library.dart';
import 'storage.dart';

final downloads = Downloads();

/// Saves songs for offline playback, one at a time. Finished downloads are
/// listed in [UserLibrary.downloads]; files live in the app support folder.
class Downloads {
  /// Songs waiting or downloading, with progress from 0 to 1.
  final progress = ValueNotifier<Map<String, double>>({});

  /// A message when a download failed, shown once by the app frame.
  final error = ValueNotifier<String?>(null);

  final _queue = <Track>[];
  bool _running = false;
  Directory? _dir;

  Future<Directory> _folder() async => _dir ??= await Directory(
    '${(await dataDir()).path}${Platform.pathSeparator}downloads',
  ).create(recursive: true);

  /// The downloaded file for [track], if it is complete.
  Future<File?> fileFor(Track track) async {
    if (!userLibrary.downloads.value.contains(track)) return null;
    final file = File(
      '${(await _folder()).path}${Platform.pathSeparator}${track.id}',
    );
    return await file.exists() ? file : null;
  }

  bool isDownloaded(Track track) => userLibrary.downloads.value.contains(track);

  void download(Iterable<Track> tracks) {
    for (final t in tracks) {
      if (isDownloaded(t) || progress.value.containsKey(t.id)) continue;
      _queue.add(t);
      _setProgress(t.id, 0);
    }
    _run();
  }

  Future<void> remove(Track track) async {
    userLibrary.downloads.value = userLibrary.downloads.value
        .where((t) => t != track)
        .toList();
    final file = File(
      '${(await _folder()).path}${Platform.pathSeparator}${track.id}',
    );
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (e) {
      // Still open (e.g. playing on Windows): it is no longer listed, and
      // a later download of the song simply replaces it.
      debugPrint('Could not delete ${file.path}: $e');
    }
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    while (_queue.isNotEmpty) {
      final track = _queue.removeAt(0);
      try {
        await _fetch(track);
        userLibrary.downloads.value = [track, ...userLibrary.downloads.value];
      } catch (e) {
        debugPrint('Download failed for ${track.id}: $e');
        error.value = 'Couldn\'t download "${track.title}"';
      }
      progress.value = {...progress.value}..remove(track.id);
    }
    _running = false;
  }

  Future<void> _fetch(Track track) async {
    final stream = await audioStream(track.id);
    final dir = await _folder();
    final part = File('${dir.path}${Platform.pathSeparator}${track.id}.part');
    final sink = part.openWrite();
    var received = 0;
    var reported = 0.0;
    try {
      await for (final chunk in stream.read()) {
        sink.add(chunk);
        received += chunk.length;
        final p = received / stream.length;
        // Only notify every 5% to keep rebuilds cheap.
        if (p - reported >= 0.05) _setProgress(track.id, reported = p);
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      // Don't leave half a song behind.
      if (await part.exists()) await part.delete();
      rethrow;
    }
    await part.rename('${dir.path}${Platform.pathSeparator}${track.id}');
  }

  void _setProgress(String id, double p) =>
      progress.value = {...progress.value, id: p};
}
