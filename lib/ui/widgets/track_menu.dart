import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/downloads.dart';
import '../../services/library.dart';
import '../../services/player.dart';
import '../shell.dart';
import '../theme.dart';
import 'artwork.dart';
import 'common.dart';
import 'sleep_timer_picker.dart';

/// The ⋯ button for a song. [inPlayer]: the playing song's menu (full
/// player and desktop player bar), which also has the sleep timer.
class TrackMenu extends StatelessWidget {
  const TrackMenu(this.track, {super.key, this.color, this.inPlayer = false});

  final Track track;
  final Color? color;
  final bool inPlayer;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'More',
      icon: Icon(
        Icons.more_horiz_rounded,
        color: color ?? EncoreColors.textSecondary,
      ),
      onPressed: () => showTrackMenu(context, track, inPlayer: inPlayer),
    );
  }
}

/// A song's actions: queue, radio, like, download, go to artist/album (and
/// the sleep timer for the playing song). Phones get a bottom sheet with
/// the song at the top, like YouTube Music and Spotify, so it never covers
/// the row it came from. Desktop gets a pop-up menu under the button, or at
/// [position] (a right-click).
Future<void> showTrackMenu(
  BuildContext context,
  Track track, {
  bool inPlayer = false,
  Offset? position,
}) async {
  final actions = _actions(track, inPlayer: inPlayer);
  final chosen = isWide(context)
      ? await _popup(context, actions, position)
      : await _sheet(context, track, actions);
  if (chosen != null && context.mounted) chosen.run(context);
}

class _Action {
  const _Action(this.icon, this.label, this.run, {this.detail});

  final IconData icon;
  final String label;
  final void Function(BuildContext context) run;

  /// Shown on the right, e.g. the sleep timer's time left.
  final String? detail;
}

List<_Action> _actions(Track track, {required bool inPlayer}) {
  final liked = userLibrary.isLiked(track);
  final downloading = downloads.progress.value.containsKey(track.id);
  return [
    if (!inPlayer && player.current != track)
      _Action(Icons.playlist_play_rounded, 'Play next', (context) {
        player.playNext(track);
        showToast(context, 'Playing next');
      }),
    _Action(Icons.radio_rounded, 'Start radio', (_) => player.playRadio(track)),
    _Action(
      liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      liked ? 'Remove from liked songs' : 'Like',
      (context) {
        userLibrary.toggleLike(track);
        showToast(
          context,
          liked ? 'Removed from Liked songs' : 'Added to Liked songs',
        );
      },
    ),
    if (downloads.isDownloaded(track))
      _Action(Icons.delete_outline_rounded, 'Remove download', (context) {
        downloads.remove(track);
        showToast(context, 'Download removed');
      })
    else if (!downloading)
      _Action(Icons.download_rounded, 'Download', (context) {
        downloads.download([track]);
        showToast(context, 'Downloading "${track.title}"');
      }),
    if (track.artistId case final id?)
      _Action(Icons.person_rounded, 'Go to artist', (_) => openArtist(id)),
    if (track.albumId case final id?)
      _Action(Icons.album_rounded, 'Go to album', (_) => openCollection(id)),
    if (inPlayer)
      _Action(
        Icons.bedtime_outlined,
        'Sleep timer',
        showSleepTimer,
        detail: sleepTimerStatus(short: true),
      ),
  ];
}

Future<_Action?> _popup(
  BuildContext context,
  List<_Action> actions,
  Offset? position,
) {
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final Rect anchor;
  if (position != null) {
    anchor = Rect.fromLTWH(position.dx, position.dy, 0, 0);
  } else {
    // Just under the ⋯ button.
    final box = context.findRenderObject()! as RenderBox;
    anchor = Rect.fromPoints(
      box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
  }
  return showMenu<_Action>(
    context: context,
    position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
    items: [
      for (final action in actions)
        PopupMenuItem(
          value: action,
          height: 44,
          child: Row(
            children: [
              Icon(action.icon, size: 20, color: EncoreColors.textSecondary),
              const SizedBox(width: 14),
              Flexible(
                child: Text(action.label, overflow: TextOverflow.ellipsis),
              ),
              if (action.detail case final detail?) ...[
                const SizedBox(width: 16),
                Text(
                  detail,
                  style: const TextStyle(color: EncoreColors.accent),
                ),
              ],
            ],
          ),
        ),
    ],
  );
}

Future<_Action?> _sheet(
  BuildContext context,
  Track track,
  List<_Action> actions,
) {
  return showModalBottomSheet<_Action>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: EncoreColors.surfaceRaised,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Artwork(track.artUrl, size: 48, radius: 6),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(fontSize: 15),
                ),
                subtitle: Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: EncoreColors.textSecondary,
                  ),
                ),
              ),
              const Divider(color: EncoreColors.hairline, height: 16),
              for (final action in actions)
                ListTile(
                  leading: Icon(action.icon, color: EncoreColors.text),
                  title: Text(action.label),
                  trailing: action.detail == null
                      ? null
                      : Text(
                          action.detail!,
                          style: const TextStyle(color: EncoreColors.accent),
                        ),
                  onTap: () => Navigator.pop(context, action),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}
