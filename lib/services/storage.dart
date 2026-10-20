import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Builds with `--dart-define=ENCORE_TEST=true` (the integration tests) keep
/// their data apart from the user's library.
const _isTest = bool.fromEnvironment('ENCORE_TEST');

Directory? _dir;

/// Where the app keeps its library file and downloads.
Future<Directory> dataDir() async => _dir ??= await Directory(
  [
    (await getApplicationSupportDirectory()).path,
    if (_isTest) 'test_data',
  ].join(Platform.pathSeparator),
).create(recursive: true);
