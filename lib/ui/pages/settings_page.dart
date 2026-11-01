import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models.dart';
import '../../services/art_cache.dart';
import '../../services/downloads.dart';
import '../../services/library.dart';
import '../../services/settings.dart';
import '../shortcuts.dart';
import '../theme.dart';
import '../widgets/widgets.dart';

/// Sound quality, data, storage and about: only what is worth choosing.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// Sizes on disk, measured when the page opens and after clearing.
  late Future<(int, int)> _sizes = _measure();

  static Future<(int, int)> _measure() async =>
      (await downloads.size(), await artCacheSize());

  void _remeasure() => setState(() => _sizes = _measure());

  @override
  Widget build(BuildContext context) {
    final desktop = !Platform.isAndroid && !Platform.isIOS;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        // Rows as wide as a phone's at most, so a control is never far from
        // what it sets (the rest of a desktop window stays empty).
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: EdgeInsets.only(
              bottom: 32,
              right: max(0, constraints.maxWidth - 720),
            ),
            children: [
              const PageTitle('Settings'),
              const SectionHeader('Sound and data'),
              _QualityRow(
                title: 'Streaming quality',
                setting: settings.streamQuality,
              ),
              if (Platform.isAndroid)
                ValueListenableBuilder(
                  valueListenable: settings.saveDataOnMobile,
                  builder: (context, on, _) => _Row(
                    title: 'Save data on mobile data',
                    subtitle: 'Stream at low quality when not on Wi-Fi',
                    trailing: Switch(
                      value: on,
                      onChanged: (v) => settings.saveDataOnMobile.value = v,
                    ),
                    onTap: () => settings.saveDataOnMobile.value = !on,
                  ),
                ),
              _QualityRow(
                title: 'Download quality',
                setting: settings.downloadQuality,
              ),
              const SectionHeader('Storage'),
              FutureBuilder(
                future: _sizes,
                builder: (context, snapshot) {
                  final (downloaded, art) = snapshot.data ?? (null, null);
                  return Column(
                    children: [
                      ValueListenableBuilder(
                        valueListenable: userLibrary.downloads,
                        builder: (context, tracks, _) => _Row(
                          title: 'Downloads',
                          subtitle: tracks.isEmpty
                              ? 'None'
                              : '${songCount(tracks.length)} · '
                                    '${_size(downloaded)}',
                          trailing: TextButton(
                            onPressed: tracks.isEmpty
                                ? null
                                : () => _removeDownloads(context),
                            child: const Text('Remove all'),
                          ),
                        ),
                      ),
                      _Row(
                        title: 'Artwork kept on this device',
                        subtitle:
                            '${_size(art)} · shows art at once, even offline',
                        trailing: TextButton(
                          onPressed: art == 0
                              ? null
                              : () async {
                                  await clearArtCache();
                                  imageCache.clear();
                                  _remeasure();
                                },
                          child: const Text('Clear'),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SectionHeader('About'),
              FutureBuilder(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) => _Row(
                  title: 'Encore',
                  subtitle: snapshot.data == null
                      ? 'Version'
                      : 'Version ${snapshot.data!.version} '
                            '(${snapshot.data!.buildNumber})',
                ),
              ),
              _Row(
                title: 'Source code',
                subtitle: 'github.com/mohdaffankhan/encore',
                trailing: const Icon(
                  Icons.open_in_new_rounded,
                  size: 20,
                  color: EncoreColors.textSecondary,
                ),
                onTap: () => launchUrl(
                  Uri.https('github.com', '/mohdaffankhan/encore'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              if (desktop)
                const _Row(
                  title: 'Keyboard shortcuts',
                  subtitle: 'Ctrl + /',
                  onTap: showShortcuts,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removeDownloads(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EncoreColors.surfaceRaised,
        title: const Text('Remove all downloads?'),
        content: const Text(
          "The songs stay in your library, but won't play offline until "
          'downloaded again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await downloads.removeAll();
    _remeasure();
  }
}

/// e.g. "84 MB"; "…" while it is measured.
String _size(int? bytes) {
  if (bytes == null) return '…';
  if (bytes < 1 << 20) return '${(bytes / 1024).round()} KB';
  if (bytes < 1 << 30) return '${(bytes / (1 << 20)).round()} MB';
  return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
}

/// A setting: what it is, what it's set to, and a control on the right.
class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad - 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleSmall?.copyWith(fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(
                        color: EncoreColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// A quality setting: tap to pick from High / Normal / Low.
class _QualityRow extends StatelessWidget {
  const _QualityRow({required this.title, required this.setting});

  final String title;
  final ValueNotifier<AudioQuality> setting;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: setting,
      builder: (context, quality, _) => _Row(
        title: title,
        subtitle: '${quality.label} · ${quality.detail}',
        trailing: const Icon(
          Icons.expand_more_rounded,
          color: EncoreColors.textSecondary,
        ),
        onTap: () => showActionMenu(context, [
          for (final q in AudioQuality.values)
            MenuAction(
              q == quality
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              q.label,
              (_) => setting.value = q,
              detail: q.detail,
            ),
        ], header: _SheetTitle(title)),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}
