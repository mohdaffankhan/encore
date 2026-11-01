import 'package:flutter/material.dart';

import '../../services/player.dart';
import '../theme.dart';
import '../widgets/widgets.dart';

/// The songs after the current one: tap to jump, drag the handle to
/// reorder, × to take one out.
class UpNext extends StatelessWidget {
  const UpNext({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([player.queue, player.index]),
      builder: (context, _) {
        final start = player.index.value + 1;
        final upNext = player.upNext;
        // Keys that follow a song as it moves. "Play next" can queue a song
        // twice, so each copy is told apart by which one it is.
        final seen = <String, int>{};
        final keys = [
          for (final t in upNext)
            ValueKey((t.id, seen[t.id] = (seen[t.id] ?? -1) + 1)),
        ];
        if (upNext.isEmpty) {
          return const Message(
            icon: Icons.queue_music_rounded,
            text: 'Nothing queued',
          );
        }
        return ReorderableList(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: upNext.length,
          onReorderItem: player.moveUpNext,
          itemBuilder: (context, i) => TrackTile(
            key: keys[i],
            track: upNext[i],
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onTap: () => player.jumpTo(start + i),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Remove from queue',
                  onPressed: () => player.removeUpNext(i),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: EncoreColors.textTertiary,
                  ),
                ),
                ReorderableDragStartListener(
                  index: i,
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      // No tooltip: on phones it takes the long-press and
                      // the drag never starts.
                      child: Icon(
                        Icons.drag_handle_rounded,
                        semanticLabel: 'Drag to reorder',
                        color: EncoreColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
