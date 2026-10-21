import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/player.dart';

/// Keyboard and media-key controls, active on every screen. While a text
/// field is being typed in, every key goes to the text field (Space, K, L,
/// the arrows...) and only the media keys still control playback.
class PlayerShortcuts extends StatelessWidget {
  const PlayerShortcuts({super.key, required this.child});

  final Widget child;

  static const _seekStep = Duration(seconds: 10);
  static const _volumeStep = 0.1;

  static final Map<ShortcutActivator, VoidCallback> _mediaKeys = {
    const SingleActivator(LogicalKeyboardKey.mediaPlayPause): player.toggle,
    const SingleActivator(LogicalKeyboardKey.mediaPlay): player.audio.play,
    const SingleActivator(LogicalKeyboardKey.mediaPause): player.audio.pause,
    const SingleActivator(LogicalKeyboardKey.mediaTrackNext): player.next,
    const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious):
        player.previous,
  };

  static final Map<ShortcutActivator, VoidCallback> _keys = {
    // Play / pause
    const SingleActivator(LogicalKeyboardKey.space): player.toggle,
    const SingleActivator(LogicalKeyboardKey.keyK): player.toggle,
    // Tracks
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
    const SingleActivator(LogicalKeyboardKey.arrowDown, control: true): () =>
        player.changeVolume(-_volumeStep),
    // Like
    const SingleActivator(LogicalKeyboardKey.keyL): player.toggleLikeCurrent,
  };

  /// True while the keyboard focus is in a text field.
  static bool get isTyping =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>() !=
      null;

  static KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    for (final bindings in [_mediaKeys, if (!isTyping) _keys]) {
      for (final MapEntry(key: activator, value: action) in bindings.entries) {
        if (activator.accepts(event, keyboard)) {
          action();
          return KeyEventResult.handled;
        }
      }
    }
    // Not ours: let it reach the text field (or the rest of the app).
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Autofocus so shortcuts work before anything has been clicked.
    return Focus(autofocus: true, onKeyEvent: _onKey, child: child);
  }
}
