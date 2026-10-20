import 'package:flutter/material.dart';

import '../../services/player.dart';
import '../art_colors.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import 'buttons.dart';
import 'full_player.dart';

/// The compact player above the bottom navigation on phones, tinted with
/// the artwork's colour. Tap to open the full player.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([player.index, nowPlayingColor]),
      builder: (context, _) {
        final track = player.current;
        if (track == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Material(
            color: backdropColor(nowPlayingColor.value),
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => openFullPlayer(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                    child: Row(
                      children: [
                        Artwork(track.artUrl, size: 44, radius: 8),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: EncoreColors.text.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        LikeButton(track),
                        const PlayPauseButton(size: 28),
                      ],
                    ),
                  ),
                  const _ProgressLine(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: StreamBuilder(
        stream: player.audio.positionStream,
        builder: (context, snapshot) {
          final total = player.audio.duration?.inMilliseconds ?? 0;
          final pos = snapshot.data?.inMilliseconds ?? 0;
          return LinearProgressIndicator(
            minHeight: 2,
            value: total > 0 ? (pos / total).clamp(0, 1) : 0,
            color: EncoreColors.text,
            backgroundColor: Colors.white12,
          );
        },
      ),
    );
  }
}
