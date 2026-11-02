import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Just the parts of just_audio's player that the app uses, with a playlist
/// like the real one: the song playing (index 0) and the one lined up after
/// it. Shared by the tests of the player and what listens to it.
class FakeAudio implements AudioPlayer {
  final errors = StreamController<PlayerException>.broadcast(sync: true);
  final states = StreamController<ProcessingState>.broadcast(sync: true);
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);
  final playingChanges = StreamController<bool>.broadcast(sync: true);
  final durations = StreamController<Duration?>.broadcast(sync: true);
  final jumps = StreamController<PositionDiscontinuity>.broadcast(sync: true);
  final indexes = StreamController<int?>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);

  /// Where each load started (null: the beginning).
  final loads = <Duration?>[];
  final seeks = <Duration>[];

  /// The player's songs: the current one, then the one lined up.
  final sources = <AudioSource>[];

  /// While set, loading waits for it.
  Completer<void>? gate;

  /// Seeks never complete (Android, when the stream can't serve them).
  var seeksHang = false;

  @override
  Stream<PlayerException> get errorStream => errors.stream;
  @override
  Stream<ProcessingState> get processingStateStream => states.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  Stream<bool> get playingStream => playingChanges.stream;
  @override
  Stream<Duration?> get durationStream => durations.stream;
  @override
  Stream<PositionDiscontinuity> get positionDiscontinuityStream => jumps.stream;
  @override
  Stream<int?> get currentIndexStream => indexes.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  double speed = 1;
  @override
  double volume = 1;
  @override
  ProcessingState processingState = ProcessingState.idle;
  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration? duration;
  @override
  int? currentIndex;

  @override
  List<IndexedAudioSource> get sequence =>
      sources.whereType<IndexedAudioSource>().toList();

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loads.add(initialPosition);
    sources
      ..clear()
      ..add(source);
    currentIndex = 0;
    processingState = ProcessingState.loading;
    await gate?.future;
    processingState = ProcessingState.ready;
    position = initialPosition ?? Duration.zero;
    duration = const Duration(minutes: 4);
    return duration;
  }

  @override
  Future<void> addAudioSource(AudioSource source) async => sources.add(source);

  @override
  Future<void> removeAudioSourceAt(int index) async {
    sources.removeAt(index);
    if (currentIndex != null && currentIndex! > index) {
      currentIndex = currentIndex! - 1;
    }
  }

  @override
  Future<void> play() async => playingChanges.add(playing = true);
  @override
  Future<void> pause() async => playingChanges.add(playing = false);
  @override
  Future<void> seek(Duration? to, {int? index}) async {
    seeks.add(to!);
    position = to;
    if (seeksHang) await Completer<void>().future;
  }

  @override
  Future<void> setVolume(double volume) async => this.volume = volume;
  @override
  Future<void> setSpeed(double speed) async => this.speed = speed;

  /// Plays on to [to], as the position updates say.
  void playTo(Duration to) => positions.add(position = to);

  /// What the player reports as it plays: [position] of the current song.
  void report() => events.add(
    PlaybackEvent(
      processingState: ProcessingState.ready,
      updatePosition: position,
      duration: duration,
      currentIndex: currentIndex,
    ),
  );

  /// The current song played to its end and the lined-up one follows, as
  /// the real player does by itself (no gap).
  void playOn() {
    position = duration ?? Duration.zero;
    report();
    currentIndex = 1;
    position = Duration.zero;
    indexes.add(1);
  }

  /// What the desktop player reports when a stream breaks off: the end,
  /// with the position reset to 0.
  void endEarly() {
    report();
    position = Duration.zero;
    processingState = ProcessingState.completed;
    states.add(ProcessingState.completed);
  }

  /// What the player reports when the song's stream fails mid-way.
  void breakOff() {
    processingState = ProcessingState.idle;
    errors.add(PlayerException(0, 'Source error', 0));
    playing = false; // it pauses itself right after
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
