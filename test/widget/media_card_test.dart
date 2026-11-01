import 'package:encore/models.dart';
import 'package:encore/ui/theme.dart';
import 'package:encore/ui/widgets/shelves.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Bug: home cards overflowed (the yellow and black stripes) with a larger
// system font size, and with titles whose fallback font is taller.

void main() {
  const card = MediaRef(
    kind: MediaKind.album,
    id: 'MPREb_x',
    title: 'A long album title that takes up two lines on the card',
    subtitle: 'Album • Somebody',
    artUrl: '',
  );

  // Cards were bare gestures: a screen reader read the text but couldn't
  // open them.
  testWidgets('screen readers can open a card', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: ShelfView(Shelf('Albums', cards: [card])),
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.text(card.title)),
      isSemantics(isButton: true, hasTapAction: true),
    );
    semantics.dispose();
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('cards fit at font size $scale', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: ShelfView(Shelf('Albums', cards: [card, card])),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
