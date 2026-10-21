import 'package:flutter/material.dart';

import '../../services/player.dart';

/// Swipe left for the next song, right for the previous one (touch, or
/// dragging with the mouse). The child follows the pointer and springs back.
/// A swipe always changes song (unlike the Previous button, which restarts
/// a song that is more than 3 s in).
class SwipeToSkip extends StatefulWidget {
  const SwipeToSkip({
    super.key,
    required this.child,
    this.onNext = _next,
    this.onPrevious = _previous,
  });

  final Widget child;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  static void _next() => player.next();
  static void _previous() => player.previous(restart: false);

  /// How far (as a share of the width) or how fast a swipe must go.
  static const distance = 0.25;
  static const velocity = 700.0;

  @override
  State<SwipeToSkip> createState() => _SwipeToSkipState();
}

class _SwipeToSkipState extends State<SwipeToSkip>
    with SingleTickerProviderStateMixin {
  /// The horizontal offset of the child, in logical pixels.
  late final _offset = AnimationController.unbounded(vsync: this);

  /// The child's width, measured when a drag starts.
  double _width = 300;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _end(DragEndDetails details) {
    final width = _width;
    final dx = _offset.value;
    final v = details.primaryVelocity ?? 0;
    if (dx < -width * SwipeToSkip.distance || v < -SwipeToSkip.velocity) {
      widget.onNext();
    } else if (dx > width * SwipeToSkip.distance || v > SwipeToSkip.velocity) {
      widget.onPrevious();
    }
    _springBack();
  }

  void _springBack() => _offset.animateTo(
    0,
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
  );

  void _start(DragStartDetails details) {
    _offset.stop();
    _width = context.size?.width ?? _width;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: _start,
      onHorizontalDragUpdate: (d) => _offset.value += d.delta.dx,
      onHorizontalDragEnd: _end,
      // E.g. the drag turned out to be vertical (swipe up for lyrics).
      onHorizontalDragCancel: _springBack,
      child: AnimatedBuilder(
        animation: _offset,
        builder: (context, child) {
          final shift = (_offset.value.abs() / _width).clamp(0.0, 1.0);
          return Transform.translate(
            offset: Offset(_offset.value, 0),
            child: Opacity(opacity: 1 - shift * 0.5, child: child),
          );
        },
        child: widget.child,
      ),
    );
  }
}
