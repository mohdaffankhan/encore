import 'package:flutter/material.dart';

import '../../models.dart';
import '../art_colors.dart';
import '../theme.dart';
import 'lyrics_view.dart';

/// Phones: the lyrics as a sheet along the bottom of the full player, like
/// Spotify and YouTube Music. Closed, it is a "Lyrics" bar; drag it up (or
/// swipe up on the song, see [LyricsSheetController.dragBy]) and it follows
/// the finger, snapping open or closed. Swipe down on it (once the lyrics
/// are scrolled to the top), tap its close button or press Back to close.
class LyricsSheet extends StatefulWidget {
  const LyricsSheet({super.key, required this.track, required this.controller});

  final Track track;
  final LyricsSheetController controller;

  /// Height of the closed sheet's bar.
  static const barHeight = 64.0;

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

/// Opens, closes and drags the [LyricsSheet], and says whether it is open.
class LyricsSheetController {
  final sheet = DraggableScrollableController();

  /// True while the sheet is mostly open (it follows the song then).
  final open = ValueNotifier<bool>(false);

  /// The closed size, as a share of the player's height.
  double closedSize = 0.1;

  /// The player's height, for turning drags into sizes.
  double height = 600;

  static const _snap = Duration(milliseconds: 260);

  /// True while the sheet is all the way down (just its bar showing).
  bool get isClosed => !sheet.isAttached || sheet.size <= closedSize + 0.001;

  void openSheet() => _animate(1);

  void close() => _animate(closedSize);

  /// Follows a drag that started on the song (negative [dy] is up).
  void dragBy(double dy) {
    if (!sheet.isAttached) return;
    sheet.jumpTo((sheet.size - dy / height).clamp(closedSize, 1.0));
  }

  /// Ends a drag that started on the song: snaps by speed, else by size.
  void endDrag(double velocity) {
    if (!sheet.isAttached) return;
    final opening =
        velocity < -300 ||
        (velocity <= 300 && sheet.size > (closedSize + 1) / 2);
    opening ? openSheet() : close();
  }

  void _animate(double size) {
    if (!sheet.isAttached) return;
    sheet.animateTo(size, duration: _snap, curve: Curves.easeOutCubic);
  }

  void dispose() {
    sheet.dispose();
    open.dispose();
  }
}

class _LyricsSheetState extends State<LyricsSheet> {
  LyricsSheetController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.sheet.addListener(_onSize);
  }

  @override
  void dispose() {
    _controller.sheet.removeListener(_onSize);
    super.dispose();
  }

  void _onSize() {
    if (!_controller.sheet.isAttached) return;
    final closed = _controller.closedSize;
    _controller.open.value =
        _controller.sheet.size > closed + (1 - closed) * 0.6;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final closed = (LyricsSheet.barHeight / height).clamp(0.0, 1.0);
        _controller
          ..height = height
          ..closedSize = closed;
        return DraggableScrollableSheet(
          controller: _controller.sheet,
          initialChildSize: _controller.open.value ? 1 : closed,
          minChildSize: closed,
          snap: true,
          snapSizes: [closed, 1],
          snapAnimationDuration: LyricsSheetController._snap,
          builder: (context, scroll) => ValueListenableBuilder(
            valueListenable: nowPlayingColor,
            builder: (context, color, child) => Material(
              color: backdropColor(color),
              elevation: 8,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
            child: LyricsView(
              widget.track,
              key: ValueKey(widget.track.id),
              controller: scroll,
              visible: _controller.open,
              header: _Header(widget.track, _controller),
            ),
          ),
        );
      },
    );
  }
}

/// The bar of the closed sheet, and the header of the open one: a grab
/// handle, "Lyrics" and, when open, the song and a close button.
class _Header extends StatelessWidget {
  const _Header(this.track, this.controller);

  final Track track;
  final LyricsSheetController controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder(
      valueListenable: controller.open,
      builder: (context, open, _) => InkWell(
        onTap: open ? null : controller.openSheet,
        child: SizedBox(
          height: LyricsSheet.barHeight,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: EncoreColors.text.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Lyrics', style: text.titleMedium),
                            if (open)
                              Text(
                                '${track.title} · ${track.artist}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(
                                  color: EncoreColors.text.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (open)
                        IconButton(
                          tooltip: 'Close lyrics',
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          onPressed: controller.close,
                        )
                      else
                        const Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: EncoreColors.textSecondary,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
