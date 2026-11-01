import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'api/clients.dart';
import 'app.dart';
import 'self_test.dart';
import 'services/desktop_window.dart';
import 'services/downloads.dart';
import 'services/home_cache.dart';
import 'services/library.dart';
import 'services/media_session.dart';
import 'services/player.dart';
import 'services/session.dart';
import 'services/settings.dart';
import 'services/storage.dart';
import 'services/windows_media_controls.dart';
import 'ui/art_colors.dart';

Future<void> main([List<String> args = const []]) async {
  final selfTest = args.contains('--self-test');
  if (selfTest) useTestData();
  WidgetsFlutterBinding.ensureInitialized();
  // A song is ~3-8 MB; mpv's default 32 MB read-ahead buffer is wasted RAM.
  JustAudioMediaKit.bufferSize = 8 * 1024 * 1024;
  // The next song is lined up in the player; mpv opens it ahead, so it
  // follows without a gap.
  JustAudioMediaKit.prefetchPlaylist = true;
  JustAudioMediaKit.ensureInitialized(); // Windows + Linux backend
  if (Platform.isAndroid) {
    // Notification panel / lock screen player and background playback.
    await AudioService.init(
      builder: EncoreAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.encore.playback',
        androidNotificationChannelName: 'Playback',
        androidNotificationOngoing: true,
        androidNotificationIcon: 'drawable/ic_stat_encore',
      ),
    );
  } else if (Platform.isLinux) {
    // MPRIS: the desktop's media controls, playerctl, headset buttons.
    try {
      await AudioService.init(
        builder: EncoreAudioHandler.new,
        config: const AudioServiceConfig(
          // MPRIS names the player after these.
          androidNotificationChannelId: 'io.github.mohdaffankhan.Encore',
          androidNotificationChannelName: 'Encore',
        ),
      );
    } catch (e) {
      // No session bus (e.g. a server): it still plays.
      debugPrint('No media controls: $e');
    }
  } else if (Platform.isWindows) {
    WindowsMediaControls(player).start();
  }
  if (Platform.isWindows || Platform.isLinux) DesktopWindow(player).start();
  // Artwork is decoded at display size, so a smaller cache still holds
  // plenty of images (Flutter's default is 100 MB).
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 48 << 20
    ..maximumSize = 400;
  await userLibrary.load();
  // Which YouTube clients to ask for songs (an online file, kept current).
  await loadClients();
  await settings.load();
  await playbackSession.restore();
  await loadLastHome();
  unawaited(downloads.resume());
  watchNowPlayingColor();
  runApp(const EncoreApp());
  if (selfTest) {
    await runSelfTest(mediaKeys: args.contains('--media-check'));
  }
}
