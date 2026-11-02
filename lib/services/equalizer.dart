import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'settings.dart';

/// Android's own equalizer, part of the player's audio pipeline (see
/// player.dart); null elsewhere.
final AndroidEqualizer? androidEqualizer = Platform.isAndroid
    ? AndroidEqualizer()
    : null;

final equalizer = Equalizer();

/// A five-band equalizer: Android's system equalizer on phones, FFmpeg's
/// `equalizer` filter (built into mpv) on desktop. Its settings live in
/// [Settings.equalizerOn] and [Settings.equalizerGains].
class Equalizer {
  /// The bands' centres, in Hz: Android's usual five.
  static const bands = [60, 230, 910, 3600, 14000];

  /// How far a band goes either way, in dB.
  static const maxGain = 12.0;

  /// Gains for each band, by name.
  static const presets = <String, List<double>>{
    'Flat': [0, 0, 0, 0, 0],
    'Bass boost': [6, 4, 0, 0, 0],
    'Treble boost': [0, 0, 0, 4, 6],
    'Vocal': [-2, 0, 4, 3, 0],
    'Rock': [5, 2, -2, 2, 5],
    'Pop': [-1, 2, 4, 2, -1],
    'Electronic': [5, 3, 0, 2, 4],
    'Acoustic': [3, 1, 1, 2, 3],
  };

  /// The preset [gains] match, if any.
  static String? presetFor(List<double> gains) {
    for (final MapEntry(:key, :value) in presets.entries) {
      if (listEquals(value, gains)) return key;
    }
    return null;
  }

  /// mpv's audio filter for [gains] (FFmpeg's `equalizer`, one per band,
  /// two octaves wide); empty when it would change nothing.
  static String mpvFilter(List<double> gains) {
    if (gains.every((g) => g == 0)) return '';
    final filters = [
      for (final (i, g) in gains.indexed)
        if (g != 0) 'equalizer=f=${bands[i]}:t=o:w=2:g=${_db(g)}',
    ];
    return 'lavfi=[${filters.join(',')}]';
  }

  static String _db(double g) =>
      g == g.roundToDouble() ? '${g.toInt()}' : g.toStringAsFixed(1);

  /// Sets desktop players' filters; replaced in tests.
  @visibleForTesting
  Future<void> Function(String filter) setMpvFilter =
      JustAudioMediaKit.setAudioFilter;

  bool _started = false;

  /// Applies the settings now and whenever they change.
  void start() {
    if (_started) return;
    _started = true;
    settings.equalizerOn.addListener(_apply);
    settings.equalizerGains.addListener(_apply);
    _apply();
  }

  /// The gains in effect: none while it is off.
  List<double> get _gains => settings.equalizerOn.value
      ? settings.equalizerGains.value
      : List.filled(bands.length, 0);

  void _apply() {
    final gains = _gains;
    if (androidEqualizer case final eq?) {
      unawaited(_applyAndroid(eq, gains));
    } else {
      unawaited(
        setMpvFilter(mpvFilter(gains)).catchError((Object e) {
          debugPrint('Equalizer (mpv) failed: $e');
        }),
      );
    }
  }

  /// Each of the phone's bands takes the gain of our band nearest to it
  /// (phones may have other bands), within what the phone allows.
  Future<void> _applyAndroid(AndroidEqualizer eq, List<double> gains) async {
    try {
      await eq.setEnabled(settings.equalizerOn.value);
      // Known once the player has been used (it says what bands it has).
      final params = await eq.parameters;
      for (final band in params.bands) {
        final nearest = _nearestBand(band.centerFrequency);
        await band.setGain(
          gains[nearest].clamp(params.minDecibels, params.maxDecibels),
        );
      }
    } catch (e) {
      debugPrint('Equalizer (Android) failed: $e');
    }
  }

  /// Our band nearest [hz] (on a log scale, as hearing is).
  static int _nearestBand(double hz) {
    var best = 0;
    for (var i = 1; i < bands.length; i++) {
      if ((log(bands[i]) - log(hz)).abs() <
          (log(bands[best]) - log(hz)).abs()) {
        best = i;
      }
    }
    return best;
  }
}
