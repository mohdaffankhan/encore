import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/player.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/track_menu.dart';
import 'buttons.dart';
import 'controls.dart';
import 'full_player.dart';

/// The desktop player bar along the bottom of the window: song on the left,
/// transport and seek in the middle, lyrics/queue/volume on the right.
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  static const height = 88.0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: player.nowPlaying,
      builder: (context, _, _) {
        final track = player.current;
        if (track == null) return const SizedBox.shrink();
        final text = Theme.of(context).textTheme;
        // Clicking anywhere on the bar that isn't a control opens the full
        // player (buttons, the sliders and links keep their own clicks).
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openFullPlayer(context),
            child: _bar(context, track, text),
          ),
        );
      },
    );
  }

  Widget _bar(BuildContext context, Track track, TextTheme text) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: EncoreColors.background,
        border: Border(top: BorderSide(color: EncoreColors.hairline)),
      ),
      child: Row(
        children: [
          // Song
          Expanded(
            flex: 3,
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => openFullPlayer(context),
                  child: Artwork(track.artUrl, size: 56, radius: 8),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      InkWell(
                        onTap: track.artistId == null
                            ? null
                            : () => openArtist(track.artistId!),
                        child: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: EncoreColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                LikeButton(track),
                TrackMenu(track, inPlayer: true),
              ],
            ),
          ),
          // Transport
          Expanded(
            flex: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [TransportControls(), SeekBar(timesBeside: true)],
              ),
            ),
          ),
          // Extras
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const SleepTimerIndicator(size: 20),
                IconButton(
                  tooltip: 'Lyrics',
                  iconSize: 20,
                  color: EncoreColors.textSecondary,
                  icon: const Icon(Icons.lyrics_outlined),
                  onPressed: () =>
                      openFullPlayer(context, view: PlayerView.lyrics),
                ),
                IconButton(
                  tooltip: 'Up next',
                  iconSize: 20,
                  color: EncoreColors.textSecondary,
                  icon: const Icon(Icons.queue_music_rounded),
                  onPressed: () =>
                      openFullPlayer(context, view: PlayerView.queue),
                ),
                const VolumeControl(),
                IconButton(
                  tooltip: 'Full screen player',
                  iconSize: 20,
                  color: EncoreColors.textSecondary,
                  icon: const Icon(Icons.open_in_full_rounded),
                  onPressed: () => openFullPlayer(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
