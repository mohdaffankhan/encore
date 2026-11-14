import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'settings.dart';
import 'storage.dart';

/// A published release of Encore on GitHub.
@immutable
class Release {
  const Release({
    required this.version,
    required this.page,
    this.notes = const [],
    this.files = const {},
  });

  /// e.g. 0.3.0 (the tag without its "v").
  final String version;

  /// Its page on GitHub, for whoever updates by hand.
  final Uri page;

  /// "What's new", one line each.
  final List<String> notes;

  /// Its files by name.
  final Map<String, ReleaseFile> files;

  static Release? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    final page = Uri.tryParse('${json['html_url']}');
    if (tag is! String || page == null || !page.isScheme('https')) return null;
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    if (parseVersion(version) == null) return null;
    return Release(
      version: version,
      page: page,
      notes: whatsNew(json['body'] is String ? json['body'] as String : ''),
      files: {
        for (final a in json['assets'] is List ? json['assets'] as List : [])
          // ignore: use_null_aware_elements (the key comes from it)
          if (ReleaseFile.fromJson(a) case final f?) f.name: f,
      },
    );
  }
}

@immutable
class ReleaseFile {
  const ReleaseFile(this.name, this.url, this.size, this.sha256);

  final String name;
  final Uri url;
  final int size;

  /// From GitHub (hex), to check the download against; null if not given.
  final String? sha256;

  /// Only Encore's own release files, from GitHub, over https.
  static ReleaseFile? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final url = Uri.tryParse('${json['browser_download_url']}');
    final size = json['size'];
    if (name is! String || url == null || size is! int || size <= 0) {
      return null;
    }
    if (!url.isScheme('https') ||
        url.host != 'github.com' ||
        !url.path.startsWith('/$repo/releases/download/')) {
      return null;
    }
    final digest = json['digest'];
    final sha = digest is String && digest.startsWith('sha256:')
        ? digest.substring(7).toLowerCase()
        : null;
    return ReleaseFile(name, url, size, sha);
  }
}

const repo = 'mohdaffankhan/encore';

/// "1.2.3" as numbers (a "+build" or "-pre" ending left out); null if it
/// isn't a version.
List<int>? parseVersion(String version) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version.trim());
  if (m == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m[i]!)];
}

/// Whether [version] is newer than [than].
bool isNewer(String version, String than) {
  final a = parseVersion(version), b = parseVersion(than);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// The "What's new" list of release notes, as plain lines.
@visibleForTesting
List<String> whatsNew(String body) {
  final lines = const LineSplitter().convert(body);
  final start = lines.indexWhere(
    (l) => RegExp(r"^#+\s*what'?s new", caseSensitive: false).hasMatch(l),
  );
  final from = start < 0 ? lines : lines.skip(start + 1);
  return [
    for (final l in from.takeWhile((l) => !l.startsWith('#')))
      if (RegExp(r'^\s*[-*]\s+').hasMatch(l))
        l
            .replaceFirst(RegExp(r'^\s*[-*]\s+'), '')
            .replaceAll('**', '')
            .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
            .trim(),
  ].where((l) => l.isNotEmpty).take(8).toList();
}

/// How this copy of Encore can update itself.
enum UpdateWay {
  /// Download the APK and open Android's installer.
  androidApk,

  /// Download the installer and run it (Encore closes, then reopens).
  windowsInstaller,

  /// Open the release page (portable zip, AppImage, tar.gz, AUR).
  page,

  /// Updated by something else (Flathub): no reminders.
  none,
}

/// When to remind: never twice within [minGap], and a version skipped not
/// again for [skipFor] (an even newer one may come sooner).
class UpdatePolicy {
  const UpdatePolicy({
    this.skipFor = const Duration(days: 10),
    this.minGap = const Duration(days: 3),
    this.checkEvery = const Duration(hours: 20),
  });

  final Duration skipFor;
  final Duration minGap;
  final Duration checkEvery;

  bool shouldCheck(UpdateState s, DateTime now) =>
      s.checkedAt == null || now.difference(s.checkedAt!) >= checkEvery;

  bool shouldRemind(
    UpdateState s,
    Release latest,
    String current,
    DateTime now,
  ) {
    if (!isNewer(latest.version, current)) return false;
    if (s.shownAt case final shown? when now.difference(shown) < minGap) {
      return false;
    }
    if (s.skipped case final skipped?) {
      final at = s.skippedAt ?? now;
      // That version (or an older one), skipped lately: not yet.
      if (!isNewer(latest.version, skipped) && now.difference(at) < skipFor) {
        return false;
      }
    }
    return true;
  }
}

/// What was asked and answered, kept between runs.
@immutable
class UpdateState {
  const UpdateState({
    this.checkedAt,
    this.shownAt,
    this.skipped,
    this.skippedAt,
  });

  final DateTime? checkedAt;
  final DateTime? shownAt;
  final String? skipped;
  final DateTime? skippedAt;

  UpdateState copyWith({
    DateTime? checkedAt,
    DateTime? shownAt,
    String? skipped,
    DateTime? skippedAt,
  }) => UpdateState(
    checkedAt: checkedAt ?? this.checkedAt,
    shownAt: shownAt ?? this.shownAt,
    skipped: skipped ?? this.skipped,
    skippedAt: skippedAt ?? this.skippedAt,
  );

  Map<String, Object> toJson() => {
    'checkedAt': ?checkedAt?.toIso8601String(),
    'shownAt': ?shownAt?.toIso8601String(),
    'skipped': ?skipped,
    'skippedAt': ?skippedAt?.toIso8601String(),
  };

  static UpdateState fromJson(Object? json) {
    if (json is! Map) return const UpdateState();
    DateTime? at(String key) =>
        json[key] is String ? DateTime.tryParse(json[key] as String) : null;
    return UpdateState(
      checkedAt: at('checkedAt'),
      shownAt: at('shownAt'),
      skipped: json['skipped'] is String ? json['skipped'] as String : null,
      skippedAt: at('skippedAt'),
    );
  }
}

/// A download that didn't finish or didn't match what GitHub published.
class UpdateFailed implements Exception {
  const UpdateFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

final updates = Updates();

/// New versions of Encore: told about at startup (not often, see
/// [UpdatePolicy]), and installed from the release's own files, checked
/// against GitHub's checksums first.
class Updates {
  Updates({
    this.policy = const UpdatePolicy(),
    this.latestUrl = 'https://api.github.com/repos/$repo/releases/latest',
    this._dir,
  });

  final UpdatePolicy policy;
  final String latestUrl;
  final Directory? _dir;

  @visibleForTesting
  HttpClient http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..userAgent = 'Encore';

  @visibleForTesting
  DateTime Function() now = DateTime.now;

  /// This copy's version (tests give their own).
  Future<String> Function() currentVersion = () async =>
      (await PackageInfo.fromPlatform()).version;

  /// How this copy updates (tests choose).
  UpdateWay Function() way = howToUpdate;

  UpdateState state = const UpdateState();

  Future<File> _file() async => File(
    '${(_dir ?? await dataDir()).path}${Platform.pathSeparator}updates.json',
  );

  Future<void> _load() async {
    try {
      state = UpdateState.fromJson(
        jsonDecode(await (await _file()).readAsString()),
      );
    } catch (_) {
      // Never checked, or unreadable: from scratch.
    }
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(state), flush: true);
      await temp.rename(file.path);
    } catch (e) {
      debugPrint('Saving update state failed: $e');
    }
  }

  /// The newest published release, or null (offline, or GitHub said no).
  Future<Release?> latest() async {
    try {
      final req = await http.getUrl(Uri.parse(latestUrl));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final text = await utf8
          .decodeStream(res)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != HttpStatus.ok) return null;
      return Release.fromJson(jsonDecode(text));
    } catch (e) {
      debugPrint('Update check: $e');
      return null;
    }
  }

  /// At startup: a newer release to tell the user about, or null. Asks
  /// GitHub at most once a day, and only when a reminder could be shown.
  Future<Release?> check() async {
    if (way() == UpdateWay.none || !settings.updateReminders.value) return null;
    await _load();
    final at = now();
    if (!policy.shouldCheck(state, at)) return null;
    final current = await currentVersion();
    final release = await latest();
    state = state.copyWith(checkedAt: at);
    if (release == null || !policy.shouldRemind(state, release, current, at)) {
      await _save();
      return null;
    }
    state = state.copyWith(shownAt: at);
    await _save();
    return release;
  }

  /// Settings' "Check for updates": asks now, whatever was answered before.
  /// The release if newer, else null; throws if GitHub can't be reached.
  Future<Release?> checkNow() async {
    final release = await latest();
    if (release == null) throw const UpdateFailed("Couldn't reach GitHub");
    return isNewer(release.version, await currentVersion()) ? release : null;
  }

  /// "Skip": not again for this version for 10 days.
  Future<void> skip(Release release) async {
    state = state.copyWith(skipped: release.version, skippedAt: now());
    await _save();
  }

  /// The file this copy updates from.
  Future<ReleaseFile?> fileFor(Release release) async {
    switch (way()) {
      case UpdateWay.androidApk:
        String? abi;
        try {
          abi = await _android.invokeMethod<String>('abi');
        } catch (e) {
          // Unknown: the APK for every phone.
          debugPrint('Processor type unknown: $e');
        }
        return release.files['encore-android-$abi.apk'] ??
            release.files['encore-android.apk'];
      case UpdateWay.windowsInstaller:
        return release.files['encore-windows-setup.exe'];
      case UpdateWay.page || UpdateWay.none:
        return null;
    }
  }

  /// Downloads [file] (to [dir]) and checks it: its size, and the checksum
  /// GitHub published. [progress] gets 0 to 1. A broken download throws
  /// [UpdateFailed] and leaves nothing behind.
  Future<File> download(
    ReleaseFile file, {
    required Directory dir,
    void Function(double)? progress,
    bool Function()? cancelled,
  }) async {
    final out = File('${dir.path}${Platform.pathSeparator}${file.name}');
    final part = File('${out.path}.part');
    try {
      await dir.create(recursive: true);
      final req = await http.getUrl(file.url);
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != HttpStatus.ok) {
        throw UpdateFailed('The download was refused (${res.statusCode})');
      }
      final sink = part.openWrite();
      var got = 0;
      final hash = _DigestSink();
      final hasher = sha256.startChunkedConversion(hash);
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          if (cancelled?.call() ?? false) {
            throw const UpdateFailed('Cancelled');
          }
          got += chunk.length;
          if (got > file.size) {
            throw const UpdateFailed('The download is bigger than expected');
          }
          sink.add(chunk);
          hasher.add(chunk);
          progress?.call(got / file.size);
        }
      } finally {
        await sink.close();
      }
      hasher.close();
      if (got != file.size) {
        throw const UpdateFailed('The download stopped part way');
      }
      if (file.sha256 case final want? when hash.digest.toString() != want) {
        throw const UpdateFailed("The download doesn't match the release");
      }
      if (await out.exists()) await out.delete();
      return await part.rename(out.path);
    } on UpdateFailed {
      await _delete(part);
      rethrow;
    } catch (e) {
      await _delete(part);
      throw UpdateFailed(
        e is SocketException || e is TimeoutException || e is HttpException
            ? 'No connection'
            : "The download couldn't be saved",
      );
    }
  }

  static Future<void> _delete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static const _android = MethodChannel('dev.encore.app/update');

  /// Where downloads go: Android's cache (shared with the installer through
  /// Encore's file provider), or the temp folder.
  static Future<Directory> downloadsDir() async => Directory(
    '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}updates',
  );

  /// Android: opens the installer for [apk]. False if Android first needs
  /// the user to allow Encore to install apps (its settings are opened).
  static Future<bool> installApk(File apk) async =>
      await _android.invokeMethod<bool>('install', {'path': apk.path}) ?? false;

  /// Windows: runs [setup] silently once Encore has closed, then opens
  /// Encore again; Encore closes right after.
  static Future<void> runInstaller(File setup) async {
    final app = Platform.resolvedExecutable;
    await Process.start(
      'cmd',
      [
        '/c',
        // A moment for Encore to close; the installer closes it anyway.
        'timeout /t 2 /nobreak >nul & '
            '"${setup.path}" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART '
            '/CLOSEAPPLICATIONS & start "" "$app"',
      ],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
    exit(0);
  }
}

/// How this copy was installed, so how it updates.
UpdateWay howToUpdate() {
  if (const bool.fromEnvironment('ENCORE_TEST') || kDebugMode) {
    return UpdateWay.none;
  }
  if (Platform.isAndroid) return UpdateWay.androidApk;
  if (Platform.isWindows) {
    // Installed (the installer's uninstaller beside it), or portable.
    final dir = File(Platform.resolvedExecutable).parent.path;
    return File('$dir${Platform.pathSeparator}unins000.exe').existsSync()
        ? UpdateWay.windowsInstaller
        : UpdateWay.page;
  }
  if (Platform.isLinux) {
    // Flathub updates it itself.
    return Platform.environment.containsKey('FLATPAK_ID')
        ? UpdateWay.none
        : UpdateWay.page;
  }
  return UpdateWay.none;
}

class _DigestSink implements Sink<Digest> {
  late Digest digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
