import 'package:encore/models.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/player.dart';
import 'package:encore/ui/pages/collection_page.dart';
import 'package:encore/ui/pages/library_page.dart';
import 'package:encore/ui/shell.dart';
import 'package:encore/ui/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test.dart' show pumpApp;

// Liked songs, History, Downloads and playlists couldn't be searched or
// sorted: a long list meant scrolling for a song.

const _songs = [
  Track(id: 'a', title: 'Zebra', artist: 'Moby', album: 'Play', artUrl: ''),
  Track(id: 'b', title: 'Apple', artist: 'Coldplay', album: 'X', artUrl: ''),
  Track(id: 'c', title: 'Mango', artist: 'Adele', artUrl: ''),
];

List<String> _ids(List<Track> tracks) => [for (final t in tracks) t.id];

void main() {
  test('filters by title, artist or album, and sorts', () {
    expect(_ids(filterSongs(_songs, '', SongOrder.own)), ['a', 'b', 'c']);
    expect(_ids(filterSongs(_songs, 'cold', SongOrder.own)), ['b']);
    expect(_ids(filterSongs(_songs, 'play', SongOrder.own)), ['a', 'b']);
    expect(_ids(filterSongs(_songs, 'MOBY zeb', SongOrder.own)), ['a']);
    expect(_ids(filterSongs(_songs, '', SongOrder.title)), ['b', 'c', 'a']);
    expect(_ids(filterSongs(_songs, '', SongOrder.artist)), ['c', 'b', 'a']);
    expect(_ids(filterSongs(_songs, '', SongOrder.album)), [
      'a',
      'b',
      'c',
    ], reason: 'songs without an album last');
  });

  tearDown(() {
    userLibrary.liked.value = [];
    userLibrary.playlists.value = [];
    player.queue.value = [];
    player.index.value = -1;
  });

  for (final (where, size) in [
    ('phone', const Size(400, 860)),
    ('desktop', const Size(1400, 900)),
  ]) {
    testWidgets('$where: liked songs can be searched and sorted', (
      tester,
    ) async {
      userLibrary.liked.value = [..._songs];
      await pumpApp(tester, size);
      final liked = libraryCollections.first;
      openPage(liked.page(), tab: AppTab.library);
      await tester.pumpAndSettle();
      final tiles = find.byType(TrackTile);
      List<String> shown() => [
        for (final t in tester.widgetList<TrackTile>(tiles)) t.track.id,
      ];
      expect(shown(), ['a', 'b', 'c']);

      await tester.enterText(find.byType(TextField).last, 'cold');
      await tester.pumpAndSettle();
      expect(shown(), ['b']);
      await tester.enterText(find.byType(TextField).last, 'nothing');
      await tester.pumpAndSettle();
      expect(find.text('No songs match "nothing"'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(shown(), ['a', 'b', 'c']);

      await tester.tap(find.text('Recently added'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title').last);
      await tester.pumpAndSettle();
      expect(shown(), ['b', 'c', 'a']);

      // A song plays with the list as shown.
      await tester.tap(find.text('Mango'));
      await tester.pump();
      expect(_ids(player.queue.value), ['b', 'c', 'a']);
      expect(player.current?.id, 'c');
    });
  }

  testWidgets('a playlist is reordered only in its own order', (tester) async {
    final p = userLibrary.createPlaylist('Mix', tracks: [..._songs]);
    await pumpApp(tester, const Size(400, 860));
    openPage(CollectionPage.playlist(p.id), tab: AppTab.library);
    await tester.pumpAndSettle();
    final handles = find.byIcon(Icons.drag_handle_rounded);
    expect(handles, findsNWidgets(3));
    expect(find.text('Custom order'), findsOneWidget);

    await tester.tap(find.text('Custom order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Artist').last);
    await tester.pumpAndSettle();
    expect(handles, findsNothing, reason: 'sorted: no dragging');
    expect(_ids(userLibrary.playlist(p.id)!.tracks), ['a', 'b', 'c']);
  });
}
