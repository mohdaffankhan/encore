import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'storage.dart';

final userLibrary = UserLibrary();

/// Everything stored on the device, kept in one small JSON file.
class UserLibrary {
  final history = ValueNotifier<List<Track>>([]);
  final liked = ValueNotifier<List<Track>>([]);
  final searches = ValueNotifier<List<String>>([]);
  final downloads = ValueNotifier<List<Track>>([]);

  File? _file;
  Future<void> _lastWrite = Future.value();

  /// Completes when everything changed so far is saved.
  Future<void> get saved => _lastWrite;

  Future<void> load() async {
    final dir = await dataDir();
    _file = File('${dir.path}${Platform.pathSeparator}library.json');
    final file = _file!;
    try {
      if (!await file.exists()) {
        // First run, or a crash after the old file was replaced: the last
        // finished save is the temporary file.
        final temp = File('${file.path}.tmp');
        if (await temp.exists()) await temp.rename(file.path);
      }
      final json = jsonDecode(await file.readAsString());
      List<Track> tracks(String key) => [
        for (final t in json[key] as List? ?? []) Track.fromJson(t),
      ];
      history.value = tracks('history');
      liked.value = tracks('liked');
      downloads.value = tracks('downloads');
      searches.value = List<String>.from(json['searches'] ?? []);
    } on PathNotFoundException {
      // First run: start empty.
    } catch (e) {
      // Unreadable: keep it aside rather than overwrite it on the next save.
      debugPrint('Library unreadable, starting empty: $e');
      try {
        await file.rename('${file.path}.unreadable');
      } catch (_) {}
    }
    for (final n in [history, liked, searches, downloads]) {
      n.addListener(_save);
    }
  }

  void addPlayed(Track track) => history.value = [
    track,
    ...history.value.where((t) => t != track),
  ].take(200).toList();

  bool isLiked(Track track) => liked.value.contains(track);

  void toggleLike(Track track) => liked.value = isLiked(track)
      ? liked.value.where((t) => t != track).toList()
      : [track, ...liked.value];

  void addSearch(String query) => searches.value = [
    query,
    ...searches.value.where((q) => q != query),
  ].take(10).toList();

  void removeSearch(String query) =>
      searches.value = searches.value.where((q) => q != query).toList();

  void _save() {
    final file = _file;
    if (file == null) return;
    final json = jsonEncode({
      'history': history.value,
      'liked': liked.value,
      'searches': searches.value,
      'downloads': downloads.value,
    });
    // Chain writes so an older snapshot can never land after a newer one.
    // Write a temporary file, then swap it in: if the app is killed
    // mid-save, the previous library file is still whole.
    _lastWrite = _lastWrite.then((_) async {
      try {
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(json, flush: true);
        await temp.rename(file.path);
      } catch (e) {
        debugPrint('Saving library failed: $e');
      }
    });
  }
}
