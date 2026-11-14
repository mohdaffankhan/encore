import 'dart:io';

import 'package:flutter/material.dart';

import '../../api/auth.dart';
import '../../api/innertube.dart' as yt;
import '../../models.dart';
import '../../services/account.dart';
import '../theme.dart';
import '../widgets/widgets.dart';
import 'library_page.dart' show SyncStatus;
import 'sign_in.dart';

/// How sign-in pages open (tests use their own).
@visibleForTesting
var openSignIn = openSignInPage;
@visibleForTesting
var pasteSignIn = askForPastedCookies;

/// Whether this device can show Google's sign-in page in Encore: Android
/// and Windows. Linux signs in with the browser instead (tests change it).
@visibleForTesting
var hasSignInWindow = Platform.isAndroid || Platform.isWindows;

/// Settings' account rows: sign in to YouTube Music (optional), who is
/// signed in, their channels, signing out.
class AccountSettings extends StatefulWidget {
  const AccountSettings({super.key});

  @override
  State<AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<AccountSettings> {
  /// A sign-in, sign-out or channel change is under way.
  var _busy = false;

  bool get _desktop => Platform.isWindows || Platform.isLinux;

  /// The ways in this device has, best first.
  List<Widget> _signInButtons(String label) => [
    if (hasSignInWindow)
      FilledButton.icon(
        onPressed: _busy ? null : _signIn,
        icon: const Icon(Icons.login_rounded),
        label: Text(label),
      )
    else
      // Linux: no sign-in window (see sign_in.dart); the browser's.
      FilledButton.icon(
        onPressed: _busy ? null : () => _signIn(paste: true),
        icon: const Icon(Icons.login_rounded),
        label: const Text('Sign in with your browser'),
      ),
    if (_desktop && hasSignInWindow)
      TextButton(
        onPressed: _busy ? null : () => _signIn(paste: true),
        child: const Text('Sign in with your browser'),
      ),
  ];

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message) {
    if (mounted) showToast(context, message);
  }

  Future<void> _signIn({bool paste = false}) async {
    if (!paste) return _run(() => _openPage());
    // Nothing is under way while the user pastes: busy only once checking.
    if (_busy) return;
    final cookies = await pasteSignIn(context);
    if (cookies != null) await _run(() => _finish(cookies, page: false));
  }

  Future<void> _openPage() async {
    YouTubeCookies? cookies;
    try {
      cookies = await openSignIn(context);
    } on SignInUnavailable {
      if (!mounted) return;
      _say(
        Platform.isWindows
            ? "The sign-in window needs Microsoft Edge WebView2. Use "
                  '"Sign in with your browser" instead.'
            : 'The sign-in window needs WebKitGTK. Use "Sign in with your '
                  'browser" instead.',
      );
      return;
    } catch (e) {
      debugPrint('Sign-in page failed: $e');
      _say("The sign-in page couldn't open.");
      return;
    }
    if (cookies == null) return; // Closed.
    await _finish(cookies, page: true);
  }

  Future<void> _finish(YouTubeCookies cookies, {required bool page}) async {
    final problem = await account.signInWith(cookies);
    // The sign-in page's copy of the session isn't needed any more.
    try {
      if (page) await account.clearBrowser?.call();
    } catch (e) {
      debugPrint('Clearing the sign-in page failed: $e');
    }
    _say(problem ?? 'Signed in as ${account.info.value?.name ?? 'you'}');
  }

  Future<void> _signOut() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of YouTube Music?'),
        content: const Text(
          'Your songs, playlists and downloads on this device stay. '
          'Recommendations will no longer be made for you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await _run(account.signOut);
    _say('Signed out');
  }

  Future<void> _pickChannel() => _run(() async {
    List<AccountChannel> channels;
    try {
      channels = await yt.accountChannels();
    } catch (e) {
      _say("Couldn't load your channels. Check your connection.");
      return;
    }
    if (!mounted) return;
    if (channels.length < 2) {
      _say('This account has only one channel.');
      return;
    }
    final picked = await showModalBottomSheet<AccountChannel>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in channels)
              ListTile(
                leading: _Avatar(c.photoUrl, c.name, size: 36),
                title: Text(c.name),
                subtitle: c.handle.isEmpty ? null : Text(c.handle),
                trailing: c.pageId == account.pageId
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(c),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await account.useChannel(picked);
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([account.status, account.info]),
      builder: (context, _) {
        final pad = pagePadding(context);
        final text = Theme.of(context).textTheme;
        final who = account.info.value;
        final status = account.status.value;
        final secondary = text.bodySmall?.copyWith(
          color: EncoreColors.textSecondary,
        );
        final busy = _busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null;
        if (status == AccountStatus.signedOut || who == null) {
          return Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YouTube Music account',
                  style: text.titleSmall?.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 3),
                Text(
                  'Optional. Signed in, your home, mixes and radio are made '
                  'for you, and your likes and playlists stay in sync. '
                  'Encore is unofficial: Google could limit accounts that '
                  'use it.',
                  style: secondary,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ..._signInButtons('Sign in'),
                    ?busy,
                  ],
                ),
              ],
            ),
          );
        }
        final ended = status == AccountStatus.ended;
        return Padding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Avatar(who.photoUrl, who.name, size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          who.name,
                          style: text.titleSmall?.copyWith(fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          ended
                              ? 'Your sign-in has ended. Sign in again for '
                                    'recommendations made for you.'
                              : [
                                  if (who.handle.isNotEmpty) who.handle,
                                  'Signed in to YouTube Music',
                                ].join(' · '),
                          style: ended
                              ? secondary?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                )
                              : secondary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (ended)
                    ..._signInButtons('Sign in again')
                  else
                    OutlinedButton(
                      onPressed: _busy ? null : _pickChannel,
                      child: const Text('Switch channel'),
                    ),
                  TextButton(
                    onPressed: _busy ? null : _signOut,
                    child: Text(ended ? 'Forget account' : 'Sign out'),
                  ),
                  ?busy,
                ],
              ),
              if (!ended)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: SyncStatus(inset: false),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.url, this.name, {required this.size});

  final String url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = name.characters.firstOrNull?.toUpperCase() ?? '?';
    final fallback = CircleAvatar(
      radius: size / 2,
      backgroundColor: EncoreColors.surfaceHigh,
      child: Text(letter, style: TextStyle(color: EncoreColors.text)),
    );
    if (url.isEmpty) return fallback;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          ),
        ),
      ),
    );
  }
}
