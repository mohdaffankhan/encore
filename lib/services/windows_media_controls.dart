import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../ui/widgets/artwork.dart' show sizedArt;
import 'player.dart';

/// Windows' own media controls (windows/runner/media_controls.cpp): the
/// media overlay the volume and media keys bring up, the lock screen, and
/// the keyboard's media keys, which Windows sends to the app that is
/// playing whether it is in front or not (so they never reach the wrong
/// app, and no key is grabbed behind Windows' back).
class WindowsMediaControls {
  WindowsMediaControls(this.player, {MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(name);

  static const name = 'dev.encore.app/media_controls';

  final Player player;
  final MethodChannel _channel;

  /// What was last sent, so the overlay is only told about changes (not
  /// every position update, and the art not again on play / pause).
  String? _item;
  bool? _playing;

  void start() {
    _channel.setMethodCallHandler((call) async {
      switch ((call.method, call.arguments)) {
        case ('button', 'play'):
          await player.play();
        case ('button', 'pause'):
          await player.audio.pause();
        case ('button', 'next'):
          await player.next();
        case ('button', 'previous'):
          await player.previous();
        case ('seek', final int millis):
          await player.seek(Duration(milliseconds: millis));
      }
    });
    player.nowPlaying.addListener(_sendItem);
    player.audio.durationStream.listen((_) => _sendItem());
    player.audio.playingStream.listen((_) => _sendState());
    // A seek (from the app or the overlay) moves the overlay's bar too.
    player.audio.positionDiscontinuityStream.listen((_) => _sendState(true));
  }

  void _sendItem() {
    final track = player.current;
    if (track == null) {
      if (_item != null) _call('clear', null);
      _item = null;
      return;
    }
    final duration = player.audio.duration ?? track.duration ?? Duration.zero;
    final key = '${track.id} ${duration.inSeconds}';
    if (key == _item) return;
    _item = key;
    _call('item', {
      'title': track.title,
      'artist': track.artist,
      'album': track.album ?? '',
      'artUrl': sizedArt(track.artUrl, 544),
      'duration': duration.inMilliseconds,
    });
    _sendState(true);
  }

  void _sendState([bool moved = false]) {
    if (player.current == null) return;
    final playing = player.audio.playing;
    if (!moved && playing == _playing) return;
    _playing = playing;
    _call('state', {
      'playing': playing,
      'position': player.position.inMilliseconds,
    });
  }

  Future<void> _call(String method, Object? arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (e) {
      debugPrint('Windows media controls: $e');
    }
  }
}
