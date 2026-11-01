import 'dart:io';

import 'package:encore/api/stream.dart';
import 'package:encore/models.dart';
import 'package:encore/services/settings.dart';
import 'package:encore/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('quality', () {
    // What YouTube offers for a song (Opus and AAC, in bits per second).
    final formats = [
      {'itag': 140, 'bitrate': 130000},
      {'itag': 249, 'bitrate': 52000},
      {'itag': 251, 'bitrate': 140000},
      {'itag': 250, 'bitrate': 70000},
      {'itag': 139, 'bitrate': 49000},
    ];

    int itag(AudioQuality q) => pickFormat(formats, q)['itag'] as int;

    test('high is the best, low the least data, normal in between', () {
      expect(itag(AudioQuality.high), 251);
      expect(itag(AudioQuality.normal), 250);
      expect(itag(AudioQuality.low), 139);
    });

    test('normal takes the lowest when nothing is that low', () {
      final rich = [
        {'itag': 251, 'bitrate': 140000},
        {'itag': 140, 'bitrate': 130000},
      ];
      expect(pickFormat(rich, AudioQuality.normal)['itag'], 140);
    });
  });

  group('saving', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('encore_settings');
      useDataDir(dir);
    });

    tearDown(() => dir.delete(recursive: true));

    test('settings are there the next time', () async {
      final before = Settings();
      await before.load();
      before.streamQuality.value = AudioQuality.low;
      before.downloadQuality.value = AudioQuality.normal;
      before.saveDataOnMobile.value = false;
      await before.saved;

      final after = Settings();
      await after.load();
      expect(after.streamQuality.value, AudioQuality.low);
      expect(after.downloadQuality.value, AudioQuality.normal);
      expect(after.saveDataOnMobile.value, isFalse);
    });

    test('a damaged file leaves the defaults', () async {
      await File('${dir.path}/settings.json').writeAsString('{"stream');
      final settings = Settings();
      await settings.load();
      expect(settings.streamQuality.value, AudioQuality.high);
    });

    test('desktops stream at the chosen quality', () async {
      final settings = Settings()..streamQuality.value = AudioQuality.normal;
      expect(await settings.streamingQuality(), AudioQuality.normal);
    });
  });
}
