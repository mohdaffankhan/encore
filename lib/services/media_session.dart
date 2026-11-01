import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'library.dart';
import 'player.dart';

/// Connects the player to the system media controls on Android: the player
/// in the notification panel and on the lock screen, headset buttons, and
/// background playback. Shows like, previous, play/pause and next (like
/// Spotify and YouTube Music), and no stop.
class EncoreAudioHandler extends BaseAudioHandler with SeekHandler {
  EncoreAudioHandler() {
    final audio = player.audio;
    audio.playbackEventStream.listen((_) => _broadcastState());
    audio.playingStream.listen((_) => _broadcastState());
    audio.durationStream.listen((_) => _broadcastItem());
    player.nowPlaying.addListener(_broadcastItem);
    // The heart follows likes made anywhere (and the song changing).
    userLibrary.liked.addListener(_broadcastState);
    player.nowPlaying.addListener(_broadcastState);
  }

  static const _like = 'like';

  static const _states = {
    ProcessingState.idle: AudioProcessingState.idle,
    ProcessingState.loading: AudioProcessingState.loading,
    ProcessingState.buffering: AudioProcessingState.buffering,
    ProcessingState.ready: AudioProcessingState.ready,
    ProcessingState.completed: AudioProcessingState.completed,
  };

  void _broadcastState() {
    final audio = player.audio;
    final track = player.current;
    final liked = track != null && userLibrary.isLiked(track);
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.custom(
            androidIcon: liked
                ? 'drawable/ic_favorite'
                : 'drawable/ic_favorite_border',
            label: liked ? 'Unlike' : 'Like',
            name: _like,
          ),
          MediaControl.skipToPrevious,
          audio.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        // Previous, play/pause and next also show in the compact
        // (collapsed) view.
        androidCompactActionIndices: const [1, 2, 3],
        systemActions: const {MediaAction.seek},
        processingState: player.loading.value
            ? AudioProcessingState.loading
            : _states[audio.processingState]!,
        playing: audio.playing,
        updatePosition: audio.position,
        bufferedPosition: audio.bufferedPosition,
        speed: audio.speed,
        queueIndex: player.index.value,
      ),
    );
  }

  void _broadcastItem() {
    final track = player.current;
    if (track == null) return;
    mediaItem.add(
      MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: player.audio.duration ?? track.duration,
        artUri: track.artUrl.isEmpty ? null : Uri.parse(track.artUrl),
      ),
    );
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.audio.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() => player.next();

  @override
  Future<void> skipToPrevious() => player.previous();

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == _like) player.toggleLikeCurrent();
  }

  /// There is no stop button; if the system asks (e.g. the notification is
  /// dismissed while paused), just pause.
  @override
  Future<void> stop() => player.audio.pause();

  /// Swiped away from the recent apps: the music stops and its notification
  /// goes, as in Spotify and YouTube Music (it went on playing).
  @override
  Future<void> onTaskRemoved() async {
    await player.audio.pause();
    await super.stop();
  }
}
