# just_audio_media_kit 2.1.0, patched for Encore

A copy of [just_audio_media_kit](https://github.com/Pato05/just_audio_media_kit)
2.1.0 (public domain, see LICENSE), used through `dependency_overrides` in
Encore's pubspec.yaml. The only change: `JustAudioMediaKit.audioFilter` /
`setAudioFilter()`, which set mpv's audio filters (its `af` property) on every
player, for Encore's equalizer (FFmpeg's `equalizer` filter, built into mpv).
The changes are marked "Patched in for Encore". The example app is left out.
