import 'package:encore/api/innertube.dart' as yt;
import 'package:encore/models.dart';
import 'package:encore/services/player.dart';
import 'package:encore/ui/pages/artist_page.dart';
import 'package:encore/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

// The artist page's Radio played their top song's radio: now the artist's
// own (YouTube Music's Mix), and the top song's only when there's none.

Track _song(String id) => Track(id: id, title: id, artist: 'A', artUrl: '');

Artist _artist({bool radio = true, List<Track>? top}) => Artist(
  name: 'A',
  subtitle: '',
  artUrl: '',
  topSongs: top ?? [_song('top')],
  shelves: const [],
  radio: radio
      ? (videoId: 'seed', playlistId: 'RDEMabc', params: 'wAEB')
      : null,
);

void main() {
  heroShadeTests();
  late List<String> asked;

  setUp(() => asked = []);
  tearDown(() {
    fetchArtistRadio = yt.artistRadio;
    player.queue.value = [];
    player.index.value = -1;
  });

  testWidgets("plays the artist's own radio", (tester) async {
    fetchArtistRadio = (r) async {
      asked.add(r.playlistId);
      return [_song('m1'), _song('m2'), _song('m3')];
    };
    await playArtistRadio(_artist());
    expect(asked, ['RDEMabc']);
    expect(player.queue.value.map((t) => t.id), ['m1', 'm2', 'm3']);
  });

  testWidgets("no radio on the page: the top song's", (tester) async {
    await playArtistRadio(_artist(radio: false));
    expect(player.queue.value.first.id, 'top');
  });

  testWidgets("the artist's radio failing or empty: the top song's", (
    tester,
  ) async {
    fetchArtistRadio = (r) async => throw Exception('offline');
    await playArtistRadio(_artist());
    expect(player.queue.value.first.id, 'top');
    fetchArtistRadio = (r) async => const [];
    await playArtistRadio(_artist(top: [_song('top2')]));
    expect(player.queue.value.first.id, 'top2');
  });
}

void heroShadeTests() {
  test("the shade over an artist's photo follows the theme (a fixed grey "
      'stood out in the tinted ones)', () {
    final was = EncoreColors.theme;
    addTearDown(() => EncoreColors.theme = was);
    for (final theme in encoreThemes) {
      EncoreColors.theme = theme;
      final colors = heroShade().colors;
      expect(colors.last, EncoreColors.surface, reason: theme.name);
      expect(
        colors[1],
        EncoreColors.surface.withValues(alpha: 0.6),
        reason: theme.name,
      );
    }
  });
}
