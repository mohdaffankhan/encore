import 'package:flutter/material.dart';

import '../../services/player.dart';
import '../theme.dart';
import '../widgets/widgets.dart';

/// The songs after the current one: tap to jump, drag the handle to
/// reorder, and the song's menu (⋯, right-click, long-press) takes one out.
class UpNext extends StatelessWidget {
  const UpNext({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([player.queue, player.index]),
      builder: (context, _) {
        final start = player.index.value + 1;
        final upNext = player.upNext;
        if (upNext.isEmpty) {
          return const Message(
            icon: Icons.queue_music_rounded,
            text: 'Nothing queued',
          );
        }
        // Keys that follow a song as it moves. "Play next" can queue a song
        // twice, so each copy is told apart by which one it is.
        final seen = <String, int>{};
        final keys = [
          for (final t in upNext)
            ValueKey((t.id, seen[t.id] = (seen[t.id] ?? -1) + 1)),
        ];
        return ReorderableList(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: upNext.length,
          onReorderItem: player.moveUpNext,
          itemBuilder: (context, i) => _Row(
            key: keys[i],
            index: i,
            child: TrackTile(
              track: upNext[i],
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onTap: () => player.jumpTo(start + i),
              removeFromQueue: () => player.removeUpNext(i),
              trailing: _Handle(index: i),
            ),
          ),
        );
      },
    );
  }
}

/// Tells its [_Handle] whether the pointer is over the row.
class _Row extends StatefulWidget {
  const _Row({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  final _hovered = ValueNotifier(false);

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _hovered.value = true,
      onExit: (_) => _hovered.value = false,
      child: _Hovered(notifier: _hovered, child: widget.child),
    );
  }
}

class _Hovered extends InheritedNotifier<ValueNotifier<bool>> {
  const _Hovered({required super.notifier, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Hovered>()?.notifier?.value ??
      false;
}

/// The drag handle. With a mouse (desktop) it shows only over its row, like
/// Spotify's queue, so the list isn't a column of handles; on phones it is
/// always there to grab.
class _Handle extends StatelessWidget {
  const _Handle({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final shown = !isWide(context) || _Hovered.of(context);
    return ReorderableDragStartListener(
      index: index,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: AnimatedOpacity(
          opacity: shown ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          child: const Padding(
            padding: EdgeInsets.all(8),
            // No tooltip: on phones it takes the long-press and the drag
            // never starts.
            child: Icon(
              Icons.drag_handle_rounded,
              semanticLabel: 'Drag to reorder',
              color: EncoreColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
