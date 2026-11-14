import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api/innertube.dart' as yt;
import '../models.dart';
import 'account.dart';
import 'library.dart';
import 'storage.dart';

final youtubeSync = YouTubeSync();

/// A change to send to the signed-in account.
@immutable
class SyncOp {
  const SyncOp(this.kind, this.id, {this.attempts = 0});

  /// `like` or `unlike` (a song, [id] its video id).
  final String kind;
  final String id;
  final int attempts;

  SyncOp retried() => SyncOp(kind, id, attempts: attempts + 1);

  Map<String, Object> toJson() => {
    'kind': kind,
    'id': id,
    'attempts': attempts,
  };

  static SyncOp? fromJson(Object? json) => switch (json) {
    {'kind': final String kind, 'id': final String id}
        when const {'like', 'unlike'}.contains(kind) && id.isNotEmpty =>
      SyncOp(
        kind,
        id,
        attempts: json['attempts'] is int ? json['attempts'] as int : 0,
      ),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is SyncOp && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => '$kind $id';
}

/// Keeps the signed-in YouTube Music account up to date with what happens
/// in Encore, so its recommendations learn from it: songs liked or unliked
/// here are liked there, and songs played are counted there (they show in
/// its history). Changes wait in an outbox (kept on disk) while offline,
/// and go one at a time, spaced out, never in a burst.
class YouTubeSync {
  YouTubeSync({
    this._account,
    this._library,
    this._dir,
    this.spacing = const Duration(seconds: 1),
    this.retryAfter = const Duration(seconds: 30),
  });

  final Account? _account;
  final UserLibrary? _library;
  final Directory? _dir;
  Account get _acc => _account ?? account;
  UserLibrary get _lib => _library ?? userLibrary;

  /// Between two requests that change the account.
  final Duration spacing;

  /// The first wait after a failure; doubled each time, up to 16 times.
  final Duration retryAfter;

  /// Waiting to be sent, oldest first.
  final pending = ValueNotifier<List<SyncOp>>(const []);

  /// Songs liked as last seen (to tell what changed).
  var _liked = <String>{};

  /// While true, library changes come from the account and aren't sent
  /// back (see [applyingRemote]).
  var _remote = false;

  var _started = false;
  int _generation = 0;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _load();
    _liked = {for (final t in _lib.liked.value) t.id};
    _generation = _acc.generation.value;
    _lib.liked.addListener(_likedChanged);
    _acc.generation.addListener(_accountChanged);
    _acc.status.addListener(_kick);
    _kick();
  }

  @visibleForTesting
  void stop() {
    if (!_started) return;
    _started = false;
    _lib.liked.removeListener(_likedChanged);
    _acc.generation.removeListener(_accountChanged);
    _acc.status.removeListener(_kick);
    _retry?.cancel();
  }

  /// Runs [change] to the library without sending it to the account (it
  /// came from there).
  T applyingRemote<T>(T Function() change) {
    _remote = true;
    try {
      return change();
    } finally {
      _remote = false;
      _liked = {for (final t in _lib.liked.value) t.id};
    }
  }

  void _likedChanged() {
    final now = {for (final t in _lib.liked.value) t.id};
    final added = now.difference(_liked);
    final removed = _liked.difference(now);
    _liked = now;
    if (_remote || !_acc.signedIn) return;
    for (final id in added) {
      _add(SyncOp('like', id));
    }
    for (final id in removed) {
      _add(SyncOp('unlike', id));
    }
  }

  /// Queues [op]; it replaces anything pending for the same song (only the
  /// last word counts).
  void _add(SyncOp op) {
    pending.value = [
      for (final p in pending.value)
        if (p.id != op.id) p,
      op,
    ];
    _save();
    _kick();
  }

  /// Signed out, or someone else signed in: what was waiting was for the
  /// account before.
  void _accountChanged() {
    final changed = _acc.generation.value != _generation;
    _generation = _acc.generation.value;
    if (!changed) return;
    _retry?.cancel();
    _failures = 0;
    if (pending.value.isNotEmpty) {
      pending.value = const [];
      _save();
    }
  }

  Timer? _retry;
  var _failures = 0;
  Future<void>? _running;

  /// Completes when the outbox is as empty as it can get for now.
  @visibleForTesting
  Future<void> get idle async {
    while (_running != null) {
      await _running;
    }
  }

  void _kick() {
    if (_running != null || !_acc.signedIn || pending.value.isEmpty) return;
    if (_retry?.isActive ?? false) return;
    _running = _send().whenComplete(() => _running = null);
  }

  Future<void> _send() async {
    final gen = _acc.generation.value;
    var first = true;
    while (pending.value.isNotEmpty) {
      if (!_acc.signedIn || _acc.generation.value != gen) return;
      if (!first) await Future<void>.delayed(spacing);
      first = false;
      if (!_acc.signedIn || _acc.generation.value != gen) return;
      if (pending.value.isEmpty) return;
      final op = pending.value.first;
      try {
        await _perform(op);
      } on yt.YouTubeError catch (e) {
        if (e.rejected) {
          debugPrint('YouTube refused $op: $e');
          _remove(op);
          continue;
        }
        _failed(op, e);
        return;
      } catch (e) {
        _failed(op, e);
        return;
      }
      _failures = 0;
      _remove(op);
    }
  }

  Future<void> _perform(SyncOp op) => switch (op.kind) {
    'like' => yt.rateSong(op.id, yt.Rating.like),
    _ => yt.rateSong(op.id, yt.Rating.none),
  };

  /// Takes [op] off the list, unless it was replaced meanwhile (a newer
  /// word for the same song, which still has to go).
  void _remove(SyncOp op) {
    final list = pending.value;
    final i = list.indexWhere((p) => identical(p, op));
    if (i < 0) return;
    pending.value = [...list]..removeAt(i);
    _save();
  }

  void _failed(SyncOp op, Object e) {
    debugPrint('Sending $op failed, trying later: $e');
    final wait = retryAfter * pow(2, min(_failures, 5)).toInt();
    _failures++;
    _retry = Timer(wait, () {
      _retry = null;
      _kick();
    });
  }

  /// Sends what's waiting now (on a new connection, or a pull to refresh).
  void retryNow() {
    _retry?.cancel();
    _retry = null;
    _kick();
  }

  // Saving.

  File? _file;
  Future<void>? _lastWrite;

  @visibleForTesting
  Future<void> get saved => _lastWrite ?? Future.value();

  Future<File> _path() async => _file ??= File(
    '${(_dir ?? await dataDir()).path}${Platform.pathSeparator}'
    'youtube_sync.json',
  );

  Future<void> _load() async {
    try {
      final json = jsonDecode(await (await _path()).readAsString());
      pending.value = [
        for (final op in json['pending'] as List? ?? const [])
          ?SyncOp.fromJson(op),
      ];
    } on PathNotFoundException {
      // Nothing waiting.
    } catch (e) {
      debugPrint('Sync outbox unreadable, starting empty: $e');
    }
  }

  void _save() {
    final json = jsonEncode({'pending': pending.value});
    _lastWrite = (_lastWrite ?? Future.value()).then((_) async {
      try {
        final file = await _path();
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(json, flush: true);
        await temp.rename(file.path);
      } catch (e) {
        debugPrint('Saving the sync outbox failed: $e');
      }
    });
  }
}

/// Counts songs played in Encore as plays on the signed-in account (they
/// show in its history and shape its recommendations): once a song has
/// been heard for 30 seconds (or half of it, if shorter), as YouTube counts
/// a play; skipped songs aren't counted.
class PlayReporter {
  PlayReporter({
    required this.nowPlaying,
    required Stream<Duration> positions,
    this._account,
    this.report = _report,
    this.retryAfter = const Duration(minutes: 1),
  }) {
    nowPlaying.addListener(_changed);
    _positions = positions.listen(_position);
    _changed();
  }

  final ValueListenable<Track?> nowPlaying;
  final Account? _account;
  Account get _acc => _account ?? account;
  final Future<void> Function(Track) report;
  final Duration retryAfter;
  late final StreamSubscription<Duration> _positions;

  Track? _track;
  var _reported = false;
  Duration _last = Duration.zero;

  /// Reports sent (tests).
  @visibleForTesting
  final sent = <String>[];

  static Future<void> _report(Track track) async {
    final stats = await yt.playbackStatsUrl(track.id);
    if (stats != null) await yt.reportPlayback(stats);
  }

  static Duration needed(Track track) {
    const most = Duration(seconds: 30);
    final half = (track.duration ?? most * 2) ~/ 2;
    final at = half < most ? half : most;
    // Very short or unknown-length songs still need a moment.
    return at < const Duration(seconds: 5) ? const Duration(seconds: 5) : at;
  }

  void _changed() {
    if (nowPlaying.value == _track) return;
    _track = nowPlaying.value;
    _reported = false;
    _last = Duration.zero;
  }

  void _position(Duration at) {
    final track = _track;
    if (track == null) return;
    // Back at the start of the same song (repeat one): a new play.
    if (_reported && at < const Duration(seconds: 2) && _last > at) {
      _reported = false;
    }
    _last = at;
    if (_reported || at < needed(track) || !_acc.signedIn) return;
    _reported = true;
    unawaited(_send(track, 0));
  }

  Future<void> _send(Track track, int attempt) async {
    final gen = _acc.generation.value;
    try {
      await report(track);
      sent.add(track.id);
    } catch (e) {
      debugPrint('Counting the play of ${track.id} failed: $e');
      if (attempt >= 2 || (e is yt.YouTubeError && e.rejected)) return;
      await Future<void>.delayed(retryAfter * (attempt + 1));
      if (_acc.signedIn && _acc.generation.value == gen) {
        await _send(track, attempt + 1);
      }
    }
  }

  void dispose() {
    nowPlaying.removeListener(_changed);
    unawaited(_positions.cancel());
  }
}
