import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'downloads.dart';

/// Android: while songs download, a notification shows their progress
/// ("Downloading 2 of 5", the song, a bar), and Encore keeps running to
/// finish them after it is closed (DownloadService). When they are done
/// with Encore off screen, a notification says how many were saved.
class DownloadNotice {
  DownloadNotice(this.downloads);

  final Downloads downloads;

  static const channel = MethodChannel('dev.encore.app/downloads');

  bool _showing = false;

  /// When the bar last moved, and which song it showed: Android drops a
  /// notification's updates when an app posts several a second (each 5%
  /// of a fast download did), so the bar moves at most once a second; a
  /// new song shows at once.
  DateTime? _sentAt;
  String? _sentSong;

  @visibleForTesting
  DateTime Function() now = DateTime.now;

  void start() => downloads.progress.addListener(_update);

  @visibleForTesting
  void stop() => downloads.progress.removeListener(_update);

  void _update() {
    final left = downloads.progress.value;
    final current = downloads.current;
    final before = downloads.done + downloads.notDone;
    if (left.isEmpty) {
      if (!_showing) return;
      _showing = false;
      _sentSong = null;
      _send('finished', {
        'done': downloads.done,
        'failed': downloads.notDone,
        'notify':
            WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed,
      });
      return;
    }
    // Between songs: the next one reports in a moment.
    if (current == null) return;
    _showing = true;
    final number = before + 1;
    final at = now();
    if (current.id == _sentSong &&
        at.difference(_sentAt!) < const Duration(seconds: 1)) {
      return;
    }
    _sentAt = at;
    _sentSong = current.id;
    _send('progress', {
      'title': current.title,
      'number': number,
      'total': before + left.length,
      'percent': ((left[current.id] ?? 0) * 100).round(),
    });
  }

  void _send(String method, Map<String, Object> args) {
    channel.invokeMethod(method, args).catchError((Object e) {
      debugPrint('Download notice: $e');
    });
  }
}
