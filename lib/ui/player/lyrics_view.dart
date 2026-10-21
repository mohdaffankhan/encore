import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/lyrics.dart';
import '../../models.dart';
import '../../services/player.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Lyrics for [track]. Synced lyrics follow playback (only rebuilding when
/// the line changes) and can be tapped to seek.
///
/// Inside the phone lyrics sheet it scrolls with the sheet's [controller],
/// with the sheet's [header] as part of the same scroll, so dragging
/// anywhere on the sheet moves it. It only follows the song while [visible]
/// is true (the sheet is open), and jumps to the current line when it
/// becomes visible.
class LyricsView extends StatefulWidget {
  const LyricsView(
    this.track, {
    super.key,
    this.controller,
    this.header,
    this.visible,
  });

  final Track track;
  final ScrollController? controller;
  final Widget? header;
  final ValueNotifier<bool>? visible;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  late Future<Lyrics?> _lyrics = lyricsFor(widget.track);
  final _keys = <GlobalKey>[];
  StreamSubscription<Duration>? _position;
  int _line = -1;

  bool get _visible => widget.visible?.value ?? true;

  @override
  void initState() {
    super.initState();
    widget.visible?.addListener(_onVisible);
  }

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) {
      old.visible?.removeListener(_onVisible);
      widget.visible?.addListener(_onVisible);
    }
  }

  @override
  void dispose() {
    widget.visible?.removeListener(_onVisible);
    _position?.cancel();
    super.dispose();
  }

  void _onVisible() {
    if (_visible) _showLine(_line, animate: false);
  }

  void _follow(List<LyricLine> lines) {
    if (_position != null) return;
    _keys.addAll(List.generate(lines.length, (_) => GlobalKey()));
    _position = player.audio.positionStream.listen((pos) {
      final line = lines.lastIndexWhere((l) => l.time <= pos);
      if (line == _line || !mounted) return;
      setState(() => _line = line);
      _showLine(line);
    });
  }

  /// Scrolls the current line into view, unless the sheet is closed (it
  /// would scroll the header out of the closed sheet's bar).
  void _showLine(int line, {bool animate = true}) {
    if (!_visible || line < 0 || line >= _keys.length) return;
    final ctx = _keys[line].currentContext;
    if (ctx == null || !ctx.mounted) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.35,
      duration: animate ? const Duration(milliseconds: 350) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _lyrics,
      builder: (context, snapshot) => CustomScrollView(
        controller: widget.controller,
        slivers: [
          if (widget.header case final header?)
            SliverToBoxAdapter(child: header),
          ..._body(context, snapshot),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context, AsyncSnapshot<Lyrics?> snapshot) {
    Widget fill(Widget child) =>
        SliverFillRemaining(hasScrollBody: false, child: child);
    if (snapshot.connectionState != ConnectionState.done) {
      return [
        fill(
          const Center(
            child: CircularProgressIndicator(color: EncoreColors.text),
          ),
        ),
      ];
    }
    if (snapshot.hasError) {
      return [
        fill(
          ErrorRetry(
            message: "Couldn't load lyrics.",
            onRetry: () => setState(() => _lyrics = lyricsFor(widget.track)),
          ),
        ),
      ];
    }
    final lyrics = snapshot.data;
    if (lyrics == null) {
      return [
        fill(
          const Message(
            icon: Icons.lyrics_outlined,
            text: 'No lyrics for this song',
          ),
        ),
      ];
    }
    final text = Theme.of(context).textTheme;
    if (lyrics.synced.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.all(28),
          sliver: SliverToBoxAdapter(
            child: Text(
              lyrics.plain,
              style: text.titleMedium?.copyWith(height: 1.7),
            ),
          ),
        ),
      ];
    }
    final lines = lyrics.synced;
    _follow(lines);
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
        // All lines built (not lazily), so any line can be scrolled to.
        sliver: SliverToBoxAdapter(
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
        ),
      ),
    ];
  }
}
