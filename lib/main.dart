import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app.dart';
import 'services/library.dart';
import 'ui/art_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A song is ~3-8 MB; mpv's default 32 MB read-ahead buffer is wasted RAM.
  JustAudioMediaKit.bufferSize = 8 * 1024 * 1024;
  JustAudioMediaKit.ensureInitialized(); // Windows + Linux backend
  if (Platform.isAndroid) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'dev.encore.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'drawable/ic_stat_encore',
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
