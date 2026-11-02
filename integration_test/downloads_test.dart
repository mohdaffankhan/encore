import 'package:encore/api/innertube.dart';
import 'package:encore/main.dart' as app;
import 'package:encore/models.dart';
import 'package:encore/services/downloads.dart';
import 'package:encore/services/library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Android: downloads go on after Encore is closed (swiped away from the
// recent apps), with their progress in a notification, and finish.
// Run by tool/android_downloads_check.sh, which closes Encore when this
// says it is ready and checks the notifications.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('downloads finish after Encore is closed', (tester) async {
    await app.main();
    await tester.pump();
    for (final t in [...userLibrary.downloads.value]) {
      await downloads.remove(t);
    }
    // More than a moment's worth (a song takes ~1 s on Wi-Fi), so they are
    // still going when it closes. From searches: the home feed doesn't
    // always have songs.
    final songs = <Track>[];
    for (final q in ['Daft Punk', 'Coldplay', 'Arijit Singh']) {
      final found = await search(q, SearchFilter.songs);
      songs.addAll(found.whereType<Track>().take(4));
    }
    expect(songs, hasLength(12));
    downloads.download(songs);
    // ignore: avoid_print
    print('[downloads] ready');
    // The host script closes Encore now; once the downloads are done,
    // Encore shuts down, ending this test there. The script checks the
    // notifications (and removes the test app).
    await Future<void>.delayed(const Duration(minutes: 4));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
