import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:encore/services/art_cache.dart';
import 'package:encore/ui/widgets/artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Bug: on every song change the players flashed the placeholder (a music
// note) before the new art arrived: Flutter reports no frame while new art
// loads, and that showed the placeholder over the old art.

void main() {
  final png = File('assets/brand/icon_256.png').readAsBytesSync();
  late Completer<Uint8List> second;

  setUp(() {
    useArtCacheDir(null);
    second = Completer();
    downloadArt = (url) =>
        url.endsWith('one') ? Future.value(png) : second.future;
  });

  testWidgets('new art keeps the old one showing until it is ready', (
    tester,
  ) async {
    final url = ValueNotifier('https://art/one');
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ValueListenableBuilder(
            valueListenable: url,
            builder: (_, url, _) => Artwork(url, size: 100),
          ),
        ),
      ),
    );
    // Loading and decoding happen outside the fake clock.
    for (
      var i = 0;
      i < 50 && tester.widget<RawImage>(find.byType(RawImage)).image == null;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final first = tester.widget<RawImage>(find.byType(RawImage)).image;
    expect(first, isNotNull, reason: 'the first art loaded');

    url.value = 'https://art/two'; // still downloading
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final shown = find.byType(RawImage);
    expect(shown, findsOneWidget, reason: 'not the placeholder alone');
    expect(tester.widget<RawImage>(shown).image, isNotNull);
    final opacity = tester.widget<AnimatedOpacity>(
      find.byType(AnimatedOpacity),
    );
    expect(opacity.opacity, 1, reason: 'the old art, not faded out');
  });
}
