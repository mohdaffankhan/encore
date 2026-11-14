// By hand: the latest release on GitHub is read, and its Windows installer
// and Android APK download and match GitHub's checksums (nothing installed).
//   flutter test test/live/update_live_test.dart
import 'dart:io';

import 'package:encore/services/updates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the latest release downloads, checked', () async {
    final u = Updates();
    final release = await u.latest();
    expect(release, isNotNull);
    // ignore: avoid_print
    print('latest: ${release!.version}, ${release.notes.length} notes, '
        'files ${release.files.keys.join(', ')}');
    final dir = await Directory.systemTemp.createTemp('encore_update_live');
    addTearDown(() => dir.delete(recursive: true));
    for (final name in ['encore-windows-setup.exe', 'encore-android-arm64-v8a.apk']) {
      final file = release.files[name]!;
      expect(file.sha256, isNotNull, reason: 'GitHub gives a checksum');
      final got = await u.download(file, dir: dir);
      expect(await got.length(), file.size);
      // ignore: avoid_print
      print('$name: ${file.size} bytes, checksum matches');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
