import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Builds with `--dart-define=ENCORE_TEST=true` (the integration tests) and
/// `encore --self-test` keep their data apart from the user's library.
var _isTest = const bool.fromEnvironment('ENCORE_TEST');

void useTestData() => _isTest = true;

Directory? _dir;

@visibleForTesting
void useDataDir(Directory dir) => _dir = dir;

/// Where the app keeps its library file and downloads.
Future<Directory> dataDir() async {
  if (_dir case final dir?) return dir;
  final support = await getApplicationSupportDirectory();
  if (Platform.isLinux) await moveOldLinuxData(support);
  return _dir = await Directory(
    [support.path, if (_isTest) 'test_data'].join(Platform.pathSeparator),
  ).create(recursive: true);
}

/// Linux keeps app data in a folder named after the app id, which changed
/// from `dev.encore.app` (0.1.4 and before): moves the library (and
/// downloads) from the old folder into [support] once.
@visibleForTesting
Future<void> moveOldLinuxData(Directory support) async {
  final old = Directory(
    '${support.parent.path}${Platform.pathSeparator}dev.encore.app',
  );
  try {
    if (old.path == support.path || !await old.exists()) return;
    if (await support.exists()) {
      // Only into a new, empty folder: never over a library.
      if (!await support.list().isEmpty) return;
      await support.delete();
    }
    await old.rename(support.path);
  } catch (e) {
    debugPrint('Moving the old library failed: $e');
  }
}
