import 'package:encore/models.dart';
import 'package:encore/services/library.dart';
import 'package:encore/ui/pages/collection_page.dart';
import 'package:encore/ui/shell.dart';
import 'package:encore/ui/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_test.dart' show pumpApp;

// Songs and playlists couldn't be shared.

const _song = Track(id: 'abc', title: 'Song', artist: 'Band', artUrl: '');

void main() {
  test('links to YouTube Music', () {
    expect(
      songShareText(_song),
      'Song – Band\nhttps://music.youtube.com/watch?v=abc',
    );
    expect(
      collectionLink('VLPL123'),
      'https://music.youtube.com/playlist?list=PL123',
    );
    expect(
      collectionLink('MPREb_x'),
      'https://music.youtube.com/browse/MPREb_x',
    );
  });

  test("one of the user's playlists: links that play it on YouTube", () {
    final small = Playlist(id: '1', name: 'Mix', tracks: const [_song]);
    expect(
      playlistShareText(small),
      'Mix (1 song)\nhttps://www.youtube.com/watch_videos?video_ids=abc',
    );
    final big = Playlist(
      id: '2',
      name: 'Long',
      tracks: [
        for (var i = 0; i < 60; i++)
          Track(id: 's$i', title: 'S', artist: 'A', artUrl: ''),
      ],
    );
    final lines = playlistShareText(big).split('\n');
    expect(lines.first, 'Long (60 songs)');
    expect(lines.skip(1), [startsWith('Part 1: '), startsWith('Part 2: ')]);
  });

  group('sharing', () {
    String? copied;
    final sent = <MethodCall>[];

    setUp(() {
      copied = null;
      sent.clear();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.encore.app/share'),
        (call) async {
          sent.add(call);
          return null;
        },
      );
    });

    tearDown(() {
      shareSheet = false;
      userLibrary.playlists.value = [];
    });

    Future<void> shareFromMenu(WidgetTester tester) async {
      final p = userLibrary.createPlaylist('Mix', tracks: const [_song]);
      openPage(CollectionPage.playlist(p.id));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
    }

    testWidgets('desktop: a song is copied, and it says so', (tester) async {
      shareSheet = false;
      await pumpApp(tester, const Size(1400, 900));
      await shareFromMenu(tester);
      expect(copied, songShareText(_song));
      expect(find.text('Link copied'), findsOneWidget);
    });

    testWidgets("Android: a song goes to the share sheet", (tester) async {
      shareSheet = true;
      await pumpApp(tester, const Size(400, 860));
      await shareFromMenu(tester);
      expect(sent.single.arguments, {
        'text': songShareText(_song),
        'subject': 'Song',
      });
      expect(copied, isNull);
    });

    testWidgets('a playlist is shared from its options', (tester) async {
      shareSheet = false;
      await pumpApp(tester, const Size(1400, 900));
      final p = userLibrary.createPlaylist('Mix', tracks: const [_song]);
      openPage(CollectionPage.playlist(p.id));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Playlist options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(copied, playlistShareText(userLibrary.playlist(p.id)!));
    });
  });
}
