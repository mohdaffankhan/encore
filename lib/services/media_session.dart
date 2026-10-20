import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'player.dart';

/// Connects the player to the system media controls on Android: the player
/// in the notification panel and on the lock screen, headset buttons, and
/// background playback. Shows exactly previous, play/pause and next.
class EncoreAudioHandler extends BaseAudioHandler with SeekHandler {
  EncoreAudioHandler() {
    final audio = player.audio;
    audio.playbackEventStream.listen((_) => _broadcastState());
    audio.playingStream.listen((_) => _broadcastState());
    audio.durationStream.listen((_) => _broadcastItem());
    player.index.addListener(_broadcastItem);
  }

  static const _states = {
    ProcessingState.idle: AudioProcessingState.idle,
    ProcessingState.loading: AudioProcessingState.loading,
    ProcessingState.buffering: AudioProcessingState.buffering,
    ProcessingState.ready: AudioProcessingState.ready,
    ProcessingState.completed: AudioProcessingState.completed,
  };

  void _broadcastState() {
    final audio = player.audio;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          audio.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        // All three buttons also show in the compact (collapsed) view.
        androidCompactActionIndices: const [0, 1, 2],
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
  Future<void> play() => player.audio.play();

  @override
  Future<void> pause() => player.audio.pause();

  @override
  Future<void> seek(Duration position) => player.audio.seek(position);

  @override
  Future<void> skipToNext() => player.next();

  @override
  Future<void> skipToPrevious() => player.previous();

  /// There is no stop button; if the system asks (e.g. the notification is
  /// dismissed while paused), just pause.
  @override
  Future<void> stop() => player.audio.pause();
}
