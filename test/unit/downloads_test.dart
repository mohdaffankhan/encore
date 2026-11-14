import 'dart:async';
import 'dart:io';
import 'dart:math';

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

  // Settings: free up space.
  test('every download can be removed at once, with its file', () async {
    final folder = await Directory('${dir.path}/downloads').create();
    for (final id in ['a', 'b']) {
      await File('${folder.path}/$id').writeAsString('audio $id');
    }
    userLibrary.downloads.value = [_song('a'), _song('b')];
    final downloads = Downloads();
    expect(await downloads.size(), greaterThan(0));
    await downloads.removeAll();
    expect(userLibrary.downloads.value, isEmpty);
    expect(await downloads.size(), 0);
  });

  Future<void> allDone(Downloads d) async {
    while (d.progress.value.isNotEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await d.saved;
  }

  test('a few download at once (one at a time was slow), never more', () async {
    var now = 0, most = 0;
    final d = Downloads()
      ..fetch = (t) async {
        most = max(most, ++now);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        now--;
      };
    d.download([for (var i = 0; i < 10; i++) _song('s$i')]);
    await allDone(d);
    expect(most, Downloads.parallel);
    expect(userLibrary.downloads.value, hasLength(10));
  });

  test('songs that fail are said once, all together (not one message each)',
      () async {
    final said = <String?>[];
    final d = Downloads()
      ..fetch = (t) async {
        if (t.id != 'ok') throw const SocketException('offline');
      };
    d.error.addListener(() => said.add(d.error.value));
    d.download([for (final id in ['a', 'b', 'ok', 'c']) _song(id)]);
    await allDone(d);
    expect(said, ["Couldn't download 3 songs"]);
    expect(d.notDone, 3);
    expect(d.done, 1);
  });

  test('one song failing is named', () async {
    final d = Downloads()..fetch = (t) async => throw const SocketException('x');
    d.download([_song('a')]);
    await allDone(d);
    expect(d.error.value, "Couldn't download \"Song a\"");
  });

  test('songs added while others download join in', () async {
    final gate = Completer<void>();
    final fetched = <String>[];
    final d = Downloads()
      ..fetch = (t) async {
        await gate.future;
        fetched.add(t.id);
      };
    d.download([_song('a')]);
    await Future<void>.delayed(Duration.zero);
    d.download([_song('b'), _song('c')]);
    gate.complete();
    await allDone(d);
    expect(fetched.toSet(), {'a', 'b', 'c'});
  });

  test('those downloading when the app closed carry on too', () async {
    final before = Downloads()..fetch = (_) => Completer<void>().future;
    before.download([for (final id in ['a', 'b', 'c', 'd', 'e']) _song(id)]);
    await Future<void>.delayed(Duration.zero);
    await before.saved;
    final fetched = <String>[];
    final after = Downloads()..fetch = (t) async => fetched.add(t.id);
    await after.resume();
    await allDone(after);
    expect(fetched.toSet(), {'a', 'b', 'c', 'd', 'e'});
  });
}

