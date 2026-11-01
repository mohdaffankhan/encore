import 'package:encore/models.dart';
import 'package:encore/services/library.dart';
import 'package:encore/services/media_session.dart';
import 'package:encore/services/player.dart';
import 'package:flutter_test/flutter_test.dart';

// The notification had no like button (Spotify and YouTube Music do).

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
    String heart() => handler.playbackState.value.controls.first.androidIcon;

    userLibrary.liked.value = [...userLibrary.liked.value];
    expect(heart(), 'drawable/ic_favorite_border');
    expect(handler.playbackState.value.controls, hasLength(4));

    await handler.customAction('like');
    expect(userLibrary.isLiked(song), isTrue);
    expect(heart(), 'drawable/ic_favorite');

    await handler.customAction('like');
    expect(userLibrary.isLiked(song), isFalse);
    expect(heart(), 'drawable/ic_favorite_border');
  });
}
