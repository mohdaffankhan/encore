import 'dart:io';

import 'package:encore/models.dart';
import 'package:encore/services/player.dart';
import 'package:encore/services/session.dart';
import 'package:encore/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import '../fake_audio.dart';

// Closing the app (or Android closing it in the background) lost the queue
// and the song: it opened with nothing playing.

Track _song(String id) =>
    Track(id: id, title: 'Song $id', artist: 'Artist', artUrl: '');

void main() {
  late Directory dir;
  final started = <(FakeAudio, PlaybackSession)>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('encore_session');
    useDataDir(dir);
  });

  tearDown(() async {
    // Stops saving every few seconds, and waits for the last save.
    for (final (audio, session) in started) {
      await audio.pause();
      await session.saved;
    }
    started.clear();
    await dir.delete(recursive: true);
  });

  /// The app starting: a new player, with what was saved put back.
  Future<(Player, FakeAudio, PlaybackSession)> start() async {
    final audio = FakeAudio();
    final player = Player(
      audio: audio,
      source: (t) async => AudioSource.uri(Uri.parse('https://x/${t.id}')),
      prepare: (_) {},
    );
    final session = PlaybackSession(player);
    started.add((audio, session));
    await session.restore();
    return (player, audio, session);
  }

  test('the app opens on the song it was closed on, where it was', () async {
    final (player, audio, session) = await start();
    // Three songs, so no radio (network) is asked for.
    await player.playList([_song('a'), _song('b'), _song('c')], 1);
    player.cycleRepeat();
    audio.position = const Duration(seconds: 75);
    await audio.pause();
    await session.saved;

    final (again, againAudio, _) = await start();
    expect(again.queue.value, [_song('a'), _song('b'), _song('c')]);
    expect(again.current, _song('b'));
    expect(again.repeat.value, Repeat.all);
    expect(again.position, const Duration(seconds: 75));
    expect(againAudio.loads, isEmpty, reason: 'nothing loads until played');

    await again.play();
    expect(againAudio.loads, [const Duration(seconds: 75)]);
    expect(againAudio.playing, isTrue);
  });

  test('seeking before playing moves where it will play from', () async {
    final (player, audio, session) = await start();
    await player.playList([_song('a'), _song('b')], 0);
    await audio.pause();
    await session.saved;

    final (again, againAudio, _) = await start();
    await again.seek(const Duration(minutes: 2));
    expect(againAudio.loads, isEmpty);
    expect(again.position, const Duration(minutes: 2));
    await again.play();
    expect(againAudio.loads, [const Duration(minutes: 2)]);
  });

  test('a damaged file starts with nothing playing', () async {
    await File('${dir.path}/session.json').writeAsString('{"queue": [');
    final (player, _, _) = await start();
    expect(player.current, isNull);
  });
}
