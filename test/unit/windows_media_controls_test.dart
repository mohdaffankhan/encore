import 'package:encore/models.dart';
import 'package:encore/services/player.dart';
import 'package:encore/services/windows_media_controls.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import '../fake_audio.dart';

// On Windows the media overlay, lock screen and media keys knew nothing of
// Encore: the keys only worked while its window was in front.

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
  late FakeAudio audio;
  late Player player;

  setUp(() {
    sent = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent.add(call);
      return null;
    });
    audio = FakeAudio()
      ..processingState = ProcessingState.ready
      ..position = const Duration(seconds: 30)
      ..duration = const Duration(minutes: 3);
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
