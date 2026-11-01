import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/player.dart';
import 'shell.dart';
import 'theme.dart';

/// A keyboard shortcut, as listed in the shortcuts dialog (Ctrl+/).
class Shortcut {
  const Shortcut(this.keys, this.label, this.activators, this.action);

  /// How it is written in the list, e.g. "Ctrl + →".
  final String keys;
  final String label;
  final List<ShortcutActivator> activators;
  final VoidCallback action;
}

/// Keyboard, media-key and mouse-button controls, active on every screen,
/// mostly as in Spotify. While a text field is being typed in, every key
/// goes to the text field (Space, K, L, the arrows...) and only the media
/// keys still control playback.
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

  static final shortcuts = [
    Shortcut('Space  or  K', 'Play / pause', const [
      SingleActivator(LogicalKeyboardKey.space),
      SingleActivator(LogicalKeyboardKey.keyK),
    ], player.toggle),
    Shortcut('Ctrl + →', 'Next song', const [
      SingleActivator(LogicalKeyboardKey.arrowRight, control: true),
    ], player.next),
    Shortcut('Ctrl + ←', 'Previous song', const [
      SingleActivator(LogicalKeyboardKey.arrowLeft, control: true),
    ], player.previous),
    Shortcut('→  /  ←', 'Forward / back 10 seconds', const [
      SingleActivator(LogicalKeyboardKey.arrowRight),
    ], () => player.seekBy(_seekStep)),
    Shortcut('', '', const [
      SingleActivator(LogicalKeyboardKey.arrowLeft),
    ], () => player.seekBy(-_seekStep)),
    Shortcut('Ctrl + ↑  /  ↓', 'Volume up / down', const [
      SingleActivator(LogicalKeyboardKey.arrowUp, control: true),
    ], () => player.changeVolume(_volumeStep)),
    Shortcut('', '', const [
      SingleActivator(LogicalKeyboardKey.arrowDown, control: true),
    ], () => player.changeVolume(-_volumeStep)),
    Shortcut('M', 'Mute / unmute', const [
      SingleActivator(LogicalKeyboardKey.keyM),
    ], player.toggleMute),
    Shortcut('Ctrl + S', 'Shuffle', const [
      SingleActivator(LogicalKeyboardKey.keyS, control: true),
    ], player.toggleShuffle),
    Shortcut('Ctrl + R', 'Repeat', const [
      SingleActivator(LogicalKeyboardKey.keyR, control: true),
    ], player.cycleRepeat),
    Shortcut('L', 'Like the song', const [
      SingleActivator(LogicalKeyboardKey.keyL),
    ], player.toggleLikeCurrent),
    Shortcut('Ctrl + K  or  /', 'Search', const [
      SingleActivator(LogicalKeyboardKey.keyK, control: true),
      SingleActivator(LogicalKeyboardKey.keyF, control: true),
      SingleActivator(LogicalKeyboardKey.slash),
    ], focusSearch),
    Shortcut('Alt + ←', 'Back', const [
      SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true),
      SingleActivator(LogicalKeyboardKey.browserBack),
    ], goBack),
    Shortcut('Ctrl + ,', 'Settings', const [
      SingleActivator(LogicalKeyboardKey.comma, control: true),
    ], openSettings),
    Shortcut('Esc', 'Close the player', const [
      SingleActivator(LogicalKeyboardKey.escape),
    ], closeOverlay),
    Shortcut('Ctrl + /', 'Keyboard shortcuts', const [
      SingleActivator(LogicalKeyboardKey.slash, control: true),
      CharacterActivator('?'),
    ], showShortcuts),
  ];

  /// True while the keyboard focus is in a text field.
  static bool get isTyping =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>() !=
      null;

  static KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    for (final MapEntry(key: activator, value: action) in _mediaKeys.entries) {
      if (activator.accepts(event, keyboard)) {
        action();
        return KeyEventResult.handled;
      }
    }
    if (isTyping) return KeyEventResult.ignored;
    for (final shortcut in shortcuts) {
      if (shortcut.activators.any((a) => a.accepts(event, keyboard))) {
        shortcut.action();
        return KeyEventResult.handled;
      }
    }
    // Not ours: let it reach the text field (or the rest of the app).
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // The mouse's back button, as in a browser.
      onPointerDown: (event) {
        if (event.buttons & kBackMouseButton != 0) goBack();
      },
      // Autofocus so shortcuts work before anything has been clicked.
      child: Focus(autofocus: true, onKeyEvent: _onKey, child: child),
    );
  }
}

/// The list of keyboard shortcuts (Ctrl+/).
void showShortcuts() {
  final context = shellKey.currentContext;
  if (context == null) return;
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in PlayerShortcuts.shortcuts)
              if (s.label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(s.label)),
                      Text(
                        s.keys,
                        style: const TextStyle(
                          color: EncoreColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
