import 'dart:async';
import 'dart:io';

import 'package:encore/api/stream.dart';
import 'package:encore/models.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/player.dart';
import 'package:encore/services/youtube_audio_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import '../fake_audio.dart';

// Bug: a song that broke off mid-way (its link stopped working, e.g. the
// phone changed networks) stayed stuck: Play did nothing, and dragging the
// seek bar did nothing either. Now it is loaded again from where it stopped.

Track _song(String id) =>
    Track(id: id, title: 'Song $id', artist: 'Artist', artUrl: '');

void main() {
  late FakeAudio audio;
  late Player player;
  late List<String> prepared;

  setUp(() async {
    audio = FakeAudio();
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

  // M and the speaker buttons share this, so unmuting anywhere goes back
  // to the level from before.
  test('unmuting goes back to the level before', () {
    audio.volume = 0.4;
    player.toggleMute();
    expect(audio.volume, 0);
    player.toggleMute();
    expect(audio.volume, 0.4);
  });

  // Songs had a gap between them: each was only loaded once the one
  // before had ended.
  group('no gap between songs', () {
    setUp(() async {
      await player.playList([for (final id in 'abcd'.split('')) _song(id)], 0);
      await settle();
    });

    List<String> lined() => [
      for (final s in audio.sources)
        (s as UriAudioSource).uri.pathSegments.last,
    ];

    test('the next song is lined up in the player as one plays', () {
      expect(lined(), ['a', 'b']);
    });

    test('when the player moves on by itself, the app follows', () async {
      final loads = audio.loads.length;
      audio.playOn();
      await settle();
      expect(player.current, _song('b'));
      expect(audio.loads, hasLength(loads), reason: 'nothing loaded again');
      expect(lined(), ['b', 'c'], reason: 'the one after is lined up');
      expect(userLibrary.history.value.first, _song('b'));
    });

    test('moving the next song lines up the new next one', () async {
      player.moveUpNext(2, 0); // d first
      await settle();
      expect(lined(), ['a', 'd']);
    });

    test('repeat one lines up nothing', () async {
      player.cycleRepeat();
      player.cycleRepeat();
      expect(player.repeat.value, Repeat.one);
      await settle();
      expect(lined(), ['a']);
    });

    // The desktop player takes a stream that broke off for the song's end,
    // and moved on to the lined-up song, skipping the rest of this one.
    test('a song whose stream broke off goes on from there', () async {
      final streamed = Player(
        audio: audio,
        source: (t) async => YouTubeAudioSource(
          AudioStream(Uri.parse('https://x/${t.id}'), 'audio/webm', 1000),
          tag: t,
        ),
        prepare: (_) {},
      );
      await streamed.playList([_song('a'), _song('b')], 0);
      await settle();
      audio.playTo(const Duration(minutes: 1));
      (audio.sources.first as YouTubeAudioSource).stream.brokeOff = true;
      // The end, as the desktop player reports it: 0, then the next song.
      audio.playTo(Duration.zero);
      audio
        ..currentIndex = 1
        ..indexes.add(1);
      await settle();
      expect(streamed.current, _song('a'));
      expect(audio.loads.last, const Duration(minutes: 1));
    });

    test('a song that played to its end moves on', () async {
      audio.playTo(const Duration(minutes: 3, seconds: 58));
      audio.playOn();
      await settle();
      expect(player.current, _song('b'));
    });
  });

  group('up next', () {
    setUp(() async {
      await player.playList([for (final id in 'abcde'.split('')) _song(id)], 0);
      prepared.clear();
    });

    List<String> queue() => [for (final t in player.queue.value) t.id];

    test('a song moves later or earlier', () {
      player.moveUpNext(0, 2); // b after d
      expect(queue(), ['a', 'c', 'd', 'b', 'e']);
      player.moveUpNext(3, 0); // e first
      expect(queue(), ['a', 'e', 'c', 'd', 'b']);
      expect(prepared.last, 'e', reason: 'the new next song is prepared');
    });

    test('a song taken out stays out when shuffle is turned off', () {
      player.toggleShuffle();
      final out = player.upNext.first;
      player.removeUpNext(0);
      expect(player.queue.value, isNot(contains(out)));
      player.toggleShuffle();
      expect(player.queue.value, isNot(contains(out)));
      expect(player.queue.value, hasLength(4));
    });

    test('clearing up next keeps the song playing, and stays cleared', () {
      player.toggleShuffle();
      player.clearUpNext();
      expect(queue(), ['a']);
      expect(player.current?.id, 'a');
      player.toggleShuffle();
      expect(queue(), ['a'], reason: 'not back when shuffle is turned off');
    });
  });

  test('gives up after three tries and says so', () async {
    for (var i = 0; i < 4; i++) {
      audio.breakOff();
      await settle();
    }
    expect(audio.loads, hasLength(1 + 3));
    expect(player.error.value, contains('Song a'));
  });

  // It only ever said "Couldn't play": not whether to check the connection
  // or that the song itself is unavailable.
  test("a song that can't play says why, when that helps", () {
    final song = _song('a');
    expect(
      couldNotPlay(song, const SocketException('Failed host lookup')),
      'Couldn\'t play "Song a": no connection',
    );
    expect(
      couldNotPlay(song, const HttpException('This video is unavailable')),
      'Couldn\'t play "Song a": This video is unavailable',
    );
    expect(
      couldNotPlay(song, const HttpException('Audio stream: HTTP 403')),
      'Couldn\'t play "Song a"',
      reason: 'nothing the user can act on',
    );
  });
}
