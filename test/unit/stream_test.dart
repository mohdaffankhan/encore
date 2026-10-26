import 'dart:io';

import 'package:encore/api/stream.dart';
import 'package:flutter_test/flutter_test.dart';

// Audio arrives in range requests; one that YouTube refuses or cuts short is
// tried again from where it stopped, so the song doesn't stall.

/// Serves [data] by range, after failing as [fail] says for each request.
Future<(HttpServer, List<String>)> _server(
  List<int> data,
  String? Function(int request) fail,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final ranges = <String>[];
  var n = 0;
  server.listen((req) async {
    final range = req.headers.value(HttpHeaders.rangeHeader)!;
    ranges.add(range);
    final [from, to] = range.substring(6).split('-').map(int.parse).toList();
    final res = req.response;
    switch (fail(n++)) {
      case 'refuse':
        res.statusCode = HttpStatus.forbidden;
      case 'cut':
        res.statusCode = HttpStatus.partialContent;
        // Half the bytes, then the connection ends.
        res.add(data.sublist(from, from + (to - from + 1) ~/ 2));
      default:
        res.statusCode = HttpStatus.partialContent;
        res.add(data.sublist(from, to + 1));
    }
    await res.close();
  });
  return (server, ranges);
}

void main() {
  final data = List.generate(3 << 20, (i) => i % 251);
  setUp(() => retryDelay = Duration.zero);

  Future<List<int>> readAll(HttpServer server, [int start = 0]) async {
    final stream = AudioStream(
      Uri.parse('http://127.0.0.1:${server.port}/audio'),
      'audio/webm',
      data.length,
    );
    return [await for (final c in stream.read(start)) ...c];
  }

  test('reads every byte, a chunk at a time', () async {
    final (server, ranges) = await _server(data, (_) => null);
    addTearDown(server.close);
    expect(await readAll(server), data);
    expect(ranges, hasLength(3));
  });

  test('a refused request is tried again', () async {
    final (server, ranges) = await _server(
      data,
      (n) => n == 1 ? 'refuse' : null,
    );
    addTearDown(server.close);
    expect(await readAll(server), data);
    expect(ranges[1], ranges[2], reason: 'the same range again');
  });

  test('a request cut short goes on from where it stopped', () async {
    final (server, ranges) = await _server(data, (n) => n == 0 ? 'cut' : null);
    addTearDown(server.close);
    expect(await readAll(server, 1000), data.sublist(1000));
    final half = 1000 + (1 << 20) ~/ 2;
    expect(ranges[1], startsWith('bytes=$half-'));
  });

  test('gives up when it keeps failing', () async {
    final (server, _) = await _server(data, (_) => 'refuse');
    addTearDown(server.close);
    await expectLater(readAll(server), throwsA(isA<HttpException>()));
  });
}
