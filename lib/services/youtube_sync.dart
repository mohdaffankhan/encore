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
  const SyncOp(
    this.kind,
    this.id, {
    this.ids = const [],
    this.name,
    this.attempts = 0,
  });

  /// What it does, and what [id] is:
  /// - `like`, `unlike`: a song (video id);
  /// - `save`, `unsave`: an album or playlist (its page's browse id);
  /// - `follow`, `unfollow`: an artist (page or channel id);
  /// - `create`: an Encore playlist (its local id) to make on the account;
  /// - `add`, `remove`, `reorder`: songs [ids] of the account's playlist
  ///   [id] (`reorder`: all of them, in their new order);
  /// - `rename` ([name]), `delete`: the account's playlist [id].
  final String kind;
  final String id;
  final List<String> ids;
  final String? name;
  final int attempts;

  static const kinds = {
    'like',
    'unlike',
    'save',
    'unsave',
    'follow',
    'unfollow',
    'create',
    'add',
    'remove',
    'reorder',
    'rename',
    'delete',
  };

  /// Ops with the same key replace each other: only the last word counts.
  String? get key => switch (kind) {
    'like' || 'unlike' => 'song:$id',
    'save' || 'unsave' => 'saved:$id',
    'follow' || 'unfollow' => 'artist:$id',
    'create' => 'create:$id',
    'rename' => 'rename:$id',
    'reorder' => 'reorder:$id',
    _ => null,
  };

  Map<String, Object> toJson() => {
    'kind': kind,
    'id': id,
    if (ids.isNotEmpty) 'ids': ids,
    'name': ?name,
    'attempts': attempts,
  };

  static SyncOp? fromJson(Object? json) => switch (json) {
    {'kind': final String kind, 'id': final String id}
        when kinds.contains(kind) && id.isNotEmpty =>
      SyncOp(
        kind,
        id,
        ids: [
          for (final i in json['ids'] is List ? json['ids'] as List : const [])
            if (i is String && i.isNotEmpty) i,
        ],
        name: json['name'] is String ? json['name'] as String : null,
        attempts: json['attempts'] is int ? json['attempts'] as int : 0,
      ),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is SyncOp &&
      other.kind == kind &&
      other.id == id &&
      listEquals(other.ids, ids) &&
      other.name == name;

  @override
  int get hashCode => Object.hash(kind, id, Object.hashAll(ids), name);

  @override
  String toString() =>
      [kind, id, if (ids.isNotEmpty) ids.join(','), ?name].join(' ');
}

/// A playlist as last agreed between Encore and the account.
@immutable
class PlaylistBase {
  const PlaylistBase(this.name, this.ids);

  final String name;
  final List<String> ids;

  Map<String, Object> toJson() => {'name': name, 'ids': ids};

  static PlaylistBase? fromJson(Object? json) => switch (json) {
    {'name': final String name, 'ids': final List ids} => PlaylistBase(
      name,
      ids.whereType<String>().toList(),
    ),
    _ => null,
  };
}

/// What the account had, as fetched for a sync.
class _Remote {
  _Remote({
    required this.liked,
    required this.playlists,
    required this.saved,
    required this.artists,
  });

  final List<Track> liked;

  /// The account's own playlists, by id.
  final Map<String, Collection> playlists;
  final List<MediaRef> saved;
  final List<MediaRef> artists;
}

enum SyncState { idle, syncing, failed }

/// What the first sync after signing in will do, for the user to agree to
/// first: what goes to the account, what comes into Encore, and about how
/// long sending takes.
@immutable
class SyncPlan {
  const SyncPlan({
    this.likes = 0,
    this.playlists = 0,
    this.playlistSongs = 0,
    this.saved = 0,
    this.artists = 0,
    this.requests = 0,
    this.newLikes = 0,
    this.newPlaylists = 0,
    this.newSaved = 0,
    this.newArtists = 0,
  });

  // To the account.
  final int likes;
  final int playlists;

  /// Songs added to the account's playlists (new ones and existing ones).
  final int playlistSongs;
  final int saved;
  final int artists;

  /// Requests sending it takes.
  final int requests;

  // Into Encore.
  final int newLikes;
  final int newPlaylists;
  final int newSaved;
  final int newArtists;

  bool get sends => requests > 0;

  /// About how long sending takes ([spacing] apart, plus the reply).
  Duration estimate(Duration spacing) =>
      (spacing + const Duration(milliseconds: 400)) * requests;
}

/// Three-way merge of a set: what is in [local] and [remote] now, against
/// [base], what they last agreed on (null: never; then nothing is taken
/// away, both are combined). Something added on either side is kept;
/// something removed on either side goes.
@visibleForTesting
Set<String> mergeSets(
  Set<String> local,
  Set<String> remote,
  Set<String>? base,
) {
  if (base == null) return {...local, ...remote};
  return {
    for (final id in {...local, ...remote})
      if (base.contains(id) ? local.contains(id) && remote.contains(id) : true)
        id,
  };
}

/// The merged order of [keep]: the account's order, unless only Encore's
/// changed since [base] (then Encore's); new songs added in Encore go at
/// the end (where Encore adds them), new on the account where they are.
@visibleForTesting
List<String> mergeOrder(
  List<String> local,
  List<String> remote,
  List<String>? base,
  Set<String> keep,
) {
  List<String> common(List<String> l, Set<String> other) => [
    for (final id in l)
      if (other.contains(id)) id,
  ];
  final shared = local.toSet().intersection(remote.toSet());
  var order = common(remote, keep);
  if (base != null) {
    final baseSet = base.toSet();
    final inAll = shared.intersection(baseSet);
    final localMoved = !listEquals(common(local, inAll), common(base, inAll));
    final remoteMoved = !listEquals(common(remote, inAll), common(base, inAll));
    if (localMoved && !remoteMoved) {
      final localOrder = common(local, keep);
      final rest = [
        for (final id in order)
          if (!local.contains(id)) id,
      ];
      order = [...localOrder, ...rest];
    }
  }
  final seen = order.toSet();
  return [
    ...order,
    for (final id in local)
      if (keep.contains(id) && !seen.contains(id)) id,
  ];
}

/// The fewest moves that turn [from] into [to] (both the same songs): the
/// songs not in their longest run already in order, each moved before the
/// song that should follow it (null: to the end), done in this order.
@visibleForTesting
List<(String, String?)> movesFor(List<String> from, List<String> to) {
  final position = {for (var i = 0; i < from.length; i++) from[i]: i};
  final seq = [for (final id in to) position[id] ?? -1];
  // Longest increasing run of positions: those stay.
  final tails = <int>[];
  final tailAt = <int>[];
  final prev = List.filled(seq.length, -1);
  for (var i = 0; i < seq.length; i++) {
    var lo = 0, hi = tails.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (tails[mid] < seq[i]) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0) prev[i] = tailAt[lo - 1];
    if (lo == tails.length) {
      tails.add(seq[i]);
      tailAt.add(i);
    } else {
      tails[lo] = seq[i];
      tailAt[lo] = i;
    }
  }
  final stays = <int>{};
  for (var i = tailAt.isEmpty ? -1 : tailAt.last; i >= 0; i = prev[i]) {
    stays.add(i);
  }
  return [
    for (var i = to.length - 1; i >= 0; i--)
      if (!stays.contains(i)) (to[i], i + 1 < to.length ? to[i + 1] : null),
  ];
}

/// Keeps Encore's library and the signed-in YouTube Music account the same,
/// both ways, so the account's recommendations learn from Encore and what
/// is done on YouTube Music shows here:
/// - liked songs; the account's own playlists (made, renamed, songs added,
///   removed or moved, deleted); albums and playlists saved to the library;
///   artists followed;
/// - changes made in Encore go at once (or when back online) through an
///   outbox kept on disk: one at a time, in order, spaced out, never in a
///   burst;
/// - a sync ([sync]) fetches the account's library and merges it with
///   Encore's against what the two last agreed on: what was added on either
///   side is kept, what was removed on either side goes. The first sync
///   only combines (nothing is removed).
class YouTubeSync {
  YouTubeSync({
    this._account,
    this._library,
    this._dir,
    this.spacing = const Duration(seconds: 1),
    this.readSpacing = const Duration(milliseconds: 300),
    this.retryAfter = const Duration(seconds: 30),
    this.every = const Duration(minutes: 30),
    this.firstSync = const Duration(seconds: 5),
  });

  final Account? _account;
  final UserLibrary? _library;
  final Directory? _dir;
  Account get _acc => _account ?? account;
  UserLibrary get _lib => _library ?? userLibrary;

  /// Between two requests that change the account.
  final Duration spacing;

  /// Between the requests a sync reads the account with.
  final Duration readSpacing;

  /// The first wait after a failure; doubled each time, up to 32 times.
  final Duration retryAfter;

  /// How often to sync while Encore runs (signed in).
  final Duration every;

  /// After starting, signed in: the first sync (null: none).
  final Duration? firstSync;

  /// Waiting to be sent, oldest first.
  final pending = ValueNotifier<List<SyncOp>>(const []);

  final state = ValueNotifier(SyncState.idle);

  /// How many changes the current run of sending has had (done ones
  /// included): with [pending], how far it has got. 0 when nothing is
  /// waiting.
  final total = ValueNotifier(0);

  /// Sending failed (offline): it is waiting to try again.
  final waiting = ValueNotifier(false);

  /// The first sync after signing in, waiting for the user to agree to
  /// [SyncPlan] ([answer]).
  final question = ValueNotifier<SyncPlan?>(null);
  Completer<bool>? _answer;

  /// Something to tell the user (shown once, then cleared).
  final notice = ValueNotifier<String?>(null);

  /// The user's answer to [question]: true to sync, false to sign out
  /// (nothing has been sent).
  void answer(bool sync) {
    question.value = null;
    final answer = _answer;
    _answer = null;
    if (answer != null && !answer.isCompleted) answer.complete(sync);
  }

  /// When the last sync finished (null: not since signing in).
  final lastSynced = ValueNotifier<DateTime?>(null);

  // What was last agreed with the account (null: never, before the first
  // sync after signing in).
  Set<String>? _likedBase;
  Map<String, PlaylistBase>? _playlistBase;
  Set<String>? _savedBase;
  Set<String>? _artistsBase;

  // The library as last seen (to tell what changed).
  var _liked = <String>{};
  var _playlists = <String, Playlist>{};
  var _saved = <String>{};
  var _artists = <String>{};

  /// While true, library changes come from the account and aren't sent
  /// back (see [applyingRemote]).
  var _remote = false;

  var _started = false;
  int _generation = 0;
  Timer? _periodic;
  Timer? _first;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _load();
    _snapshot();
    _generation = _acc.generation.value;
    for (final part in _parts) {
      part.addListener(_libraryChanged);
    }
    _acc.generation.addListener(_accountChanged);
    _acc.status.addListener(_kick);
    if (_acc.signedIn && pending.value.isNotEmpty) {
      final n = pending.value.length;
      total.value = n;
      notice.value =
          'Sending $n ${n == 1 ? 'change' : 'changes'} to YouTube Music, '
          'from where it left off.';
    }
    _periodic = Timer.periodic(every, (_) => unawaited(sync()));
    if (firstSync case final wait? when _acc.signedIn) {
      _first = Timer(wait, () => unawaited(sync()));
    }
    _kick();
  }

  List<ValueListenable<Object>> get _parts => [
    _lib.liked,
    _lib.playlists,
    _lib.savedMedia,
    _lib.artists,
  ];

  @visibleForTesting
  void stop() {
    if (!_started) return;
    _started = false;
    for (final part in _parts) {
      part.removeListener(_libraryChanged);
    }
    _acc.generation.removeListener(_accountChanged);
    _acc.status.removeListener(_kick);
    _retry?.cancel();
    _periodic?.cancel();
    _first?.cancel();
  }

  void _snapshot() {
    _liked = {for (final t in _lib.liked.value) t.id};
    _playlists = {for (final p in _lib.playlists.value) p.id: p};
    _saved = {for (final r in _lib.savedMedia.value) r.id};
    _artists = {for (final r in _lib.artists.value) r.id};
  }

  /// Runs [change] to the library without sending it to the account (it
  /// came from there).
  T applyingRemote<T>(T Function() change) {
    _remote = true;
    try {
      return change();
    } finally {
      _remote = false;
      _snapshot();
    }
  }

  void _libraryChanged() {
    if (_remote) return;
    final send = _acc.signedIn;
    final liked = {for (final t in _lib.liked.value) t.id};
    final saved = {for (final r in _lib.savedMedia.value) r.id};
    final artists = {for (final r in _lib.artists.value) r.id};
    final playlists = {for (final p in _lib.playlists.value) p.id: p};
    if (send) {
      for (final id in liked.difference(_liked)) {
        _add(SyncOp('like', id));
      }
      for (final id in _liked.difference(liked)) {
        _add(SyncOp('unlike', id));
      }
      for (final id in saved.difference(_saved)) {
        _add(SyncOp('save', id));
      }
      for (final id in _saved.difference(saved)) {
        _add(SyncOp('unsave', id));
      }
      for (final id in artists.difference(_artists)) {
        _add(SyncOp('follow', id));
      }
      for (final id in _artists.difference(artists)) {
        _add(SyncOp('unfollow', id));
      }
      _playlistsChanged(_playlists, playlists);
    }
    _liked = liked;
    _saved = saved;
    _artists = artists;
    _playlists = playlists;
  }

  void _playlistsChanged(
    Map<String, Playlist> before,
    Map<String, Playlist> now,
  ) {
    for (final p in now.values) {
      final old = before[p.id];
      final remote = p.remoteId;
      if (remote == null) {
        // New in Encore: made on the account too.
        if (old == null) _add(SyncOp('create', p.id));
        continue;
      }
      if (old == null || old.remoteId != remote) continue;
      final was = [for (final t in old.tracks) t.id];
      final ids = [for (final t in p.tracks) t.id];
      final added = [
        for (final id in ids)
          if (!was.contains(id)) id,
      ];
      final removed = [
        for (final id in was)
          if (!ids.contains(id)) id,
      ];
      if (removed.isNotEmpty) _add(SyncOp('remove', remote, ids: removed));
      if (added.isNotEmpty) _add(SyncOp('add', remote, ids: added));
      if (p.name != old.name) _add(SyncOp('rename', remote, name: p.name));
      final kept = [
        for (final id in was)
          if (ids.contains(id)) id,
      ];
      final keptNow = [
        for (final id in ids)
          if (was.contains(id)) id,
      ];
      if (!listEquals(kept, keptNow)) {
        _add(SyncOp('reorder', remote, ids: ids));
      }
    }
    for (final old in before.values) {
      if (now.containsKey(old.id)) continue;
      if (old.remoteId case final remote?) {
        _add(SyncOp('delete', remote));
      } else {
        // Deleted before it was made there: nothing to make.
        _drop((op) => op.kind == 'create' && op.id == old.id);
      }
    }
  }

  /// Queues [op]; it replaces anything pending with the same key (only the
  /// last word counts).
  void _add(SyncOp op) {
    _changes++;
    final key = op.key;
    final before = pending.value.length;
    pending.value = [
      for (final p in pending.value)
        if (key == null || p.key != key) p,
      op,
    ];
    if (before == 0) total.value = 0;
    total.value += pending.value.length - before;
    _save();
    _kick();
  }

  void _drop(bool Function(SyncOp) which) {
    final kept = pending.value.where((op) => !which(op)).toList();
    if (kept.length == pending.value.length) return;
    total.value -= pending.value.length - kept.length;
    pending.value = kept;
    if (kept.isEmpty) total.value = 0;
    _save();
  }

  /// Signed out, or someone else signed in: what was waiting, and what was
  /// agreed, was with the account before.
  void _accountChanged() {
    final changed = _acc.generation.value != _generation;
    _generation = _acc.generation.value;
    if (!changed) return;
    _retry?.cancel();
    _retry = null;
    _failures = 0;
    pending.value = const [];
    total.value = 0;
    waiting.value = false;
    // Signed out while the first sync was asking: no answer needed.
    answer(false);
    _likedBase = null;
    _playlistBase = null;
    _savedBase = null;
    _artistsBase = null;
    lastSynced.value = null;
    state.value = SyncState.idle;
    _save();
    // Just signed in: fetch the account's library.
    if (_acc.signedIn) unawaited(sync());
  }

  Timer? _retry;
  var _failures = 0;
  Future<void>? _running;

  /// Completes when the outbox is as empty as it can get for now.
  @visibleForTesting
  Future<void> get idle async {
    while (_running != null || _syncing != null) {
      await _running;
      await _syncing;
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
      if (_acc.generation.value != gen) return;
      _failures = 0;
      waiting.value = false;
      _agreed(op);
      _remove(op);
    }
  }

  Future<void> _perform(SyncOp op) async {
    switch (op.kind) {
      case 'like':
        await yt.rateSong(op.id, yt.Rating.like);
      case 'unlike':
        await yt.rateSong(op.id, yt.Rating.none);
      case 'save' || 'unsave':
        final playlistId = op.id.startsWith('VL')
            ? op.id.substring(2)
            : (await yt.collection(op.id, maxPages: 0)).playlistId;
        if (playlistId == null) throw yt.YouTubeError('save ${op.id}', 404);
        await yt.savePlaylist(playlistId, op.kind == 'save');
      case 'follow' || 'unfollow':
        final channel = op.id.startsWith('UC')
            ? (await yt.artist(op.id)).channelId ?? op.id
            : yt.channelOf(op.id);
        await yt.followArtist(channel, op.kind == 'follow');
      case 'create':
        await _create(op.id);
      case 'add':
        for (var i = 0; i < op.ids.length; i += 50) {
          await yt.editPlaylist(op.id, [
            for (final id in op.ids.skip(i).take(50)) yt.addAction(id),
          ]);
        }
      case 'remove':
        final entries = (await _entries(op.id)).$2;
        final actions = [
          for (final id in op.ids)
            for (final entry in entries[id] ?? const <String>[])
              yt.removeAction(id, entry),
        ];
        for (var i = 0; i < actions.length; i += 50) {
          await yt.editPlaylist(op.id, actions.skip(i).take(50).toList());
        }
      case 'reorder':
        final (order, entries) = await _entries(op.id);
        final wanted = [
          for (final id in op.ids)
            if (entries.containsKey(id)) id,
        ];
        final current = [
          for (final id in order)
            if (wanted.contains(id)) id,
        ];
        final moves = [
          for (final (id, before) in movesFor(current, wanted))
            yt.moveAction(
              entries[id]!.first,
              before == null ? null : entries[before]!.first,
            ),
        ];
        for (var i = 0; i < moves.length; i += 50) {
          await yt.editPlaylist(op.id, moves.skip(i).take(50).toList());
        }
      case 'rename':
        await yt.editPlaylist(op.id, [yt.renameAction(op.name ?? '')]);
      case 'delete':
        await yt.deletePlaylist(op.id);
    }
  }

  /// [op] is done: both sides now agree on it. Without this, a song liked
  /// in Encore and later unliked on YouTube Music would look new in Encore
  /// at the next sync, and come back.
  void _agreed(SyncOp op) {
    _changes++;
    void set(Set<String>? base, bool add) {
      if (base == null) return;
      add ? base.add(op.id) : base.remove(op.id);
    }

    final playlist = _playlistBase?[op.id];
    switch (op.kind) {
      case 'like' || 'unlike':
        set(_likedBase, op.kind == 'like');
      case 'save' || 'unsave':
        set(_savedBase, op.kind == 'save');
      case 'follow' || 'unfollow':
        set(_artistsBase, op.kind == 'follow');
      case 'add' when playlist != null:
        _playlistBase![op.id] = PlaylistBase(playlist.name, [
          ...playlist.ids,
          for (final id in op.ids)
            if (!playlist.ids.contains(id)) id,
        ]);
      case 'remove' when playlist != null:
        _playlistBase![op.id] = PlaylistBase(playlist.name, [
          for (final id in playlist.ids)
            if (!op.ids.contains(id)) id,
        ]);
      case 'reorder' when playlist != null:
        _playlistBase![op.id] = PlaylistBase(playlist.name, op.ids);
      case 'rename' when playlist != null:
        _playlistBase![op.id] = PlaylistBase(op.name ?? '', playlist.ids);
      case 'delete':
        _playlistBase?.remove(op.id);
    }
  }

  /// The account's playlist [id]: its songs in order, and each song's
  /// entries (what removing or moving it takes).
  Future<(List<String>, Map<String, List<String>>)> _entries(String id) async {
    final c = await yt.collection('VL$id', maxPages: 50);
    final order = <String>[];
    for (final t in c.tracks) {
      if (!order.contains(t.id)) order.add(t.id);
    }
    return (order, c.entryIds);
  }

  /// Makes Encore's playlist [localId] on the account, as it is now, and
  /// links the two.
  Future<void> _create(String localId) async {
    final p = _lib.playlist(localId);
    if (p == null || p.remoteId != null) return; // Deleted, or made.
    // Made with its first 50 songs (one request with a thousand may be
    // refused), and linked at once; the rest go as changes after it, so a
    // failure part way never makes it twice.
    final first = p.tracks.take(50).toList();
    final remote = await yt.createPlaylist(p.name, [
      for (final t in first) t.id,
    ]);
    final now = _lib.playlist(localId);
    if (now == null) {
      // Deleted while it was being made: delete it there too.
      _add(SyncOp('delete', remote));
      return;
    }
    applyingRemote(
      () => _lib.playlists.value = [
        for (final q in _lib.playlists.value)
          q.id == localId ? q.copyWith(remoteId: remote) : q,
      ],
    );
    (_playlistBase ??= {})[remote] = PlaylistBase(p.name, [
      for (final t in first) t.id,
    ]);
    // The rest of its songs, and changes made while it was being made.
    _playlistsChanged(
      {localId: p.copyWith(remoteId: remote, tracks: first)},
      {localId: now.copyWith(remoteId: remote)},
    );
    _save();
  }

  /// Takes [op] off the list, unless it was replaced meanwhile (a newer
  /// word for the same thing, which still has to go).
  void _remove(SyncOp op) {
    final list = pending.value;
    final i = list.indexWhere((p) => identical(p, op));
    if (i < 0) return;
    pending.value = [...list]..removeAt(i);
    if (pending.value.isEmpty) total.value = 0;
    _save();
  }

  void _failed(SyncOp op, Object e) {
    debugPrint('Sending $op failed, trying later: $e');
    waiting.value = true;
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

  // Fetching and merging.

  Future<String?>? _syncing;

  /// Goes up with every change queued or sent: a sync whose fetch saw it
  /// change merges nothing (its copy of the account may be from before).
  var _changes = 0;

  /// Brings Encore and the account together. Returns why not, or null
  /// once done. Changes still waiting to be sent go first: a sync with
  /// them unsent would take them for things removed on the account.
  Future<String?> sync() =>
      _syncing ??= _sync().whenComplete(() => _syncing = null);

  Future<String?> _sync() async {
    if (!_acc.signedIn) return 'Sign in to sync with YouTube Music.';
    final gen = _acc.generation.value;
    state.value = SyncState.syncing;
    try {
      retryNow();
      while (_running != null) {
        await _running;
      }
      if (pending.value.isNotEmpty) {
        throw const SocketException('Changes are still waiting to be sent');
      }
      final changes = _changes;
      final remote = await _fetch();
      if (_acc.generation.value != gen || !_acc.signedIn) {
        return 'Signed out while syncing.';
      }
      // Changed meanwhile (sent, or still to send): next time.
      if (pending.value.isNotEmpty || _running != null || _changes != changes) {
        state.value = SyncState.idle;
        return 'Your library changed while syncing. Sync again in a moment.';
      }
      if (_likedBase == null) {
        // The first sync for this account: say what it will do first.
        final plan = _plan(remote);
        if (plan.sends) {
          final answer = _answer = Completer<bool>();
          question.value = plan;
          final go = await answer.future;
          if (_acc.generation.value != gen || !_acc.signedIn) {
            return 'Signed out while syncing.';
          }
          if (!go) {
            state.value = SyncState.idle;
            await _acc.signOut();
            return 'Signed out. Nothing was sent to YouTube Music.';
          }
          if (pending.value.isNotEmpty || _changes != changes) {
            state.value = SyncState.idle;
            return 'Your library changed while syncing. Sync again in a '
                'moment.';
          }
        }
      }
      _merge(remote);
      lastSynced.value = DateTime.now();
      state.value = SyncState.idle;
      _save();
      _kick();
      return null;
    } catch (e) {
      debugPrint('Sync failed: $e');
      if (_acc.generation.value == gen) state.value = SyncState.failed;
      return "Couldn't sync with YouTube Music";
    }
  }

  Future<_Remote> _fetch() async {
    Future<T> read<T>(Future<T> Function() request) async {
      await Future<void>.delayed(readSpacing);
      return request();
    }

    final liked = await read(() => yt.collection('VLLM', maxPages: 50));
    final library = await read(yt.libraryPlaylists);
    final own = <String, Collection>{};
    final savedPlaylists = <MediaRef>[];
    for (final p in library) {
      final c = await read(() => yt.collection('VL${p.id}', maxPages: 50));
      if (c.owned) {
        own[p.id] = c;
      } else {
        savedPlaylists.add(
          MediaRef(
            kind: MediaKind.playlist,
            id: 'VL${p.id}',
            title: p.title,
            subtitle: p.subtitle,
            artUrl: p.artUrl,
          ),
        );
      }
    }
    final albums = await read(yt.savedAlbums);
    final artists = await read(yt.followedArtists);
    return _Remote(
      liked: liked.tracks,
      playlists: own,
      saved: [...albums, ...savedPlaylists],
      artists: artists,
    );
  }

  /// What merging [remote] into a library never synced before (nothing is
  /// removed then) will send and bring.
  SyncPlan _plan(_Remote remote) {
    final remoteLiked = {for (final t in remote.liked) t.id};
    final localLiked = {for (final t in _lib.liked.value) t.id};
    final likes = localLiked.difference(remoteLiked).length;
    var playlists = 0, songs = 0, requests = likes;
    final linked = <String>{};
    for (final p in _lib.playlists.value) {
      final ids = {for (final t in p.tracks) t.id};
      final there = remote.playlists[p.remoteId];
      if (there == null) {
        // Made on the account: with 50 songs, then 50 at a time.
        playlists++;
        songs += ids.length;
        requests += 1 + (max(0, ids.length - 50) + 49) ~/ 50;
      } else {
        linked.add(p.remoteId!);
        final added = ids.difference({for (final t in there.tracks) t.id});
        songs += added.length;
        requests += (added.length + 49) ~/ 50;
      }
    }
    final remoteSaved = {for (final r in remote.saved) r.id};
    final saved = [
      for (final r in _lib.savedMedia.value)
        if (!remoteSaved.contains(r.id)) r,
    ];
    // Albums are looked up first (what saving one saves).
    for (final r in saved) {
      requests += r.id.startsWith('VL') ? 1 : 2;
    }
    final remoteArtists = {for (final r in remote.artists) r.id};
    final artists = _lib.artists.value
        .where((r) => !remoteArtists.contains(r.id))
        .length;
    requests += artists * 2;
    final localSaved = {for (final r in _lib.savedMedia.value) r.id};
    final localArtists = {for (final r in _lib.artists.value) r.id};
    return SyncPlan(
      likes: likes,
      playlists: playlists,
      playlistSongs: songs,
      saved: saved.length,
      artists: artists,
      requests: requests,
      newLikes: remoteLiked.difference(localLiked).length,
      newPlaylists: remote.playlists.keys
          .where((id) => !linked.contains(id))
          .length,
      newSaved: remoteSaved.difference(localSaved).length,
      newArtists: remoteArtists.difference(localArtists).length,
    );
  }

  void _merge(_Remote remote) {
    applyingRemote(() {
      _mergeLiked(remote.liked);
      _mergePlaylists(remote.playlists);
      _mergeSaved(remote.saved);
      _mergeArtists(remote.artists);
    });
  }

  void _mergeLiked(List<Track> remote) {
    final local = _lib.liked.value;
    final byId = {
      for (final t in remote) t.id: t,
      for (final t in local) t.id: t,
    };
    final remoteIds = [for (final t in remote) t.id];
    final localIds = [for (final t in local) t.id];
    final merged = mergeSets(localIds.toSet(), remoteIds.toSet(), _likedBase);
    // Newest first, as the account lists them; liked in Encore since, first.
    final order = [
      for (final id in localIds)
        if (merged.contains(id) && !remoteIds.contains(id)) id,
      for (final id in remoteIds)
        if (merged.contains(id)) id,
    ];
    _lib.liked.value = [for (final id in order.toSet()) byId[id]!];
    for (final id in merged.difference(remoteIds.toSet())) {
      _add(SyncOp('like', id));
    }
    for (final id in remoteIds.toSet().difference(merged)) {
      _add(SyncOp('unlike', id));
    }
    _likedBase = merged;
  }

  void _mergePlaylists(Map<String, Collection> remote) {
    final base = _playlistBase;
    final next = <String, PlaylistBase>{};
    final playlists = [..._lib.playlists.value];
    final linked = {
      for (final p in playlists)
        if (p.remoteId != null) p.remoteId!: p,
    };

    for (final MapEntry(key: id, value: c) in remote.entries) {
      final remoteIds = _unique([for (final t in c.tracks) t.id]);
      final was = base?[id];
      final local = linked[id];
      if (local == null) {
        final unchanged =
            was != null &&
            was.name == c.title &&
            listEquals(was.ids, remoteIds);
        if (unchanged) {
          // Deleted in Encore (while signed out): delete it there.
          _add(SyncOp('delete', id));
          continue;
        }
        // New on the account (or changed there since): in Encore too.
        final made = Playlist(
          id: 'yt-$id-${DateTime.now().microsecondsSinceEpoch}',
          name: c.title.isEmpty ? 'My playlist' : c.title,
          tracks: _uniqueTracks(c.tracks),
          source: 'YouTube Music',
          remoteId: id,
        );
        playlists.add(made);
        next[id] = PlaylistBase(made.name, remoteIds);
        continue;
      }
      final localIds = [for (final t in local.tracks) t.id];
      final keep = mergeSets(
        localIds.toSet(),
        remoteIds.toSet(),
        was?.ids.toSet(),
      );
      final order = mergeOrder(localIds, remoteIds, was?.ids, keep);
      final byId = {
        for (final t in c.tracks) t.id: t,
        for (final t in local.tracks) t.id: t,
      };
      final name = switch (was) {
        // Renamed in Encore only: Encore's name; otherwise the account's.
        final b? when b.name == c.title => local.name,
        _ => c.title.isEmpty ? local.name : c.title,
      };
      final merged = local.copyWith(
        name: name,
        tracks: [for (final id in order) byId[id]!],
      );
      final i = playlists.indexWhere((p) => p.id == local.id);
      playlists[i] = merged;
      // What the account still needs.
      final remoteSet = remoteIds.toSet();
      final removed = [
        for (final id in remoteIds)
          if (!keep.contains(id)) id,
      ];
      final added = [
        for (final id in order)
          if (!remoteSet.contains(id)) id,
      ];
      if (removed.isNotEmpty) _add(SyncOp('remove', id, ids: removed));
      if (added.isNotEmpty) _add(SyncOp('add', id, ids: added));
      if (name != c.title) _add(SyncOp('rename', id, name: name));
      final afterRemote = [
        for (final r in remoteIds)
          if (keep.contains(r)) r,
        ...added,
      ];
      if (!listEquals(afterRemote, order)) {
        _add(SyncOp('reorder', id, ids: order));
      }
      next[id] = PlaylistBase(name, order);
    }

    // Linked playlists no longer on the account: deleted there.
    for (final p in [...playlists]) {
      final remoteId = p.remoteId;
      if (remoteId == null || remote.containsKey(remoteId)) continue;
      final was = base?[remoteId];
      final unchanged =
          was != null &&
          was.name == p.name &&
          listEquals(was.ids, [for (final t in p.tracks) t.id]);
      final i = playlists.indexOf(p);
      if (unchanged) {
        playlists.removeAt(i);
      } else {
        // Changed in Encore since: kept, and made there again.
        playlists[i] = p.copyWith(unlink: true);
      }
    }
    _lib.playlists.value = playlists;
    // Encore's own playlists not on the account yet: made there.
    for (final p in playlists) {
      if (p.remoteId == null) _add(SyncOp('create', p.id));
    }
    _playlistBase = next;
  }

  void _mergeSaved(List<MediaRef> remote) {
    final merged = _mergeRefs(_lib.savedMedia.value, remote, _savedBase);
    _lib.savedMedia.value = merged.$1;
    for (final id in merged.$2) {
      _add(SyncOp('save', id));
    }
    for (final id in merged.$3) {
      _add(SyncOp('unsave', id));
    }
    _savedBase = {for (final r in merged.$1) r.id};
  }

  void _mergeArtists(List<MediaRef> remote) {
    // The account names artists by channel; Encore by the artist's page,
    // which is usually the same.
    final merged = _mergeRefs(_lib.artists.value, remote, _artistsBase);
    _lib.artists.value = merged.$1;
    for (final id in merged.$2) {
      _add(SyncOp('follow', id));
    }
    for (final id in merged.$3) {
      _add(SyncOp('unfollow', id));
    }
    _artistsBase = {for (final r in merged.$1) r.id};
  }

  /// Merged list (Encore's order, then new ones from the account), what
  /// the account still needs added, and removed.
  (List<MediaRef>, List<String>, List<String>) _mergeRefs(
    List<MediaRef> local,
    List<MediaRef> remote,
    Set<String>? base,
  ) {
    final remoteIds = {for (final r in remote) r.id};
    final keep = mergeSets({for (final r in local) r.id}, remoteIds, base);
    final seen = <String>{};
    final list = [
      for (final r in [...local, ...remote])
        if (keep.contains(r.id) && seen.add(r.id)) r,
    ];
    return (
      list,
      [
        for (final r in list)
          if (!remoteIds.contains(r.id)) r.id,
      ],
      [
        for (final id in remoteIds)
          if (!keep.contains(id)) id,
      ],
    );
  }

  static List<String> _unique(List<String> ids) => ids.toSet().toList();

  static List<Track> _uniqueTracks(List<Track> tracks) =>
      tracks.toSet().toList();

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
      Set<String>? ids(String key) => json[key] is List
          ? (json[key] as List).whereType<String>().toSet()
          : null;
      _likedBase = ids('liked');
      _savedBase = ids('saved');
      _artistsBase = ids('artists');
      if (json['playlists'] case final Map playlists) {
        _playlistBase = {
          for (final MapEntry(:key, :value) in playlists.entries)
            if (key is String) key: ?PlaylistBase.fromJson(value),
        };
      }
      if (json['lastSynced'] case final String at) {
        lastSynced.value = DateTime.tryParse(at);
      }
    } on PathNotFoundException {
      // Nothing waiting, never synced.
    } catch (e) {
      debugPrint('Sync state unreadable, starting over: $e');
    }
  }

  void _save() {
    final json = jsonEncode({
      'pending': pending.value,
      'liked': ?_likedBase?.toList(),
      'saved': ?_savedBase?.toList(),
      'artists': ?_artistsBase?.toList(),
      'playlists': ?_playlistBase,
      'lastSynced': ?lastSynced.value?.toIso8601String(),
    });
    _lastWrite = (_lastWrite ?? Future.value()).then((_) async {
      try {
        final file = await _path();
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(json, flush: true);
        await temp.rename(file.path);
      } catch (e) {
        debugPrint('Saving the sync state failed: $e');
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
