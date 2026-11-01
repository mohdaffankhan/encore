import 'package:audio_service/audio_service.dart';
import 'package:encore/models.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/media_session.dart';
import 'package:encore/services/player.dart';
import 'package:flutter_test/flutter_test.dart';

// The notification had no like button (Spotify and YouTube Music do).
// The compact view pointed past the notification's own buttons (the like
// button isn't one of them), which Android 12 and older reject.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const song = Track(id: 's', title: 'Song', artist: 'X', artUrl: '');

  setUp(() {
    player.queue.value = [song];
    player.index.value = 0;
    userLibrary.liked.value = [];
  });

  tearDown(() {
    player.queue.value = [];
    player.index.value = -1;
    userLibrary.liked.value = [];
  });

  test('the notification likes the song, and shows it is liked', () async {
    final handler = EncoreAudioHandler();
    String heart() => handler.playbackState.value.controls.last.androidIcon;

    userLibrary.liked.value = [...userLibrary.liked.value];
    expect(heart(), 'drawable/ic_favorite_border');
    expect(handler.playbackState.value.controls, hasLength(4));

    // The notification's own buttons are the ones that aren't custom; the
    // compact view shows previous, play/pause and next among them.
    final own = [
      for (final c in handler.playbackState.value.controls)
        if (c.customAction == null) c,
    ];
    expect(
      [
        for (final i
            in handler.playbackState.value.androidCompactActionIndices!)
          own[i].action,
      ],
      [MediaAction.skipToPrevious, MediaAction.play, MediaAction.skipToNext],
    );

    await handler.customAction('like');
    expect(userLibrary.isLiked(song), isTrue);
    expect(heart(), 'drawable/ic_favorite');

    await handler.customAction('like');
    expect(userLibrary.isLiked(song), isFalse);
    expect(heart(), 'drawable/ic_favorite_border');
  });
}
