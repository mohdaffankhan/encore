import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app.dart';
import 'services/library.dart';
import 'services/media_session.dart';
import 'ui/art_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A song is ~3-8 MB; mpv's default 32 MB read-ahead buffer is wasted RAM.
  JustAudioMediaKit.bufferSize = 8 * 1024 * 1024;
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
  }
  // Artwork is decoded at display size, so a smaller cache still holds
  // plenty of images (Flutter's default is 100 MB).
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 48 << 20
    ..maximumSize = 400;
  await userLibrary.load();
  watchNowPlayingColor();
  runApp(const EncoreApp());
}
