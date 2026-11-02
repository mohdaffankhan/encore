import 'dart:async';
import 'dart:io';

import 'package:encore/models.dart';
import 'package:encore/services/download_notice.dart';
import 'package:encore/services/downloads.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Downloads stopped when Encore was closed on Android, and showed no
// progress outside the app: Android's notification shows "n of total"
// with the song and a bar, and says how many were saved at the end. It
// posted every 5% of every song, several a second, which Android drops.

Track _song(String id) =>
    Track(id: id, title: 'Song $id', artist: 'Artist', artUrl: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final calls = <MethodCall>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('encore_notice');
    useDataDir(dir);
    userLibrary.downloads.value = [];
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DownloadNotice.channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() => dir.delete(recursive: true));

  test('shows each song as n of total, then how many were saved', () async {
    final gates = {
      for (final id in ['a', 'b', 'c']) id: Completer<void>(),
    };
    final downloads = Downloads()
      ..fetch = (t) async {
        if (t.id == 'b') throw const HttpException('refused');
        await gates[t.id]!.future;
      };
    final notice = DownloadNotice(downloads)..start();
    addTearDown(notice.stop);
    var clock = DateTime(2026);
    notice.now = () => clock;

    downloads.download([_song('a'), _song('b'), _song('c')]);
    await Future<void>.delayed(Duration.zero);
    expect(calls.last.method, 'progress');
    expect(calls.last.arguments, {
      'title': 'Song a',
      'number': 1,
      'total': 3,
      'percent': 0,
    });

    // A fast download reports every 5%: the bar moves at most once a
    // second (Android drops a notification's updates beyond a few a
    // second).
    final sent = calls.length;
    for (var p = 0.05; p < 1; p += 0.05) {
      downloads.progress.value = {...downloads.progress.value, 'a': p};
    }
    expect(calls, hasLength(sent), reason: 'within the same second');
    clock = clock.add(const Duration(seconds: 1));
    downloads.progress.value = {...downloads.progress.value, 'a': 0.5};
    expect(calls, hasLength(sent + 1));
    expect(calls.last.arguments, containsPair('percent', 50));

    gates['a']!.complete();
    await Future<void>.delayed(Duration.zero);
    // b failed straight away; c is the third of three.
    expect(calls.last.arguments, containsPair('title', 'Song c'));
    expect(calls.last.arguments, containsPair('number', 3));
    expect(calls.last.arguments, containsPair('total', 3));

    gates['c']!.complete();
    while (downloads.progress.value.isNotEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(calls.last.method, 'finished');
    expect(calls.last.arguments, containsPair('done', 2));
    expect(calls.last.arguments, containsPair('failed', 1));
    expect(calls.where((c) => c.method == 'finished'), hasLength(1));

    // A new batch counts from the start again.
    gates['d'] = Completer<void>();
    downloads.download([_song('d')]);
    await Future<void>.delayed(Duration.zero);
    expect(calls.last.arguments, containsPair('number', 1));
    expect(calls.last.arguments, containsPair('total', 1));
    gates['d']!.complete();
    while (downloads.progress.value.isNotEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await downloads.saved;
  });
}
