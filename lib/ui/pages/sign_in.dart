import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/auth.dart';
import '../../services/storage.dart';
import '../theme.dart';

/// Google's own sign-in page, which goes on to YouTube Music once signed in.
final signInUrl = Uri.parse(
  'https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube'
  '&passive=true&continue=${Uri.encodeComponent('$musicOrigin/')}',
);

/// Whether [url] is YouTube Music itself (the sign-in is done once there).
@visibleForTesting
bool reachedMusic(String? url) {
  final uri = Uri.tryParse(url ?? '');
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'music.youtube.com';
}

const _cookies = MethodChannel('dev.encore.app/cookies');

Future<String> _desktopProfile() async =>
    '${(await dataDir()).path}${Platform.pathSeparator}SignIn';

/// Forgets what the sign-in page kept (its copy of the session), so only
/// Encore's own copy is left, and signing out leaves nothing behind.
Future<void> clearSignInBrowser() async {
  if (Platform.isAndroid) {
    await _cookies.invokeMethod('clear');
  } else if (Platform.isWindows || Platform.isLinux) {
    await WebviewWindow.clearAll(
      windows: WindowsWebviewOptions(userDataFolder: await _desktopProfile()),
    );
  }
}

/// Opens Google's sign-in page in the app; the cookies once signed in to
/// YouTube Music, or null if the user closed it.
Future<YouTubeCookies?> openSignInPage(BuildContext context) async {
  if (Platform.isAndroid) {
    return Navigator.of(context, rootNavigator: true).push<YouTubeCookies>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const AndroidSignInPage(),
      ),
    );
  }
  return _desktopSignIn();
}

/// Desktop: a browser window of its own (WebView2 on Windows, WebKitGTK on
/// Linux), on a profile kept apart from the user's browsers.
Future<YouTubeCookies?> _desktopSignIn() async {
  if (!await WebviewWindow.isWebviewAvailable()) {
    throw const SignInUnavailable();
  }
  // Start from a clean page: a session left from before would be shared.
  await clearSignInBrowser();
  final web = await WebviewWindow.create(
    configuration: CreateConfiguration(
      title: 'Sign in to YouTube Music',
      windowWidth: 520,
      windowHeight: 720,
      titleBar: const TitleBarOptions(showNavigation: true, showHost: true),
      windows: WindowsWebviewOptions(userDataFolder: await _desktopProfile()),
    ),
  );
  var closed = false;
  unawaited(web.onClose.then((_) => closed = true));
  await web.launch(signInUrl.toString());
  YouTubeCookies? found;
  while (!closed) {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (closed || !reachedMusic(web.navigationState.value.url)) continue;
    try {
      final cookies = await web.getAllCookies();
      found = YouTubeCookies({
        for (final c in cookies)
          if (c.domain.toLowerCase().endsWith('youtube.com')) c.name: c.value,
      });
    } catch (e) {
      debugPrint('Sign-in cookies unreadable: $e');
      continue;
    }
    if (found.usable) break;
    found = null;
  }
  if (!closed) {
    web.close();
    await web.onClose.timeout(const Duration(seconds: 5), onTimeout: () {});
  }
  return found;
}

/// The sign-in window can't open (desktop without WebView2 / WebKitGTK).
class SignInUnavailable implements Exception {
  const SignInUnavailable();
}

/// Android: Google's sign-in in a WebView; done once it reaches YouTube
/// Music.
class AndroidSignInPage extends StatefulWidget {
  const AndroidSignInPage({super.key});

  @override
  State<AndroidSignInPage> createState() => _AndroidSignInPageState();
}

class _AndroidSignInPageState extends State<AndroidSignInPage> {
  late final WebViewController _web;
  var _progress = 0;
  var _done = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => mounted ? setState(() => _progress = p) : null,
          onUrlChange: (change) => _check(change.url),
          onPageFinished: _check,
        ),
      );
    // A clean page: no session left from before.
    clearSignInBrowser().whenComplete(() => _web.loadRequest(signInUrl));
  }

  Future<void> _check(String? url) async {
    if (_done || !reachedMusic(url)) return;
    final header = await _cookies.invokeMethod<String>('get', {
      'url': '$musicOrigin/',
    });
    final cookies = header == null ? null : YouTubeCookies.parse(header);
    if (cookies == null || _done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(cookies);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Sign in to YouTube Music'),
      leading: IconButton(
        tooltip: 'Close',
        icon: const Icon(Icons.close_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
      bottom: _progress < 100
          ? PreferredSize(
              preferredSize: const Size.fromHeight(2),
              child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress / 100,
                minHeight: 2,
              ),
            )
          : null,
    ),
    body: WebViewWidget(controller: _web),
  );
}

/// Desktop's other way in: sign in with the user's own browser and paste
/// its YouTube Music cookies here. Returns them, or null if cancelled.
Future<YouTubeCookies?> askForPastedCookies(BuildContext context) =>
    showDialog<YouTubeCookies>(
      context: context,
      builder: (_) => const PasteSignInDialog(),
    );

class PasteSignInDialog extends StatefulWidget {
  const PasteSignInDialog({super.key});

  @override
  State<PasteSignInDialog> createState() => _PasteSignInDialogState();
}

class _PasteSignInDialogState extends State<PasteSignInDialog> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final cookies = YouTubeCookies.parse(_text.text);
    if (cookies == null) {
      setState(
        () => _error = _text.text.trim().isEmpty
            ? 'Paste the cookies first.'
            : "These aren't signed-in YouTube Music cookies.",
      );
      return;
    }
    Navigator.of(context).pop(cookies);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hint = text.bodyMedium?.copyWith(color: EncoreColors.textSecondary);
    return AlertDialog(
      title: const Text('Sign in with your browser'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '1. Open music.youtube.com in a private window and sign in.\n'
                '2. Press F12, open Network, and click any request to '
                'music.youtube.com.\n'
                '3. Under Request Headers, copy the value of "cookie" and '
                'paste it here.\n'
                '4. Close the private window without signing out.',
                style: hint,
              ),
              const SizedBox(height: 8),
              Text(
                'These cookies sign in to your account: paste them only '
                'into Encore, never anywhere else.',
                style: hint,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _text,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  labelText: 'Cookies',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Sign in')),
      ],
    );
  }
}
