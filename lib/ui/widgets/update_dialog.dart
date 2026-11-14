import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/updates.dart';
import '../theme.dart';

/// "Encore 0.3.0 is out": what's new, and Skip or Update.
Future<void> offerUpdate(
  BuildContext context,
  Release release, {
  required String current,
}) async {
  final update = await showDialog<bool>(
    context: context,
    builder: (context) => UpdateDialog(release, current: current),
  );
  if (!context.mounted) return;
  if (update == true) {
    await startUpdate(context, release);
  } else if (update == false) {
    await updates.skip(release);
  }
}

class UpdateDialog extends StatelessWidget {
  const UpdateDialog(this.release, {super.key, required this.current});

  final Release release;
  final String current;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final secondary = text.bodySmall?.copyWith(
      color: EncoreColors.textSecondary,
    );
    return AlertDialog(
      title: Text('Encore ${release.version} is out'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You have $current.', style: secondary),
              if (release.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text("What's new", style: text.titleSmall),
                const SizedBox(height: 6),
                for (final note in release.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('•  $note', style: text.bodyMedium),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Update'),
        ),
      ],
    );
  }
}

/// How an update installs, by kind (tests answer themselves).
@visibleForTesting
var installApk = Updates.installApk;
@visibleForTesting
var runInstaller = Updates.runInstaller;
@visibleForTesting
var openReleasePage = (Uri page) =>
    launchUrl(page, mode: LaunchMode.externalApplication);
@visibleForTesting
var downloadsDir = Updates.downloadsDir;
@visibleForTesting
var downloadUpdate = updates.download;

/// Downloads the release's file for this copy (checked against GitHub's
/// checksum) and installs it; or opens the release page where Encore can't
/// update itself (portable, AppImage, tar.gz). A failure says why, with
/// Try again and the release page, and changes nothing.
Future<void> startUpdate(BuildContext context, Release release) async {
  final way = updates.way();
  final file = await updates.fileFor(release);
  if (!context.mounted) return;
  if (file == null || way == UpdateWay.page) {
    await openReleasePage(release.page);
    return;
  }
  while (true) {
    if (!context.mounted) return;
    final result = await showDialog<Object?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Downloading(file),
    );
    if (!context.mounted) return;
    if (result is File) {
      if (way == UpdateWay.windowsInstaller) {
        await runInstaller(result);
        return;
      }
      // Android: its installer, once the user allows Encore to install
      // apps (the first time, its settings open; then Install again).
      while (!await installApk(result)) {
        if (!context.mounted) return;
        final again = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Allow Encore to install the update'),
            content: const Text(
              'Turn on "Allow from this source" for Encore, come back, '
              'then tap Install.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Install'),
              ),
            ],
          ),
        );
        if (again != true) return;
      }
      return;
    }
    if (result is! UpdateFailed || result.message == 'Cancelled') return;
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Couldn't download the update"),
        content: Text(
          '${result.message}. Nothing was changed: Encore is as it was.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('page'),
            child: const Text('Open download page'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('retry'),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
    if (next == 'page') await openReleasePage(release.page);
    if (next != 'retry') return;
  }
}

/// The download, with its progress and Cancel; pops the checked file, or
/// the [UpdateFailed].
@visibleForTesting
class Downloading extends StatefulWidget {
  const Downloading(this.file, {super.key});

  final ReleaseFile file;

  @override
  State<Downloading> createState() => _DownloadingState();
}

class _DownloadingState extends State<Downloading> {
  double _progress = 0;
  var _cancelled = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    Object result;
    try {
      result = await downloadUpdate(
        widget.file,
        dir: await downloadsDir(),
        progress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        cancelled: () => _cancelled,
      );
    } on UpdateFailed catch (e) {
      result = e;
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final mb = (widget.file.size / (1 << 20)).toStringAsFixed(1);
    return AlertDialog(
      title: const Text('Downloading the update'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: _progress == 0 ? null : _progress),
          const SizedBox(height: 8),
          Text(
            '${(_progress * 100).round()}% of $mb MB',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: EncoreColors.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _cancelled
              ? null
              : () => setState(() => _cancelled = true),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
