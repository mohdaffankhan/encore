import 'dart:async';

import 'package:encore/api/auth.dart';
import 'package:encore/models.dart';
import 'package:encore/services/account.dart';
import 'package:encore/ui/pages/account_settings.dart';
import 'package:encore/ui/pages/sign_in.dart';
import 'package:encore/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/account_test.dart' show MemoryStore, goodCookies;
import 'shell_test.dart' show pumpApp;

const me = AccountInfo(name: 'Test Listener', handle: '@testlistener');

late MemoryStore store;
var browserCleared = 0;

/// The app's account, signed out, answering sign-in checks with [who].
void resetAccount({AccountInfo? who = me}) {
  store = MemoryStore();
  account.reset(store: store);
  account.whoIs = () async => who;
  browserCleared = 0;
  account.clearBrowser = () async => browserCleared++;
}

Future<void> signInDirectly() async {
  expect(await account.signInWith(goodCookies()), isNull);
}

Future<void> openSettingsPage(WidgetTester tester, {bool phone = false}) async {
  await pumpApp(tester, phone ? const Size(400, 860) : const Size(1400, 900));
  openSettings();
  await tester.pumpAndSettle();
}

void main() {
  setUp(resetAccount);
  tearDown(() {
    account.reset(store: MemoryStore());
    openSignIn = openSignInPage;
    pasteSignIn = askForPastedCookies;
    hasSignInWindow = true;
  });

  testWidgets('signed out: Settings offers signing in, and says it is '
      'optional and unofficial', (tester) async {
    await openSettingsPage(tester);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('YouTube Music account'), findsOneWidget);
    expect(find.textContaining('Optional.'), findsOneWidget);
    expect(find.textContaining('unofficial'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sign in with your browser'), findsOneWidget);
  });

  testWidgets('phone: the account rows are at the top of Settings', (
    tester,
  ) async {
    await openSettingsPage(tester, phone: true);
    expect(find.text('Sign in'), findsOneWidget);
    final account = tester.getTopLeft(find.text('Account')).dy;
    final appearance = tester.getTopLeft(find.text('Appearance')).dy;
    expect(account, lessThan(appearance));
  });

  testWidgets('signing in shows who is signed in', (tester) async {
    var opened = 0;
    openSignIn = (context) async {
      opened++;
      return goodCookies();
    };
    await openSettingsPage(tester);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(account.status.value, AccountStatus.signedIn);
    expect(find.text('Signed in as Test Listener'), findsOneWidget);
    expect(find.text('Test Listener'), findsOneWidget);
    expect(
      find.text('@testlistener · Signed in to YouTube Music'),
      findsOneWidget,
    );
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Switch channel'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    expect(browserCleared, 1, reason: "the sign-in page's copy is removed");
    await account.saved;
    expect(store.json!['info']['name'], 'Test Listener');
  });

  testWidgets('closing the sign-in page changes nothing', (tester) async {
    openSignIn = (context) async => null;
    await openSettingsPage(tester);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(account.status.value, AccountStatus.signedOut);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('a sign-in YouTube refuses says so and stays signed out', (
    tester,
  ) async {
    resetAccount(who: null);
    openSignIn = (context) async => goodCookies();
    await openSettingsPage(tester);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.textContaining("didn't accept"), findsOneWidget);
    expect(account.status.value, AccountStatus.signedOut);
    expect(find.text('Sign in'), findsOneWidget);
    expect(store.value, isNull);
  });

  testWidgets('offline while signing in says so', (tester) async {
    account.whoIs = () async => throw Exception('offline');
    openSignIn = (context) async => goodCookies();
    await openSettingsPage(tester);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't reach YouTube Music"), findsOneWidget);
    expect(account.status.value, AccountStatus.signedOut);
  });

  testWidgets('the sign-in page failing to open says so', (tester) async {
    openSignIn = (context) async => throw Exception('no window');
    await openSettingsPage(tester);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text("The sign-in page couldn't open."), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget, reason: 'can try again');
  });

  testWidgets('no WebView on the computer points to the browser way in', (
    tester,
  ) async {
    openSignIn = (context) async => throw const SignInUnavailable();
    await openSettingsPage(tester);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sign in with your browser'), findsNWidgets(2));
  });

  testWidgets('while signing in, the buttons wait (no second window)', (
    tester,
  ) async {
    final page = Completer<YouTubeCookies?>();
    var opened = 0;
    openSignIn = (context) {
      opened++;
      return page.future;
    };
    await openSettingsPage(tester);
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.tap(find.text('Sign in'), warnIfMissed: false);
    await tester.tap(
      find.text('Sign in with your browser'),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(opened, 1);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    page.complete(null);
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('signing out asks first; cancelling keeps the sign-in', (
    tester,
  ) async {
    await signInDirectly();
    await openSettingsPage(tester);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out of YouTube Music?'), findsOneWidget);
    expect(find.textContaining('playlists and downloads'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(account.status.value, AccountStatus.signedIn);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(account.status.value, AccountStatus.signedOut);
    expect(find.text('Signed out'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(store.value, isNull);
    expect(browserCleared, 1);
  });

  testWidgets('an ended sign-in: says so once, offers signing in again', (
    tester,
  ) async {
    await signInDirectly();
    account.whoIs = () async => null;
    await openSettingsPage(tester);
    // YouTube no longer accepts it (noticed by a request).
    account.replied(account.headers()!, const [], 401, null);
    await tester.pumpAndSettle();
    expect(account.status.value, AccountStatus.ended);
    expect(
      find.textContaining('sign-in has ended. Sign in again in Settings'),
      findsOneWidget,
    );
    expect(account.notice.value, isNull, reason: 'shown once');
    expect(find.text('Test Listener'), findsOneWidget);
    expect(find.textContaining('Your sign-in has ended'), findsOneWidget);
    expect(find.text('Sign in again'), findsOneWidget);
    expect(find.text('Forget account'), findsOneWidget);
    expect(find.text('Switch channel'), findsNothing);

    account.whoIs = () async => me;
    openSignIn = (context) async => goodCookies();
    await tester.tap(find.text('Sign in again'));
    await tester.pumpAndSettle();
    expect(account.status.value, AccountStatus.signedIn);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('forgetting an ended account', (tester) async {
    await signInDirectly();
    account.whoIs = () async => null;
    account.replied(account.headers()!, const [], 401, null);
    await openSettingsPage(tester);
    await tester.tap(find.text('Forget account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(account.status.value, AccountStatus.signedOut);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('Linux (no sign-in window): signing in is with the browser, '
      'and never opens a window', (tester) async {
    hasSignInWindow = false;
    var windows = 0;
    openSignIn = (context) async {
      windows++;
      return goodCookies();
    };
    pasteSignIn = (context) async => goodCookies();
    await openSettingsPage(tester);
    expect(find.text('Sign in'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Sign in with your browser'),
      findsOneWidget,
    );
    await tester.tap(find.text('Sign in with your browser'));
    await tester.pumpAndSettle();
    expect(account.status.value, AccountStatus.signedIn);
    expect(windows, 0);

    // Ended: signing in again is with the browser too.
    account.whoIs = () async => null;
    account.replied(account.headers()!, const [], 401, null);
    await tester.pumpAndSettle();
    expect(find.text('Sign in again'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Sign in with your browser'),
      findsOneWidget,
    );
  });

  group('signing in with a browser (paste)', () {
    final dialogSignIn = find.descendant(
      of: find.byType(PasteSignInDialog),
      matching: find.widgetWithText(FilledButton, 'Sign in'),
    );

    Future<void> openPaste(WidgetTester tester) async {
      await openSettingsPage(tester);
      await tester.tap(find.text('Sign in with your browser'));
      await tester.pumpAndSettle();
      expect(find.byType(PasteSignInDialog), findsOneWidget);
    }

    testWidgets('explains where to find the cookies, and warns', (
      tester,
    ) async {
      await openPaste(tester);
      expect(find.textContaining('private window'), findsOneWidget);
      expect(find.textContaining('never anywhere else'), findsOneWidget);
    });

    testWidgets('nothing pasted, or not cookies: says so in the dialog', (
      tester,
    ) async {
      await openPaste(tester);
      await tester.tap(dialogSignIn);
      await tester.pump();
      expect(find.text('Paste the cookies first.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(
        find.text('Paste the cookies first.'),
        findsNothing,
        reason: 'cleared on typing',
      );
      await tester.tap(dialogSignIn);
      await tester.pump();
      expect(find.textContaining("aren't signed-in"), findsOneWidget);
      expect(account.status.value, AccountStatus.signedOut);
    });

    testWidgets('pasted cookies sign in', (tester) async {
      await openPaste(tester);
      await tester.enterText(
        find.byType(TextField),
        'cookie: SAPISID=sapisid-1; SID=sid-1; __Secure-3PSIDTS=ts-1',
      );
      await tester.tap(dialogSignIn);
      await tester.pumpAndSettle();
      expect(find.byType(PasteSignInDialog), findsNothing);
      expect(account.status.value, AccountStatus.signedIn);
      expect(find.text('Signed in as Test Listener'), findsOneWidget);
      expect(browserCleared, 0, reason: 'no sign-in page was used');
    });

    testWidgets('cancel closes it, signed out', (tester) async {
      await openPaste(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(PasteSignInDialog), findsNothing);
      expect(account.status.value, AccountStatus.signedOut);
    });
  });

  testWidgets('switching channel: one channel says so', (tester) async {
    await signInDirectly();
    await openSettingsPage(tester);
    await tester.tap(find.text('Switch channel'));
    await tester.pumpAndSettle();
    // Widget tests have no network: the list can't load.
    expect(find.textContaining("Couldn't load your channels"), findsOneWidget);
    expect(account.status.value, AccountStatus.signedIn);
  });

  testWidgets('no photo: the first letter of the name instead', (tester) async {
    await signInDirectly();
    await openSettingsPage(tester);
    expect(find.text('T'), findsOneWidget);
  });

  testWidgets('a long name fits on one line', (tester) async {
    account.whoIs = () async => AccountInfo(name: 'A very long name ' * 8);
    await signInDirectly();
    await openSettingsPage(tester, phone: true);
    expect(tester.takeException(), isNull);
  });

  test('the sign-in is done only on YouTube Music itself', () {
    expect(reachedMusic('https://music.youtube.com/'), isTrue);
    expect(reachedMusic('https://music.youtube.com/library'), isTrue);
    for (final url in [
      null,
      '',
      'https://accounts.google.com/ServiceLogin',
      'http://music.youtube.com/',
      'https://music.youtube.com.evil.example/',
      'https://www.youtube.com/',
    ]) {
      expect(reachedMusic(url), isFalse, reason: url);
    }
  });
}
