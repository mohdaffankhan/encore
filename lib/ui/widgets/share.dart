import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import 'common.dart';
import 'playlist_dialogs.dart';

const _channel = MethodChannel('dev.encore.app/share');

/// A song on YouTube Music.
String songLink(Track track) => 'https://music.youtube.com/watch?v=${track.id}';

/// An album or playlist on YouTube Music, from its browse id.
String collectionLink(String browseId) => browseId.startsWith('VL')
    ? 'https://music.youtube.com/playlist?list=${browseId.substring(2)}'
    : 'https://music.youtube.com/browse/$browseId';

/// What sharing a song sends.
String songShareText(Track track) =>
    '${track.title} – ${track.artist}\n${songLink(track)}';

/// What sharing one of the user's playlists sends: it isn't on YouTube,
/// so links that play its songs there (up to 50 a link).
String playlistShareText(Playlist playlist) {
  final links = youTubeLinks(playlist.tracks);
  return [
    '${playlist.name} (${songCount(playlist.tracks.length)})',
    if (links.length == 1)
      '${links.single}'
    else
      for (final (i, link) in links.indexed) 'Part ${i + 1}: $link',
  ].join('\n');
}

/// Shares [text]: Android's share sheet (WhatsApp, Telegram, Copy…); on
/// desktop it is copied, and says so.
@visibleForTesting
bool shareSheet = Platform.isAndroid;

Future<void> share(BuildContext context, String text, {String? subject}) async {
  if (shareSheet) {
    try {
      await _channel.invokeMethod('share', {'text': text, 'subject': ?subject});
      return;
    } catch (e) {
      debugPrint('Share sheet failed, copying instead: $e');
    }
  }
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showToast(context, 'Link copied');
}
