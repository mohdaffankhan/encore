import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../api/auth.dart';
import '../api/innertube.dart' as yt;
import '../models.dart';
import 'dpapi.dart' as dpapi;
import 'storage.dart';

final account = Account();

enum AccountStatus {
  signedOut,
  signedIn,

  /// Was signed in, but YouTube no longer accepts the sign-in (signed out
  /// elsewhere, password changed, or it expired): Encore carries on signed
  /// out and asks for a new sign-in.
  ended,
}

/// Where the sign-in is kept: the system's store for secrets (Windows
/// Credential Manager's encryption, Android's Keystore, the Linux keyring).
abstract interface class SecretStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// The user's YouTube Music account: optional. Signed in, YouTube Music's
/// own recommendations (home, radio, up next) are made for them, and it
/// learns from what they play and like. Signed out, Encore works as before.
class Account implements yt.YouTubeSignIn {
  Account({SecretStore? store}) : _store = store ?? DeviceSecretStore();

  SecretStore _store;

  /// Asks YouTube who is signed in (tests answer themselves).
  @visibleForTesting
  Future<AccountInfo?> Function() whoIs = yt.accountInfo;

  /// Starts over signed out, keeping the sign-in in [store] (tests).
  @visibleForTesting
  void reset({SecretStore? store}) {
    _saveTimer?.cancel();
    if (store != null) _store = store;
    _cookies = null;
    _pageId = null;
    info.value = null;
    notice.value = null;
    status.value = AccountStatus.signedOut;
    whoIs = yt.accountInfo;
    clearBrowser = null;
    _checking = 0;
    _lastWrite = null;
  }

  final status = ValueNotifier(AccountStatus.signedOut);

  /// Something to tell the user (shown once, then cleared).
  final notice = ValueNotifier<String?>(null);

  /// Who is signed in (kept when the sign-in ends, to say whose it was).
  final info = ValueNotifier<AccountInfo?>(null);

  /// The brand channel used, if not the account's own.
  String? get pageId => _pageId;
  String? _pageId;

  /// Goes up whenever the account changes (signing in, out, switching
  /// channel, or the sign-in ending): what was loaded for the old one
  /// (the home feed) is out of date.
  final generation = ValueNotifier(0);

  YouTubeCookies? _cookies;

  /// Which [generation] each header set was made for, so a reply to a
  /// request made before signing out can't change anything after.
  final _issued = Expando<int>();

  bool get signedIn => status.value == AccountStatus.signedIn;

  /// Called when signing out or a sign-in ends: forgets the sign-in page's
  /// own copy of the session (the webview's cookies).
  Future<void> Function()? clearBrowser;

  Future<void> load() async {
    yt.signIn = this;
    String? text;
    try {
      text = await _store.read();
    } catch (e) {
      debugPrint('Account unreadable: $e');
    }
    if (text == null) return;
    try {
      final json = jsonDecode(text);
      info.value = AccountInfo.fromJson(json['info']);
      _pageId = json['pageId'] is String ? json['pageId'] as String : null;
      if (json['ended'] == true) {
        status.value = AccountStatus.ended;
        return;
      }
      final cookies = YouTubeCookies.fromJson(json);
      if (cookies == null) {
        if (info.value != null) status.value = AccountStatus.ended;
        return;
      }
      _cookies = cookies;
      status.value = AccountStatus.signedIn;
      // Name or photo changed elsewhere, or the sign-in ended meanwhile.
      unawaited(_check());
    } catch (e) {
      debugPrint('Account unreadable: $e');
    }
  }

  /// Signs in with cookies from the sign-in page (or pasted from a
  /// browser): checks with YouTube that they work first. Returns why not,
  /// or null when signed in.
  Future<String?> signInWith(YouTubeCookies cookies) async {
    if (!cookies.usable) return 'That sign-in is incomplete. Try again.';
    final (oldCookies, oldStatus, oldPage) = (_cookies, status.value, _pageId);
    void restore() {
      _cookies = oldCookies;
      _pageId = oldPage;
      status.value = oldStatus;
    }

    _cookies = cookies;
    _pageId = null;
    status.value = AccountStatus.signedIn;
    final gen = _checking = ++_checks;
    AccountInfo? who;
    try {
      who = await whoIs();
    } catch (e) {
      debugPrint('Sign-in check failed: $e');
      restore();
      return "Couldn't reach YouTube Music. Check your connection and try "
          'again.';
    } finally {
      if (gen == _checking) _checking = 0;
    }
    if (who == null) {
      restore();
      return "YouTube Music didn't accept that sign-in. Try again.";
    }
    info.value = who;
    _changed();
    await _save();
    return null;
  }

  /// Forgets the sign-in on this device. The library stays as it is.
  Future<void> signOut() async {
    _saveTimer?.cancel();
    _cookies = null;
    _pageId = null;
    info.value = null;
    status.value = AccountStatus.signedOut;
    _changed();
    await _lastWrite;
    try {
      await _store.delete();
    } catch (e) {
      debugPrint('Removing the account failed: $e');
    }
    await _clearBrowser();
  }

  /// Uses YouTube Music as [channel] (one of [yt.accountChannels]).
  Future<void> useChannel(AccountChannel channel) async {
    if (!signedIn || channel.pageId == _pageId) return;
    _pageId = channel.pageId;
    info.value = AccountInfo(
      name: channel.name,
      handle: channel.handle,
      photoUrl: channel.photoUrl,
    );
    _changed();
    await _save();
    unawaited(_check());
  }

  void _changed() {
    generation.value++;
    yt.resetVisitor();
  }

  @override
  Map<String, String>? headers() {
    final cookies = _cookies;
    if (!signedIn || cookies == null || !cookies.usable) return null;
    final headers = authHeaders(cookies, pageId: _pageId);
    _issued[headers] = generation.value;
    return headers;
  }

  @override
  void replied(
    Map<String, String> signed,
    List<Cookie> cookies,
    int status,
    Map<String, dynamic>? json,
  ) {
    if (_issued[signed] != generation.value || !signedIn) return;
    if (_cookies?.update(cookies) ?? false) _saveSoon();
    final refused =
        status == HttpStatus.unauthorized ||
        (json != null && signedInReply(json) == false);
    if (refused) unawaited(_check());
  }

  /// Non-zero while a check is running (and which one).
  var _checking = 0;
  var _checks = 0;

  /// Asks YouTube who is signed in: updates the name and photo, or notices
  /// the sign-in has ended. Network trouble changes nothing.
  Future<void> _check() async {
    if (_checking != 0 || !signedIn) return;
    final gen = _checking = ++_checks;
    final at = generation.value;
    try {
      final who = await whoIs();
      if (at != generation.value || !signedIn) return;
      if (who == null) {
        await _ended();
      } else if (who != info.value && _pageId == null) {
        info.value = who;
        await _save();
      }
    } catch (e) {
      debugPrint('Account check failed: $e');
    } finally {
      if (gen == _checking) _checking = 0;
    }
  }

  Future<void> _ended() async {
    _cookies = null;
    status.value = AccountStatus.ended;
    notice.value =
        'Your YouTube Music sign-in has ended. Sign in again in Settings.';
    _changed();
    await _save();
    await _clearBrowser();
  }

  Future<void> _clearBrowser() async {
    try {
      await clearBrowser?.call();
    } catch (e) {
      debugPrint('Clearing the sign-in page failed: $e');
    }
  }

  Timer? _saveTimer;

  /// The last save (null before any): the next one waits for it.
  Future<void>? _lastWrite;

  /// Completes when every change so far is saved.
  @visibleForTesting
  Future<void> get saved {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      return _save();
    }
    return _lastWrite ?? Future.value();
  }

  /// New cookies come with many replies: saved once they settle.
  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _save);
  }

  Future<void> _save() {
    _saveTimer?.cancel();
    final json = jsonEncode({
      'info': ?info.value?.toJson(),
      'pageId': ?_pageId,
      if (status.value == AccountStatus.ended) 'ended': true,
      if (_cookies case final cookies?) ...cookies.toJson(),
    });
    return _lastWrite = (_lastWrite ?? Future.value()).then((_) async {
      // Signed out meanwhile: nothing to keep.
      if (status.value == AccountStatus.signedOut) return;
      try {
        await _store.write(json);
      } catch (e) {
        debugPrint('Saving the account failed: $e');
      }
    });
  }
}

/// The sign-in, in a file in Encore's data folder that only this user can
/// read: on Windows also encrypted for the Windows user (DPAPI); Android
/// keeps it in the app's private storage, left out of backups.
class DeviceSecretStore implements SecretStore {
  DeviceSecretStore([this._dir]);

  final Directory? _dir;

  static const _prefix = 'dpapi:';

  Future<File> _file() async => File(
    '${(_dir ?? await dataDir()).path}${Platform.pathSeparator}account.json',
  );

  @override
  Future<String?> read() async {
    final String text;
    try {
      text = await (await _file()).readAsString();
    } on PathNotFoundException {
      return null;
    }
    if (!Platform.isWindows) return text;
    // Only ever written encrypted: anything else wasn't written by Encore.
    if (!text.startsWith(_prefix)) return null;
    return utf8.decode(
      dpapi.unprotect(base64.decode(text.substring(_prefix.length))),
    );
  }

  @override
  Future<void> write(String value) async {
    final text = Platform.isWindows
        ? '$_prefix${base64.encode(dpapi.protect(utf8.encode(value)))}'
        : value;
    final file = await _file();
    final temp = File('${file.path}.tmp');
    // Private before anything is in it.
    await temp.writeAsString('', flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', temp.path]);
    }
    await temp.writeAsString(text, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<void> delete() async {
    for (final f in [await _file(), File('${(await _file()).path}.tmp')]) {
      try {
        await f.delete();
      } on PathNotFoundException {
        // None.
      }
    }
  }
}
