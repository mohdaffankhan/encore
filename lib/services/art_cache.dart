import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

// Artwork kept on disk. Flutter's image cache is only in memory, so every
// launch (and every list scrolled back to after it was evicted) downloaded
// the art again, and it popped in late.

/// The cache's size limit; the least recently used art goes first.
const _maxBytes = 100 << 20;

/// The art at [url], from disk when it was downloaded before.
class CachedArt extends ImageProvider<CachedArt> {
  const CachedArt(this.url);

  final String url;

  @override
  Future<CachedArt> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CachedArt key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _codec(decode),
        scale: 1,
        debugLabel: url,
      );

  Future<ui.Codec> _codec(ImageDecoderCallback decode) async {
    try {
      final bytes = await artBytes(url);
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      // Not kept as failed, so it is tried again next time it is shown.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) => other is CachedArt && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// Downloads the art at [url] to disk (if it isn't there yet), so it shows
/// at once later, e.g. for the next song.
Future<void> prefetchArt(String url) =>
    artBytes(url).then((_) {}, onError: (_) {});

final _loading = <String, Future<Uint8List>>{};

/// The bytes of [url]: from disk, else downloaded (and kept).
Future<Uint8List> artBytes(String url) =>
    _loading[url] ??= _bytes(url).whenComplete(() {
      // A block: returning the removed future would wait on itself.
      _loading.remove(url);
    });

Future<Uint8List> _bytes(String url) async {
  final dir = await _cacheDir();
  final file = dir == null
      ? null
      : File('${dir.path}${Platform.pathSeparator}${_name(url)}');
  if (file != null) {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) {
        // Recently used: kept longest.
        unawaited(file.setLastModified(DateTime.now()).catchError((_) {}));
        return bytes;
      }
    } on FileSystemException {
      // Not cached yet.
    }
  }
  final bytes = await downloadArt(url);
  if (file != null) unawaited(_keep(file, bytes));
  return bytes;
}

/// Written aside and swapped in, so a half-written file is never read.
Future<void> _keep(File file, Uint8List bytes) async {
  try {
    final part = File('${file.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(file.path);
  } catch (e) {
    debugPrint('Keeping art failed: $e');
  }
}

final _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);

/// Replaced in tests.
@visibleForTesting
Future<Uint8List> Function(String url) downloadArt = _download;

Future<Uint8List> _download(String url) async {
  Future<Uint8List> get() async {
    final res = await (await _http.getUrl(Uri.parse(url))).close();
    if (res.statusCode != HttpStatus.ok) {
      await res.drain<void>();
      throw HttpException('Art: HTTP ${res.statusCode}', uri: Uri.parse(url));
    }
    return consolidateHttpClientResponseBytes(res);
  }

  return get().timeout(const Duration(seconds: 20));
}

Future<Directory?>? _dir;

@visibleForTesting
void useArtCacheDir(Directory? dir) => _dir = Future.value(dir);

Future<Directory?> _cacheDir() => _dir ??= () async {
  try {
    final base = await getApplicationCacheDirectory();
    final dir = await Directory('${base.path}${Platform.pathSeparator}art')
        .create(recursive: true);
    unawaited(trimArtCache(dir));
    return dir;
  } catch (e) {
    // No cache folder (e.g. in widget tests): straight from the network.
    debugPrint('No art cache: $e');
    return null;
  }
}();

/// Removes the least recently used art while the cache is over [maxBytes],
/// down to three quarters of it. Run once per launch.
@visibleForTesting
Future<void> trimArtCache(Directory dir, {int maxBytes = _maxBytes}) async {
  try {
    final files = [
      await for (final f in dir.list())
        if (f is File) (f, await f.stat()),
    ];
    var total = files.fold(0, (sum, f) => sum + f.$2.size);
    if (total <= maxBytes) return;
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in files) {
      if (total <= maxBytes * 3 ~/ 4) break;
      await file.delete();
      total -= stat.size;
    }
  } catch (e) {
    debugPrint('Trimming the art cache failed: $e');
  }
}

/// How much space the art kept on disk takes, in bytes.
Future<int> artCacheSize() async {
  final dir = await _cacheDir();
  if (dir == null) return 0;
  try {
    return await _filesIn(dir).fold<int>(0, (sum, f) => sum + f.lengthSync());
  } catch (e) {
    return 0;
  }
}

/// Deletes the art kept on disk (Settings: free up space). It comes back
/// as songs and pages are shown.
Future<void> clearArtCache() async {
  final dir = await _cacheDir();
  if (dir == null) return;
  await for (final file in _filesIn(dir)) {
    try {
      await file.delete();
    } catch (_) {
      // Being written: it goes next time.
    }
  }
}

Stream<File> _filesIn(Directory dir) =>
    dir.list().where((f) => f is File).cast<File>();

/// A file name for [url] (FNV-1a, 64 bits): the same on every launch,
/// unlike [String.hashCode].
String _name(String url) {
  var hash = 0xcbf29ce484222325;
  for (final unit in url.codeUnits) {
    hash = (hash ^ unit) * 0x100000001b3;
  }
  return hash.toUnsigned(64).toRadixString(16);
}
