import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'storage.dart';

/// The home feed as last loaded, shown at once when the app opens (and
/// when offline) instead of a spinner while the new one loads.
List<Shelf>? lastHome;

Future<File> _file() async =>
    File('${(await dataDir()).path}${Platform.pathSeparator}home.json');

Future<void> loadLastHome() async {
  try {
    lastHome = [
      for (final s in jsonDecode(await (await _file()).readAsString()) as List)
        Shelf.fromJson(s),
    ];
  } on PathNotFoundException {
    // Never loaded yet.
  } catch (e) {
    debugPrint('Last home feed unreadable: $e');
  }
}

Future<void> saveHome(List<Shelf> shelves) async {
  lastHome = shelves;
  try {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(shelves), flush: true);
    await temp.rename(file.path);
  } catch (e) {
    debugPrint('Saving the home feed failed: $e');
  }
}
