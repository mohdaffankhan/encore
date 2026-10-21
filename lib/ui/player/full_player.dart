import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/player.dart';
import '../art_colors.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/widgets.dart';
import 'buttons.dart';
import 'controls.dart';
import 'lyrics_sheet.dart';
import 'lyrics_view.dart';
import 'swipe_to_skip.dart';
import 'up_next.dart';

enum PlayerView { song, lyrics, queue }

/// Opens the full-screen player, optionally on lyrics or the queue.
void openFullPlayer(BuildContext context, {PlayerView view = PlayerView.song}) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      // Not opaque: pulling the player down shows the app behind it.
      opaque: false,
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

class _FullPlayerState extends State<FullPlayer>
    with SingleTickerProviderStateMixin {
  late var _view = widget.initialView;

  /// Phones: how far the player is pulled down (to close it).
  late final _pull = AnimationController.unbounded(vsync: this);

  /// Phones: lyrics are a sheet over the song, not a view of their own.
  final _lyrics = LyricsSheetController();

  @override
  void initState() {
    super.initState();
    if (widget.initialView == PlayerView.lyrics) _lyrics.open.value = true;
  }

  @override
  void dispose() {
    _lyrics.dispose();
    _pull.dispose();
    super.dispose();
  }

  /// Phones: a vertical drag on the song pulls the lyrics sheet up or, with
  /// the sheet closed, pulls the player down to close it. Both follow the
  /// finger.
  void _dragUpdate(DragUpdateDetails details) {
    final dy = details.delta.dy;
    if (_pull.value > 0 || (dy > 0 && _lyrics.isClosed)) {
      _pull.value = (_pull.value + dy).clamp(0, double.infinity);
    } else {
      _lyrics.dragBy(dy);
    }
  }

  void _dragEnd(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (_pull.value > 0) {
      if (_pull.value > 150 || v > 700) {
        Navigator.pop(context);
      } else {
        _pull.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    } else {
      _lyrics.endDrag(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    // Phones: Back closes the lyrics or up next before the player.
    return ValueListenableBuilder(
      valueListenable: _lyrics.open,
      builder: (context, lyricsOpen, child) => PopScope(
        canPop: wide || (_view != PlayerView.queue && !lyricsOpen),
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (lyricsOpen) {
            _lyrics.close();
          } else {
            setState(() => _view = PlayerView.song);
          }
        },
        child: child!,
      ),
      child: AnimatedBuilder(
        animation: _pull,
        builder: (context, child) =>
            Transform.translate(offset: Offset(0, _pull.value), child: child),
        child: _scaffold(),
      ),
    );
  }

  Widget _scaffold() {
    return Scaffold(
      body: ValueListenableBuilder(
        valueListenable: player.nowPlaying,
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
                    child: _ViewTabs(
                      _view == PlayerView.queue
                          ? PlayerView.queue
                          : PlayerView.song,
                      (v) => setState(() => _view = v),
                      includeLyrics: false,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SleepTimerIndicator(size: 24),
        TrackMenu(track, color: EncoreColors.text, inPlayer: true),
      ],
    ),
  );

  Widget _narrow(Track track) {
    final onSong = _view != PlayerView.queue;
    return Stack(
      children: [
        Column(
          children: [
            _topBar(track),
            Expanded(
              // Swipe up on the song for lyrics, down to close the player.
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: onSong ? _dragUpdate : null,
                onVerticalDragEnd: onSong ? _dragEnd : null,
                child: Column(
                  children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: onSong
                            ? Padding(
                                key: const ValueKey('song'),
                                padding: const EdgeInsets.fromLTRB(
                                  28,
                                  24,
                                  28,
                                  8,
                                ),
                                child: Center(
                                  child: SwipeToSkip(child: _BigArt(track)),
                                ),
                              )
                            : const UpNext(key: ValueKey('queue')),
                      ),
                    ),
                    _NowPlayingInfo(track),
                    // Room for the closed lyrics sheet.
                    if (onSong) const SizedBox(height: LyricsSheet.barHeight),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (onSong)
          Positioned.fill(
            child: LyricsSheet(track: track, controller: _lyrics),
          ),
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

/// Pill tabs: Song / Lyrics / Up next (Song / Up next on phones).
class _ViewTabs extends StatelessWidget {
  const _ViewTabs(
    this.selected,
    this.onSelect, {
    this.includeSong = true,
    this.includeLyrics = true,
  });

  final PlayerView selected;
  final ValueChanged<PlayerView> onSelect;
  final bool includeSong;

  /// Phones show lyrics in a sheet instead of a tab.
  final bool includeLyrics;

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
            if ((includeSong || view != PlayerView.song) &&
                (includeLyrics || view != PlayerView.lyrics))
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
