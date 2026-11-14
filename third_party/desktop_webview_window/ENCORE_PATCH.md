# desktop_webview_window 0.4.3, patched for Encore

A copy of [desktop_webview_window](https://pub.dev/packages/desktop_webview_window)
0.4.3 (Apache 2.0, see LICENSE), used as a path dependency in Encore's
pubspec.yaml for the YouTube Music sign-in window on Windows.

The only change: `pubspec.yaml` registers the plugin for Windows only. On
Linux it would link WebKitGTK into Encore, so Encore wouldn't start on a
system without it, for an optional feature; Linux signs in with "Sign in with
your browser" instead. The macOS and Linux sources, example, tests and tools
are left out.
