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

  /// Newest first.
  final playlists = ValueNotifier<List<Playlist>>([]);

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
      playlists.value = [
        for (final p in json['playlists'] as List? ?? []) Playlist.fromJson(p),
      ];
    } on PathNotFoundException {
      // First run: start empty.
    } catch (e) {
      // Unreadable: keep it aside rather than overwrite it on the next save.
      debugPrint('Library unreadable, starting empty: $e');
      try {
        await file.rename('${file.path}.unreadable');
      } catch (_) {}
    }
    for (final MapEntry(key: name, value: part) in _parts.entries) {
      part.addListener(() {
        _encoded.remove(name);
        _save();
      });
    }
  }

  /// What is saved, by name in the file.
  late final _parts = <String, ValueListenable<Object>>{
    'history': history,
    'liked': liked,
    'searches': searches,
    'downloads': downloads,
    'playlists': playlists,
  };

  /// Each part's JSON as last saved, so a change encodes only its own part.
  /// Encoding everything (big imported playlists too) for every song played
  /// took about 20 ms on the UI thread: a dropped frame as songs changed.
  final _encoded = <String, String>{};

  /// The parts the last save encoded.
  @visibleForTesting
  final encodedParts = <String>[];

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

  Playlist? playlist(String id) =>
      playlists.value.where((p) => p.id == id).firstOrNull;

  /// A new playlist (each song once), shown first.
  Playlist createPlaylist(
    String name, {
    List<Track> tracks = const [],
    String? source,
  }) {
    final playlist = Playlist(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'My playlist' : name.trim(),
      tracks: tracks.toSet().toList(),
      source: source,
    );
    playlists.value = [playlist, ...playlists.value];
    return playlist;
  }

  void renamePlaylist(String id, String name) {
    if (name.trim().isEmpty) return;
    _updatePlaylist(id, (p) => p.copyWith(name: name.trim()));
  }

  void deletePlaylist(String id) =>
      playlists.value = playlists.value.where((p) => p.id != id).toList();

  /// Adds the songs not already in it, at the end; returns how many.
  int addToPlaylist(String id, List<Track> tracks) {
    var added = 0;
    _updatePlaylist(id, (p) {
      final fresh = tracks.toSet().difference(p.tracks.toSet()).toList();
      added = fresh.length;
      return p.copyWith(tracks: [...p.tracks, ...fresh]);
    });
    return added;
  }

  void removeFromPlaylist(String id, Track track) => _updatePlaylist(
    id,
    (p) => p.copyWith(tracks: p.tracks.where((t) => t != track).toList()),
  );

  /// Moves the song at [from] to [to] (indexes in the list without it).
  void moveInPlaylist(String id, int from, int to) => _updatePlaylist(id, (p) {
    final tracks = List.of(p.tracks);
    tracks.insert(to, tracks.removeAt(from));
    return p.copyWith(tracks: tracks);
  });

  void _updatePlaylist(String id, Playlist Function(Playlist) change) =>
      playlists.value = [
        for (final p in playlists.value) p.id == id ? change(p) : p,
      ];

  String _encode(String name, Object value) {
    encodedParts.add(name);
    return jsonEncode(value);
  }

  void _save() {
    final file = _file;
    if (file == null) return;
    encodedParts.clear();
    final parts = [
      for (final MapEntry(key: name, value: part) in _parts.entries)
        '${jsonEncode(name)}:${_encoded[name] ??= _encode(name, part.value)}',
    ];
    final json = '{${parts.join(',')}}';
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
