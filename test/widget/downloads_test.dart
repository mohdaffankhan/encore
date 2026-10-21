import 'dart:io';

import 'package:encore/models.dart';
import 'package:encore/services/downloads.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';

// A widget test so that all network requests fail (status 400), like a
// download going wrong.

void main() {
  const track = Track(id: 'abc', title: 'A Song', artist: 'X', artUrl: '');
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('encore_downloads_test');
    useDataDir(dir);
  });
  tearDown(() async {
    userLibrary.downloads.value = [];
    downloads.error.value = null;
    await dir.delete(recursive: true);
  });

  List<String> files() => Directory('${dir.path}/downloads').existsSync()
      ? Directory('${dir.path}/downloads')
            .listSync()
            .map((f) => f.uri.pathSegments.last)
            .toList()
      : [];

  testWidgets('a failed download says so and leaves nothing behind', (
    tester,
  ) async {
    await tester.runAsync(() async {
      downloads.download([track]);
      expect(downloads.progress.value, contains('abc'));
      while (downloads.progress.value.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    expect(downloads.error.value, 'Couldn\'t download "A Song"');
    expect(downloads.isDownloaded(track), isFalse);
    expect(files(), isEmpty);
  });

  testWidgets('removing a download whose file is in use does not throw', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final folder = await Directory('${dir.path}/downloads').create();
      final file = File('${folder.path}/abc');
      await file.writeAsString('audio');
      userLibrary.downloads.value = [track];
      // Hold it open, as the player does while it plays (on Windows this
      // blocks deleting it).
      final open = await file.open();
      try {
        await downloads.remove(track);
      } finally {
        await open.close();
      }
    });
    expect(downloads.isDownloaded(track), isFalse);
  });
}
