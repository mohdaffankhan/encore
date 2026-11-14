import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encore/api/auth.dart';
import 'package:encore/api/innertube.dart' as yt;
import 'package:encore/models.dart';
import 'package:encore/services/account.dart';
import 'package:encore/services/home_cache.dart';
import 'package:encore/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_youtube.dart';

/// The secret store, in memory.
class MemoryStore implements SecretStore {
  String? value;
  var failReads = false;
  var writes = 0;

  @override
  Future<String?> read() async {
    if (failReads) throw Exception('locked keyring');
    return value;
  }

  @override
  Future<void> write(String v) async {
    writes++;
    value = v;
  }

  @override
  Future<void> delete() async => value = null;

  Map<String, dynamic>? get json =>
      value == null ? null : jsonDecode(value!) as Map<String, dynamic>;
}

YouTubeCookies goodCookies([Map<String, String> extra = const {}]) =>
    YouTubeCookies({
      'SAPISID': 'sapisid-1',
      'SID': 'sid-1',
      '__Secure-3PSIDTS': 'ts-1',
      ...extra,
    });

/// Lets queued work (checks started without waiting) run.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  secretStoreTests();

  group('cookies and the Authorization header', () {
    test('SAPISIDHASH is the time and sha1 of time, SAPISID and origin', () {
      final at = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
      final expected = sha1
          .convert(utf8.encode('1700000000 abc https://music.youtube.com'))
          .toString();
      expect(sapisidHash('abc', now: at), 'SAPISIDHASH 1700000000_$expected');
    });

    test('usable needs the hash cookie and a session cookie', () {
      expect(YouTubeCookies({'SAPISID': 'a'}).usable, isFalse);
      expect(YouTubeCookies({'SID': 'a'}).usable, isFalse);
      expect(YouTubeCookies({'SAPISID': 'a', 'SID': 'b'}).usable, isTrue);
      expect(
        YouTubeCookies({'__Secure-3PAPISID': 'a', '__Secure-3PSID': 'b'})
            .sapisid,
        'a',
      );
    });

    test('auth headers carry the cookies, hash, origin and channel', () {
      final h = authHeaders(goodCookies(), pageId: 'brand-1');
      expect(h['Cookie'], contains('SAPISID=sapisid-1'));
      expect(h['Authorization'], startsWith('SAPISIDHASH '));
      expect(h['X-Origin'], 'https://music.youtube.com');
      expect(h['X-Goog-AuthUser'], '0');
      expect(h['X-Goog-PageId'], 'brand-1');
      expect(authHeaders(goodCookies()).containsKey('X-Goog-PageId'), isFalse);
    });

    test('a pasted Cookie header, with or without its name', () {
      for (final text in [
        'SAPISID=a; SID=b; HSID=c',
        'cookie: SAPISID=a; SID=b; HSID=c',
        'Cookie:SAPISID=a;\nSID=b;  HSID=c  ',
      ]) {
        final c = YouTubeCookies.parse(text);
        expect(c, isNotNull, reason: text);
        expect(c!.all, {'SAPISID': 'a', 'SID': 'b', 'HSID': 'c'});
      }
    });

    test('a pasted cookies.txt keeps only YouTube cookies', () {
      final c = YouTubeCookies.parse(
        '# Netscape HTTP Cookie File\n'
        '.youtube.com\tTRUE\t/\tTRUE\t0\tSAPISID\ta\n'
        '#HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tb\n'
        '.google.com\tTRUE\t/\tTRUE\t0\tNID\tnope\n',
      );
      expect(c!.all, {'SAPISID': 'a', 'SID': 'b'});
    });

    test('pasted text that can not sign in is refused', () {
      for (final text in [
        '',
        'hello world',
        'SAPISID=a',
        'SID=b; HSID=c',
        '{"cookies": 1}',
      ]) {
        expect(YouTubeCookies.parse(text), isNull, reason: text);
      }
    });

    test('malformed cookie values are dropped, not sent', () {
      final c = YouTubeCookies.parse('SAPISID=a; SID=b; BAD=x"y; =z; E=');
      expect(c!.all.keys, unorderedEquals(['SAPISID', 'SID']));
    });

    test('a reply replaces changed cookies and removes expired ones', () {
      final c = goodCookies({'OLD': 'x'});
      final now = DateTime.utc(2026, 11, 14);
      final changed = c.update([
        Cookie('__Secure-3PSIDTS', 'ts-2')..domain = '.youtube.com',
        Cookie('OLD', 'gone')..maxAge = 0,
        Cookie('NID', 'google')..domain = '.google.com',
      ], now: now);
      expect(changed, isTrue);
      expect(c.all['__Secure-3PSIDTS'], 'ts-2');
      expect(c.all.containsKey('OLD'), isFalse);
      expect(c.all.containsKey('NID'), isFalse, reason: 'other sites');
      expect(c.update([Cookie('SID', 'sid-1')], now: now), isFalse);
      c.update([
        Cookie('SID', 'x')..expires = now.subtract(const Duration(days: 1)),
      ], now: now);
      expect(c.all.containsKey('SID'), isFalse);
    });

    test('saved cookies are read back, and broken ones are not', () {
      final c = goodCookies();
      expect(YouTubeCookies.fromJson(c.toJson())!.all, c.all);
      expect(YouTubeCookies.fromJson(null), isNull);
      expect(YouTubeCookies.fromJson({'cookies': 'x'}), isNull);
      expect(
        YouTubeCookies.fromJson({
          'cookies': {'SAPISID': 'a'},
        }),
        isNull,
      );
    });

    test('whether a reply was signed in', () {
      Map<String, dynamic> reply(String v) => {
        'responseContext': {
          'serviceTrackingParams': [
            {
              'params': [
                {'key': 'other', 'value': 'x'},
                {'key': 'logged_in', 'value': v},
              ],
            },
          ],
        },
      };
      expect(signedInReply(reply('1')), isTrue);
      expect(signedInReply(reply('0')), isFalse);
      expect(signedInReply({}), isNull);
      expect(
        signedInReply({
          'responseContext': {'serviceTrackingParams': 3},
        }),
        isNull,
      );
    });
  });

  group('account', () {
    late FakeYouTube youtube;
    late MemoryStore store;
    late Directory dir;
    late Account a;
    var cleared = 0;

    setUp(() async {
      youtube = FakeYouTube();
      await youtube.start();
      store = MemoryStore();
      dir = await Directory.systemTemp.createTemp('encore_account');
      useDataDir(dir);
      a = Account(store: store);
      clearHomeOnAccountChange(a.generation);
      cleared = 0;
      a.clearBrowser = () async => cleared++;
      yt.signIn = a;
      yt.resetVisitor();
    });

    tearDown(() async {
      yt.signIn = null;
      await youtube.stop();
      await dir.delete(recursive: true);
    });

    test(
      'signing in checks with YouTube, then signs every request in',
      () async {
        final gen = a.generation.value;
        expect(await a.signInWith(goodCookies()), isNull);
        expect(a.status.value, AccountStatus.signedIn);
        expect(a.info.value!.name, 'Test Listener');
        expect(a.info.value!.handle, '@testlistener');
        expect(a.generation.value, greaterThan(gen));
        await a.saved;
        expect(store.json!['cookies']['SID'], 'sid-1');
        expect(store.json!['info']['name'], 'Test Listener');

        final home = await yt.home();
        expect(home.single.title, 'Made for you');
        final r = youtube.to('browse').last;
        expect(youtube.signedIn(r), isTrue);
        expect(r.header('x-goog-authuser'), '0');
      },
    );

    test('signed out, requests carry no sign-in at all', () async {
      final home = await yt.home();
      expect(home.single.title, 'Popular right now');
      final r = youtube.to('browse').last;
      expect(r.header('authorization'), isNull);
      expect(r.header('cookie'), isNull);
    });

    test('cookies YouTube does not accept are refused, nothing kept', () async {
      youtube.sessionEnded = true;
      final problem = await a.signInWith(goodCookies());
      expect(problem, contains("didn't accept"));
      expect(a.status.value, AccountStatus.signedOut);
      expect(a.info.value, isNull);
      expect(store.value, isNull);
      await yt.home();
      expect(youtube.to('browse').last.header('authorization'), isNull);
    });

    test('incomplete cookies are refused without asking YouTube', () async {
      final problem = await a.signInWith(YouTubeCookies({'SID': 'x'}));
      expect(problem, isNotNull);
      expect(youtube.requests, isEmpty);
      expect(a.status.value, AccountStatus.signedOut);
    });

    test('offline while signing in: says so, keeps what was before', () async {
      youtube.failWith = 503;
      final problem = await a.signInWith(goodCookies());
      expect(problem, contains("Couldn't reach"));
      expect(a.status.value, AccountStatus.signedOut);
      expect(store.value, isNull);
    });

    test('cookies YouTube replaces are used and saved', () async {
      await a.signInWith(goodCookies());
      youtube.session['__Secure-3PSIDTS'] = 'ts-2';
      youtube.nextCookies.add(
        '__Secure-3PSIDTS=ts-2; Domain=.youtube.com; Path=/; Secure; HttpOnly',
      );
      // Sent with the old one; the reply brings the new one.
      await yt.browse('FEmusic_home');
      final home = await yt.home();
      expect(home.single.title, 'Made for you');
      expect(youtube.to('browse').last.cookies['__Secure-3PSIDTS'], 'ts-2');
      await a.saved;
      expect(store.json!['cookies']['__Secure-3PSIDTS'], 'ts-2');
    });

    test('a malformed Set-Cookie does not lose the others', () async {
      await a.signInWith(goodCookies());
      youtube.nextCookies.addAll([
        'bad cookie',
        'NEW=1; Domain=.youtube.com; Path=/',
      ]);
      await yt.browse('FEmusic_home');
      await yt.browse('FEmusic_home');
      expect(youtube.to('browse').last.cookies['NEW'], '1');
    });

    test(
      'a sign-in that ended is noticed; Encore carries on signed out',
      () async {
        await a.signInWith(goodCookies());
        final gen = a.generation.value;
        youtube.sessionEnded = true;
        await yt.home();
        await settle();
        expect(a.status.value, AccountStatus.ended);
        expect(a.notice.value, contains('ended'));
        expect(a.info.value!.name, 'Test Listener', reason: 'says whose');
        expect(a.generation.value, greaterThan(gen));
        expect(cleared, 1);
        await a.saved;
        expect(store.json!['ended'], isTrue);
        expect(store.json!.containsKey('cookies'), isFalse);
        youtube.requests.clear();
        await yt.home();
        expect(youtube.to('browse').last.header('authorization'), isNull);
      },
    );

    test('one signed-out reply alone does not end the sign-in', () async {
      await a.signInWith(goodCookies());
      youtube.handlers['browse'] = (r, signed) => {};
      youtube.sessionEnded = true;
      final done = yt.browse('FEmusic_home');
      await done;
      youtube.sessionEnded = false; // the check finds it fine
      await settle();
      expect(a.status.value, AccountStatus.signedIn);
    });

    test('server errors and lost connections do not end the sign-in', () async {
      await a.signInWith(goodCookies());
      youtube.failWith = 500;
      await expectLater(yt.home(), throwsA(isA<HttpException>()));
      youtube.failWith = 401;
      await expectLater(yt.home(), throwsA(isA<HttpException>()));
      youtube.failWith = 500; // the check after the 401 fails too
      await settle();
      expect(a.status.value, AccountStatus.signedIn);
    });

    test('many signed-out replies make one check, not one each', () async {
      await a.signInWith(goodCookies());
      final hold = youtube.hold = Completer();
      youtube.sessionEnded = true;
      final pending = [for (var i = 0; i < 5; i++) yt.browse('FEmusic_home')];
      await settle();
      hold.complete();
      youtube.hold = null;
      await Future.wait(pending);
      await settle();
      expect(
        youtube.to('account/account_menu').length,
        2,
        reason: 'one at sign-in, one check',
      );
      expect(a.status.value, AccountStatus.ended);
    });

    test('signing out forgets everything but the library', () async {
      await a.signInWith(goodCookies());
      await saveHome([const Shelf('Made for you')]);
      final gen = a.generation.value;
      await a.signOut();
      expect(a.status.value, AccountStatus.signedOut);
      expect(a.info.value, isNull);
      expect(store.value, isNull);
      expect(cleared, 1);
      expect(a.generation.value, greaterThan(gen));
      await settle();
      expect(lastHome, isNull);
      expect(File('${dir.path}/home.json').existsSync(), isFalse);
      await yt.home();
      expect(youtube.to('browse').last.header('cookie'), isNull);
    });

    test('a reply arriving after signing out changes nothing', () async {
      await a.signInWith(goodCookies());
      final hold = youtube.hold = Completer();
      youtube.nextCookies.add('__Secure-3PSIDTS=ts-late; Domain=.youtube.com');
      final late = yt.browse('FEmusic_home');
      await settle();
      await a.signOut();
      hold.complete();
      await late;
      await settle();
      await a.saved;
      expect(store.value, isNull);
      expect(a.status.value, AccountStatus.signedOut);
    });

    test('a reply arriving after signing in again changes nothing', () async {
      await a.signInWith(goodCookies());
      final hold = youtube.hold = Completer();
      youtube.nextCookies.add('SID=other; Domain=.youtube.com');
      final late = yt.browse('FEmusic_home');
      await settle();
      youtube.hold = null;
      await a.signOut();
      await a.signInWith(goodCookies());
      hold.complete();
      await late;
      await a.saved;
      expect(store.json!['cookies']['SID'], 'sid-1');
    });

    test('a saved sign-in is used after a restart, and checked', () async {
      await a.signInWith(goodCookies());
      await a.saved;
      final again = Account(store: store);
      yt.signIn = again;
      await again.load();
      expect(again.status.value, AccountStatus.signedIn);
      expect(again.info.value!.name, 'Test Listener');
      await settle();
      expect(youtube.to('account/account_menu').length, 2);
      final home = await yt.home();
      expect(home.single.title, 'Made for you');
    });

    test(
      'a sign-in that ended while closed is noticed after a restart',
      () async {
        await a.signInWith(goodCookies());
        await a.saved;
        youtube.sessionEnded = true;
        final again = Account(store: store);
        await again.load();
        await settle();
        expect(again.status.value, AccountStatus.ended);
      },
    );

    test('an ended sign-in stays ended after a restart', () async {
      store.value = jsonEncode({
        'info': {'name': 'Old'},
        'ended': true,
      });
      await a.load();
      expect(a.status.value, AccountStatus.ended);
      expect(a.info.value!.name, 'Old');
      expect(a.headers(), isNull);
    });

    test('a broken or unreadable store starts signed out', () async {
      store.value = '{not json';
      await a.load();
      expect(a.status.value, AccountStatus.signedOut);
      store
        ..value = jsonEncode(goodCookies().toJson())
        ..failReads = true;
      final b = Account(store: store);
      await b.load();
      expect(b.status.value, AccountStatus.signedOut);
    });

    test('signing in again after it ended', () async {
      await a.signInWith(goodCookies());
      youtube.sessionEnded = true;
      await yt.home();
      await settle();
      expect(a.status.value, AccountStatus.ended);
      youtube.sessionEnded = false;
      expect(await a.signInWith(goodCookies()), isNull);
      expect(a.status.value, AccountStatus.signedIn);
      await a.saved;
      expect(store.json!.containsKey('ended'), isFalse);
    });

    test('a failed new sign-in keeps the ended one as it was', () async {
      store.value = jsonEncode({
        'info': {'name': 'Old'},
        'ended': true,
      });
      await a.load();
      youtube.sessionEnded = true;
      expect(await a.signInWith(goodCookies()), isNotNull);
      expect(a.status.value, AccountStatus.ended);
    });

    test(
      'a brand channel: requests use its page id, kept on restart',
      () async {
        await a.signInWith(goodCookies());
        await a.useChannel(
          const AccountChannel(name: 'Brand', handle: '@brand', pageId: 'p-9'),
        );
        expect(a.info.value!.name, 'Brand');
        await yt.home();
        expect(youtube.to('browse').last.header('x-goog-pageid'), 'p-9');
        expect(
          youtube.to('browse').last.body['context']['user']['onBehalfOfUser'],
          'p-9',
        );
        await settle();
        expect(a.info.value!.name, 'Brand', reason: 'not the account name');
        await a.saved;
        final again = Account(store: store);
        await again.load();
        expect(again.pageId, 'p-9');
        expect(again.headers()!['X-Goog-PageId'], 'p-9');
      },
    );

    test('channels: own and brand, not other Google accounts', () async {
      await a.signInWith(goodCookies());
      Map<String, Object> item(String name, Map<String, Object> extra) => {
        'accountItem': {
          'accountName': {
            'runs': [
              {'text': name},
            ],
          },
          'accountByline': {
            'runs': [
              {'text': '$name byline'},
            ],
          },
          ...extra,
        },
      };
      // As YouTube sends it: every item has a sign-in token; each Google
      // account signed in on the page is a section of its own.
      Map<String, Object> section(List<Map<String, Object>> items) => {
        'accountSectionListRenderer': {
          'contents': [
            {
              'accountItemSectionRenderer': {'contents': items},
            },
          ],
        },
      };
      Map<String, Object> tokens([String? pageId]) => {
        'serviceEndpoint': {
          'selectActiveIdentityEndpoint': {
            'supportedTokens': [
              {
                'accountSigninToken': {'signinUrl': '/signin?x'},
              },
              if (pageId != null)
                {
                  'pageIdToken': {'pageId': pageId},
                },
            ],
          },
        },
      };
      youtube.handlers['account/accounts_list'] = (r, signed) => {
        'actions': [
          {
            'getMultiPageMenuAction': {
              'menu': {
                'multiPageMenuRenderer': {
                  'sections': [
                    section([
                      item('Me', {'isSelected': true, ...tokens()}),
                      item('Brand', tokens('p-9')),
                    ]),
                    section([item('Other Google account', tokens())]),
                  ],
                },
              },
            },
          },
        ],
      };
      final channels = await yt.accountChannels();
      expect(channels.map((c) => c.name), ['Me', 'Brand']);
      expect(channels.first.pageId, isNull);
      expect(channels.first.selected, isTrue);
      expect(channels.last.pageId, 'p-9');
      expect(channels.last.handle, 'Brand byline');
    });

    test('a non-JSON reply is an error, not a crash', () async {
      youtube.handlers['browse'] = (r, signed) => null;
      youtube.failWith = 200;
      await expectLater(
        yt.browse('FEmusic_home'),
        throwsA(isA<HttpException>()),
      );
    });
  });
}

void secretStoreTests() {
  group('the sign-in on disk', () {
    late Directory dir;
    late DeviceSecretStore store;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('encore_secret');
      store = DeviceSecretStore(dir);
    });
    tearDown(() => dir.delete(recursive: true));

    File file() => File('${dir.path}${Platform.pathSeparator}account.json');

    test('nothing saved: nothing read', () async {
      expect(await store.read(), isNull);
    });

    test('read back as written; deleting leaves nothing', () async {
      const secret = '{"cookies":{"SID":"very-secret-value"}}';
      await store.write(secret);
      expect(await store.read(), secret);
      await store.write('{"second":1}');
      expect(await store.read(), '{"second":1}');
      await store.delete();
      expect(await store.read(), isNull);
      expect(dir.listSync(), isEmpty);
    });

    test(
      'Windows: encrypted for this Windows user, not readable as text',
      () async {
        await store.write('{"cookies":{"SID":"very-secret-value"}}');
        final text = file().readAsStringSync();
        expect(text, startsWith('dpapi:'));
        expect(text, isNot(contains('very-secret')));
      },
      skip: !Platform.isWindows,
    );

    test(
      'Windows: a file changed or not written by Encore is not used',
      () async {
        file().writeAsStringSync('{"cookies":{"SID":"x","SAPISID":"y"}}');
        expect(await store.read(), isNull);
        file().writeAsStringSync('dpapi:${base64.encode([1, 2, 3, 4])}');
        await expectLater(store.read(), throwsA(anything));
        // The account then starts signed out (load catches it).
        final a = Account(store: store);
        await a.load();
        expect(a.status.value, AccountStatus.signedOut);
      },
      skip: !Platform.isWindows,
    );

    test('Linux and Android: only this user can read the file', () async {
      await store.write('{}');
      final mode = (await file().stat()).mode & 0x1ff;
      expect(mode, 0x180, reason: 'rw------- (600)');
    }, skip: Platform.isWindows);
  });
}
