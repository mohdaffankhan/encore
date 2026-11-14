import 'package:encore/services/library.dart';
import 'package:encore/ui/pages/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test.dart' show pumpApp;

// Offline (every request fails), so these check what the page does with
// the query; test/live and the e2e check the real results.

Future<void> _search(WidgetTester tester, String text) async {
  await pumpApp(tester, const Size(1400, 900));
  await tester.tap(find.text('Search').first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => userLibrary.searches.value = []);

  testWidgets('a search can be narrowed to Videos (covers, uploads)', (
    tester,
  ) async {
    await _search(tester, 'sammi meri waar');
    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .map((c) => (c.label as Text).data)
        .toList();
    expect(chips, ['Songs', 'Videos', 'Albums', 'Artists', 'Playlists']);
  });

  testWidgets('a pasted link looks up its song, without filters', (
    tester,
  ) async {
    await _search(tester, 'https://youtu.be/YlycL6ky2Wc?si=GCLgmi9AL9I2bEZ_');
    expect(find.text('Search failed.'), findsOneWidget, reason: 'offline');
    expect(find.byType(ChoiceChip), findsNothing);
    expect(userLibrary.searches.value, isEmpty, reason: 'not a search');
  });

  group('phone: Search again (as in the Play Store)', () {
    final nav = find.byType(NavigationBar);
    Future<void> tapSearchTab(WidgetTester tester) async {
      await tester.tap(find.descendant(of: nav, matching: find.text('Search')));
      await tester.pumpAndSettle();
    }

    testWidgets('the first tap opens Search; again puts the cursor in the box',
        (tester) async {
      await pumpApp(tester, const Size(400, 860));
      await tapSearchTab(tester);
      expect(searchField.hasFocus, isFalse, reason: 'just opened');
      await tapSearchTab(tester);
      expect(searchField.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue, reason: 'keyboard up');
    });

    testWidgets('keyboard put away while the box has the cursor: it comes '
        'back', (tester) async {
      await pumpApp(tester, const Size(400, 860));
      await tapSearchTab(tester);
      await tapSearchTab(tester);
      tester.testTextInput.hide();
      expect(tester.testTextInput.isVisible, isFalse);
      final shown = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        (call) async {
          shown.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.textInput,
          null,
        ),
      );
      await tapSearchTab(tester);
      expect(shown, contains('TextInput.show'));
    });
  });

  group('recent searches', () {
    testWidgets('Clear all clears them, Undo brings them back', (
      tester,
    ) async {
      userLibrary.searches.value = ['arijit', 'pritam', 'sanam'];
      await pumpApp(tester, const Size(400, 860));
      await tester.tap(find.text('Search').last);
      await tester.pumpAndSettle();
      expect(find.text('Recent searches'), findsOneWidget);
      // On the right of its heading.
      expect(
        tester.getCenter(find.text('Clear all')).dx,
        greaterThan(tester.getCenter(find.text('Recent searches')).dx),
      );
      expect(
        (tester.getCenter(find.text('Clear all')).dy -
                tester.getCenter(find.text('Recent searches')).dy)
            .abs(),
        lessThan(6),
      );
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();
      expect(userLibrary.searches.value, isEmpty);
      expect(find.text('Recent searches'), findsNothing);
      expect(find.text('Recent searches cleared'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(userLibrary.searches.value, ['arijit', 'pritam', 'sanam']);
    });

    Future<void> clearAll(WidgetTester tester) async {
      userLibrary.searches.value = ['arijit'];
      await pumpApp(tester, const Size(400, 860));
      await tester.tap(find.text('Search').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear all'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Recent searches cleared'), findsOneWidget);
    }

    testWidgets('the message goes by itself after 4 seconds (it stayed)', (
      tester,
    ) async {
      await clearAll(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Recent searches cleared'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Recent searches cleared'), findsNothing);
      expect(userLibrary.searches.value, isEmpty, reason: 'not undone');
    });

    testWidgets('swiped away, it goes at once', (tester) async {
      await clearAll(tester);
      await tester.drag(
        find.text('Recent searches cleared'),
        const Offset(300, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recent searches cleared'), findsNothing);
    });
  });
}

