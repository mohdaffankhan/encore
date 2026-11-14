// By hand: the artist page's own radio (YouTube Music's Mix) is read, and
// its songs are the artist's.
//   flutter test test/live/artist_radio_live_test.dart
import 'package:encore/api/innertube.dart' as yt;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("an artist's radio", () async {
    final artist = await yt.artist('UCDxKh1gFWeYsqePvgVzmPoQ'); // Arijit Singh
    expect(artist.radio?.playlistId, startsWith('RDEM'));
    final songs = await yt.artistRadio(artist.radio!);
    expect(songs.length, greaterThan(10));
    final theirs = songs.where((t) => t.artist.contains('Arijit')).length;
    // A mix: theirs, and similar artists.
    expect(theirs, greaterThan(3));
  });
}
