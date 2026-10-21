import 'package:encore/services/sleep_timer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

/// Just the parts of the player the sleep timer uses.
class _FakeAudio implements AudioPlayer {
  @override
  bool playing = true;
  @override
  double volume = 0.8;
  final volumes = <double>[];

  @override
  Future<void> pause() async => playing = false;

  @override
  Future<void> setVolume(double v) async => volumes.add(volume = v);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeAudio audio;
  late SleepTimer timer;

  setUp(() {
    audio = _FakeAudio();
    timer = SleepTimer(() => audio);
  });

  test('pauses after the set time, fading out, then restores volume', () {
    fakeAsync((async) {
      timer.set(const Duration(minutes: 15));
      expect(timer.remaining!.inMinutes, 14);

      async.elapse(const Duration(minutes: 14, seconds: 49));
      expect(audio.playing, isTrue, reason: 'not yet');
      expect(audio.volumes, isEmpty);

      async.elapse(const Duration(seconds: 6));
      expect(audio.playing, isTrue, reason: 'fading');
      expect(audio.volume, lessThan(0.8));

      async.elapse(const Duration(seconds: 6));
      expect(audio.playing, isFalse);
      expect(audio.volume, 0.8, reason: 'volume is given back');
      expect(audio.volumes.reduce((a, b) => a < b ? a : b), lessThan(0.1));
      expect(timer.setting.value, isNull, reason: 'turns itself off');
    });
  });

  test('turning it off stops it, even mid-fade', () {
    fakeAsync((async) {
      timer.set(const Duration(minutes: 15));
      async.elapse(const Duration(minutes: 5));
      timer.cancel();
      async.elapse(const Duration(hours: 1));
      expect(audio.playing, isTrue);
      expect(audio.volumes, isEmpty);

      timer.set(const Duration(minutes: 15));
      async.elapse(const Duration(minutes: 14, seconds: 55));
      timer.cancel();
      async.elapse(const Duration(minutes: 1));
      expect(audio.playing, isTrue);
      expect(audio.volume, 0.8);
    });
  });

  test('setting a new time mid-fade starts over', () {
    fakeAsync((async) {
      timer.set(const Duration(minutes: 15));
      async.elapse(const Duration(minutes: 14, seconds: 55));
      timer.set(const Duration(minutes: 30));
      async.elapse(const Duration(minutes: 1));
      expect(audio.playing, isTrue, reason: 'old fade stopped');
      expect(audio.volume, 0.8);
      async.elapse(const Duration(minutes: 30));
      expect(audio.playing, isFalse, reason: 'new time applies');
      expect(audio.volume, 0.8);
    });
  });

  test('when already paused, it just turns off at the time', () {
    fakeAsync((async) {
      audio.playing = false;
      timer.set(const Duration(minutes: 15));
      async.elapse(const Duration(minutes: 16));
      expect(audio.playing, isFalse);
      expect(audio.volume, 0.8);
      expect(timer.setting.value, isNull);
    });
  });

  test('end of song: pauses once, at the next song end only', () {
    expect(timer.takeEndOfSong(), isFalse, reason: 'off');
    timer.set(const Duration(minutes: 15));
    expect(timer.takeEndOfSong(), isFalse, reason: 'timed, not end of song');

    timer.untilEndOfSong();
    expect(timer.setting.value!.endOfSong, isTrue);
    expect(timer.remaining, isNull);
    expect(timer.takeEndOfSong(), isTrue);
    expect(timer.setting.value, isNull);
    expect(timer.takeEndOfSong(), isFalse, reason: 'only once');
  });

  test('end of song replaces a timed setting', () {
    fakeAsync((async) {
      timer.set(const Duration(minutes: 15));
      timer.untilEndOfSong();
      async.elapse(const Duration(hours: 1));
      expect(audio.playing, isTrue, reason: 'the timed one is gone');
      expect(timer.setting.value!.endOfSong, isTrue);
    });
  });
}
