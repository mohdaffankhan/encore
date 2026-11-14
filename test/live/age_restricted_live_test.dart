// Run by hand only: age-restricted music videos play as their song
// versions (Encore streams signed out).
//   flutter test test/live/age_restricted_live_test.dart
import 'package:encore/api/stream.dart';
import 'package:encore/models.dart';
import 'package:encore/services/track_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final video in const [
    Track(id: 'B3eAMGXFw1o', title: 'Bitch Better Have My Money', artist: 'Rihanna', artUrl: ''),
    Track(id: 'qkO6iBwcoe4', title: "Rammstein - ''Pussy'' - (OFFICIAL VIDEO) -  [FIXED AUDIO] - (English CC)", artist: 'Rammstein', artUrl: ''),
  ]) {
    test(video.title, () async {
      await expectLater(audioStream(video.id), throwsA(isA<AgeRestricted>()));
      Track? used;
      final s = await trackStream(video, quality: AudioQuality.high, onVersion: (v) => used = v);
      expect(used, isNotNull);
      // ignore: avoid_print
      print('${video.id} plays as ${used!.id} "${used!.title}" by ${used!.artist} (${s.length} bytes)');
    });
  }
}
