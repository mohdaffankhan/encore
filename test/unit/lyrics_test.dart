import 'package:encore/api/lyrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses timestamps and text, sorted by time', () {
    final lines = parseLrc('''
[00:12.50] Second
[00:01.00] First
[01:02.25] Third
''');
    expect(lines.map((l) => l.text), ['First', 'Second', 'Third']);
    expect(lines.map((l) => l.time.inMilliseconds), [1000, 12500, 62250]);
  });

  test('a line with several timestamps repeats', () {
    final lines = parseLrc('[00:10.00][00:30.00] Chorus');
    expect(lines.map((l) => l.time.inSeconds), [10, 30]);
    expect(lines.every((l) => l.text == 'Chorus'), isTrue);
  });

  test('ignores metadata and blank lines, keeps empty lyric lines', () {
    final lines = parseLrc('[ar: Someone]\n\n[00:05.00]\n[00:06.00] Hi');
    expect(lines.map((l) => l.text), ['', 'Hi']);
  });
}
