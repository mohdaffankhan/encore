import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import 'storage.dart';

final settings = Settings();

/// The user's settings, kept in a small file of their own.
class Settings {
  final streamQuality = ValueNotifier(AudioQuality.high);

  /// Android: stream at [AudioQuality.low] on mobile data (a metered
  /// network), whatever [streamQuality] says.
  final saveDataOnMobile = ValueNotifier(true);

  final downloadQuality = ValueNotifier(AudioQuality.high);

  /// Windows: closing the window keeps the music playing in the tray.
  final closeToTray = ValueNotifier(true);

  /// How fast songs play (1 is normal), at the same pitch.
  final speed = ValueNotifier(1.0);

  /// The name of the app's theme (one of `encoreThemes`).
  final theme = ValueNotifier('Ember');

  /// The speeds offered.
  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  late final _all = <String, ValueNotifier<Object>>{
    'streamQuality': streamQuality,
    'saveDataOnMobile': saveDataOnMobile,
    'downloadQuality': downloadQuality,
    'closeToTray': closeToTray,
    'speed': speed,
    'theme': theme,
  };

  File? _file;
  Future<void> _lastWrite = Future.value();

  /// Completes when every change so far is saved.
  @visibleForTesting
  Future<void> get saved => _lastWrite;

  Future<void> load() async {
    final file = _file = File(
      '${(await dataDir()).path}${Platform.pathSeparator}settings.json',
    );
    try {
      final json = jsonDecode(await file.readAsString()) as Map;
      AudioQuality quality(String key) =>
          AudioQuality.values.asNameMap()[json[key]] ?? AudioQuality.high;
      streamQuality.value = quality('streamQuality');
      downloadQuality.value = quality('downloadQuality');
      if (json['saveDataOnMobile'] case final bool save) {
        saveDataOnMobile.value = save;
      }
      if (json['closeToTray'] case final bool tray) closeToTray.value = tray;
      if (json['theme'] case final String name) theme.value = name;
      if (json['speed'] case final num s when speeds.contains(s.toDouble())) {
        speed.value = s.toDouble();
      }
    } on PathNotFoundException {
      // Never changed: the defaults.
    } catch (e) {
      debugPrint('Settings unreadable, using the defaults: $e');
    }
    for (final setting in _all.values) {
      setting.addListener(_save);
    }
  }

  void _save() {
    final file = _file;
    if (file == null) return;
    final json = jsonEncode({
      for (final MapEntry(:key, :value) in _all.entries)
        key: switch (value.value) {
          AudioQuality q => q.name,
          final other => other,
        },
    });
    _lastWrite = _lastWrite.then((_) async {
      try {
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(json, flush: true);
        await temp.rename(file.path);
      } catch (e) {
        debugPrint('Saving settings failed: $e');
      }
    });
  }

  /// The quality to stream at now: lower on mobile data if so set.
  Future<AudioQuality> streamingQuality() async =>
      saveDataOnMobile.value && await onMobileData()
      ? AudioQuality.low
      : streamQuality.value;
}

const _network = MethodChannel('dev.encore.app/network');

/// Android: whether the phone is on a metered network (mobile data, or a
/// hotspot). Desktops: never.
Future<bool> onMobileData() async {
  if (!Platform.isAndroid) return false;
  try {
    return await _network.invokeMethod<bool>('isMetered') ?? false;
  } catch (e) {
    debugPrint('Network type unknown: $e');
    return false;
  }
}
