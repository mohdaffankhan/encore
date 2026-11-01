import 'dart:async';

import 'package:encore/models.dart';
import 'package:encore/services/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

// Bug: a song that broke off mid-way (its link stopped working, e.g. the
// phone changed networks) stayed stuck: Play did nothing, and dragging the
// seek bar did nothing either. Now it is loaded again from where it stopped.

/// Just the parts of the audio player the player uses.
class _FakeAudio implements AudioPlayer {
  final errors = StreamController<PlayerException>.broadcast(sync: true);
  final states = StreamController<ProcessingState>.broadcast(sync: true);
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);

  /// Where each load started (null: the beginning).
  final loads = <Duration?>[];
  final seeks = <Duration>[];

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
  double speed = 1;
  @override
  ProcessingState processingState = ProcessingState.idle;
  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration? duration;

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loads.add(initialPosition);
    processingState = ProcessingState.loading;
    await gate?.future;
    processingState = ProcessingState.ready;
    position = initialPosition ?? Duration.zero;
    duration = const Duration(minutes: 4);
    return duration;
  }

  @override
  Future<void> play() async => playing = true;
  @override
  Future<void> pause() async => playing = false;
  @override
  Future<void> seek(Duration? to, {int? index}) async {
    seeks.add(to!);
    position = to;
    if (seeksHang) await Completer<void>().future;
  }

  /// What the desktop player reports when a stream breaks off: the end,
  /// with the position reset to 0.
  void endEarly() {
    events.add(
      PlaybackEvent(
        processingState: ProcessingState.ready,
        updatePosition: position,
      ),
    );
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

Track _song(String id) =>
    Track(id: id, title: 'Song $id', artist: 'Artist', artUrl: '');

void main() {
  late _FakeAudio audio;
  late Player player;
  late List<String> prepared;

  setUp(() async {
    audio = _FakeAudio();
    prepared = [];
    player = Player(
      audio: audio,
      source: (t) async => AudioSource.uri(Uri.parse('https://x/${t.id}')),
      prepare: (t) => prepared.add(t.id),
    );
    // Two songs, so no radio (network) is asked for.
    await player.playList([_song('a'), _song('b')], 0);
    audio.position = const Duration(seconds: 90);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a song that breaks off is loaded again from there, playing', () async {
    audio.breakOff();
    await settle();
    expect(audio.loads, [null, const Duration(seconds: 90)]);
    expect(player.current, _song('a'));
    expect(audio.playing, isTrue);
  });

  test(
    'a paused song that breaks off stays paused when loaded again',
    () async {
      await audio.pause();
      audio.breakOff();
      await settle();
      expect(audio.loads.last, const Duration(seconds: 90));
      expect(audio.playing, isFalse);
    },
  );

  test('Play on a song that broke off loads it again', () async {
    // E.g. it failed for good earlier: nothing is loaded, and paused.
    audio.processingState = ProcessingState.idle;
    audio.playing = false;
    player.toggle();
    await settle();
    expect(audio.loads.last, const Duration(seconds: 90));
    expect(audio.playing, isTrue);
  });

  test(
    'dragging the seek bar on a song that broke off plays from there',
    () async {
      audio.processingState = ProcessingState.idle;
      await player.seek(const Duration(minutes: 2));
      expect(audio.loads.last, const Duration(minutes: 2));
      expect(audio.playing, isTrue);
    },
  );

  test('a seek while the song loads is kept for when it is ready', () async {
    audio.gate = Completer();
    final playing = player.jumpTo(1);
    await settle();
    await player.seek(const Duration(minutes: 1));
    expect(audio.seeks, isEmpty, reason: 'not while loading');
    audio.gate!.complete();
    await playing;
    expect(audio.seeks, [const Duration(minutes: 1)]);
  });

  test('a seek that never completes does not leave the song loading', () async {
    audio
      ..gate = Completer()
      ..seeksHang = true;
    final playing = player.jumpTo(1);
    await settle();
    await player.seek(const Duration(minutes: 1));
    audio.gate!.complete();
    await playing.timeout(const Duration(seconds: 2));
    expect(player.loading.value, isFalse);
    expect(audio.playing, isTrue);
  });

  test(
    'a song that ends long before its length carries on from there',
    () async {
      audio.endEarly();
      await settle();
      expect(player.current, _song('a'), reason: 'not skipped');
      expect(audio.loads.last!.inSeconds, 90);
    },
  );

  test('a song that really ends moves on', () async {
    audio.position = const Duration(minutes: 4);
    audio.endEarly();
    await settle();
    expect(player.current, _song('b'));
  });

  // Each song change waited for YouTube to give the song's link.
  test('the next song is prepared while one plays', () async {
    expect(prepared, ['b']);
  });

  test('gives up after three tries and says so', () async {
    for (var i = 0; i < 4; i++) {
      audio.breakOff();
      await settle();
    }
    expect(audio.loads, hasLength(1 + 3));
    expect(player.error.value, contains('Song a'));
  });
}
