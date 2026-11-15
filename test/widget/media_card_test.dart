import 'package:encore/models.dart';
import 'package:encore/ui/theme.dart';
import 'package:encore/ui/widgets/media_card.dart';
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

  // Phones showed two big cards across; YouTube Music's app shows about
  // two and a half (the next one peeks in, so it's clear the row scrolls).
  for (final (device, width, cardWidth, across) in [
    ('phone', 412.0, MediaCard.phoneWidth, (3.1, 3.8)),
    ('desktop', 1400.0, MediaCard.width, (0.0, 99.0)),
  ]) {
    testWidgets('$device: cards $cardWidth wide', (tester) async {
      tester.view
        ..physicalSize = Size(width, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: ListView(
              children: [
                ShelfView(Shelf('Listen again', cards: List.filled(8, card))),
              ],
            ),
          ),
        ),
      );
      final first = tester.getRect(find.byType(MediaCard).first);
      expect(first.width, cardWidth);
      final visible = find
          .byType(MediaCard)
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget).first))
          .fold<double>(
            0,
            (sum, r) =>
                sum +
                ((r.right.clamp(0, width) - r.left.clamp(0, width)) / r.width),
          );
      expect(visible, inInclusiveRange(across.$1, across.$2));
      expect(tester.takeException(), isNull);
    });
  }
}
