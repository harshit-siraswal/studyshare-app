import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/utils/youtube_link_utils.dart';

void main() {
  group('parseYoutubeLink', () {
    test('parses canonical watch urls', () {
      final link = parseYoutubeLink(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );

      expect(link, isNotNull);
      expect(link!.videoId, 'dQw4w9WgXcQ');
      expect(link.watchUri.toString(), contains('watch?v=dQw4w9WgXcQ'));
      expect(link.embedUri.toString(), contains('/embed/dQw4w9WgXcQ'));
      expect(link.startSeconds, 0);
    });

    test('parses youtu.be timestamp links', () {
      final link = parseYoutubeLink('https://youtu.be/dQw4w9WgXcQ?t=43s');

      expect(link, isNotNull);
      expect(link!.videoId, 'dQw4w9WgXcQ');
      expect(link.startSeconds, 43);
      expect(link.watchUri.toString(), contains('t=43s'));
    });

    test('parses shorts urls', () {
      final link = parseYoutubeLink(
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
      );

      expect(link, isNotNull);
      expect(link!.videoId, 'dQw4w9WgXcQ');
      expect(link.startSeconds, 0);
      expect(
        link.watchUri.toString(),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(link.embedUri.toString(), contains('/embed/dQw4w9WgXcQ'));
    });

    test('parses embed urls with start', () {
      final link = parseYoutubeLink(
        'https://www.youtube.com/embed/dQw4w9WgXcQ?start=90',
      );

      expect(link, isNotNull);
      expect(link!.videoId, 'dQw4w9WgXcQ');
      expect(link.startSeconds, 90);
    });

    test('parses redirect urls', () {
      final link = parseYoutubeLink(
        'https://www.youtube.com/redirect?q=https%3A%2F%2Fyoutu.be%2FdQw4w9WgXcQ%3Ft%3D12s',
      );

      expect(link, isNotNull);
      expect(link!.videoId, 'dQw4w9WgXcQ');
      expect(link.startSeconds, 12);
    });

    test('parses deep link inputs through normalization', () {
      final link = parseYoutubeLink('vnd.youtube://dQw4w9WgXcQ?t=90s');

      expect(link, isNotNull);
      expect(link!.videoId, 'dQw4w9WgXcQ');
      expect(link.startSeconds, 90);
      expect(link.watchUri.toString(), contains('t=90s'));
    });

    test('parses watch urls with fragment timestamps', () {
      final link = parseYoutubeLink(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ#t=1m30s',
      );

      expect(link, isNotNull);
      expect(link!.startSeconds, 90);
    });

    test('returns null for non-youtube urls', () {
      expect(parseYoutubeLink('https://vimeo.com/123456'), isNull);
      expect(parseYoutubeLink('https://www.dailymotion.com/video/x5e9eog'), isNull);
    });

    test('returns null for invalid urls', () {
      expect(parseYoutubeLink('not a valid url'), isNull);
      expect(parseYoutubeLink('://bad'), isNull);
    });

    test('returns null for youtube urls without video id', () {
      expect(parseYoutubeLink('https://www.youtube.com/'), isNull);
      expect(parseYoutubeLink('https://www.youtube.com/feed/trending'), isNull);
    });

    test('returns null for empty input', () {
      expect(parseYoutubeLink(''), isNull);
    });

    test('parses mobile host m.youtube.com', () {
      final link = parseYoutubeLink(
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
      );

      expect(link, isNotNull);
      expect(link!.videoId, 'dQw4w9WgXcQ');
    });

    test('parses url with playlist param without affecting videoId', () {
      final link = parseYoutubeLink(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf',
      );

      expect(link, isNotNull);
      expect(link!.videoId, 'dQw4w9WgXcQ');
    });

    test('parses combined h/m/s timestamp', () {
      final link = parseYoutubeLink(
        'https://youtu.be/dQw4w9WgXcQ?t=1h30m45s',
      );

      expect(link, isNotNull);
      expect(link!.videoId, 'dQw4w9WgXcQ');
      expect(link.startSeconds, 5445);
    });

    test('ignores extra query params for videoId and startSeconds', () {
      final link = parseYoutubeLink(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ&feature=shared&t=60s',
      );

      expect(link, isNotNull);
      expect(link!.videoId, 'dQw4w9WgXcQ');
      expect(link.startSeconds, 60);
      expect(link.watchUri.toString(), contains('t=60s'));
    });
  });
}
