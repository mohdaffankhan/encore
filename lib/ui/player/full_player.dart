import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/player.dart';
import '../art_colors.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/widgets.dart';
import 'buttons.dart';
import 'controls.dart';
import 'lyrics_view.dart';
import 'swipe_to_skip.dart';
import 'up_next.dart';

enum PlayerView { song, lyrics, queue }

/// Opens the full-screen player, optionally on lyrics or the queue.
void openFullPlayer(BuildContext context, {PlayerView view = PlayerView.song}) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => FullPlayer(initialView: view),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class FullPlayer extends StatefulWidget {
  const FullPlayer({super.key, this.initialView = PlayerView.song});

  final PlayerView initialView;

  @override
  State<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends State<FullPlayer> {
  late var _view = widget.initialView;

  /// How far the current vertical drag has gone (negative is up).
  double _dragUp = 0;

  /// Phones: swiping up on the song shows its lyrics.
  void _endSwipeUp(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (_dragUp < -80 || v < -500) setState(() => _view = PlayerView.lyrics);
    _dragUp = 0;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    // Phones: Back from lyrics or up next returns to the song first.
    return PopScope(
      canPop: wide || _view == PlayerView.song,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _view = PlayerView.song);
      },
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
    return Scaffold(
      body: ValueListenableBuilder(
        valueListenable: player.index,
        builder: (context, _, _) {
          final track = player.current;
          if (track == null) return const SizedBox.expand();
          return Stack(
            fit: StackFit.expand,
            children: [
              _Backdrop(track),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth >= 900
                      ? _wide(track)
                      : _narrow(track),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _topBar(Track track, {bool tabs = true}) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Close',
          iconSize: 30,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        Expanded(
          child: tabs
              // Shrinks to fit narrow phones beside the buttons.
              ? Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _ViewTabs(_view, (v) => setState(() => _view = v)),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SleepTimerButton(size: 24, color: EncoreColors.text),
        TrackMenu(track, color: EncoreColors.text),
      ],
    ),
  );

  Widget _narrow(Track track) {
    final onSong = _view == PlayerView.song;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: onSong ? (d) => _dragUp += d.delta.dy : null,
      onVerticalDragEnd: onSong ? _endSwipeUp : null,
      child: _narrowContent(track, onSong),
    );
  }

  Widget _narrowContent(Track track, bool onSong) {
    return Column(
      children: [
        _topBar(track),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: switch (_view) {
              PlayerView.song => Padding(
                key: const ValueKey('song'),
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
                child: Center(child: SwipeToSkip(child: _BigArt(track))),
              ),
              PlayerView.lyrics => LyricsView(track, key: ValueKey(track.id)),
              PlayerView.queue => const UpNext(key: ValueKey('queue')),
            },
          ),
        ),
        _NowPlayingInfo(track),
        if (onSong)
          _LyricsHint(() => setState(() => _view = PlayerView.lyrics)),
      ],
    );
  }

  Widget _wide(Track track) {
    final panel = _view == PlayerView.song ? PlayerView.queue : _view;
    return Column(
      children: [
        _topBar(track, tabs: false),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(48, 8, 48, 16),
                        child: Center(
                          child: SwipeToSkip(child: _BigArt(track)),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: _NowPlayingInfo(track),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(0, 8, 24, 24),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: _ViewTabs(
                          panel,
                          (v) => setState(() => _view = v),
                          includeSong: false,
                        ),
                      ),
                      Expanded(
                        child: panel == PlayerView.lyrics
                            ? LyricsView(track, key: ValueKey(track.id))
                            : const UpNext(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The "swipe up for lyrics" cue under the controls on phones.
class _LyricsHint extends StatelessWidget {
  const _LyricsHint(this.onTap);

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.keyboard_arrow_up_rounded,
              color: EncoreColors.textTertiary,
            ),
            Text(
              'Lyrics',
              style: TextStyle(
                color: EncoreColors.textTertiary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill tabs: Song / Lyrics / Up next.
class _ViewTabs extends StatelessWidget {
  const _ViewTabs(this.selected, this.onSelect, {this.includeSong = true});

  final PlayerView selected;
  final ValueChanged<PlayerView> onSelect;
  final bool includeSong;

  @override
  Widget build(BuildContext context) {
    const labels = {
      PlayerView.song: 'Song',
      PlayerView.lyrics: 'Lyrics',
      PlayerView.queue: 'Up next',
    };
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final view in labels.keys)
            if (includeSong || view != PlayerView.song)
              GestureDetector(
                onTap: () => onSelect(view),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: view == selected
                        ? EncoreColors.text
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    labels[view]!,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: view == selected
                          ? Colors.black
                          : EncoreColors.textSecondary,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// The artwork's colours as a soft, blurred-looking background. A tiny
/// decode stretched to full screen looks blurred without a blur filter.
class _Backdrop extends StatelessWidget {
  const _Backdrop(this.track);

  final Track track;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder(
        valueListenable: nowPlayingColor,
        builder: (context, color, _) => Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: backdropColor(color)),
            if (track.artUrl.isNotEmpty)
              Opacity(
                opacity: 0.55,
                child: Image.network(
                  sizedArt(track.artUrl, 60),
                  cacheWidth: 16,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x66000000), Color(0xE6000000)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigArt extends StatelessWidget {
  const _BigArt(this.track);

  final Track track;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                blurRadius: 24,
                offset: Offset(0, 12),
                color: Color(0x73000000),
              ),
            ],
          ),
          child: Artwork(track.artUrl, radius: 18),
        ),
      ),
    );
  }
}

/// Title, artist, like, seek bar and transport controls.
class _NowPlayingInfo extends StatelessWidget {
  const _NowPlayingInfo(this.track);

  final Track track;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: track.artistId == null
                          ? null
                          : () => openArtist(track.artistId!),
                      child: Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyLarge?.copyWith(
                          color: EncoreColors.text.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              LikeButton(track, size: 26),
            ],
          ),
          const SizedBox(height: 12),
          const SeekBar(),
          const SizedBox(height: 8),
          const TransportControls(large: true),
        ],
      ),
    );
  }
}
