import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/player.dart';
import 'theme.dart';
import 'widgets/artwork.dart';

/// The current song's artwork colour, used to tint the players.
final nowPlayingColor = ValueNotifier<Color?>(null);

final _cache = <String, Color?>{};

void watchNowPlayingColor() => player.index.addListener(() async {
  final url = player.current?.artUrl;
  if (url == null) return;
  final color = await artColor(url);
  if (player.current?.artUrl == url) nowPlayingColor.value = color;
});

/// The most vivid colour of [url]'s artwork, or null if it can't be read.
/// Decodes the art at 8×8 and picks from those 64 pixels, which is cheap
/// enough not to cause a dropped frame (unlike full palette quantizing).
Future<Color?> artColor(String url) async {
  if (url.isEmpty) return null;
  if (_cache.containsKey(url)) return _cache[url];
  Color? best;
  try {
    final image = await _decode(
      ResizeImage(NetworkImage(sizedArt(url, 60)), width: 8, height: 8),
    );
    final data = await image.toByteData();
    image.dispose();
    var bestScore = -1.0;
    for (var i = 0; data != null && i + 3 < data.lengthInBytes; i += 4) {
      final c = Color.fromARGB(
        255,
        data.getUint8(i),
        data.getUint8(i + 1),
        data.getUint8(i + 2),
      );
      final hsv = HSVColor.fromColor(c);
      // Prefer saturated, reasonably bright pixels over greys and shadows.
      final score = hsv.saturation * (0.3 + hsv.value);
      if (score > bestScore) (bestScore, best) = (score, c);
    }
  } catch (_) {
    best = null;
  }
  if (_cache.length >= 60) _cache.remove(_cache.keys.first);
  return _cache[url] = best;
}

Future<ui.Image> _decode(ImageProvider provider) {
  final done = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      done.complete(info.image.clone());
      info.dispose();
      stream.removeListener(listener);
    },
    onError: (e, _) {
      done.completeError(e);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return done.future;
}

/// A deep, muted backdrop for [color], for headers and players.
Color backdropColor(Color? color) {
  if (color == null) return EncoreColors.surfaceHigh;
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withSaturation((hsl.saturation * 0.75).clamp(0, 0.6))
      .withLightness(0.22)
      .toColor();
}
