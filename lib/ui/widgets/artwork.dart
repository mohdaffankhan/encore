import 'package:flutter/material.dart';

import '../../services/art_cache.dart';
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

/// Album art, square (or round for artists), decoded at display size and
/// kept on disk ([CachedArt]). When the art changes (a new song), the old
/// art stays until the new one is ready, instead of flashing the
/// placeholder; art shown for the first time fades in.
class Artwork extends StatefulWidget {
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
  State<Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends State<Artwork> {
  /// Art has been shown here, so the next art can replace it directly.
  var _shown = false;

  static Widget get _placeholder => ColoredBox(
    color: EncoreColors.surfaceHigh,
    child: Center(
      child: Icon(Icons.music_note_rounded, color: EncoreColors.textTertiary),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final image = LayoutBuilder(
      builder: (context, constraints) {
        final logical = widget.size ?? constraints.biggest.shortestSide;
        final px = (logical * MediaQuery.devicePixelRatioOf(context)).ceil();
        if (widget.url.isEmpty || px <= 0 || !px.isFinite) {
          _shown = false;
          return _placeholder;
        }
        return Image(
          // Decode at display size: the biggest RAM saving for image lists.
          image: ResizeImage.resizeIfNeeded(
            px,
            null,
            CachedArt(sizedArt(widget.url, px)),
          ),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) {
            _shown = false;
            return _placeholder;
          },
          frameBuilder: (_, child, frame, sync) {
            // Flutter reports no frame again while new art loads, although
            // [child] still shows the old art (gaplessPlayback).
            final fadeIn = !sync && !_shown;
            if (frame != null) _shown = true;
            return Stack(
              fit: StackFit.expand,
              children: [
                _placeholder,
                AnimatedOpacity(
                  opacity: frame != null || sync || !fadeIn ? 1 : 0,
                  duration: fadeIn
                      ? const Duration(milliseconds: 200)
                      : Duration.zero,
                  curve: Curves.easeOut,
                  child: child,
                ),
              ],
            );
          },
        );
      },
    );
    return SizedBox.square(
      dimension: widget.size,
      child: widget.circle
          ? ClipOval(child: image)
          : ClipRRect(
              borderRadius: BorderRadius.circular(widget.radius),
              child: image,
            ),
    );
  }
}
