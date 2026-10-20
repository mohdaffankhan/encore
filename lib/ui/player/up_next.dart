import 'package:flutter/material.dart';

import '../../services/player.dart';
import '../widgets/widgets.dart';

/// The songs after the current one; tap to jump.
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
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: upNext.length,
          itemBuilder: (context, i) => TrackTile(
            track: upNext[i],
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onTap: () => player.jumpTo(start + i),
          ),
        );
      },
    );
  }
}
