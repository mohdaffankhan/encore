import 'package:encore/models.dart';
import 'package:encore/services/library.dart';
import 'package:flutter_test/flutter_test.dart';

Track track(String id) =>
    Track(id: id, title: 'Song $id', artist: 'Artist', artUrl: '');

void main() {
  late UserLibrary library;

  setUp(() => library = UserLibrary());

  test('history puts the latest first without duplicates', () {
    library
      ..addPlayed(track('a'))
      ..addPlayed(track('b'))
      ..addPlayed(track('a'));
    expect(library.history.value.map((t) => t.id), ['a', 'b']);
  });

  test('history keeps the 200 most recent songs', () {
    for (var i = 0; i < 250; i++) {
      library.addPlayed(track('$i'));
    }
    expect(library.history.value, hasLength(200));
    expect(library.history.value.first.id, '249');
  });

  test('toggleLike adds then removes', () {
    final t = track('a');
    library.toggleLike(t);
    expect(library.isLiked(t), isTrue);
    library.toggleLike(t);
    expect(library.isLiked(t), isFalse);
  });

  test('recent searches are unique, newest first, at most 10', () {
    for (var i = 0; i < 12; i++) {
      library.addSearch('q$i');
    }
    library.addSearch('q5');
    expect(library.searches.value.first, 'q5');
    expect(library.searches.value, hasLength(10));
    expect(library.searches.value.where((q) => q == 'q5'), hasLength(1));
    library.removeSearch('q5');
    expect(library.searches.value, isNot(contains('q5')));
  });
}
