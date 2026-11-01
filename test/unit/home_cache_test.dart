import 'dart:io';

import 'package:encore/models.dart';
import 'package:encore/services/home_cache.dart';
import 'package:encore/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';

// Every launch showed a spinner until the home feed loaded, and offline
// only an error: the last feed is kept to show meanwhile.

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('encore_home');
    useDataDir(dir);
    lastHome = null;
  });

  tearDown(() => dir.delete(recursive: true));

  test('the last home feed is there the next time', () async {
    const song = Track(
      id: 's',
      title: 'Song',
      artist: 'Artist',
      duration: Duration(minutes: 3),
      artUrl: 'https://art/s',
    );
    const album = MediaRef(
      kind: MediaKind.album,
      id: 'MPREb_a',
      title: 'Album',
      subtitle: 'Album • Artist',
      artUrl: 'https://art/a',
    );
    await saveHome([
      const Shelf('Quick picks', tracks: [song]),
      const Shelf('Albums', cards: [album, song]),
    ]);
    lastHome = null;
    await loadLastHome();
    final shelves = lastHome!;
    expect(shelves.map((s) => s.title), ['Quick picks', 'Albums']);
    expect(shelves[0].tracks, [song]);
    final [card, video] = shelves[1].cards;
    expect((card as MediaRef).kind, MediaKind.album);
    expect(card.title, 'Album');
    expect(video, song);
  });

  test('a damaged file is ignored', () async {
    await File('${dir.path}/home.json').writeAsString('[{"title"');
    await loadLastHome();
    expect(lastHome, isNull);
  });
}
