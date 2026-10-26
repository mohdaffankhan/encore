import 'dart:io';

import 'package:encore/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';

// The Linux app id (and so its data folder) changed: the library moves.
void main() {
  late Directory share;
  late Directory support;
  late Directory old;

  setUp(() async {
    share = await Directory.systemTemp.createTemp('encore_share');
    support = Directory('${share.path}/io.github.mohdaffankhan.Encore');
    old = Directory('${share.path}/dev.encore.app');
  });
  tearDown(() => share.delete(recursive: true));

  test('the old library moves to the new folder', () async {
    await File('${old.path}/library.json').create(recursive: true);
    await File('${old.path}/downloads/a.webm').create(recursive: true);
    await moveOldLinuxData(support);
    expect(File('${support.path}/library.json').existsSync(), isTrue);
    expect(File('${support.path}/downloads/a.webm').existsSync(), isTrue);
    expect(old.existsSync(), isFalse);
  });

  test('an empty new folder (made by a first start) is replaced', () async {
    await File('${old.path}/library.json').create(recursive: true);
    await support.create();
    await moveOldLinuxData(support);
    expect(File('${support.path}/library.json').existsSync(), isTrue);
  });

  test('never over a library already in the new folder', () async {
    await File('${old.path}/library.json').create(recursive: true);
    await File('${old.path}/library.json').writeAsString('old');
    await File('${support.path}/library.json').create(recursive: true);
    await File('${support.path}/library.json').writeAsString('new');
    await moveOldLinuxData(support);
    expect(File('${support.path}/library.json').readAsStringSync(), 'new');
    expect(old.existsSync(), isTrue, reason: 'left alone');
  });

  test('nothing to move: nothing happens', () async {
    await moveOldLinuxData(support);
    expect(support.existsSync(), isFalse);
  });
}
