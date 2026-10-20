import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/player.dart';

/// Keyboard and media-key controls, active on every screen. Text fields
/// keep Space and the arrow keys while typing.
class PlayerShortcuts extends StatelessWidget {
  const PlayerShortcuts({super.key, required this.child});

  final Widget child;

  static const _seekStep = Duration(seconds: 10);
  static const _volumeStep = 0.1;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        // Play / pause
        const SingleActivator(LogicalKeyboardKey.space): player.toggle,
        const SingleActivator(LogicalKeyboardKey.keyK): player.toggle,
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): player.toggle,
        const SingleActivator(LogicalKeyboardKey.mediaPlay): player.audio.play,
        const SingleActivator(LogicalKeyboardKey.mediaPause):
            player.audio.pause,
        // Tracks
        const SingleActivator(LogicalKeyboardKey.mediaTrackNext): player.next,
        const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious):
            player.previous,
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            player.next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            player.previous,
        // Seek
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            player.seekBy(_seekStep),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            player.seekBy(-_seekStep),
        // Volume
        const SingleActivator(LogicalKeyboardKey.arrowUp, control: true): () =>
            player.changeVolume(_volumeStep),
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          control: true,
        ): () =>
            player.changeVolume(-_volumeStep),
        // Like
        const SingleActivator(LogicalKeyboardKey.keyL):
            player.toggleLikeCurrent,
      },
      // Autofocus so shortcuts work before anything has been clicked.
      child: Focus(autofocus: true, child: child),
    );
  }
}
