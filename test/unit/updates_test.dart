import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encore/services/settings.dart';
import 'package:encore/services/updates.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A release as GitHub's API gives it (the shape of v0.2.0's).
Map<String, Object> releaseJson({
  String tag = 'v0.3.0',
  bool draft = false,
  bool pre = false,
  List<Map<String, Object>>? assets,
  String body =
      "## What's new\r\n\r\n- **Themes**: Ember and more\r\n"
      '- Equalizer, see [docs](https://x.example)\r\n\r\n## Download\r\n'
      '- Windows: setup',
}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/$repo/releases/tag/$tag',
  'draft': draft,
  'prerelease': pre,
  'body': body,
  'assets':
      assets ??
      [
        for (final name in [
          'encore-android-arm64-v8a.apk',
          'encore-android.apk',
          'encore-windows-setup.exe',
        ])
          {
            'name': name,
            'size': 1000,
            'digest': 'sha256:${'a' * 64}',
            'browser_download_url':
                'https://github.com/$repo/releases/download/$tag/$name',
          },
      ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The binding blocks real connections; these use servers of their own.
  HttpOverrides.global = null;

  group('versions', () {
    test('newer is by number, not by text', () {
      expect(isNewer('0.3.0', '0.2.9'), isTrue);
      expect(isNewer('0.10.0', '0.9.0'), isTrue);
      expect(isNewer('1.0.0', '0.99.99'), isTrue);
      expect(isNewer('0.2.1', '0.2.1'), isFalse);
      expect(isNewer('0.2.0', '0.2.1'), isFalse);
      expect(isNewer('0.2.1+26', '0.2.1'), isFalse, reason: 'build left out');
      expect(isNewer('nonsense', '0.2.1'), isFalse);
    });
  });

  group('a release from GitHub', () {
    test('its version, page, files and what is new', () {
      final r = Release.fromJson(releaseJson())!;
      expect(r.version, '0.3.0');
      expect(r.page.toString(), 'https://github.com/$repo/releases/tag/v0.3.0');
      expect(r.notes, ['Themes: Ember and more', 'Equalizer, see docs']);
      final apk = r.files['encore-android-arm64-v8a.apk']!;
      expect(apk.size, 1000);
      expect(apk.sha256, 'a' * 64);
    });

    test('drafts and pre-releases are never offered', () {
      expect(Release.fromJson(releaseJson(draft: true)), isNull);
      expect(Release.fromJson(releaseJson(pre: true)), isNull);
      expect(Release.fromJson(releaseJson(tag: 'latest')), isNull);
      expect(Release.fromJson('nonsense'), isNull);
    });

    test("only Encore's own release files, from GitHub over https", () {
      Map<String, Object> asset(String url) => {
        'name': 'encore-android.apk',
        'size': 10,
        'browser_download_url': url,
      };
      for (final url in [
        'http://github.com/$repo/releases/download/v0.3.0/encore-android.apk',
        'https://evil.example/$repo/releases/download/v0.3.0/encore-android.apk',
        'https://github.com/someone/else/releases/download/v1/encore-android.apk',
      ]) {
        final r = Release.fromJson(releaseJson(assets: [asset(url)]))!;
        expect(r.files, isEmpty, reason: url);
      }
    });

    test('release notes without a What\'s new heading: their list', () {
      expect(whatsNew('- one\n- two\n\nmore text'), ['one', 'two']);
      expect(whatsNew(''), isEmpty);
    });
  });

  group('when to remind', () {
    const policy = UpdatePolicy();
    final now = DateTime(2026, 11, 20, 12);
    final r030 = Release.fromJson(releaseJson())!;
    final r040 = Release.fromJson(releaseJson(tag: 'v0.4.0'))!;

    bool remind(UpdateState s, Release r) =>
        policy.shouldRemind(s, r, '0.2.1', now);

    test('a newer version: yes; the same or older: no', () {
      expect(remind(const UpdateState(), r030), isTrue);
      expect(
        policy.shouldRemind(const UpdateState(), r030, '0.3.0', now),
        isFalse,
      );
      expect(
        policy.shouldRemind(const UpdateState(), r030, '0.4.0', now),
        isFalse,
      );
    });

    test('skipped: not again for 10 days, then again', () {
      final skipped = UpdateState(
        skipped: '0.3.0',
        skippedAt: now.subtract(const Duration(days: 9)),
        shownAt: now.subtract(const Duration(days: 9)),
      );
      expect(remind(skipped, r030), isFalse);
      final later = UpdateState(
        skipped: '0.3.0',
        skippedAt: now.subtract(const Duration(days: 10)),
        shownAt: now.subtract(const Duration(days: 10)),
      );
      expect(remind(later, r030), isTrue);
    });

    test('an even newer version than the one skipped: sooner, but not '
        'within 3 days of the last reminder', () {
      final skipped = UpdateState(
        skipped: '0.3.0',
        skippedAt: now.subtract(const Duration(days: 4)),
        shownAt: now.subtract(const Duration(days: 4)),
      );
      expect(remind(skipped, r040), isTrue);
      final justShown = UpdateState(
        skipped: '0.3.0',
        skippedAt: now.subtract(const Duration(days: 1)),
        shownAt: now.subtract(const Duration(days: 1)),
      );
      expect(remind(justShown, r040), isFalse);
    });

    test('shown and closed without an answer: not again for 3 days', () {
      final shown = UpdateState(shownAt: now.subtract(const Duration(days: 2)));
      expect(remind(shown, r030), isFalse);
    });

    test('GitHub is asked at most about once a day', () {
      expect(policy.shouldCheck(const UpdateState(), now), isTrue);
      expect(
        policy.shouldCheck(
          UpdateState(checkedAt: now.subtract(const Duration(hours: 5))),
          now,
        ),
        isFalse,
      );
      expect(
        policy.shouldCheck(
          UpdateState(checkedAt: now.subtract(const Duration(hours: 21))),
          now,
        ),
        isTrue,
      );
    });

    test('kept between runs', () {
      final s = UpdateState(
        checkedAt: now,
        shownAt: now,
        skipped: '0.3.0',
        skippedAt: now,
      );
      final back = UpdateState.fromJson(jsonDecode(jsonEncode(s)));
      expect(back.skipped, '0.3.0');
      expect(back.skippedAt, now);
      expect(UpdateState.fromJson('broken').skipped, isNull);
    });
  });

  group('checking at startup', () {
    late HttpServer server;
    late Directory dir;
    late Updates u;
    var asked = 0;
    Object? answer;
    var clock = DateTime(2026, 11, 20, 12);

    setUp(() async {
      asked = 0;
      answer = releaseJson();
      clock = DateTime(2026, 11, 20, 12);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        asked++;
        req.response.write(jsonEncode(answer));
        await req.response.close();
      });
      dir = await Directory.systemTemp.createTemp('encore_updates');
      u = Updates(latestUrl: 'http://127.0.0.1:${server.port}/latest', dir: dir)
        ..way = (() => UpdateWay.windowsInstaller)
        ..currentVersion = (() async => '0.2.1')
        ..now = (() => clock);
      settings.updateReminders.value = true;
    });

    tearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
      settings.updateReminders.value = true;
    });

    test('a newer release is offered once, then not for days', () async {
      expect((await u.check())?.version, '0.3.0');
      clock = clock.add(const Duration(days: 1));
      expect(await u.check(), isNull, reason: 'shown yesterday');
      clock = clock.add(const Duration(days: 2));
      expect(await u.check(), isNotNull, reason: '3 days on');
    });

    test('skipped: 10 days of quiet for it, kept across restarts', () async {
      final r = (await u.check())!;
      await u.skip(r);
      final again =
          Updates(latestUrl: 'http://127.0.0.1:${server.port}/latest', dir: dir)
            ..way = (() => UpdateWay.windowsInstaller)
            ..currentVersion = (() async => '0.2.1');
      for (final days in [1, 4, 9]) {
        again.now = () => clock.add(Duration(days: days));
        expect(await again.check(), isNull, reason: 'day $days');
      }
      again.now = () => clock.add(const Duration(days: 10, hours: 1));
      expect(await again.check(), isNotNull);
    });

    test('up to date, or GitHub unreachable: nothing, quietly', () async {
      u.currentVersion = () async => '0.3.0';
      expect(await u.check(), isNull);
      answer = {'message': 'rate limited'};
      clock = clock.add(const Duration(days: 2));
      expect(await u.check(), isNull);
      await server.close(force: true);
      clock = clock.add(const Duration(days: 2));
      expect(await u.check(), isNull);
    });

    test('reminders turned off, or a Flatpak (Flathub updates it): GitHub '
        'is not even asked', () async {
      settings.updateReminders.value = false;
      expect(await u.check(), isNull);
      settings.updateReminders.value = true;
      u.way = () => UpdateWay.none;
      expect(await u.check(), isNull);
      expect(asked, 0);
    });

    test(
      'Check for updates in Settings asks now, whatever was answered',
      () async {
        final r = (await u.check())!;
        await u.skip(r);
        expect((await u.checkNow())?.version, '0.3.0');
        u.currentVersion = () async => '0.3.0';
        expect(await u.checkNow(), isNull);
        await server.close(force: true);
        await expectLater(u.checkNow(), throwsA(isA<UpdateFailed>()));
      },
    );
  });

  group('the file for this copy', () {
    final r = Release.fromJson(releaseJson())!;
    const channel = MethodChannel('dev.encore.app/update');
    String? abi;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => abi);
    });

    test(
      "Android: the APK for the phone's processor, else the one for all",
      () async {
        final u = Updates()..way = (() => UpdateWay.androidApk);
        abi = 'arm64-v8a';
        expect((await u.fileFor(r))?.name, 'encore-android-arm64-v8a.apk');
        abi = 'x86_64';
        expect((await u.fileFor(r))?.name, 'encore-android.apk');
      },
    );

    test(
      'Windows (installed): the installer; elsewhere: none (the page)',
      () async {
        final u = Updates()..way = (() => UpdateWay.windowsInstaller);
        expect((await u.fileFor(r))?.name, 'encore-windows-setup.exe');
        u.way = () => UpdateWay.page;
        expect(await u.fileFor(r), isNull);
      },
    );
  });

  group('downloading', () {
    late HttpServer server;
    late Directory dir;
    final data = List.generate(300000, (i) => i % 251);
    final sha = sha256.convert(data).toString();
    late void Function(HttpResponse) serve;

    setUp(() async {
      serve = (res) => res.add(data);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        serve(req.response);
        await req.response.close();
      });
      dir = await Directory.systemTemp.createTemp('encore_update_dl');
    });

    tearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    ReleaseFile file({int? size, String? hash}) => ReleaseFile(
      'encore-windows-setup.exe',
      Uri.parse('http://127.0.0.1:${server.port}/setup'),
      size ?? data.length,
      hash ?? sha,
    );

    List<String> left() => [
      for (final f in dir.listSync()) f.uri.pathSegments.last,
    ];

    test(
      'the whole file, checked against the checksum, with progress',
      () async {
        final seen = <double>[];
        final f = await Updates().download(
          file(),
          dir: dir,
          progress: seen.add,
        );
        expect(await f.readAsBytes(), data);
        expect(seen.last, 1);
        expect(left(), ['encore-windows-setup.exe']);
      },
    );

    Future<void> fails(ReleaseFile f, String why) async {
      await expectLater(
        Updates().download(f, dir: dir),
        throwsA(
          isA<UpdateFailed>().having(
            (e) => e.message,
            'message',
            contains(why),
          ),
        ),
      );
      expect(left(), isEmpty, reason: 'nothing half-downloaded is left');
    }

    test("a file that doesn't match the checksum is thrown away", () async {
      await fails(file(hash: 'b' * 64), "doesn't match");
    });

    test('a download that stops part way is thrown away', () async {
      serve = (res) => res.add(data.sublist(0, 1000));
      await fails(file(), 'stopped part way');
    });

    test('a bigger file than published is thrown away', () async {
      await fails(file(size: 100, hash: null), 'bigger than expected');
    });

    test('refused (404): said, nothing kept', () async {
      serve = (res) => res.statusCode = 404;
      await fails(file(), 'refused');
    });

    test('offline: "No connection", nothing kept', () async {
      final f = file();
      await server.close(force: true);
      await fails(f, 'No connection');
    });

    test('cancelled: stops, nothing kept', () async {
      await expectLater(
        Updates().download(file(), dir: dir, cancelled: () => true),
        throwsA(isA<UpdateFailed>()),
      );
      expect(left(), isEmpty);
    });

    test('a file left from an earlier try is replaced', () async {
      File('${dir.path}/encore-windows-setup.exe').writeAsStringSync('old');
      final f = await Updates().download(file(), dir: dir);
      expect(await f.length(), data.length);
    });
  });

  group('Windows: running the installer', () {
    test('silent, closing what holds the files, then Encore reopens: '
        'the installer is started directly (through cmd, the quoted paths '
        'broke and nothing was installed)', () {
      expect(Updates.installerArgs, [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
        '/RELAUNCH',
      ]);
      final source = File('lib/services/updates.dart').readAsStringSync();
      expect(source, isNot(contains("'cmd'")));
    });

    test(
      'the installer reopens Encore only for an update Encore started '
      '(/RELAUNCH, or the /CLOSEAPPLICATIONS of 0.3.0), not for release checks',
      () {
        final iss = File('windows/installer.iss').readAsStringSync();
        expect(iss, contains('Check: UpdatedFromEncore'));
        expect(iss, contains("'/RELAUNCH'"));
        expect(iss, contains("'/CLOSEAPPLICATIONS'"));
        final checks = File('tool/release_check.sh').readAsStringSync();
        expect(checks, isNot(contains('RELAUNCH')));
        expect(checks, isNot(contains('CLOSEAPPLICATIONS')));
      },
    );
  });
}
