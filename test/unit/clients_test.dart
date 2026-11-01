import 'dart:convert';
import 'dart:io';

import 'package:encore/api/clients.dart';
import 'package:encore/api/stream.dart';
import 'package:encore/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';

// Playback hung on one built-in YouTube client: when YouTube stopped serving
// it, every copy broke until a new release. The clients now come from a file
// online (kept on the device), and the next is asked when one is refused.

Map<String, Object> _client(String name, {String version = '1.0'}) => {
  'clientName': name,
  'clientId': 7,
  'clientVersion': version,
  'userAgent': 'Agent of $name',
  'deviceMake': 'Maker',
};

void main() {
  tearDown(resetClients);

  group('the clients file', () {
    test("its clients come first, then the built-in one", () {
      expect(
        applyClients(
          jsonEncode({
            'player': [_client('TVHTML5')],
          }),
        ),
        true,
      );
      expect(playerClients.map((c) => c.name), ['TVHTML5', 'VISIONOS']);
      expect(playerClients.first.context(null), {
        'clientName': 'TVHTML5',
        'clientVersion': '1.0',
        'deviceMake': 'Maker',
        'userAgent': 'Agent of TVHTML5',
        'hl': 'en',
      });
    });

    test('only checked fields are taken; anything off is dropped', () {
      applyClients(
        jsonEncode({
          'player': [
            {..._client('GOOD'), 'script': 'rm -rf /', 'osName': 'x\ny'},
            _client('bad name'),
            {..._client('NOID'), 'clientId': '7'},
            {..._client('LONG'), 'userAgent': 'x' * 301},
          ],
          'musicClientVersion': '1.20270101.01.00',
        }),
      );
      expect(playerClients.map((c) => c.name), ['GOOD', 'VISIONOS']);
      expect(playerClients.first.device, {'deviceMake': 'Maker'});
      expect(musicClientVersion, '1.20270101.01.00');
    });

    // CI runs this on every push: a mistake in the file is caught before
    // it reaches every installed app.
    test("the repo's own file is usable", () {
      final text = File('config/youtube_clients.json').readAsStringSync();
      expect(applyClients(text), isTrue);
      expect(playerClients, contains(visionOs));
    });

    test('a broken file changes nothing', () {
      expect(applyClients('{"player": ['), isFalse);
      expect(
        applyClients(
          jsonEncode({
            'player': [_client('a b')],
          }),
        ),
        isFalse,
      );
      expect(playerClients, [visionOs]);
      expect(musicClientVersion, builtInMusicVersion);
    });

    test('the last good copy is used at once, before the network', () async {
      final dir = await Directory.systemTemp.createTemp('encore_clients');
      addTearDown(() => dir.delete(recursive: true));
      useDataDir(dir);
      final file = jsonEncode({
        'player': [_client('SAVED')],
      });
      await loadClients(fetch: () async => file);
      // Fetched and saved in the background.
      final saved = File('${dir.path}/youtube_clients.json');
      for (
        var i = 0;
        i < 100 && (!saved.existsSync() || saved.lengthSync() < file.length);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(playerClients.first.name, 'SAVED');

      resetClients();
      // Offline the next time: the saved copy still applies.
      await loadClients(fetch: () async => null);
      expect(playerClients.first.name, 'SAVED');
    });
  });

  test('a client YouTube refuses makes way for the next', () async {
    final asked = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      final body = jsonDecode(await utf8.decodeStream(req));
      final name = body['context']['client']['clientName'] as String;
      asked.add('$name ${req.headers.value('X-YouTube-Client-Name')}');
      req.response.write(
        jsonEncode(
          name == 'BROKEN'
              ? {
                  'playabilityStatus': {
                    'status': 'UNPLAYABLE',
                    'reason': 'Not for this app',
                  },
                }
              : {
                  'playabilityStatus': {'status': 'OK'},
                  'streamingData': {
                    'adaptiveFormats': [
                      {
                        'itag': 251,
                        'mimeType': 'audio/webm; codecs="opus"',
                        'bitrate': 140000,
                        'contentLength': '1000',
                        'url': 'https://audio/$name',
                      },
                    ],
                  },
                },
        ),
      );
      await req.response.close();
    });
    final saved = playerEndpoint;
    addTearDown(() => playerEndpoint = saved);
    playerEndpoint = Uri.parse('http://127.0.0.1:${server.port}/player');
    applyClients(
      jsonEncode({
        'player': [_client('BROKEN'), _client('WORKS')],
      }),
    );

    final stream = await audioStream('abc');
    expect(asked, ['BROKEN 7', 'WORKS 7']);
    expect(stream.url.toString(), 'https://audio/WORKS');
    expect(stream.userAgent, 'Agent of WORKS', reason: 'reads say the same');
  });
}
