import 'package:encore/ui/widgets/artwork.dart';
import 'package:encore/ui/widgets/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDuration', () {
    test('minutes and seconds', () {
      expect(formatDuration(const Duration(seconds: 5)), '0:05');
      expect(formatDuration(const Duration(minutes: 4, seconds: 37)), '4:37');
    });

    test('hours', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });
  });

  group('sizedArt', () {
    const music = 'https://lh3.googleusercontent.com/abc=w544-h544-l90-rj';

    test('picks the smallest YouTube Music size covering the pixels', () {
      expect(sizedArt(music, 40), contains('=w60-h60'));
      expect(sizedArt(music, 96), contains('=w120-h120'));
      expect(sizedArt(music, 200), contains('=w226-h226'));
      expect(sizedArt(music, 1000), contains('=w544-h544'));
    });

    test('uses smaller video thumbnails for small tiles', () {
      const video = 'https://i.ytimg.com/vi/abc123/hqdefault.jpg?sqp=x&rs=y';
      expect(
        sizedArt(video, 96),
        'https://i.ytimg.com/vi/abc123/mqdefault.jpg',
      );
      expect(
        sizedArt(video, 400),
        'https://i.ytimg.com/vi/abc123/hqdefault.jpg',
      );
    });

    test('leaves other URLs alone', () {
      const other = 'https://example.com/a.jpg';
      expect(sizedArt(other, 50), other);
    });
  });
}
