import 'package:encore/models.dart';
import 'package:encore/services/library.dart';
import 'package:encore/ui/pages/collection_page.dart';
import 'package:encore/ui/pages/import_page.dart';
import 'package:encore/ui/pages/library_page.dart';
import 'package:encore/ui/shell.dart';
import 'package:encore/ui/widgets/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test.dart' show pumpApp;

// Playlists: making them, adding songs, changing them, and opening the
// import page. Offline: the import itself is checked by test/live and e2e.

Track _song(String id) =>
    Track(id: id, title: 'Song $id', artist: 'Artist $id', artUrl: '');

const _phone = Size(400, 860);
const _desktop = Size(1400, 900);

Future<void> _typeName(WidgetTester tester, String name) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    name,
  );
  await tester.pump();
}

Future<void> _openPlaylist(WidgetTester tester, Playlist p) async {
  openPage(CollectionPage.playlist(p.id), tab: AppTab.library);
  await tester.pumpAndSettle();
}

List<String> _ids(String id) =>
    userLibrary.playlist(id)!.tracks.map((t) => t.id).toList();

void main() {
  tearDown(() {
    userLibrary.playlists.value = [];
    userLibrary.liked.value = [];
  });

  testWidgets('New playlist: name it, it opens, and Library lists it', (
    tester,
  ) async {
    await pumpApp(tester, _phone);
    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Make your own playlists'), findsOneWidget);
    await tester.tap(find.text('New playlist'));
    await tester.pumpAndSettle();
    final create = find.widgetWithText(FilledButton, 'Create');
    expect(
      tester.widget<FilledButton>(create).onPressed,
      isNull,
      reason: 'no empty names',
    );
    await _typeName(tester, 'Road trip');
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.text('PLAYLIST'), findsOneWidget);
    expect(find.text('Road trip'), findsOneWidget);
    expect(find.textContaining("from a song's ⋯ menu"), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Road trip'), findsOneWidget, reason: 'in Library');
  });

  testWidgets('one song is "1 song", not "1 songs"', (tester) async {
    userLibrary.liked.value = [_song('a')];
    userLibrary.createPlaylist('Mix', tracks: [_song('a')]);
    await pumpApp(tester, _phone);
    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    expect(find.text('1 song'), findsNWidgets(2), reason: 'liked, playlist');
    expect(find.textContaining('1 songs'), findsNothing);
  });

  testWidgets('desktop: the sidebar lists playlists and makes new ones', (
    tester,
  ) async {
    userLibrary.createPlaylist('Focus');
    await pumpApp(tester, _desktop);
    expect(find.text('PLAYLISTS'), findsOneWidget);
    expect(find.text('Focus'), findsOneWidget);
    await tester.tap(find.byTooltip('New playlist'));
    await tester.pumpAndSettle();
    await _typeName(tester, 'Gym');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(userLibrary.playlists.value.first.name, 'Gym');
    expect(find.text('Gym'), findsWidgets, reason: 'sidebar and page');
  });

  for (final (name, size) in [('phone', _phone), ('desktop', _desktop)]) {
    testWidgets('$name: Add to playlist from a song\'s menu', (tester) async {
      final mix = userLibrary.createPlaylist('Mix');
      userLibrary.liked.value = [_song('a')];
      await pumpApp(tester, size);
      openPage(libraryCollections.first.page(), tab: AppTab.library);
      await tester.pumpAndSettle();

      Future<void> addTo(String playlist) async {
        await tester.tap(find.byTooltip('More').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add to playlist'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(playlist).last);
        await tester.pumpAndSettle();
      }

      await addTo('Mix');
      expect(find.text('Added to Mix'), findsOneWidget);
      expect(_ids(mix.id), ['a']);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await addTo('Mix');
      expect(find.text('Already in Mix'), findsOneWidget);
      expect(_ids(mix.id), ['a']);

      // Or into a new one, named on the spot.
      await addTo('New playlist');
      await _typeName(tester, 'Fresh');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(userLibrary.playlists.value.first.name, 'Fresh');
      expect(_ids(userLibrary.playlists.value.first.id), ['a']);
    });
  }

  testWidgets('a song can be removed from the playlist', (tester) async {
    final p = userLibrary.createPlaylist(
      'Mix',
      tracks: [_song('a'), _song('b')],
    );
    await pumpApp(tester, _phone);
    await _openPlaylist(tester, p);
    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from this playlist'));
    await tester.pumpAndSettle();
    expect(_ids(p.id), ['b']);
    expect(find.text('Song a'), findsNothing);
  });

  for (final (name, size) in [('phone', _phone), ('desktop', _desktop)]) {
    testWidgets('$name: songs are reordered by dragging the handle', (
      tester,
    ) async {
      final p = userLibrary.createPlaylist(
        'Mix',
        tracks: [_song('a'), _song('b'), _song('c')],
      );
      await pumpApp(tester, size);
      await _openPlaylist(tester, p);
      final handle = find.byIcon(Icons.drag_handle_rounded);
      final row = tester.getSize(find.byType(TrackTile).first).height;
      final gesture = await tester.startGesture(tester.getCenter(handle.first));
      await tester.pump(kLongPressTimeout);
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(Offset(0, row * 2.2 / 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_ids(p.id), ['b', 'c', 'a']);
    });
  }

  testWidgets('rename, then delete (after asking)', (tester) async {
    final p = userLibrary.createPlaylist('Mix', tracks: [_song('a')]);
    await pumpApp(tester, _phone);
    await _openPlaylist(tester, p);
    await tester.tap(find.byTooltip('Playlist options'));
    await tester.pumpAndSettle();
    expect(find.text('Open in YouTube'), findsOneWidget);
    expect(find.text('Copy song list'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await _typeName(tester, 'Evening');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(userLibrary.playlist(p.id)!.name, 'Evening');
    expect(find.text('Evening'), findsOneWidget);

    await tester.tap(find.byTooltip('Playlist options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(userLibrary.playlist(p.id), isNotNull, reason: 'cancelled');

    await tester.tap(find.byTooltip('Playlist options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(userLibrary.playlist(p.id), isNull);
    expect(find.byType(CollectionPage), findsNothing, reason: 'page closed');
  });

  testWidgets('Copy song list copies "Title - Artist" lines', (tester) async {
    final p = userLibrary.createPlaylist(
      'Mix',
      tracks: [_song('a'), _song('b')],
    );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'];
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpApp(tester, _desktop);
    await _openPlaylist(tester, p);
    await tester.tap(find.byTooltip('Playlist options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy song list'));
    await tester.pumpAndSettle();
    expect(copied, 'Song a - Artist a\nSong b - Artist b');
    expect(find.text('Copied 2 songs'), findsOneWidget);
  });

  group('import page', () {
    // (The Search tab's box is in the tree too, behind this tab.)
    final linkField = find.descendant(
      of: find.byType(ImportPage),
      matching: find.byType(TextField),
    );

    Future<void> openImport(WidgetTester tester) async {
      await pumpApp(tester, _phone);
      await tester.tap(find.text('Library').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import playlist'));
      await tester.pumpAndSettle();
    }

    testWidgets('a link that isn\'t a playlist says so', (tester) async {
      await openImport(tester);
      await tester.enterText(linkField, 'https://youtu.be/abc');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();
      expect(find.textContaining("isn't a playlist link"), findsOneWidget);
    });

    testWidgets('a failed import keeps the link, with the reason', (
      tester,
    ) async {
      const link = 'https://open.spotify.com/playlist/6fGsXMDMl4nueTKDXxyKxt';
      await openImport(tester);
      await tester.enterText(linkField, link);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('private'), findsWidgets);
      expect(find.text(link), findsOneWidget);
      expect(userLibrary.playlists.value, isEmpty);
    });

    testWidgets('pasting a playlist link into search opens the import', (
      tester,
    ) async {
      await pumpApp(tester, _phone);
      await tester.tap(find.text('Search').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'https://open.spotify.com/playlist/6fGsXMDMl4nueTKDXxyKxt?si=x',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(find.byType(ImportPage), findsOneWidget);
      expect(userLibrary.searches.value, isEmpty);
    });
  });
}
