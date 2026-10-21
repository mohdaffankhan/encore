# Encore

## Releasing (mandatory)

Ask the owner before releasing anything (pushing a version tag, publishing
a draft). All tests must pass first.

A release is only published after `sh tool/release_check.sh <tag> <device>`
passes on the draft's actual files. Never publish, retag over, or mark a
release "Latest" any other way, and never call a fix done because debug
builds or `flutter test` pass: those don't shrink code/resources like
release builds do (v0.1.1 shipped an APK that crashed on play because the
notification icons were stripped). Verify fixes on a release build.

Commits: short one-line messages, no AI co-author trailer.

## Testing on the owner's phone

The owner's phone has the real app (`dev.encore.app`) with their library.
Debug/profile builds are `dev.encore.app.test`. Never run plain `flutter test`
or `flutter drive` against the phone: at the end flutter uninstalls by the
project's app id, which removes the REAL app. Use
`tool/android_background_check.sh` (passes `--no-uninstall`, removes only the
test app, fails if the real app goes missing), or add `--no-uninstall` and
remove `dev.encore.app.test` yourself. Release checks use `adb install -r`,
which keeps data.

## Features and tests

`FEATURES.md` lists every feature and fixed bug with the tests covering it.
Each change adds or updates its row and its tests (a test that fails
without the change). Before saying something works, run the offline tests,
the Windows e2e (`tool/windows_keyboard_check.ps1`) and, with the phone
connected, the Android e2e and release check. When a test fails, find the
cause before running it again.

## Latest build on the owner's devices

After changes are tested, keep the newest build installed on the phone
(`adb install -r` of the release APK, keeping the library) whenever it is
connected, and on this PC (the Windows installer, replacing the old one).

Versions in pubspec.yaml (`name+build`): the name is the next release
(it only moves on after that release is published); the build number goes
up for every build installed on the owner's devices (Android needs it to be
the same or higher to update). GitHub builds use that same build number, so
an official release always installs over a test build.
