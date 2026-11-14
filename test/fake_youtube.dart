import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encore/api/innertube.dart' as yt;

/// A request the fake got.
class FakeRequest {
  FakeRequest(this.endpoint, this.query, this.headers, this.body);

  final String endpoint;
  final Map<String, String> query;
  final Map<String, String> headers;
  final Map<String, dynamic> body;

  String? header(String name) => headers[name.toLowerCase()];

  Map<String, String> get cookies => {
    for (final part in (header('cookie') ?? '').split(';'))
      if (part.contains('='))
        part.substring(0, part.indexOf('=')).trim(): part
            .substring(part.indexOf('=') + 1)
            .trim(),
  };
}

/// A stand-in for YouTube Music's API (music.youtube.com/youtubei/v1), on
/// this machine: it signs requests in as YouTube does (the cookies plus a
/// valid SAPISIDHASH), and answers each endpoint with [handlers].
class FakeYouTube {
  late final HttpServer _server;
  final requests = <FakeRequest>[];

  /// The cookies of the one signed-in session it knows; a request is signed
  /// in when it carries all of them and a valid Authorization header.
  Map<String, String> session = {
    'SAPISID': 'sapisid-1',
    'SID': 'sid-1',
    '__Secure-3PSIDTS': 'ts-1',
  };

  /// While true, no sign-in is accepted (it ended on YouTube's side).
  var sessionEnded = false;

  /// Set-Cookie headers for the next reply only.
  final nextCookies = <String>[];

  /// Every reply fails with this HTTP status, if set.
  int? failWith;

  /// Replies wait for this first, if set.
  Completer<void>? hold;

  /// Answers by endpoint; the default ones are below.
  final handlers = <String, Object? Function(FakeRequest, bool signedIn)>{};

  static FakeRequest? last;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    yt.musicApiBase = 'http://127.0.0.1:${_server.port}/youtubei/v1';
    _server.listen(_serve);
  }

  Future<void> stop() async {
    yt.musicApiBase = 'https://music.youtube.com/youtubei/v1';
    await _server.close(force: true);
  }

  List<FakeRequest> to(String endpoint) =>
      requests.where((r) => r.endpoint == endpoint).toList();

  bool signedIn(FakeRequest r) {
    if (sessionEnded) return false;
    final cookies = r.cookies;
    if (session.entries.any((e) => cookies[e.key] != e.value)) return false;
    final auth = r.header('authorization') ?? '';
    final match = RegExp(r'^SAPISIDHASH (\d+)_([0-9a-f]{40})$').firstMatch(auth);
    if (match == null) return false;
    final expected = sha1
        .convert(
          utf8.encode('${match[1]} ${session['SAPISID']} https://music.youtube.com'),
        )
        .toString();
    final age = DateTime.now().millisecondsSinceEpoch ~/ 1000 - int.parse(match[1]!);
    return match[2] == expected &&
        age.abs() < 300 &&
        r.header('x-origin') == 'https://music.youtube.com';
  }

  Future<void> _serve(HttpRequest req) async {
    final text = await utf8.decodeStream(req);
    final headers = <String, String>{};
    req.headers.forEach((name, values) => headers[name] = values.join(', '));
    final endpoint = req.uri.path.replaceFirst('/youtubei/v1/', '');
    final r = FakeRequest(
      endpoint,
      req.uri.queryParameters,
      headers,
      text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>,
    );
    requests.add(r);
    last = r;
    // Taken by the request that arrives next, whenever it replies.
    final setCookies = List.of(nextCookies);
    nextCookies.clear();
    if (hold case final wait?) await wait.future;
    final res = req.response;
    for (final c in setCookies) {
      res.headers.add(HttpHeaders.setCookieHeader, c);
    }
    if (failWith case final status?) {
      res.statusCode = status;
      res.write('<html>error</html>');
      await res.close();
      return;
    }
    final signed = signedIn(r);
    final handler = handlers[endpoint] ?? _defaults[endpoint];
    final body = handler?.call(r, signed) ?? {};
    // A handler answering with a number fails with that HTTP status.
    if (body is int) {
      res.statusCode = body;
      await res.close();
      return;
    }
    res.headers.contentType = ContentType.json;
    res.write(
      jsonEncode({
        if (body is Map) ...body,
        'responseContext': {
          'visitorData': 'visitor-1',
          'serviceTrackingParams': [
            {
              'service': 'GFEEDBACK',
              'params': [
                {'key': 'logged_in', 'value': signed ? '1' : '0'},
              ],
            },
          ],
        },
      }),
    );
    await res.close();
  }

  static final _defaults = <String, Object? Function(FakeRequest, bool)>{
    'account/account_menu': (r, signed) => signed ? accountMenu() : {},
    'browse': (r, signed) => r.body['browseId'] == 'FEmusic_home'
        ? homeFeed(signed ? 'Made for you' : 'Popular right now')
        : {},
  };
}

Map<String, Object> accountMenu({
  String name = 'Test Listener',
  String handle = '@testlistener',
  String photo = 'https://yt3.example/photo=s88',
}) => {
  'actions': [
    {
      'openPopupAction': {
        'popup': {
          'multiPageMenuRenderer': {
            'header': {
              'activeAccountHeaderRenderer': {
                'accountName': {
                  'runs': [
                    {'text': name},
                  ],
                },
                'channelHandle': {
                  'runs': [
                    {'text': handle},
                  ],
                },
                'accountPhoto': {
                  'thumbnails': [
                    {'url': photo, 'width': 88, 'height': 88},
                  ],
                },
              },
            },
          },
        },
      },
    },
  ],
};

/// A home feed with one shelf called [title] holding one song.
Map<String, Object> homeFeed(String title, {String songId = 'song0000001'}) => {
  'contents': {
    'musicCarouselShelfRenderer': {
      'header': {
        'musicCarouselShelfBasicHeaderRenderer': {
          'title': {
            'runs': [
              {'text': title},
            ],
          },
        },
      },
      'contents': [
        {
          'musicResponsiveListItemRenderer': {
            'playlistItemData': {'videoId': songId},
            'flexColumns': [
              {
                'musicResponsiveListItemFlexColumnRenderer': {
                  'text': {
                    'runs': [
                      {'text': '$title song'},
                    ],
                  },
                },
              },
              {
                'musicResponsiveListItemFlexColumnRenderer': {
                  'text': {
                    'runs': [
                      {'text': 'Some Artist'},
                    ],
                  },
                },
              },
            ],
          },
        },
      ],
    },
  },
};
