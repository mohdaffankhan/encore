import 'package:flutter/material.dart';

import '../../services/sleep_timer.dart';
import '../theme.dart';
import 'common.dart';

const _durations = [
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(minutes: 45),
  Duration(hours: 1),
];

String _label(Duration d) =>
    d.inMinutes < 60 ? '${d.inMinutes} minutes' : '1 hour';

/// What the sleep timer is doing, or null when it is off. [short] for the
/// menu ("29 min", "End of song").
String? sleepTimerStatus({bool short = false}) {
  final setting = sleepTimer.setting.value;
  if (setting == null) return null;
  final left = sleepTimer.remaining;
  if (left == null) {
    return short ? 'End of song' : 'Pausing at the end of this song';
  }
  final minutes = (left.inSeconds / 60).ceil();
  return short ? '$minutes min' : 'Pausing in $minutes min';
}

/// Picks the sleep timer: a sheet on phones, a dialog on desktop.
Future<void> showSleepTimer(BuildContext context) async {
  final status = sleepTimerStatus();
  final endOfSong = sleepTimer.setting.value?.endOfSong ?? false;
  final options = <(String, VoidCallback, bool)>[
    for (final d in _durations) (_label(d), () => sleepTimer.set(d), false),
    ('End of song', sleepTimer.untilEndOfSong, endOfSong),
    if (status != null) ('Turn off', sleepTimer.cancel, false),
  ];
  Widget list(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (label, _, selected) in options)
        ListTile(
          title: Text(label),
          trailing: selected
              ? const Icon(Icons.check_rounded, color: EncoreColors.accent)
              : null,
          onTap: () => Navigator.pop(context, label),
        ),
    ],
  );
  final title = Text(
    status ?? 'Sleep timer',
    style: TextStyle(
      fontWeight: FontWeight.w700,
      color: status == null ? EncoreColors.text : EncoreColors.accent,
    ),
  );
  final String? chosen;
  if (isWide(context)) {
    chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: title,
        backgroundColor: EncoreColors.surfaceRaised,
        children: [SizedBox(width: 320, child: list(context))],
      ),
    );
  } else {
    chosen = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: EncoreColors.surfaceRaised,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(alignment: Alignment.centerLeft, child: title),
            ),
            list(context),
          ],
        ),
      ),
    );
  }
  if (chosen == null) return;
  for (final (label, apply, _) in options) {
    if (label == chosen) apply();
  }
  if (context.mounted) {
    showToast(
      context,
      chosen == 'Turn off' ? 'Sleep timer off' : sleepTimerStatus()!,
    );
  }
}
