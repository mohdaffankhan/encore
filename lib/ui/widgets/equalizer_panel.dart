import 'package:flutter/material.dart';

import '../../services/equalizer.dart';
import '../../services/settings.dart';
import '../theme.dart';
import 'common.dart';

/// What the equalizer is set to, for a menu or a settings row: "Off", a
/// preset's name, or "Custom".
String equalizerStatus() {
  if (!settings.equalizerOn.value) return 'Off';
  return Equalizer.presetFor(settings.equalizerGains.value) ?? 'Custom';
}

/// The equalizer, in a sheet on phones or a dialog on desktop (from the
/// player's menu).
Future<void> showEqualizer(BuildContext context) {
  if (isWide(context)) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: EncoreColors.surfaceRaised,
        child: const SizedBox(
          width: 480,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: EqualizerPanel(),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: EncoreColors.surfaceRaised,
    builder: (context) => const SafeArea(child: EqualizerPanel()),
  );
}

/// On/off, presets, and a slider per band.
class EqualizerPanel extends StatelessWidget {
  const EqualizerPanel({super.key});

  static String _hz(int hz) => hz < 1000
      ? '$hz Hz'
      : '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)} kHz';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        settings.equalizerOn,
        settings.equalizerGains,
      ]),
      builder: (context, _) {
        final on = settings.equalizerOn.value;
        final gains = settings.equalizerGains.value;
        final preset = Equalizer.presetFor(gains);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text(
                'Equalizer',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              value: on,
              onChanged: (v) => settings.equalizerOn.value = v,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final MapEntry(key: name, value: values)
                      in Equalizer.presets.entries)
                    ChoiceChip(
                      label: Text(name),
                      selected: on && preset == name,
                      onSelected: (_) {
                        settings.equalizerGains.value = values;
                        settings.equalizerOn.value = true;
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 236,
              child: Row(
                children: [
                  for (final (i, hz) in Equalizer.bands.indexed)
                    Expanded(
                      child: _Band(
                        label: _hz(hz),
                        gain: gains[i],
                        enabled: on,
                        onChanged: (g) {
                          settings.equalizerGains.value = [...gains]..[i] = g;
                          settings.equalizerOn.value = true;
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One band: its gain, a vertical slider, and its frequency.
class _Band extends StatelessWidget {
  const _Band({
    required this.label,
    required this.gain,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double gain;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final db = gain == 0 ? '0' : '${gain > 0 ? '+' : ''}${gain.round()}';
    return Semantics(
      label: '$label band',
      child: Column(
        children: [
          Text(
            '$db dB',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: enabled ? EncoreColors.text : EncoreColors.textTertiary,
            ),
          ),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              // A plain track and the thumb: a gain is up or down from 0,
              // not filled from the bottom like a volume.
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: EncoreColors.surfaceHighest,
                  inactiveTrackColor: EncoreColors.surfaceHighest,
                  trackHeight: 4,
                  tickMarkShape: SliderTickMarkShape.noTickMark,
                  thumbColor: enabled
                      ? EncoreColors.accent
                      : EncoreColors.textTertiary,
                ),
                child: Slider(
                  value: gain,
                  min: -Equalizer.maxGain,
                  max: Equalizer.maxGain,
                  divisions: (Equalizer.maxGain * 2).round(),
                  label: '$db dB',
                  onChanged: (g) => onChanged(g.roundToDouble()),
                ),
              ),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: EncoreColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
