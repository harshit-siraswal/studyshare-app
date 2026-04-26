import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/youtube_link_utils.dart';

class ClientYoutubeTranscriptResult {
  final String videoId;
  final String? language;
  final String text;

  const ClientYoutubeTranscriptResult({
    required this.videoId,
    required this.text,
    this.language,
  });
}

class YoutubeTranscriptClientService {
  static const List<String> _defaultLanguageCandidates = <String>[
    'en',
    'en-us',
    'en-gb',
    'en-in',
    'hi',
    'hi-in',
  ];

  Future<ClientYoutubeTranscriptResult> fetchTranscript(
    String url, {
    String? preferredLanguage,
  }) async {
    final link = parseYoutubeLink(url);
    if (link == null) {
      throw Exception('Invalid YouTube URL');
    }

    final track = await _fetchBestTrack(
      link.videoId,
      preferredLanguage: preferredLanguage,
    );
    if (track != null) {
      final text = await _fetchJson3Transcript(
        link.videoId,
        track.languageCode,
        kind: track.kind,
      );
      if (text.length > 20) {
        return ClientYoutubeTranscriptResult(
          videoId: link.videoId,
          language: track.languageCode,
          text: text,
        );
      }
    }

    final guessed = await _tryLanguageGuesses(
      link.videoId,
      preferredLanguage: preferredLanguage,
    );
    if (guessed != null) return guessed;

    throw Exception('Transcript unavailable from this device');
  }

  Future<_CaptionTrack?> _fetchBestTrack(
    String videoId, {
    String? preferredLanguage,
  }) async {
    final uri = Uri.https('www.youtube.com', '/api/timedtext', <String, String>{
      'type': 'list',
      'v': videoId,
    });
    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final tracks = _parseTrackList(response.body);
      return _pickTrack(tracks, preferredLanguage: preferredLanguage);
    } catch (_) {
      return null;
    }
  }

  Future<ClientYoutubeTranscriptResult?> _tryLanguageGuesses(
    String videoId, {
    String? preferredLanguage,
  }) async {
    for (final languageCode in _buildLanguageCandidates(preferredLanguage)) {
      for (final kind in <String?>[null, 'asr']) {
        try {
          final text = await _fetchJson3Transcript(
            videoId,
            languageCode,
            kind: kind,
          );
          if (text.length > 20) {
            return ClientYoutubeTranscriptResult(
              videoId: videoId,
              language: languageCode,
              text: text,
            );
          }
        } catch (_) {}
      }
    }
    return null;
  }

  Future<String> _fetchJson3Transcript(
    String videoId,
    String languageCode, {
    String? kind,
  }) async {
    final query = <String, String>{
      'v': videoId,
      'lang': languageCode,
      'fmt': 'json3',
    };
    if (kind != null && kind.isNotEmpty) {
      query['kind'] = kind;
    }
    final uri = Uri.https('www.youtube.com', '/api/timedtext', query);
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Transcript request failed (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    final events = decoded is Map<String, dynamic> && decoded['events'] is List
        ? decoded['events'] as List
        : const [];

    final parts = <String>[];
    for (final event in events) {
      if (event is! Map) continue;
      final segs = event['segs'];
      if (segs is! List) continue;
      final text = segs
          .whereType<Map>()
          .map((segment) => '${segment['utf8'] ?? ''}')
          .join(' ');
      final normalized = _normalizeText(text);
      if (normalized.isNotEmpty) {
        parts.add(normalized);
      }
    }
    return parts.join(' ').trim();
  }

  List<String> _buildLanguageCandidates(String? preferredLanguage) {
    final normalized = (preferredLanguage ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('_', '-');
    final base = normalized.split('-').first;
    final values = <String>[
      normalized,
      if (base.isNotEmpty) base,
      ..._defaultLanguageCandidates,
    ].where((value) => value.isNotEmpty).toList();
    return values.toSet().toList();
  }

  List<_CaptionTrack> _parseTrackList(String xml) {
    final matches = RegExp(r'<track\b([^>]*)\/?>', caseSensitive: false)
        .allMatches(xml);
    return matches.map((match) {
      final attributes = match.group(1) ?? '';
      return _CaptionTrack(
        languageCode: _extractAttribute(attributes, 'lang_code') ?? '',
        kind: _extractAttribute(attributes, 'kind'),
      );
    }).where((track) => track.languageCode.isNotEmpty).toList();
  }

  _CaptionTrack? _pickTrack(
    List<_CaptionTrack> tracks, {
    String? preferredLanguage,
  }) {
    if (tracks.isEmpty) return null;
    final candidates = _buildLanguageCandidates(preferredLanguage);
    tracks.sort((left, right) {
      final leftLang = left.languageCode.toLowerCase();
      final rightLang = right.languageCode.toLowerCase();
      final leftBase = leftLang.split('-').first;
      final rightBase = rightLang.split('-').first;
      final leftIndex = candidates.indexWhere(
        (candidate) => candidate == leftLang || candidate == leftBase,
      );
      final rightIndex = candidates.indexWhere(
        (candidate) => candidate == rightLang || candidate == rightBase,
      );
      final leftScore = leftIndex == -1 ? 999 : leftIndex;
      final rightScore = rightIndex == -1 ? 999 : rightIndex;
      final leftPenalty = left.kind == 'asr' ? 1 : 0;
      final rightPenalty = right.kind == 'asr' ? 1 : 0;
      return leftScore - rightScore != 0
          ? leftScore - rightScore
          : leftPenalty - rightPenalty;
    });
    return tracks.first;
  }

  String? _extractAttribute(String source, String name) {
    final match = RegExp('$name="([^"]+)"', caseSensitive: false).firstMatch(source);
    return match?.group(1);
  }

  String _normalizeText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _CaptionTrack {
  final String languageCode;
  final String? kind;

  const _CaptionTrack({
    required this.languageCode,
    this.kind,
  });
}
