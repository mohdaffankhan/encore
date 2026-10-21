# Encore

## Releasing (mandatory)

A release is only published after `sh tool/release_check.sh <tag> <device>`
passes on the draft's actual files. Never publish, retag over, or mark a
release "Latest" any other way, and never call a fix done because debug
builds or `flutter test` pass: those don't shrink code/resources like
release builds do (v0.1.1 shipped an APK that crashed on play because the
notification icons were stripped). Verify fixes on a release build.

Commits: short one-line messages, no AI co-author trailer.
