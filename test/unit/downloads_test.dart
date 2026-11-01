import 'dart:async';
import 'dart:io';

import 'package:encore/models.dart';
import 'package:encore/services/downloads.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';

// Downloading an album and closing the app lost every song not downloaded
// yet, with nothing said: they carry on the next time.

Track _song(String id) =>
    Track(id: id, title: 'Song $id', artist: 'Artist', artUrl: '');

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('encore_downloads');
    useDataDir(dir);
    userLibrary.downloads.value = [];
  });

  tearDown(() => dir.delete(recursive: true));

  test('downloads not done when the app closed carry on next time', () async {
    final before = Downloads()..fetch = (_) => Completer<void>().future;
    before.download([_song('a'), _song('b'), _song('c')]);
    await before.saved;

    final fetched = <String>[];
    final after = Downloads()..fetch = (t) async => fetched.add(t.id);
    await after.resume();
    while (after.progress.value.isNotEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await after.saved;
    expect(fetched, ['a', 'b', 'c']);
    expect(userLibrary.downloads.value.map((t) => t.id), ['c', 'b', 'a']);

    final again = Downloads()..fetch = (t) async => fetched.add(t.id);
    await again.resume();
    expect(fetched, hasLength(3), reason: 'nothing left to download');
  });
}
