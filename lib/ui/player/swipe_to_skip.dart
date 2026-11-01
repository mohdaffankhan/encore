import 'package:flutter/material.dart';

import '../../services/player.dart';

/// Swipe left for the next song, right for the previous one (touch, or
/// dragging with the mouse), like turning pages: [next] and [previous] (the
/// songs either side) sit beside the child and come in with the finger, and
/// a swipe settles on them before the song changes. Without one, the child
/// leaves that side and comes back from the other. A short drag springs
/// back.
/// A swipe always changes song (unlike the Previous button, which restarts
/// a song that is more than 3 s in).
class SwipeToSkip extends StatefulWidget {
  const SwipeToSkip({
    super.key,
    required this.child,
    this.next,
    this.previous,
    this.onNext = _next,
    this.onPrevious = _previous,
  });

  final Widget child;

  /// What the next and previous songs look like, shown beside [child]. As
  /// they are already built (and their art loaded) when the song changes,
  /// the new song's art is there at once.
  final Widget? next;
  final Widget? previous;

  final VoidCallback onNext;
  final VoidCallback onPrevious;

  static void _next() => player.next();
  static void _previous() => player.previous(restart: false);

  /// How far (as a share of the width) or how fast a swipe must go.
  static const distance = 0.25;
  static const velocity = 700.0;

  /// Space between the pages.
  static const gap = 24.0;

  @override
  State<SwipeToSkip> createState() => _SwipeToSkipState();
}

class _SwipeToSkipState extends State<SwipeToSkip>
    with SingleTickerProviderStateMixin {
  /// The horizontal offset of the child, in logical pixels.
  late final _offset = AnimationController.unbounded(vsync: this);

  /// The child's width, measured when a drag starts.
  double _width = 300;

  /// A swipe is settling: drags wait until it is done (a drag then would
  /// count from where the pages were, off to one side).
  var _settling = false;

  /// This drag started while [_settling], so it does nothing.
  var _ignoring = false;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _end(DragEndDetails details) {
    if (_ignoring) {
      _ignoring = false;
      return;
    }
    final width = _width;
    final dx = _offset.value;
    final v = details.primaryVelocity ?? 0;
    final VoidCallback skip;
    final double side;
    final Widget? coming;
    if (dx < -width * SwipeToSkip.distance || v < -SwipeToSkip.velocity) {
      (skip, side, coming) = (widget.onNext, -1, widget.next);
    } else if (dx > width * SwipeToSkip.distance || v > SwipeToSkip.velocity) {
      (skip, side, coming) = (widget.onPrevious, 1, widget.previous);
    } else {
      _springBack();
      return;
    }
    _settling = true;
    if (coming != null) {
      // The neighbour slides into place, then becomes the song: the child
      // is rebuilt as that song in the same frame the pages reset.
      _offset
          .animateTo(
            side * (width + SwipeToSkip.gap),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          )
          .whenCompleteOrCancel(() {
            _settling = false;
            skip();
            if (mounted) _offset.value = 0;
          });
      return;
    }
    // Nothing that side to show: off this side, then in from the other.
    _offset
        .animateTo(
          side * width,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeIn,
        )
        .whenCompleteOrCancel(() {
          _settling = false;
          skip();
          if (!mounted) return;
          _offset.value = -side * width * 0.5;
          _springBack();
        });
  }

  void _springBack() => _offset.animateTo(
    0,
    duration: const Duration(milliseconds: 240),
    curve: Curves.easeOutCubic,
  );

  void _start(DragStartDetails details) {
    if (_settling) {
      _ignoring = true;
      return;
    }
    _offset.stop();
    _width = context.size?.width ?? _width;
  }

  @override
  Widget build(BuildContext context) {
    final next = widget.next;
    final previous = widget.previous;
    return GestureDetector(
      onHorizontalDragStart: _start,
      onHorizontalDragUpdate: (d) {
        if (!_ignoring) _offset.value += d.delta.dx;
      },
      onHorizontalDragEnd: _end,
      // E.g. the drag turned out to be vertical (swipe up for lyrics).
      onHorizontalDragCancel: () {
        if (_ignoring) {
          _ignoring = false;
        } else if (!_settling) {
          _springBack();
        }
      },
      child: AnimatedBuilder(
        animation: _offset,
        builder: (context, child) {
          final dx = _offset.value;
          // A whole page (its own width) and the gap to that side.
          Widget beside(double side, Widget page) => Positioned.fill(
            key: ValueKey(side),
            child: Transform.translate(
              offset: Offset(dx + side * SwipeToSkip.gap, 0),
              child: FractionalTranslation(
                translation: Offset(side, 0),
                child: page,
              ),
            ),
          );
          return Stack(
            // The child sized as without the pages beside it.
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [
              // Built (and their art loaded) even while out of sight.
              if (previous != null) beside(-1, previous),
              Transform.translate(
                key: const ValueKey(0.0),
                offset: Offset(dx, 0),
                child: child,
              ),
              if (next != null) beside(1, next),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}
