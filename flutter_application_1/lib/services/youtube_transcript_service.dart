import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../utils/youtube_link_utils.dart';

class YouTubeTranscriptSegment {
  final String text;
  final double offsetSeconds;
  final double durationSeconds;
  final double endSeconds;
  final String timestamp;
  final String? language;

  const YouTubeTranscriptSegment({
    required this.text,
    required this.offsetSeconds,
    required this.durationSeconds,
    required this.endSeconds,
    required this.timestamp,
    this.language,
  });
}

class YouTubeTranscriptPayload {
  final String videoId;
  final String? language;
  final List<YouTubeTranscriptSegment> segments;
  final String fullText;

  const YouTubeTranscriptPayload({
    required this.videoId,
    required this.language,
    required this.segments,
    required this.fullText,
  });
}

class YoutubeTranscriptService {
  static const Map<String, String> _youtubeHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
    'Accept': 'text/html,application/json;q=0.9,*/*;q=0.8',
    'Cookie': 'CONSENT=YES+cb.20210328-17-p0.en+FX+; SOCS=CAI',
  };

  static const Map<String, String> _androidClient = <String, String>{
    'clientName': 'ANDROID',
    'clientVersion': '21.03.36',
    'sdkVersion': '36',
    'osVersion': '16',
    'userAgent':
        'com.google.android.youtube/21.03.36(Linux; U; Android 16; en_US; '
        'SM-S908E Build/TP1A.220624.014) gzip',
    'clientNameHeader': '3',
  };

  final http.Client _client;

  YoutubeTranscriptService({http.Client? client})
    : _client = client ?? http.Client();

  Future<YouTubeTranscriptPayload?> fetchTranscript(
    String rawUrl, {
    String preferredLanguage = 'en',
  }) async {
    final parsedLink = parseYoutubeLink(rawUrl);
    if (parsedLink == null) return null;

    final proxyTranscript = await _fetchProxyTranscript(
      parsedLink.videoId,
      preferredLanguage,
    );
    if (proxyTranscript != null) {
      return proxyTranscript;
    }

    final directTranscript = await _fetchDirectTranscript(
      parsedLink.videoId,
      preferredLanguage,
    );
    if (directTranscript != null) {
      return directTranscript;
    }

    final timedTextTranscript = await _fetchTimedTextTranscript(
      parsedLink.videoId,
      preferredLanguage,
    );
    if (timedTextTranscript != null) {
      return timedTextTranscript;
    }

    return null;
  }

  Future<YouTubeTranscriptPayload?> _fetchProxyTranscript(
    String videoId,
    String preferredLanguage,
  ) async {
    final proxyUri = Uri.https(
      AppConfig.webDomain,
      '/api/transcript',
      <String, String>{'v': videoId, 'lang': preferredLanguage},
    );

    try {
      final response = await _client
          .get(proxyUri)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body);
      return _parseTranscriptPayload(videoId, payload);
    } catch (_) {
      return null;
    }
  }

  Future<YouTubeTranscriptPayload?> _fetchDirectTranscript(
    String videoId,
    String preferredLanguage,
  ) async {
    final playerUri = Uri.parse(
      'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
    );
    final headers = <String, String>{
      ..._youtubeHeaders,
      'Content-Type': 'application/json',
      'User-Agent': _androidClient['userAgent']!,
      'X-YouTube-Client-Name': _androidClient['clientNameHeader']!,
      'X-YouTube-Client-Version': _androidClient['clientVersion']!,
    };
    final body = jsonEncode(<String, Object?>{
      'context': <String, Object?>{
        'client': <String, Object?>{
          'clientName': _androidClient['clientName'],
          'clientVersion': _androidClient['clientVersion'],
          'androidSdkVersion': int.parse(_androidClient['sdkVersion']!),
          'osName': 'Android',
          'osVersion': _androidClient['osVersion'],
          'hl': preferredLanguage,
          'gl': 'US',
          'userAgent': _androidClient['userAgent'],
        },
        'thirdParty': <String, Object?>{
          'embedUrl': 'https://www.youtube.com/watch?v=$videoId',
        },
      },
      'videoId': videoId,
      'playbackContext': <String, Object?>{
        'contentPlaybackContext': <String, Object?>{
          'html5Preference': 'HTML5_PREF_WANTS',
        },
      },
      'contentCheckOk': true,
      'racyCheckOk': true,
    });

    try {
      final response = await _client
          .post(playerUri, headers: headers, body: body)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body);
      final trackList =
          payload['captions']?['playerCaptionsTracklistRenderer']?['captionTracks'];
      if (trackList is! List || trackList.isEmpty) {
        return null;
      }

      final selectedTrack = _pickCaptionTrack(trackList, preferredLanguage);
      if (selectedTrack == null) return null;
      return _fetchCaptionTrackTranscript(videoId, selectedTrack);
    } catch (_) {
      return null;
    }
  }

  Future<YouTubeTranscriptPayload?> _fetchTimedTextTranscript(
    String videoId,
    String preferredLanguage,
  ) async {
    final listUri = Uri.parse(
      'https://www.youtube.com/api/timedtext?type=list&v=$videoId',
    );

    try {
      final listResponse = await _client
          .get(listUri, headers: _youtubeHeaders)
          .timeout(const Duration(seconds: 12));
      if (listResponse.statusCode != 200) return null;

      final tracks = _parseTimedTextTrackList(listResponse.body);
      if (tracks.isEmpty) return null;

      final orderedTracks = _sortTracks(tracks, preferredLanguage);
      for (final track in orderedTracks) {
        final transcript = await _fetchTimedTextTrackTranscript(
          videoId,
          track['languageCode'] ?? '',
          kind: track['kind'],
        );
        if (transcript != null) {
          return transcript;
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<YouTubeTranscriptPayload?> _fetchCaptionTrackTranscript(
    String videoId,
    Map<String, String> track,
  ) async {
    final baseUrl = track['baseUrl']?.trim() ?? '';
    if (baseUrl.isEmpty) return null;

    final uri = Uri.parse(
      baseUrl.contains('fmt=json3')
          ? baseUrl
          : '$baseUrl${baseUrl.contains('?') ? '&' : '?'}fmt=json3',
    );

    try {
      final response = await _client
          .get(
            uri,
            headers: <String, String>{
              ..._youtubeHeaders,
              'User-Agent': _androidClient['userAgent']!,
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      return _parseTranscriptDocument(
        videoId,
        track['languageCode'],
        response.body,
      );
    } catch (_) {
      return null;
    }
  }

  Future<YouTubeTranscriptPayload?> _fetchTimedTextTrackTranscript(
    String videoId,
    String languageCode, {
    String? kind,
  }) async {
    if (languageCode.trim().isEmpty) return null;

    final params = <String, String>{
      'v': videoId,
      'lang': languageCode,
      'fmt': 'json3',
      if ((kind ?? '').trim().isNotEmpty) 'kind': kind!.trim(),
    };

    final uri = Uri.https('www.youtube.com', '/api/timedtext', params);

    try {
      final response = await _client
          .get(uri, headers: _youtubeHeaders)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      return _parseTranscriptDocument(videoId, languageCode, response.body);
    } catch (_) {
      return null;
    }
  }

  List<Map<String, String>> _parseTimedTextTrackList(String xml) {
    final tracks = <Map<String, String>>[];
    final pattern = RegExp(r'<track\b([^>]+)\/>', caseSensitive: false);

    for (final match in pattern.allMatches(xml)) {
      final attrs = match.group(1) ?? '';
      final languageMatch = RegExp(
        r'\blang_code="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(attrs);
      if (languageMatch?.group(1)?.trim().isEmpty ?? true) continue;
      final kindMatch = RegExp(
        r'\bkind="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(attrs);
      tracks.add(<String, String>{
        'languageCode': _decodeHtmlEntities(languageMatch!.group(1)!),
        'kind': kindMatch?.group(1) == null
            ? ''
            : _decodeHtmlEntities(kindMatch!.group(1)!),
      });
    }

    return tracks;
  }

  List<Map<String, String>> _sortTracks(
    List<Map<String, String>> tracks,
    String preferredLanguage,
  ) {
    final preferred = _buildLanguageCandidates(preferredLanguage).toSet();
    final sorted = List<Map<String, String>>.from(tracks);
    sorted.sort((left, right) {
      final leftCode = _normalizeLanguageCode(left['languageCode']);
      final rightCode = _normalizeLanguageCode(right['languageCode']);
      final leftPreferred = preferred.contains(leftCode);
      final rightPreferred = preferred.contains(rightCode);
      if (leftPreferred != rightPreferred) {
        return leftPreferred ? -1 : 1;
      }

      final leftAsr = _normalizeLanguageCode(left['kind']) == 'asr';
      final rightAsr = _normalizeLanguageCode(right['kind']) == 'asr';
      if (leftAsr != rightAsr) {
        return leftAsr ? 1 : -1;
      }

      return 0;
    });
    return sorted;
  }

  Map<String, String>? _pickCaptionTrack(
    List<dynamic> rawTracks,
    String preferredLanguage,
  ) {
    final tracks = rawTracks
        .map((dynamic item) {
          if (item is! Map) return null;
          final baseUrl = item['baseUrl']?.toString().trim() ?? '';
          final languageCode = item['languageCode']?.toString().trim() ?? '';
          final kind = item['kind']?.toString().trim() ?? '';
          if (baseUrl.isEmpty || languageCode.isEmpty) return null;
          return <String, String>{
            'baseUrl': baseUrl,
            'languageCode': languageCode,
            'kind': kind,
          };
        })
        .whereType<Map<String, String>>()
        .toList();
    if (tracks.isEmpty) return null;

    final candidates = _buildLanguageCandidates(preferredLanguage);
    for (final candidate in candidates) {
      for (final track in tracks) {
        if (_normalizeLanguageCode(track['languageCode']) == candidate) {
          return track;
        }
      }
    }

    for (final candidate in candidates) {
      final base = candidate.split('-').first;
      for (final track in tracks) {
        if (_normalizeLanguageCode(track['languageCode']).split('-').first ==
            base) {
          return track;
        }
      }
    }

    for (final track in tracks) {
      if (_normalizeLanguageCode(track['kind']) != 'asr') {
        return track;
      }
    }

    return tracks.first;
  }

  YouTubeTranscriptPayload? _parseTranscriptDocument(
    String videoId,
    String? languageCode,
    String rawDocument,
  ) {
    final trimmed = rawDocument.trim();
    if (trimmed.isEmpty) return null;

    try {
      if (trimmed.startsWith('{')) {
        return _buildTranscriptFromJson3(
          videoId,
          languageCode,
          jsonDecode(trimmed),
        );
      }
    } catch (_) {
      return null;
    }

    return _buildTranscriptFromXml(videoId, languageCode, trimmed);
  }

  YouTubeTranscriptPayload? _buildTranscriptFromJson3(
    String videoId,
    String? languageCode,
    dynamic payload,
  ) {
    final events = payload is Map<String, dynamic> ? payload['events'] : null;
    if (events is! List) return null;

    final segments = <YouTubeTranscriptSegment>[];
    for (final event in events) {
      if (event is! Map) continue;
      final segs = event['segs'];
      if (segs is! List) continue;
      final text = segs
          .map(
            (dynamic part) => part is Map ? part['utf8']?.toString() ?? '' : '',
          )
          .join()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isEmpty) continue;

      final offsetSeconds = _coerceDouble(event['tStartMs']) / 1000;
      final durationSeconds = _coerceDouble(event['dDurationMs']) / 1000;
      final endSeconds = offsetSeconds + durationSeconds;

      segments.add(
        YouTubeTranscriptSegment(
          text: _decodeHtmlEntities(text),
          offsetSeconds: offsetSeconds,
          durationSeconds: durationSeconds,
          endSeconds: endSeconds,
          timestamp: _formatTimestamp(offsetSeconds),
          language: languageCode,
        ),
      );
    }

    if (segments.isEmpty) return null;
    return YouTubeTranscriptPayload(
      videoId: videoId,
      language: languageCode,
      segments: segments,
      fullText: segments.map((segment) => segment.text).join(' ').trim(),
    );
  }

  YouTubeTranscriptPayload? _buildTranscriptFromXml(
    String videoId,
    String? languageCode,
    String rawXml,
  ) {
    final segments = <YouTubeTranscriptSegment>[];
    final pattern = RegExp(
      r'<text\b([^>]*)>([\s\S]*?)<\/text>',
      caseSensitive: false,
    );

    for (final match in pattern.allMatches(rawXml)) {
      final attrs = match.group(1) ?? '';
      final rawText = _decodeHtmlEntities(match.group(2) ?? '')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (rawText.isEmpty) continue;

      final startMatch = RegExp(
        r'\bstart="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(attrs);
      final durationMatch = RegExp(
        r'\bdur="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(attrs);

      final offsetSeconds = _coerceDouble(startMatch?.group(1));
      final durationSeconds = _coerceDouble(durationMatch?.group(1));
      final endSeconds = offsetSeconds + durationSeconds;

      segments.add(
        YouTubeTranscriptSegment(
          text: rawText,
          offsetSeconds: offsetSeconds,
          durationSeconds: durationSeconds,
          endSeconds: endSeconds,
          timestamp: _formatTimestamp(offsetSeconds),
          language: languageCode,
        ),
      );
    }

    if (segments.isEmpty) return null;
    return YouTubeTranscriptPayload(
      videoId: videoId,
      language: languageCode,
      segments: segments,
      fullText: segments.map((segment) => segment.text).join(' ').trim(),
    );
  }

  YouTubeTranscriptPayload? _parseTranscriptPayload(
    String fallbackVideoId,
    dynamic payload,
  ) {
    if (payload is! Map) return null;
    final segmentsRaw = payload['segments'];
    if (segmentsRaw is! List || segmentsRaw.isEmpty) return null;

    final segments = <YouTubeTranscriptSegment>[];
    for (final item in segmentsRaw) {
      if (item is! Map) continue;
      final text = item['text']?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      final offsetSeconds = _coerceDouble(
        item['offsetSeconds'] ?? item['start'] ?? item['startSeconds'],
      );
      final durationSeconds = _coerceDouble(
        item['durationSeconds'] ?? item['duration'],
      );
      final endSeconds = _coerceDouble(item['endSeconds'] ?? item['end']);
      segments.add(
        YouTubeTranscriptSegment(
          text: text,
          offsetSeconds: offsetSeconds,
          durationSeconds: durationSeconds,
          endSeconds: endSeconds > 0
              ? endSeconds
              : offsetSeconds + durationSeconds,
          timestamp: item['timestamp']?.toString().trim().isNotEmpty == true
              ? item['timestamp'].toString().trim()
              : _formatTimestamp(offsetSeconds),
          language: item['language']?.toString(),
        ),
      );
    }

    if (segments.isEmpty) return null;
    final fullText = payload['fullText']?.toString().trim().isNotEmpty == true
        ? payload['fullText'].toString().trim()
        : payload['text']?.toString().trim().isNotEmpty == true
        ? payload['text'].toString().trim()
        : segments.map((segment) => segment.text).join(' ').trim();

    return YouTubeTranscriptPayload(
      videoId: payload['videoId']?.toString().trim().isNotEmpty == true
          ? payload['videoId'].toString().trim()
          : fallbackVideoId,
      language: payload['language']?.toString(),
      segments: segments,
      fullText: fullText,
    );
  }

  List<String> _buildLanguageCandidates(String preferredLanguage) {
    final requested = _normalizeLanguageCode(preferredLanguage);
    final base = requested.contains('-')
        ? requested.split('-').first
        : requested;
    final values = <String>[
      requested,
      base,
      'en',
      'en-us',
      'en-gb',
      'hi',
      'hi-in',
    ].where((String value) => value.isNotEmpty).toList();
    return values.toSet().toList();
  }

  String _normalizeLanguageCode(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  String _decodeHtmlEntities(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&#x2F;', '/');
  }

  double _coerceDouble(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _formatTimestamp(double seconds) {
    final safeSeconds = seconds.isFinite ? seconds.floor() : 0;
    final hours = safeSeconds ~/ 3600;
    final minutes = (safeSeconds % 3600) ~/ 60;
    final secs = safeSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }
}
