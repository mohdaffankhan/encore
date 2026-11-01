import 'package:encore/app.dart';
import 'package:encore/models.dart';
import 'package:encore/services/home_cache.dart';
import 'package:encore/services/library.dart';
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
}
