import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/library.dart';
import '../../services/player.dart';
import '../../services/sleep_timer.dart';
import '../theme.dart';
import '../widgets/sleep_timer_picker.dart';

/// Play/pause, with a spinner while a song loads. [circle] draws it as the
/// white disc used for primary controls.
class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({super.key, this.size = 24, this.circle = false});

  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final box = circle ? size * 1.75 : size + 16;
    return SizedBox.square(
      dimension: box,
      child: ValueListenableBuilder(
        valueListenable: player.loading,
        builder: (context, loading, _) => StreamBuilder(
          stream: player.audio.playingStream,
          builder: (context, snapshot) {
            final playing = snapshot.data ?? false;
            final fg = circle ? Colors.black : EncoreColors.text;
            final Widget icon = loading
                ? SizedBox.square(
                    dimension: size * 0.7,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: fg,
                    ),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: size,
                    color: fg,
                  );
            return Material(
              color: circle ? EncoreColors.text : Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: player.toggle,
                child: Tooltip(
                  message: playing ? 'Pause' : 'Play',
                  child: Center(child: icon),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class LikeButton extends StatelessWidget {
  const LikeButton(this.track, {super.key, this.size = 22});

  final Track track;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: userLibrary.liked,
      builder: (context, _, _) {
        final liked = userLibrary.isLiked(track);
        return IconButton(
          tooltip: liked ? 'Remove from liked' : 'Like',
          iconSize: size,
          icon: Icon(
            liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          ),
          color: liked ? EncoreColors.accent : EncoreColors.textSecondary,
          onPressed: () => userLibrary.toggleLike(track),
        );
      },
    );
  }
}

/// A moon shown while the sleep timer is on (it is set from the ⋯ menu);
/// tap it to change or turn off the timer.
class SleepTimerIndicator extends StatelessWidget {
  const SleepTimerIndicator({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: sleepTimer.setting,
      builder: (context, setting, _) => setting == null
          ? const SizedBox.shrink()
          : IconButton(
              tooltip: sleepTimerStatus() ?? 'Sleep timer',
              iconSize: size,
              color: EncoreColors.accent,
              icon: const Icon(Icons.bedtime_rounded),
              onPressed: () => showSleepTimer(context),
            ),
    );
  }
}
