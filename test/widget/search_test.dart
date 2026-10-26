import 'package:encore/services/library.dart';
import 'package:flutter/material.dart';
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
}
