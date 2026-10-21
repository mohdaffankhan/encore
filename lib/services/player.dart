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

class Player {
  Player() {
    audio.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onCompleted();
    });
    queue.addListener(_updateNowPlaying);
    index.addListener(_updateNowPlaying);
  }

  /// The current song. Listen to this, not [index], for song changes: a new
  /// song from search replaces the queue and is at index 0 again, so
  /// [index] doesn't change (which left the players showing the old song).
  final nowPlaying = ValueNotifier<Track?>(null);

  void _updateNowPlaying() => nowPlaying.value = current;

  final audio = AudioPlayer();
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
      await audio.seek(Duration.zero);
    } else {
      await _playAt(index.value - 1);
    }
  }

  void toggle() => audio.playing ? audio.pause() : audio.play();

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
    audio.seek(pos);
  }

  void changeVolume(double delta) =>
      audio.setVolume((audio.volume + delta).clamp(0, 1));

  void toggleLikeCurrent() {
    if (current case final track?) userLibrary.toggleLike(track);
  }

  void _onCompleted() {
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
    } catch (e) {
      debugPrint('Radio failed: $e');
    }
  }

  /// Songs skipped in a row because they couldn't play. Capped, so being
  /// offline doesn't race through the whole queue.
  int _skippedInRow = 0;

  Future<void> _playAt(int i, {bool autoplay = true, bool auto = false}) async {
    if (i < 0 || i >= queue.value.length) return;
    index.value = i;
    final track = queue.value[i];
    loading.value = true;
    try {
      // Silence the previous song while this one loads. Pause, not stop:
      // stopping would end the system media session (media_session.dart).
      await audio.pause();
      final AudioSource source;
      if (await downloads.fileFor(track) case final file?) {
        source = AudioSource.file(file.path, tag: track);
      } else {
        // Stream URLs expire, so resolve only when the track is about to play.
        final stream = await audioStream(track.id);
        source = YouTubeAudioSource(stream, tag: track);
      }
      if (index.value != i) return; // skipped while resolving
      await audio.setAudioSource(source).timeout(const Duration(seconds: 20));
      _skippedInRow = 0;
      if (autoplay) {
        audio.play();
        userLibrary.addPlayed(track);
      }
      if (i == queue.value.length - 1 && repeat.value != Repeat.all) {
        unawaited(_extendWithRadio(track));
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
