import 'dart:async';

import 'package:encore/models.dart';
import 'package:encore/services/player.dart';
import 'package:encore/services/windows_media_controls.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

// On Windows the media overlay, lock screen and media keys knew nothing of
// Encore: the keys only worked while its window was in front.

class _FakeAudio implements AudioPlayer {
  final playingChanges = StreamController<bool>.broadcast(sync: true);
  final durations = StreamController<Duration?>.broadcast(sync: true);
  final jumps = StreamController<PositionDiscontinuity>.broadcast(sync: true);

  @override
  Stream<bool> get playingStream => playingChanges.stream;
  @override
  Stream<Duration?> get durationStream => durations.stream;
  @override
  Stream<PositionDiscontinuity> get positionDiscontinuityStream => jumps.stream;
  @override
  Stream<PlayerException> get errorStream => const Stream.empty();
  @override
  Stream<ProcessingState> get processingStateStream => const Stream.empty();
  @override
  Stream<PlaybackEvent> get playbackEventStream => const Stream.empty();
  @override
  ProcessingState processingState = ProcessingState.ready;
  @override
  bool playing = false;
  @override
  Duration position = const Duration(seconds: 30);
  @override
  Duration? duration = const Duration(minutes: 3);

  @override
  Future<void> play() async => playingChanges.add(playing = true);
  @override
  Future<void> pause() async => playingChanges.add(playing = false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Track _song(String id) => Track(
  id: id,
  title: 'Song $id',
  artist: 'Artist',
  artUrl: 'https://lh3.googleusercontent.com/$id=w60-h60',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(WindowsMediaControls.name);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> sent;
  late _FakeAudio audio;
  late Player player;

  setUp(() {
    sent = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent.add(call);
      return null;
    });
    audio = _FakeAudio();
    player = Player(
      audio: audio,
      source: (t) async => AudioSource.uri(Uri.parse('https://x/${t.id}')),
      prepare: (_) {},
    );
    WindowsMediaControls(player).start();
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// Windows pressing one of its buttons.
  Future<void> press(String method, Object arguments) =>
      messenger.handlePlatformMessage(
        WindowsMediaControls.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );

  test('Windows is told the song, then only about changes', () async {
    player.queue.value = [_song('a'), _song('b')];
    player.index.value = 0;
    final item = sent.firstWhere((c) => c.method == 'item');
    expect(item.arguments['title'], 'Song a');
    expect(item.arguments['duration'], 180000);
    expect(item.arguments['artUrl'], contains('w544'), reason: 'sharp art');

    sent.clear();
    await audio.play();
    expect(sent.map((c) => c.method), ['state'], reason: 'not the art again');
    expect(sent.single.arguments, {'playing': true, 'position': 30000});

    sent.clear();
    player.index.value = 1;
    expect(sent.first.arguments['title'], 'Song b');
  });

  test("Windows' buttons control the player", () async {
    player.queue.value = [_song('a'), _song('b')];
    player.index.value = 0;
    await press('button', 'pause');
    expect(audio.playing, isFalse);
    await press('button', 'next');
    expect(player.current, _song('b'));
  });
}
