import 'dart:io';
import 'dart:typed_data';

import 'package:encore/services/art_cache.dart';
import 'package:flutter_test/flutter_test.dart';

// Art is kept on disk: it was downloaded again on every launch (Flutter's
// image cache is only in memory), so it popped in late.

void main() {
  late Directory dir;
  final downloads = <String>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('encore_art_test');
    useArtCacheDir(dir);
    downloads.clear();
    downloadArt = (url) async {
      downloads.add(url);
      return Uint8List.fromList(url.codeUnits);
    };
  });
  tearDown(() => dir.delete(recursive: true));

  Future<void> kept(int files) async {
    for (
      var i = 0;
      i < 100 &&
          dir.listSync().where((f) => !f.path.endsWith('.part')).length < files;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('art is downloaded once, then read from disk', () async {
    expect(await artBytes('https://art/a'), 'https://art/a'.codeUnits);
    await kept(1);
    expect(await artBytes('https://art/a'), 'https://art/a'.codeUnits);
    expect(downloads, ['https://art/a']);
  });

  test('art asked for twice at once is downloaded once', () async {
    await Future.wait([artBytes('https://art/b'), artBytes('https://art/b')]);
    expect(downloads, hasLength(1));
    await kept(1);
  });

  test('prefetching keeps it for later, and failures are quiet', () async {
    await prefetchArt('https://art/c');
    await kept(1);
    await artBytes('https://art/c');
    expect(downloads, hasLength(1));
    downloadArt = (_) async => throw const HttpException('offline');
    await prefetchArt('https://art/d');
  });

  test('without a cache folder, art comes straight from the network', () async {
    useArtCacheDir(null);
    await artBytes('https://art/e');
    await artBytes('https://art/e');
    expect(downloads, hasLength(2));
  });

  test('the least recently used art goes when the cache is full', () async {
    final now = DateTime.now();
    for (var i = 0; i < 4; i++) {
      final f = File('${dir.path}/$i')..writeAsBytesSync(List.filled(100, 0));
      f.setLastModifiedSync(now.subtract(Duration(minutes: 10 - i)));
    }
    await trimArtCache(dir, maxBytes: 300);
    final left = dir.listSync().map((f) => f.uri.pathSegments.last).toSet();
    expect(left, {'2', '3'}, reason: 'down to 3/4 of the limit, oldest first');
  });
}
