import 'dart:async';

import 'package:encore/models.dart';
import 'package:encore/services/desktop_window.dart';
import 'package:encore/services/player.dart';
import 'package:encore/services/settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

// The window title said "Encore" whatever played, and the desktop app had
// no tray: closing the window stopped the music.

class _FakeAudio implements AudioPlayer {
  final playingChanges = StreamController<bool>.broadcast(sync: true);

  @override
  Stream<bool> get playingStream => playingChanges.stream;
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
  Future<void> play() async => playingChanges.add(playing = true);
  @override
  Future<void> pause() async => playingChanges.add(playing = false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(DesktopWindow.name);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> sent;
  late _FakeAudio audio;
  late Player player;
  late DesktopWindow window;

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
    window = DesktopWindow(player)..start();
  });

  tearDown(() {
    window.stop();
    messenger.setMockMethodCallHandler(channel, null);
    settings.closeToTray.value = true;
  });

  List<Object?> titles() => [
    for (final c in sent)
      if (c.method == 'title') c.arguments,
  ];

  test('the title is the song while it plays, like Spotify', () async {
    player.queue.value = [
      const Track(id: 'a', title: 'Get Lucky', artist: 'Daft Punk', artUrl: ''),
    ];
    player.index.value = 0;
    await audio.play();
    await audio.pause();
    expect(titles(), ['Encore', 'Get Lucky – Daft Punk', 'Encore']);
  });

  test('closing to the tray follows the setting', () {
    settings.closeToTray.value = false;
    expect(
      [
        for (final c in sent)
          if (c.method == 'closeToTray') c.arguments,
      ],
      [true, false],
    );
  });

  test("the tray's menu plays and pauses", () async {
    player.queue.value = [
      const Track(id: 'a', title: 'A', artist: 'X', artUrl: ''),
    ];
    player.index.value = 0;
    audio.playing = true;
    await messenger.handlePlatformMessage(
      DesktopWindow.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('tray', 'playPause'),
      ),
      (_) {},
    );
    expect(audio.playing, isFalse);
  });
}
