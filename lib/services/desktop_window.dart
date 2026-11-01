import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'player.dart';
import 'settings.dart';

/// The desktop window's extras (windows/runner/desktop_window.cpp, and the
/// title on Linux): the song in the window title and the tray icon's tip,
/// the tray menu's play / pause / next / previous, and whether closing the
/// window keeps the music playing in the tray.
class DesktopWindow {
  DesktopWindow(this.player, {MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(name);

  static const name = 'dev.encore.app/window';

  final Player player;
  final MethodChannel _channel;
  String? _title;

  StreamSubscription<bool>? _playing;

  void start() {
    _channel.setMethodCallHandler((call) async {
      switch ((call.method, call.arguments)) {
        case ('tray', 'playPause'):
          player.toggle();
        case ('tray', 'next'):
          await player.next();
        case ('tray', 'previous'):
          await player.previous();
      }
    });
    player.nowPlaying.addListener(_sendTitle);
    _playing = player.audio.playingStream.listen((_) => _sendTitle());
    settings.closeToTray.addListener(_sendCloseToTray);
    _sendCloseToTray();
  }

  /// Stops following the player and the settings (the app never needs to).
  @visibleForTesting
  void stop() {
    _channel.setMethodCallHandler(null);
    player.nowPlaying.removeListener(_sendTitle);
    _playing?.cancel();
    settings.closeToTray.removeListener(_sendCloseToTray);
  }

  /// "Get Lucky – Daft Punk" while it plays, like Spotify; "Encore" when
  /// paused or nothing plays.
  @visibleForTesting
  String get title => switch (player.current) {
    final track? when player.audio.playing =>
      '${track.title} – ${track.artist}',
    _ => 'Encore',
  };

  void _sendTitle() {
    final title = this.title;
    if (title == _title) return;
    _title = title;
    _call('title', title);
  }

  void _sendCloseToTray() => _call('closeToTray', settings.closeToTray.value);

  Future<void> _call(String method, Object? arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Not on this platform (e.g. no tray on Linux).
    } catch (e) {
      debugPrint('Window: $e');
    }
  }
}
