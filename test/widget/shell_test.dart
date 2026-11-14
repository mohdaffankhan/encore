import 'package:encore/app.dart';
import 'package:encore/models.dart';
import 'package:encore/services/home_cache.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/player.dart';
import 'package:encore/ui/pages/collection_page.dart';
import 'package:encore/ui/pages/settings_page.dart';
import 'package:encore/ui/shell.dart';
import 'package:encore/ui/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Widget tests run without network (every request fails), so these also
// check that the app degrades gracefully when offline.

Future<void> pumpApp(WidgetTester tester, Size size) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const EncoreApp());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desktop: sidebar with library links, no bottom bar', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1400, 900));
    expect(find.byType(EncoreWordmark), findsOneWidget);
    expect(find.text('Liked songs'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('a problem found before the app shows is shown', (tester) async {
    userLibrary.error.value = "Your library couldn't be read";
    await pumpApp(tester, const Size(400, 860));
    expect(find.text("Your library couldn't be read"), findsOneWidget);
    expect(userLibrary.error.value, isNull, reason: 'shown once');
  });

  testWidgets('phone: bottom navigation, no sidebar', (tester) async {
    await pumpApp(tester, const Size(400, 860));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(EncoreWordmark), findsNothing);
  });

  testWidgets('home shows a retry message when offline', (tester) async {
    await pumpApp(tester, const Size(400, 860));
    expect(find.text("Couldn't load your home feed."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('offline, home shows the feed from last time', (tester) async {
    lastHome = [
      const Shelf(
        'Quick picks',
        tracks: [Track(id: 's', title: 'Kept song', artist: 'A', artUrl: '')],
      ),
    ];
    addTearDown(() => lastHome = null);
    await pumpApp(tester, const Size(400, 860));
    expect(find.text('Kept song'), findsOneWidget);
    expect(find.text("Couldn't refresh your home feed"), findsOneWidget);
    expect(find.text("Couldn't load your home feed."), findsNothing);
  });

  testWidgets('phone: the gear on home opens settings', (tester) async {
    await pumpApp(tester, const Size(400, 860));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Streaming quality'), findsOneWidget);
  });

  testWidgets('library opens an empty liked songs page', (tester) async {
    await pumpApp(tester, const Size(400, 860));
    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Liked songs'));
    await tester.pumpAndSettle();
    expect(find.text('COLLECTION'), findsOneWidget);
    expect(find.text('No songs here yet'), findsOneWidget);
    // Back returns to the library, keeping the navigation visible.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Liked songs'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('search shows the empty state before typing', (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    await tester.tap(find.text('Search').first);
    await tester.pumpAndSettle();
    expect(find.text('Find songs, albums and artists'), findsOneWidget);
  });
  // Settings opened on top of whichever tab was showing, so that tab kept
  // showing it: Home and Library seemed stuck on Settings.
  testWidgets('desktop: Settings is a place of its own in the sidebar', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1400, 900));
    Future<void> click(String label) async {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
    }

    await click('Settings');
    expect(find.byType(SettingsPage), findsOneWidget);
    await click('Library');
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('New playlist'), findsWidgets);
    await click('Settings');
    await click('Home');
    expect(find.byType(SettingsPage), findsNothing);
    await click('Library');
    expect(find.byType(SettingsPage), findsNothing);
    await click('Home');
    expect(find.byType(SettingsPage), findsNothing);
    // A sidebar playlist or collection leaves Settings too.
    await click('Settings');
    await click('Liked songs');
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('No songs here yet'), findsOneWidget);
  });

  testWidgets('desktop: sidebar places replace each other instead of piling '
      'up; back goes to Library', (tester) async {
    userLibrary.createPlaylist('Road trip');
    addTearDown(() => userLibrary.playlists.value = []);
    await pumpApp(tester, const Size(1400, 900));
    final sidebar = find.byType(Shell);
    Future<void> click(String label) async {
      await tester.tap(
        find.descendant(of: sidebar, matching: find.text(label)).first,
      );
      await tester.pumpAndSettle();
    }

    String showing() => tester
        .widgetList<CollectionPage>(find.byType(CollectionPage))
        .map((p) => p.title ?? p.playlistId ?? '')
        .join(',');

    for (final place in [
      'Liked songs',
      'Downloads',
      'History',
      'Liked songs',
      'Road trip',
      'Downloads',
      'Downloads', // again: not opened twice
    ]) {
      await click(place);
    }
    expect(find.byType(CollectionPage), findsOneWidget, reason: showing());
    expect(showing(), 'Downloads');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionPage), findsNothing);
    expect(find.text('New playlist'), findsWidgets, reason: 'Library');
  });

  testWidgets("a song in Home's quick grid plays with its radio, not the "
      'whole history after it', (tester) async {
    final history = [
      for (var i = 0; i < 50; i++)
        Track(id: 'h$i', title: 'Played $i', artist: 'A', artUrl: ''),
    ];
    userLibrary.history.value = history;
    addTearDown(() {
      userLibrary.history.value = [];
      player.queue.value = [];
      player.index.value = -1;
    });
    await pumpApp(tester, const Size(400, 860));
    await tester.tap(find.text('Played 1'));
    await tester.pump();
    expect(player.queue.value, [history[1]], reason: 'its radio follows');
  });
}
