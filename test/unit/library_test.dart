import 'dart:io';

import 'package:encore/models.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';

Track track(String id) =>
    Track(id: id, title: 'Song $id', artist: 'Artist', artUrl: '');

void main() {
  late UserLibrary library;

  setUp(() => library = UserLibrary());

  test('history puts the latest first without duplicates', () {
    library
      ..addPlayed(track('a'))
      ..addPlayed(track('b'))
      ..addPlayed(track('a'));
    expect(library.history.value.map((t) => t.id), ['a', 'b']);
  });

  test('history keeps the 200 most recent songs', () {
    for (var i = 0; i < 250; i++) {
      library.addPlayed(track('$i'));
    }
    expect(library.history.value, hasLength(200));
    expect(library.history.value.first.id, '249');
  });

  test('toggleLike adds then removes', () {
    final t = track('a');
    library.toggleLike(t);
    expect(library.isLiked(t), isTrue);
    library.toggleLike(t);
    expect(library.isLiked(t), isFalse);
  });

  test('recent searches are unique, newest first, at most 10', () {
    for (var i = 0; i < 12; i++) {
      library.addSearch('q$i');
    }
    library.addSearch('q5');
    expect(library.searches.value.first, 'q5');
    expect(library.searches.value, hasLength(10));
    expect(library.searches.value.where((q) => q == 'q5'), hasLength(1));
    library.removeSearch('q5');
    expect(library.searches.value, isNot(contains('q5')));
  });

  group('saving', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('encore_library_test');
      useDataDir(dir);
      file = File('${dir.path}${Platform.pathSeparator}library.json');
    });
    tearDown(() => dir.delete(recursive: true));

    Future<UserLibrary> loaded() async {
      final library = UserLibrary();
      await library.load();
      return library;
    }

    test('saves and loads again, replacing the old file', () async {
      final first = await loaded();
      first.toggleLike(track('a'));
      await first.saved;
      first
        ..addPlayed(track('b'))
        ..addSearch('daft punk');
      await first.saved;

      final second = await loaded();
      expect(second.liked.value.map((t) => t.id), ['a']);
      expect(second.history.value.map((t) => t.id), ['b']);
      expect(second.searches.value, ['daft punk']);
      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });

    test(
      'a crash between writing and swapping in keeps the new save',
      () async {
        // Killed after the temporary file was written, before the rename.
        await File('${file.path}.tmp').writeAsString(
          '{"liked": [${_json('a')}], "history": [], "searches": [], '
          '"downloads": []}',
        );
        final library = await loaded();
        expect(library.liked.value.map((t) => t.id), ['a']);
        expect(file.existsSync(), isTrue);
      },
    );

    test('an unreadable file is kept aside, not overwritten', () async {
      await file.writeAsString('{"liked": [${_json('a')}');
      final library = await loaded();
      expect(library.liked.value, isEmpty);
      library.toggleLike(track('b'));
      await library.saved;
      expect(
        File('${file.path}.unreadable').readAsStringSync(),
        contains('"a"'),
        reason: 'the old data is still there to recover',
      );
      expect((await loaded()).liked.value.map((t) => t.id), ['b']);
    });
  });
}

String _json(String id) =>
    '{"id": "$id", "title": "Song $id", "artist": "Artist", "artUrl": ""}';
