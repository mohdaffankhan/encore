import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'player.dart';

final sleepTimer = SleepTimer(() => player.audio);

/// What the sleep timer is set to: a time, or the end of the current song.
class SleepSetting {
  const SleepSetting.at(DateTime this.time);
  const SleepSetting.endOfSong() : time = null;

  final DateTime? time;

  bool get endOfSong => time == null;
}

/// Pauses playback after a set time (fading out first), or when the
/// current song ends.
class SleepTimer {
  SleepTimer(this._audio);

  final AudioPlayer Function() _audio;

  /// Null when the timer is off.
  final setting = ValueNotifier<SleepSetting?>(null);

  Timer? _timer;

  static const _fade = Duration(seconds: 10);

  void set(Duration duration) {
    cancel();
    setting.value = SleepSetting.at(DateTime.now().add(duration));
    late final Timer timer;
    timer = Timer(duration > _fade ? duration - _fade : Duration.zero, () {
      _fadeOutAndPause(timer);
    });
    _timer = timer;
  }

  void untilEndOfSong() {
    cancel();
    setting.value = const SleepSetting.endOfSong();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    setting.value = null;
  }

  /// Time left, or null when off or set to the end of the song.
  Duration? get remaining => switch (setting.value?.time) {
    final time? => time.difference(DateTime.now()),
    null => null,
  };

  /// Called by the player when a song finishes: true (and the timer turns
  /// off) if playback should pause here.
  bool takeEndOfSong() {
    if (setting.value?.endOfSong != true) return false;
    cancel();
    return true;
  }

  Future<void> _fadeOutAndPause(Timer timer) async {
    final audio = _audio();
    final volume = audio.volume;
    // Turned off or set again mid-fade: stop fading.
    bool current() => identical(_timer, timer);
    const steps = 20;
    for (var i = 1; i <= steps && audio.playing && current(); i++) {
      await Future<void>.delayed(_fade ~/ steps);
      if (current()) await audio.setVolume(volume * (1 - i / steps));
    }
    if (current()) {
      await audio.pause();
      cancel();
    }
    await audio.setVolume(volume);
  }
}
