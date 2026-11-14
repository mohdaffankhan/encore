import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'library.dart';
import 'settings.dart';
import 'storage.dart';
import 'track_stream.dart';

final downloads = Downloads();

/// Saves songs for offline playback, a few at a time. Finished downloads are
/// listed in [UserLibrary.downloads]; files live in the app support folder.
class Downloads {
  /// Songs waiting or downloading, with progress from 0 to 1.
  final progress = ValueNotifier<Map<String, double>>({});

  /// A message when a download failed, shown once by the app frame.
  final error = ValueNotifier<String?>(null);

  final _queue = <Track>[];
  bool _running = false;
  Directory? _dir;

  /// How many download at once (one at a time was slow for an album; more
  /// would only share the same connection).
  static const parallel = 3;

  /// The songs downloading now, in the order they started.
  final _active = <Track>[];

  /// The song downloading now (the first started, of those downloading).
  Track? get current => _active.firstOrNull;

  /// Songs that couldn't be saved since the downloads last ran out: said
  /// once when they do (one message per song flooded the screen).
  final _failed = <Track>[];

  /// Songs saved and failed since the downloads last ran out (shown in
  /// Android's notification: "2 of 5", "Downloaded 5 songs").
  int done = 0;
  int notDone = 0;

  /// Downloads a song's file; replaced in tests.
  @visibleForTesting
  late Future<void> Function(Track track) fetch = _fetch;

  Future<void> _lastWrite = Future.value();

  /// Completes when the list of songs left to download is saved.
  @visibleForTesting
  Future<void> get saved => _lastWrite;

  /// Beside the library: the downloads folder holds only songs.
  Future<File> _pendingFile() async => File(
    '${(await dataDir()).path}${Platform.pathSeparator}pending_downloads.json',
  );

  /// Carries on with the downloads not done when the app last closed.
  Future<void> resume() async {
    try {
      final json = jsonDecode(await (await _pendingFile()).readAsString());
      download([for (final t in json as List) Track.fromJson(t)]);
    } on PathNotFoundException {
      // None left.
    } catch (e) {
      debugPrint('Pending downloads unreadable: $e');
    }
  }

  /// Keeps the songs left to download, so closing the app doesn't lose
  /// them (an album's worth, with nothing said).
  void _savePending() {
    final json = jsonEncode([..._active, ..._queue]);
    _lastWrite = _lastWrite.then((_) async {
      try {
        final file = await _pendingFile();
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(json, flush: true);
        await temp.rename(file.path);
      } catch (e) {
        debugPrint('Saving pending downloads failed: $e');
      }
    });
  }

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

  /// How much space the downloaded songs take, in bytes.
  Future<int> size() async {
    var total = 0;
    try {
      await for (final f in (await _folder()).list()) {
        if (f is File) total += await f.length();
      }
    } catch (e) {
      debugPrint('Measuring downloads failed: $e');
    }
    return total;
  }

  /// Removes every download (Settings: free up space).
  Future<void> removeAll() async {
    for (final track in [...userLibrary.downloads.value]) {
      await remove(track);
    }
  }

  void download(Iterable<Track> tracks) {
    if (!_running) done = notDone = 0;
    for (final t in tracks) {
      if (isDownloaded(t) || progress.value.containsKey(t.id)) continue;
      _queue.add(t);
      _setProgress(t.id, 0);
    }
    _savePending();
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
    _failed.clear();
    await Future.wait([for (var i = 0; i < parallel; i++) _worker()]);
    _running = false;
    if (_failed.isNotEmpty) {
      error.value = _failed.length == 1
          ? "Couldn't download \"${_failed.single.title}\""
          : "Couldn't download ${_failed.length} songs";
      _failed.clear();
    }
  }

  Future<void> _fetch(Track track) async {
    // Age-restricted: its song version's audio (see trackStream).
    final stream = await trackStream(
      track,
      quality: settings.downloadQuality.value,
    );
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

  Future<void> _worker() async {
    while (_queue.isNotEmpty) {
      final track = _queue.removeAt(0);
      _active.add(track);
      _setProgress(track.id, 0); // says which song is downloading
      try {
        await fetch(track);
        userLibrary.downloads.value = [track, ...userLibrary.downloads.value];
        done++;
      } catch (e) {
        notDone++;
        _failed.add(track);
        debugPrint('Download failed for ${track.id}: $e');
      }
      _active.remove(track);
      progress.value = {...progress.value}..remove(track.id);
      _savePending();
    }
  }

  void _setProgress(String id, double p) =>
      progress.value = {...progress.value, id: p};
}
