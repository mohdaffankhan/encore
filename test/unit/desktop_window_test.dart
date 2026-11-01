import 'package:encore/models.dart';
import 'package:encore/services/desktop_window.dart';
import 'package:encore/services/player.dart';
import 'package:encore/services/settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import '../fake_audio.dart';

// The window title said "Encore" whatever played, and the desktop app had
// no tray: closing the window stopped the music.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(DesktopWindow.name);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> sent;
  late FakeAudio audio;
  late Player player;
  late DesktopWindow window;

  setUp(() {
    sent = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent.add(call);
      return null;
    });
    audio = FakeAudio()..processingState = ProcessingState.ready;
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
