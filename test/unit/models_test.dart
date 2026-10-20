import 'package:encore/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Track survives a JSON round trip', () {
    const t = Track(
      id: 'abc',
      title: 'Title',
      artist: 'Artist',
      artistId: 'UC1',
      album: 'Album',
      albumId: 'MPRE1',
      duration: Duration(minutes: 3, seconds: 5),
      artUrl: 'https://example.com/a.jpg',
    );
    final copy = Track.fromJson(t.toJson());
    expect(copy.toJson(), t.toJson());
  });

  test('Tracks are equal by id', () {
    const a = Track(id: 'x', title: 'A', artist: '', artUrl: '');
    const b = Track(id: 'x', title: 'B', artist: '', artUrl: '');
    expect(a, b);
    expect({a, b}, hasLength(1));
  });

  test('older saved tracks without optional fields still load', () {
    final t = Track.fromJson({
      'id': 'x',
      'title': 'T',
      'artist': 'A',
      'artUrl': '',
    });
    expect(t.duration, isNull);
    expect(t.artistId, isNull);
  });
}
