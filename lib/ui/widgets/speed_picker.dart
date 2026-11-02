import 'package:flutter/material.dart';

import '../../services/settings.dart';
import 'common.dart';
import 'sleep_timer_picker.dart';

/// "1.25×"; "1×" is "Normal".
String speedLabel(double speed) {
  if (speed == 1) return 'Normal';
  final text = speed.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$text×';
}

/// The playback speed, when it isn't normal (shown in the player's menu).
String? speedStatus() =>
    settings.speed.value == 1 ? null : speedLabel(settings.speed.value);

/// Picks how fast songs play: a sheet on phones, a dialog on desktop.
Future<void> showPlaybackSpeed(BuildContext context) async {
  final now = settings.speed.value;
  final chosen = await chooseOption(
    context,
    title: 'Playback speed',
    options: [for (final s in Settings.speeds) (speedLabel(s), s == now)],
  );
  if (chosen == null) return;
  settings.speed.value = Settings.speeds.firstWhere(
    (s) => speedLabel(s) == chosen,
  );
  if (context.mounted) {
    showToast(context, 'Playback speed: ${speedLabel(settings.speed.value)}');
  }
}
