import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/lyrics.dart';
import '../../models.dart';
import '../../services/player.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Lyrics for [track]. Synced lyrics follow playback (only rebuilding when
/// the line changes) and can be tapped to seek.
class LyricsView extends StatefulWidget {
  const LyricsView(this.track, {super.key});

  final Track track;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  late Future<Lyrics?> _lyrics = lyricsFor(widget.track);
  final _keys = <GlobalKey>[];
  StreamSubscription<Duration>? _position;
  int _line = -1;

  @override
  void dispose() {
    _position?.cancel();
    super.dispose();
  }

  void _follow(List<LyricLine> lines) {
    if (_position != null) return;
    _keys.addAll(List.generate(lines.length, (_) => GlobalKey()));
    _position = player.audio.positionStream.listen((pos) {
      final line = lines.lastIndexWhere((l) => l.time <= pos);
      if (line == _line || !mounted) return;
      setState(() => _line = line);
      final ctx = line >= 0 ? _keys[line].currentContext : null;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.35,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder(
      future: _lyrics,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: EncoreColors.text),
          );
        }
        if (snapshot.hasError) {
          return ErrorRetry(
            message: "Couldn't load lyrics.",
            onRetry: () => setState(() => _lyrics = lyricsFor(widget.track)),
          );
        }
        final lyrics = snapshot.data;
        if (lyrics == null) {
          return const Message(
            icon: Icons.lyrics_outlined,
            text: 'No lyrics for this song',
          );
        }
        if (lyrics.synced.isEmpty) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Text(
              lyrics.plain,
              style: text.titleMedium?.copyWith(height: 1.7),
            ),
          );
        }
        final lines = lyrics.synced;
        _follow(lines);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines.length; i++)
                InkWell(
                  key: _keys[i],
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => player.audio.seek(lines[i].time),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: text.headlineSmall!.copyWith(
                        height: 1.25,
                        color: i == _line
                            ? EncoreColors.text
                            : EncoreColors.text.withValues(
                                alpha: i < _line ? 0.45 : 0.28,
                              ),
                      ),
                      child: Text(lines[i].text.isEmpty ? '♪' : lines[i].text),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
