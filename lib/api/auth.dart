import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// The page YouTube Music's requests come from, which signed-in requests
/// prove in their Authorization header.
const musicOrigin = 'https://music.youtube.com';

/// The cookies that make a YouTube Music request signed in (as the website
/// sends them), kept current: YouTube replaces some of them every so often
/// in its replies, and the old ones stop working.
class YouTubeCookies {
  YouTubeCookies(Map<String, String> cookies) : _cookies = Map.of(cookies);

  final Map<String, String> _cookies;

  Map<String, String> get all => Map.unmodifiable(_cookies);

  /// The cookie the Authorization header is made from.
  String? get sapisid =>
      _cookies['SAPISID'] ?? _cookies['__Secure-3PAPISID'];

  /// Whether these can sign a request in: the hash's cookie and a session.
  bool get usable =>
      sapisid != null &&
      (_cookies.containsKey('SID') ||
          _cookies.containsKey('__Secure-3PSID') ||
          _cookies.containsKey('__Secure-1PSID'));

  String get header => [
    for (final MapEntry(:key, :value) in _cookies.entries) '$key=$value',
  ].join('; ');

  /// Applies a reply's Set-Cookie headers; true if anything changed.
  bool update(Iterable<Cookie> cookies, {DateTime? now}) {
    now ??= DateTime.now();
    var changed = false;
    for (final c in cookies) {
      final domain = c.domain?.toLowerCase();
      if (domain != null && !domain.endsWith('youtube.com')) continue;
      final expired =
          (c.maxAge != null && c.maxAge! <= 0) ||
          (c.expires != null && !c.expires!.isAfter(now));
      if (expired) {
        changed |= _cookies.remove(c.name) != null;
      } else if (_cookies[c.name] != c.value) {
        _cookies[c.name] = c.value;
        changed = true;
      }
    }
    return changed;
  }

  Map<String, Object> toJson() => {'cookies': _cookies};

  static YouTubeCookies? fromJson(Object? json) {
    if (json is! Map || json['cookies'] is! Map) return null;
    final cookies = <String, String>{
      for (final MapEntry(:key, :value) in (json['cookies'] as Map).entries)
        if (key is String && value is String && _validCookie(key, value))
          key: value,
    };
    final result = YouTubeCookies(cookies);
    return result.usable ? result : null;
  }

  /// Cookies pasted from a browser: a `Cookie:` header's value (or the
  /// whole header line), or a Netscape cookies.txt. Null if they can't sign
  /// anyone in.
  static YouTubeCookies? parse(String text) {
    text = text.trim();
    final cookies = <String, String>{};
    final lines = const LineSplitter().convert(text);
    final netscape = lines.where((l) => l.split('\t').length >= 7).toList();
    if (netscape.isNotEmpty) {
      for (final line in netscape) {
        final f = line.split('\t');
        var domain = f[0].trim().toLowerCase();
        if (domain.startsWith('#httponly_')) domain = domain.substring(10);
        if (!domain.endsWith('youtube.com')) continue;
        final name = f[5].trim();
        final value = f.sublist(6).join('\t').trim();
        if (_validCookie(name, value)) cookies[name] = value;
      }
    } else {
      var header = text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      header = header.replaceFirst(RegExp(r'^cookie\s*:\s*', caseSensitive: false), '');
      for (final part in header.split(';')) {
        final eq = part.indexOf('=');
        if (eq <= 0) continue;
        final name = part.substring(0, eq).trim();
        final value = part.substring(eq + 1).trim();
        if (_validCookie(name, value)) cookies[name] = value;
      }
    }
    final result = YouTubeCookies(cookies);
    return result.usable ? result : null;
  }

  static final _name = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

  static bool _validCookie(String name, String value) =>
      name.isNotEmpty &&
      _name.hasMatch(name) &&
      value.isNotEmpty &&
      value.length < 4096 &&
      !value.codeUnits.any((c) => c < 0x21 || c == 0x7f || c == 0x3b || c == 0x2c || c == 0x22 || c == 0x5c);
}

/// The Authorization header for a signed-in request: the time, and a hash
/// of the time, the SAPISID cookie and the page's origin.
String sapisidHash(String sapisid, {DateTime? now, String origin = musicOrigin}) {
  final ts = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  final hash = sha1.convert(utf8.encode('$ts $sapisid $origin'));
  return 'SAPISIDHASH ${ts}_$hash';
}

/// The headers that sign a request in as [cookies]' account, on the
/// channel [pageId] (a brand channel) if given.
Map<String, String> authHeaders(
  YouTubeCookies cookies, {
  String? pageId,
  DateTime? now,
}) => {
  'Cookie': cookies.header,
  'Authorization': sapisidHash(cookies.sapisid!, now: now),
  'X-Goog-AuthUser': '0',
  'X-Origin': musicOrigin,
  'X-Goog-PageId': ?pageId,
};

/// Whether YouTube treated the request as signed in, from a reply's
/// `responseContext`: true, false, or null when it doesn't say.
bool? signedInReply(Map<String, dynamic> json) {
  final services = json['responseContext']?['serviceTrackingParams'];
  if (services is! List) return null;
  for (final s in services) {
    final params = s is Map ? s['params'] : null;
    if (params is! List) continue;
    for (final p in params) {
      if (p is Map && p['key'] == 'logged_in') return p['value'] == '1';
    }
  }
  return null;
}
