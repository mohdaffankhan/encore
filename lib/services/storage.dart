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
Future<Directory> dataDir() async => _dir ??= await Directory(
  [
    (await getApplicationSupportDirectory()).path,
    if (_isTest) 'test_data',
  ].join(Platform.pathSeparator),
).create(recursive: true);
