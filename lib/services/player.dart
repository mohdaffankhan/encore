import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../api/innertube.dart' as yt;
import '../api/stream.dart';
import '../models.dart';
import 'downloads.dart';
import 'library.dart';
import 'sleep_timer.dart';
import 'youtube_audio_source.dart';

final player = Player();

enum Repeat { off, all, one }

/// What a song plays from: its download, or its stream from YouTube.
Future<AudioSource> sourceFor(Track track) async {
  if (await downloads.fileFor(track) case final file?) {
    return AudioSource.file(file.path, tag: track);
  }
  final ahead = _ahead.remove(track.id);
  final stream = ahead == null
      ? await audioStream(track.id)
      : await ahead.catchError((Object _) => audioStream(track.id));
  return YouTubeAudioSource(stream, tag: track);
}

/// Stream links looked up ahead, by song id.
final _ahead = <String, Future<AudioStream>>{};

/// Looks up [track]'s stream link ahead (the next song), so it starts
/// without waiting for YouTube. A link lasts hours, and an expired one is
/// renewed ([AudioStream.renew]).
void prepare(Track track) {
  if (downloads.isDownloaded(track) || _ahead.containsKey(track.id)) return;
  if (_ahead.length >= 2) _ahead.remove(_ahead.keys.first);
  _ahead[track.id] = audioStream(track.id)..ignore();
}

class Player {
  /// [audio], [source] and [prepare] are replaced in tests.
  Player({
    AudioPlayer? audio,
    Future<AudioSource> Function(Track)? source,
    void Function(Track)? prepare,
  }) : audio = audio ?? AudioPlayer(),
       _source = source ?? sourceFor,
       _prepare = prepare ?? (source == null ? _prepareStream : (_) {}) {
    this.audio.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onCompleted();
    });
    this.audio.errorStream.listen(_onError);
    this.audio.playbackEventStream.listen((event) {
      if (event.processingState == ProcessingState.ready) _lastReady = event;
    }, onError: (Object _) {});
    queue.addListener(_updateNowPlaying);
    index.addListener(_updateNowPlaying);
  }

  final Future<AudioSource> Function(Track) _source;
  final void Function(Track) _prepare;

  static void _prepareStream(Track track) => prepare(track);

  void _prepareNext() {
    if (upNext.firstOrNull case final next?) _prepare(next);
  }

  /// The current song. Listen to this, not [index], for song changes: a new
  /// song from search replaces the queue and is at index 0 again, so
  /// [index] doesn't change (which left the players showing the old song).
  final nowPlaying = ValueNotifier<Track?>(null);

  void _updateNowPlaying() => nowPlaying.value = current;

  final AudioPlayer audio;
  final queue = ValueNotifier<List<Track>>([]);
  final index = ValueNotifier<int>(-1);
  final loading = ValueNotifier<bool>(false);
  final repeat = ValueNotifier<Repeat>(Repeat.off);

  /// Shuffle mode: songs after the current one play in random order. It
  /// stays on for whatever is played next, like YouTube Music and Spotify.
  final shuffle = ValueNotifier<bool>(false);

  /// While shuffled: the queue in its original order, to go back to when
  /// shuffle is turned off.
  List<Track>? _ordered;
  final error = ValueNotifier<String?>(null);

  /// Bumped whenever the queue is replaced, so late radio results for an
  /// old queue are dropped.
  int _session = 0;

  Track? get current => index.value >= 0 && index.value < queue.value.length
      ? queue.value[index.value]
      : null;

  /// The songs either side of the current one, if any.
  Track? get nextTrack => upNext.firstOrNull;
  Track? get previousTrack =>
      current != null && index.value > 0 ? queue.value[index.value - 1] : null;

  List<Track> get upNext =>
      current == null ? const [] : queue.value.sublist(index.value + 1);

  /// Plays [track], then continues with its radio.
  Future<void> playRadio(Track track) async {
    _session++;
    _ordered = shuffle.value ? [track] : null;
    queue.value = [track];
    unawaited(_extendWithRadio(track));
    await _playAt(0);
  }

  /// Plays [tracks] starting at [start].
  Future<void> playList(
    List<Track> tracks,
    int start, {
    bool shuffled = false,
  }) async {
    _session++;
    if (shuffled) shuffle.value = true;
    var list = List.of(tracks);
    _ordered = null;
    if (shuffle.value && list.isNotEmpty) {
      _ordered = List.of(tracks);
      if (shuffled) {
        // The Shuffle button: start anywhere.
        list.shuffle();
      } else {
        // A song tapped while shuffle is on: that song, then the rest in
        // random order.
        final first = list.removeAt(start);
        list = [first, ...list..shuffle()];
      }
      start = 0;
    }
    queue.value = list;
    await _playAt(start);
  }

  Future<void> jumpTo(int i) => _playAt(i);

  void playNext(Track track) {
    if (current == null) {
      playRadio(track);
      return;
    }
    final q = [...queue.value]..insert(index.value + 1, track);
    queue.value = q;
    // Keep it next when shuffle is turned off, too.
    if (_ordered case final ordered?) {
      final at = ordered.indexOf(current!);
      _ordered = [...ordered]..insert(at + 1, track);
    }
  }

  /// Moves to the next song; with [autoplay] false it is loaded paused.
  Future<void> next({bool autoplay = true}) => _advance(autoplay: autoplay);

  /// [auto]: playback moved on by itself (the song ended), so a song that
  /// can't play is skipped rather than stopping the music.
  Future<void> _advance({bool autoplay = true, bool auto = false}) async {
    if (index.value + 1 < queue.value.length) {
      await _playAt(index.value + 1, autoplay: autoplay, auto: auto);
    } else if (repeat.value == Repeat.all && queue.value.isNotEmpty) {
      await _playAt(0, autoplay: autoplay, auto: auto);
    } else if (current case final track?) {
      await _extendWithRadio(track);
      if (index.value + 1 < queue.value.length) {
        await _playAt(index.value + 1, autoplay: autoplay, auto: auto);
      }
    }
  }

  /// The previous song. With [restart], a song more than 3 s in starts
  /// over instead (the Previous button); swiping always changes song.
  Future<void> previous({bool restart = true}) async {
    final restartSong = restart && audio.position > const Duration(seconds: 3);
    if (restartSong || index.value <= 0) {
      await seek(Duration.zero);
    } else {
      await _playAt(index.value - 1);
    }
  }

  void toggle() => audio.playing ? audio.pause() : play();

  /// Plays, loading the song again if it broke off: after a failure the
  /// player has nothing loaded, and playing it alone did nothing.
  Future<void> play() async {
    if (_broken) {
      _recoveries = 0;
      await _playAt(index.value, start: audio.position);
    } else {
      await audio.play();
    }
  }

  /// Seeks within the song. A seek while the song loads is kept for when it
  /// is ready (the player ignores it then); on a song that broke off, it
  /// loads the song again from there.
  Future<void> seek(Duration position) async {
    if (loading.value) {
      _pendingSeek = position;
    } else if (_broken) {
      _recoveries = 0;
      await _playAt(index.value, start: position);
    } else {
      await audio.seek(position);
    }
  }

  Duration? _pendingSeek;

  /// Nothing loaded for the current song: it failed (or never loaded).
  bool get _broken =>
      current != null &&
      !loading.value &&
      audio.processingState == ProcessingState.idle;

  /// Turns shuffle on (shuffling what is up next) or off (putting it back
  /// in its original order, carrying on from the current song).
  void toggleShuffle() {
    shuffle.value = !shuffle.value;
    final song = current;
    if (song == null) {
      _ordered = null;
      return;
    }
    if (shuffle.value) {
      _ordered = queue.value;
      queue.value = [
        ...queue.value.sublist(0, index.value + 1),
        ...upNext.toList()..shuffle(),
      ];
    } else if (_ordered case final ordered?) {
      _ordered = null;
      final inQueue = queue.value.toSet();
      final known = ordered.toSet();
      final q = [
        ...ordered.where(inQueue.contains),
        // Added while shuffled (e.g. radio): after the rest.
        ...queue.value.where((t) => !known.contains(t)),
      ];
      queue.value = q;
      index.value = q.indexOf(song);
    }
  }

  void cycleRepeat() => repeat.value =
      Repeat.values[(repeat.value.index + 1) % Repeat.values.length];

  /// Seeks by [offset] from the current position, within the song.
  void seekBy(Duration offset) {
    final total = audio.duration;
    var pos = audio.position + offset;
    if (pos < Duration.zero) pos = Duration.zero;
    if (total != null && pos > total) pos = total;
    seek(pos);
  }

  void changeVolume(double delta) =>
      audio.setVolume((audio.volume + delta).clamp(0, 1));

  void toggleLikeCurrent() {
    if (current case final track?) userLibrary.toggleLike(track);
  }

  /// The last report from the player while the song played, to tell how
  /// far it got: the desktop player resets the position to 0 as it reports
  /// that a song ended.
  PlaybackEvent? _lastReady;

  Duration get _heardTo {
    final event = _lastReady;
    if (event == null) return Duration.zero;
    final since = audio.playing
        ? DateTime.now().difference(event.updateTime) * audio.speed
        : Duration.zero;
    return event.updatePosition + since;
  }

  void _onCompleted() {
    // Ended well before its length: the stream broke off (the desktop
    // player takes that for the end), so carry on from there.
    final heard = _heardTo;
    if (audio.duration case final length?
        when length - heard > const Duration(seconds: 10)) {
      _recover(play: true, at: heard);
      return;
    }
    // Sleep timer set to the end of the song: line up the next one, paused.
    if (sleepTimer.takeEndOfSong()) {
      audio.pause();
      _advance(autoplay: false, auto: true);
    } else if (repeat.value == Repeat.one) {
      audio.seek(Duration.zero);
      audio.play();
    } else {
      _advance(auto: true);
    }
  }

  Future<void> _extendWithRadio(Track seed) async {
    final session = _session;
    try {
      final radio = await yt.radio(seed.id);
      if (session != _session) return;
      final known = queue.value.toSet();
      final added = radio.where((t) => !known.contains(t)).toList();
      if (shuffle.value) {
        _ordered = [...?_ordered, ...added];
        added.shuffle();
      }
      queue.value = [...queue.value, ...added];
      _prepareNext();
    } catch (e) {
      debugPrint('Radio failed: $e');
    }
  }

  /// Times the current song was loaded again after breaking off.
  int _recoveries = 0;

  /// A song that broke off mid-way (e.g. its link stopped working when the
  /// phone changed networks) is loaded again from where it stopped.
  void _onError(PlayerException e) {
    debugPrint('Playback error: $e');
    // Read now: the player pauses itself right after reporting an error.
    // Failures while loading are handled by [_playAt].
    if (!loading.value) _recover(play: audio.playing);
  }

  Future<void> _recover({required bool play, Duration? at}) async {
    if (current == null) return;
    if (_recoveries >= 3) {
      error.value = 'Couldn\'t play "${current!.title}"';
      return;
    }
    _recoveries++;
    await _playAt(
      index.value,
      autoplay: play,
      auto: play,
      start: at ?? audio.position,
    );
  }

  /// Songs skipped in a row because they couldn't play. Capped, so being
  /// offline doesn't race through the whole queue.
  int _skippedInRow = 0;

  /// Loads [source] into the player. just_audio's local proxy (which feeds
  /// [YouTubeAudioSource] to the player) closes the response short when a
  /// stream breaks off, and that throws an error nothing catches. The proxy
  /// runs in the zone it was started from, so it is started from one that
  /// logs those. Load errors still reach the caller, through [done].
  Future<void> _load(AudioSource source, Duration? start) {
    final done = Completer<void>();
    runZonedGuarded(() async {
      try {
        await audio.setAudioSource(source, initialPosition: start);
        done.complete();
      } catch (e, stack) {
        done.completeError(e, stack);
      }
    }, (e, _) => debugPrint('Audio proxy: $e'));
    return done.future;
  }

  /// Plays the song at [i]; with [start], the same song again from there.
  Future<void> _playAt(
    int i, {
    bool autoplay = true,
    bool auto = false,
    Duration? start,
  }) async {
    if (i < 0 || i >= queue.value.length) return;
    index.value = i;
    final track = queue.value[i];
    loading.value = true;
    _pendingSeek = null;
    _lastReady = null;
    if (start == null) _recoveries = 0;
    try {
      // Silence the previous song while this one loads. Pause, not stop:
      // stopping would end the system media session (media_session.dart).
      await audio.pause();
      final source = await _source(track);
      if (index.value != i) return; // skipped while resolving
      await _load(source, start).timeout(const Duration(seconds: 20));
      _skippedInRow = 0;
      if (_pendingSeek case final at?) {
        _pendingSeek = null;
        // Not awaited: a seek the stream can't serve never completes on
        // Android, which left the song loading for good.
        unawaited(audio.seek(at));
      }
      if (autoplay) {
        audio.play();
        if (start == null) userLibrary.addPlayed(track);
      }
      if (i == queue.value.length - 1 && repeat.value != Repeat.all) {
        unawaited(_extendWithRadio(track));
      } else {
        _prepareNext();
      }
    } catch (e) {
      debugPrint('Playback failed: $e');
      if (index.value == i) {
        error.value = 'Couldn\'t play "${track.title}"';
        if (auto && _skippedInRow < 3) {
          _skippedInRow++;
          unawaited(_advance(autoplay: autoplay, auto: true));
        }
      }
    } finally {
      if (index.value == i) loading.value = false;
    }
  }
}
