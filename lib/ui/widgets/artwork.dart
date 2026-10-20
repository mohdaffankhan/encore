import 'package:flutter/material.dart';

import '../theme.dart';

final _musicSize = RegExp(r'=w\d+-h\d+');
final _videoThumb = RegExp(r'(i\.ytimg\.com/vi/[^/]+/)[^?]+(\?.*)?$');

/// [url] at the smallest size YouTube offers that still covers [px] pixels,
/// so small tiles don't download and decode full-size art.
String sizedArt(String url, int px) {
  if (_musicSize.hasMatch(url)) {
    final s = [60, 120, 226, 544].firstWhere((s) => s >= px, orElse: () => 544);
    return url.replaceFirst(_musicSize, '=w$s-h$s');
  }
  return url.replaceFirstMapped(
    _videoThumb,
    (m) => '${m[1]}${px <= 160 ? 'mqdefault' : 'hqdefault'}.jpg',
  );
}

/// Album art, square (or round for artists), decoded at display size.
class Artwork extends StatelessWidget {
  const Artwork(
    this.url, {
    super.key,
    this.size,
    this.radius = 8,
    this.circle = false,
  });

  final String url;
  final double? size;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: EncoreColors.surfaceHigh,
      child: Center(
        child: Icon(Icons.music_note_rounded, color: EncoreColors.textTertiary),
      ),
    );
    final image = LayoutBuilder(
      builder: (context, constraints) {
        final logical = size ?? constraints.biggest.shortestSide;
        final px = (logical * MediaQuery.devicePixelRatioOf(context)).ceil();
        if (url.isEmpty || px <= 0 || !px.isFinite) return placeholder;
        return Image.network(
          sizedArt(url, px),
          // Decode at display size: the biggest RAM saving for image lists.
          cacheWidth: px,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => placeholder,
          frameBuilder: (_, child, frame, sync) =>
              sync || frame != null ? child : placeholder,
        );
      },
    );
    return SizedBox.square(
      dimension: size,
      child: circle
          ? ClipOval(child: image)
          : ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: image,
            ),
    );
  }
}
