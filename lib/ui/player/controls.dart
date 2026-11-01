import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/player.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'buttons.dart';

/// Shuffle, previous, play/pause, next and repeat.
class TransportControls extends StatelessWidget {
  const TransportControls({super.key, this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final skip = large ? 36.0 : 26.0;
    final side = large ? 24.0 : 20.0;
    return Row(
      mainAxisSize: large ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ValueListenableBuilder(
          valueListenable: player.shuffle,
          builder: (context, on, _) => _ModeButton(
            tooltip: on ? 'Shuffle on' : 'Shuffle off',
            icon: Icons.shuffle_rounded,
            size: side,
            on: on,
            onPressed: player.toggleShuffle,
          ),
        ),
        IconButton(
          tooltip: 'Previous',
          iconSize: skip,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: player.previous,
        ),
        PlayPauseButton(size: large ? 38 : 24, circle: true),
        IconButton(
          tooltip: 'Next',
          iconSize: skip,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: player.next,
        ),
        ValueListenableBuilder(
          valueListenable: player.repeat,
          builder: (context, mode, _) => _ModeButton(
            tooltip: switch (mode) {
              Repeat.off => 'Repeat off',
              Repeat.all => 'Repeat all',
              Repeat.one => 'Repeat one',
            },
            icon: mode == Repeat.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            size: side,
            on: mode != Repeat.off,
            onPressed: player.cycleRepeat,
          ),
        ),
      ],
    );
  }
}

/// Shuffle and repeat: orange with a dot under it while on (like Spotify),
/// a pop when pressed, and a light tap on phones, so the change is felt.
class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.tooltip,
    required this.icon,
    required this.size,
    required this.on,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final double size;
  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = on ? EncoreColors.accent : EncoreColors.textSecondary;
    return IconButton(
      tooltip: tooltip,
      isSelected: on,
      onPressed: () {
        HapticFeedback.selectionClick();
        onPressed();
      },
      icon: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Keyed by state, so each change pops in.
          TweenAnimationBuilder<double>(
            key: ValueKey('$icon $on'),
            tween: Tween(begin: 0.7, end: 1),
            duration: const Duration(milliseconds: 260),
            curve: Curves.elasticOut,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Icon(icon, size: size, color: color),
          ),
          const SizedBox(height: 2),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? EncoreColors.accent : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}

/// The seek slider with elapsed and total time. Repaints on its own layer,
/// since position updates several times a second.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, this.timesBeside = false});

  /// Times left and right of the slider (desktop bar) instead of below.
  final bool timesBeside;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  /// While dragging, the thumb follows the pointer instead of playback.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: StreamBuilder(
        stream: player.audio.positionStream,
        builder: (context, snapshot) {
          // The song's own length until the player knows it (while it
          // loads), so it can be dragged then too.
          final total =
              player.audio.duration ??
              player.current?.duration ??
              Duration.zero;
          final max = total.inMilliseconds.toDouble();
          final pos =
              _dragging ??
              (player.resumeAt ?? snapshot.data ?? Duration.zero).inMilliseconds
                  .toDouble();
          final style = Theme.of(context).textTheme.bodySmall?.copyWith(
            color: EncoreColors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          );
          final elapsed = Text(
            formatDuration(Duration(milliseconds: pos.round())),
            style: style,
          );
          final length = Text(formatDuration(total), style: style);
          final slider = Slider(
            padding: const EdgeInsets.symmetric(vertical: 10),
            max: max > 0 ? max : 1,
            value: pos.clamp(0, max > 0 ? max : 1),
            // Always enabled, ignoring drags while the length is unknown:
            // flipping the slider between enabled and
            // disabled on every song change broke Flutter's accessibility
            // tree for the hidden player bar under the full player.
            onChanged: (v) {
              if (max > 0) setState(() => _dragging = v);
            },
            onChangeEnd: (v) {
              if (max > 0) {
                player.seek(Duration(milliseconds: v.round()));
              }
              setState(() => _dragging = null);
            },
          );
          if (widget.timesBeside) {
            return Row(
              children: [
                SizedBox(width: 44, child: elapsed),
                Expanded(child: slider),
                SizedBox(
                  width: 44,
                  child: Align(alignment: Alignment.centerRight, child: length),
                ),
              ],
            );
          }
          return Column(
            children: [
              slider,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [elapsed, length],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A volume icon (click to mute) and slider.
class VolumeControl extends StatefulWidget {
  const VolumeControl({super.key});

  @override
  State<VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<VolumeControl> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: player.audio.volumeStream,
      builder: (context, snapshot) {
        final volume = snapshot.data ?? 1;
        return _WheelVolume(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MuteButton(volume),
              // Shorter when the bar is short of room.
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: _VolumeSlider(volume),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MuteButton extends StatelessWidget {
  const _MuteButton(this.volume);

  final double volume;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: volume == 0 ? 'Unmute' : 'Mute',
      iconSize: 20,
      color: EncoreColors.textSecondary,
      icon: Icon(
        volume == 0
            ? Icons.volume_off_rounded
            : volume < 0.5
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded,
      ),
      // The player keeps the level to go back to, so unmuting in the bar
      // after muting in the full player (or with M) goes back to it.
      onPressed: player.toggleMute,
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider(this.volume, {this.onChangeStart, this.onChangeEnd});

  final double volume;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Slider(
      padding: EdgeInsets.zero,
      value: volume,
      onChanged: player.audio.setVolume,
      onChangeStart: onChangeStart,
      onChangeEnd: onChangeEnd,
    );
  }
}

/// The volume as a speaker icon whose slider slides out beside it while the
/// pointer is over it (like YouTube Music's), for where a slider always
/// showing would crowd the controls. Clicking the icon mutes.
class VolumeButton extends StatefulWidget {
  const VolumeButton({super.key});

  @override
  State<VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<VolumeButton> {
  var _hovered = false;

  /// Stays open while dragging, even if the pointer leaves it.
  var _dragging = false;

  @override
  Widget build(BuildContext context) {
    final open = _hovered || _dragging;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _WheelVolume(
        child: StreamBuilder(
          stream: player.audio.volumeStream,
          builder: (context, snapshot) {
            final volume = snapshot.data ?? 1;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRect(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: open ? 100 : 0,
                    height: 40,
                    child: OverflowBox(
                      alignment: Alignment.centerRight,
                      minWidth: 100,
                      maxWidth: 100,
                      child: ExcludeFocus(
                        excluding: !open,
                        // Room for the thumb at either end.
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _VolumeSlider(
                            volume,
                            onChangeStart: (_) =>
                                setState(() => _dragging = true),
                            onChangeEnd: (_) =>
                                setState(() => _dragging = false),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _MuteButton(volume),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The mouse wheel over it turns the volume up or down (and doesn't scroll
/// the page behind it).
class _WheelVolume extends StatelessWidget {
  const _WheelVolume({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        GestureBinding.instance.pointerSignalResolver.register(
          event,
          (event) => player.changeVolume(
            (event as PointerScrollEvent).scrollDelta.dy < 0 ? 0.05 : -0.05,
          ),
        );
      },
      child: child,
    );
  }
}
