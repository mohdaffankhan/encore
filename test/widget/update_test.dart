import 'dart:io';

import 'package:encore/services/storage.dart';
import 'package:encore/services/updates.dart';
import 'package:encore/ui/theme.dart';
import 'package:encore/ui/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _release = Release(
  version: '0.3.0',
  page: Uri.parse('https://github.com/$repo/releases/tag/v0.3.0'),
  notes: const ['Themes', 'Equalizer'],
  files: {
    for (final name in ['encore-windows-setup.exe', 'encore-android.apk'])
      name: ReleaseFile(
        name,
        Uri.parse('https://github.com/$repo/releases/download/v0.3.0/$name'),
        1000,
        null,
      ),
  },
);

void main() {
  late Directory dir;
  late List<String> did;
  late List<Object> downloads;
  late List<bool> installAnswers;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('encore_update_ui');
    useDataDir(dir);
    did = [];
    downloads = [];
    installAnswers = [true];
    updates.way = () => UpdateWay.windowsInstaller;
    openReleasePage = (page) async {
      did.add('page');
      return true;
    };
    runInstaller = (file) async => did.add('installer ${file.path}');
    installApk = (file) async {
      did.add('apk');
      return installAnswers.removeAt(0);
    };
    downloadsDir = () async => dir;
    // A phone of no known processor type: the APK for every phone.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.encore.app/update'),
          (call) async => null,
        );
    // Each download answers with the next of [downloads].
    downloadUpdate = (file, {required dir, progress, cancelled}) async {
      did.add('download ${file.name}');
      progress?.call(0.5);
      final next = downloads.removeAt(0);
      if (next is UpdateFailed) throw next;
      return next as File;
    };
  });

  tearDown(() {
    updates.way = howToUpdate;
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Still being written (Skip saves as the test ends): left in temp.
    }
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => offerUpdate(context, _release, current: '0.2.1'),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets("says the new version, what's new, and the one you have", (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Encore 0.3.0 is out'), findsOneWidget);
    expect(find.text('You have 0.2.1.'), findsOneWidget);
    expect(find.text('•  Themes'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
  });

  testWidgets('Skip: remembered (not again for 10 days)', (tester) async {
    await open(tester);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(updates.state.skipped, '0.3.0');
    expect(did, isEmpty);
  });

  testWidgets('Windows: downloads the installer, then runs it', (
    tester,
  ) async {
    final setup = File('${dir.path}/encore-windows-setup.exe');
    downloads = [setup];
    await open(tester);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(did, [
      'download encore-windows-setup.exe',
      'installer ${setup.path}',
    ]);
  });

  testWidgets("a failed download says why, changes nothing; Try again "
      'tries again', (tester) async {
    final setup = File('${dir.path}/encore-windows-setup.exe');
    downloads = [const UpdateFailed('No connection'), setup];
    await open(tester);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't download the update"), findsOneWidget);
    expect(find.textContaining('No connection'), findsOneWidget);
    expect(find.textContaining('Encore is as it was'), findsOneWidget);
    expect(did, ['download encore-windows-setup.exe'], reason: 'not run');
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(did.last, 'installer ${setup.path}');
  });

  testWidgets('a failed download can be got from the release page instead', (
    tester,
  ) async {
    downloads = [const UpdateFailed("The download doesn't match the release")];
    await open(tester);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open download page'));
    await tester.pumpAndSettle();
    expect(did.last, 'page');
  });

  testWidgets('cancelled: nothing more happens', (tester) async {
    downloads = [const UpdateFailed('Cancelled')];
    await open(tester);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(did, ['download encore-windows-setup.exe']);
  });

  testWidgets('Android: downloads the APK and opens the installer', (
    tester,
  ) async {
    updates.way = () => UpdateWay.androidApk;
    downloads = [File('${dir.path}/encore-android.apk')];
    await open(tester);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(did.last, 'apk');
  });

  testWidgets('Android, the first time: asks to allow installing, then '
      'installs', (tester) async {
    updates.way = () => UpdateWay.androidApk;
    downloads = [File('${dir.path}/encore-android.apk')];
    installAnswers = [false, true];
    await open(tester);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(find.text('Allow Encore to install the update'), findsOneWidget);
    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();
    expect(did.where((d) => d == 'apk'), hasLength(2));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('portable, AppImage, tar.gz: the release page opens', (
    tester,
  ) async {
    updates.way = () => UpdateWay.page;
    await open(tester);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(did, ['page']);
  });

  testWidgets('the download shows its progress and can be cancelled', (
    tester,
  ) async {
    var stopped = false;
    downloadUpdate = (file, {required dir, progress, cancelled}) async {
      progress?.call(0.25);
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (cancelled?.call() ?? false) {
          stopped = true;
          throw const UpdateFailed('Cancelled');
        }
      }
      return File('${dir.path}/x');
    };
    await open(tester);
    await tester.tap(find.text('Update'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Downloading the update'), findsOneWidget);
    expect(find.textContaining('25% of'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(stopped, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(did, isEmpty, reason: 'nothing installed');
  });
}
