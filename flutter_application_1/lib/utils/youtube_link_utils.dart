/// Parsed representation of a YouTube URL with normalized launch targets.
class ParsedYoutubeLink {
  final String videoId;
  final int startSeconds;
  final Uri watchUri;
  final Uri embedUri;
  final Uri appUri;

  const ParsedYoutubeLink({
    required this.videoId,
    required this.startSeconds,
    required this.watchUri,
    required this.embedUri,
    required this.appUri,
  });
}

final RegExp _youtubeVideoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

final RegExp _firstUrlPattern = RegExp(
  r"""((?:https?:\/\/|www\.)[^\s<>"']+)""",
  caseSensitive: false,
);

final RegExp _watchPathPattern = RegExp(
  r'^(?:\/)?watch\?v=([A-Za-z0-9_-]{11})(?:[&#?].*)?$',
  caseSensitive: false,
);

final RegExp _relativeYoutubePathPattern = RegExp(
  r'^\/(?:watch\?|shorts\/|embed\/|live\/|v\/|playlist\?|@)',
  caseSensitive: false,
);

final RegExp _relativeYoutubePathNoSlashPattern = RegExp(
  r'^(?:watch\?|shorts\/|embed\/|live\/|v\/|playlist\?|@)',
  caseSensitive: false,
);

/// Builds canonical YouTube watch URI.
Uri buildYoutubeWatchUri(String videoId, {int startSeconds = 0}) {
  final watchQuery = <String, String>{'v': videoId};
  if (startSeconds > 0) {
    watchQuery['t'] = '${startSeconds}s';
  }
  return Uri.https('www.youtube.com', '/watch', watchQuery);
}

/// Builds canonical YouTube embed URI.
Uri buildYoutubeEmbedUri(String videoId, {int startSeconds = 0}) {
  final embedQuery = <String, String>{
    'playsinline': '1',
    'rel': '0',
    'modestbranding': '1',
  };
  if (startSeconds > 0) {
    embedQuery['start'] = startSeconds.toString();
  }
  return Uri.https('www.youtube.com', '/embed/$videoId', embedQuery);
}

/// Returns a URL with `https://` if scheme is missing.
String normalizeExternalUrl(String rawUrl) {
  var normalized = _extractLikelyExternalToken(rawUrl);
  if (normalized.isEmpty) return '';
  normalized = normalized.replaceAll('&amp;', '&');
  normalized = normalized.replaceAll(RegExp(r'[\u0000-\u001F]'), '');
  normalized = normalized.replaceAll(RegExp(r'[)\],.;]+$'), '');
  final decoded = _maybeDecodeEmbeddedUrl(normalized);
  if (decoded != null && decoded.trim().isNotEmpty) {
    normalized = decoded.trim();
  }

  final lowered = normalized.toLowerCase();
  if (lowered.startsWith('youtube:')) {
    final deepLinkId = normalized.substring(normalized.indexOf(':') + 1).trim();
    if (_youtubeVideoIdPattern.hasMatch(deepLinkId)) {
      return buildYoutubeWatchUri(deepLinkId).toString();
    }
  }

  if (lowered.startsWith('vnd.youtube://') ||
      lowered.startsWith('youtube://')) {
    final appUri = Uri.tryParse(normalized);
    if (appUri != null) {
      final deepLinkId = _extractYoutubeVideoId(appUri);
      if (deepLinkId != null) {
        final start = _extractStartSeconds(appUri);
        return buildYoutubeWatchUri(deepLinkId, startSeconds: start).toString();
      }
    }
  }

  if (_youtubeVideoIdPattern.hasMatch(normalized)) {
    return buildYoutubeWatchUri(normalized).toString();
  }

  final watchPathMatch = _watchPathPattern.firstMatch(normalized);
  if (watchPathMatch != null) {
    final videoId = watchPathMatch.group(1)!;
    return buildYoutubeWatchUri(videoId).toString();
  }

  if (normalized.startsWith('//')) {
    normalized = 'https:$normalized';
  } else if (_relativeYoutubePathPattern.hasMatch(normalized)) {
    normalized = 'https://www.youtube.com$normalized';
  } else if (_relativeYoutubePathNoSlashPattern.hasMatch(normalized)) {
    normalized = 'https://www.youtube.com/$normalized';
  } else if (!normalized.contains('://')) {
    normalized = 'https://$normalized';
  }

  final uri = Uri.tryParse(normalized);
  if (uri != null &&
      (uri.host.endsWith('youtube.com') ||
          uri.host.endsWith('youtu.be') ||
          uri.host.endsWith('youtube-nocookie.com'))) {
    final redirectTarget =
        uri.queryParameters['q'] ?? uri.queryParameters['url'];
    if (redirectTarget != null && redirectTarget.trim().isNotEmpty) {
      final redirected = normalizeExternalUrl(redirectTarget);
      if (redirected.isNotEmpty) {
        return redirected;
      }
    }
  }

  return normalized;
}

/// Tries to build a launchable URI for external links.
Uri? buildExternalUri(String rawUrl) {
  final normalized = normalizeExternalUrl(rawUrl);
  if (normalized.isEmpty) return null;
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return null;
  return uri;
}

/// Parses YouTube links from watch, short, live, embed and youtu.be URLs.
ParsedYoutubeLink? parseYoutubeLink(String rawUrl) {
  final uri = buildExternalUri(rawUrl);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  final isYouTubeHost =
      host == 'youtu.be' ||
      host.endsWith('.youtu.be') ||
      host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtube-nocookie.com' ||
      host.endsWith('.youtube-nocookie.com');
  if (!isYouTubeHost) return null;

  if (uri.path.toLowerCase() == '/redirect' ||
      uri.path.toLowerCase() == '/attribution_link') {
    final redirectedRaw =
        uri.queryParameters['q'] ??
        uri.queryParameters['url'] ??
        uri.queryParameters['u'];
    if (redirectedRaw != null && redirectedRaw.trim().isNotEmpty) {
      return parseYoutubeLink(redirectedRaw);
    }
  }

  final id = _extractYoutubeVideoId(uri);
  if (id == null) return null;
  final startSeconds = _extractStartSeconds(uri);
  final watchUri = buildYoutubeWatchUri(id, startSeconds: startSeconds);
  final embedUri = buildYoutubeEmbedUri(id, startSeconds: startSeconds);

  final appUri = Uri.parse(
    'vnd.youtube://www.youtube.com/watch?v=$id'
    '${startSeconds > 0 ? '&t=${startSeconds}s' : ''}',
  );

  return ParsedYoutubeLink(
    videoId: id,
    startSeconds: startSeconds,
    watchUri: watchUri,
    embedUri: embedUri,
    appUri: appUri,
  );
}

String? _extractYoutubeVideoId(Uri uri) {
  final host = uri.host.toLowerCase();
  final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  String? candidate;
  if (host == 'youtu.be' || host.endsWith('.youtu.be')) {
    candidate = pathSegments.isNotEmpty ? pathSegments.first : null;
  } else {
    if (uri.path == '/watch') {
      candidate = uri.queryParameters['v'] ?? uri.queryParameters['vi'];
    } else if (pathSegments.isNotEmpty) {
      final first = pathSegments.first.toLowerCase();
      if ((first == 'shorts' ||
              first == 'embed' ||
              first == 'live' ||
              first == 'v' ||
              first == 'watch') &&
          pathSegments.length > 1) {
        candidate = pathSegments[1];
      }
    }
  }

  if (candidate == null) return null;
  final clean = candidate.trim().split(RegExp(r'[?&#/]')).first.trim();
  if (!_youtubeVideoIdPattern.hasMatch(clean)) return null;
  return clean;
}

int _extractStartSeconds(Uri uri) {
  final fragment = uri.fragment;
  if (fragment.isNotEmpty) {
    final fragmentMatch = RegExp(r'(?:^|[?&])t=([^&]+)').firstMatch(fragment);
    final fragmentRaw = fragmentMatch?.group(1);
    if (fragmentRaw != null) {
      final parsed = _parseStartValue(fragmentRaw);
      if (parsed > 0) return parsed;
    }
  }

  final raw =
      uri.queryParameters['t'] ??
      uri.queryParameters['start'] ??
      uri.queryParameters['time_continue'];
  return _parseStartValue(raw);
}

int _parseStartValue(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 0;
  final value = raw.trim().toLowerCase();
  final direct = int.tryParse(value);
  if (direct != null && direct >= 0) return direct;

  final match = RegExp(
    r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$',
  ).firstMatch(value);
  if (match == null) return 0;
  final hours = int.tryParse(match.group(1) ?? '') ?? 0;
  final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
  final seconds = int.tryParse(match.group(3) ?? '') ?? 0;
  return (hours * 3600) + (minutes * 60) + seconds;
}

String _extractLikelyExternalToken(String rawUrl) {
  final raw = rawUrl.replaceAll('\n', ' ').trim();
  if (raw.isEmpty) return '';

  final match = _firstUrlPattern.firstMatch(raw);
  if (match != null) {
    return match.group(1)!.trim();
  }

  return raw;
}

String? _maybeDecodeEmbeddedUrl(String value) {
  if (!value.contains('%')) return null;
  try {
    final decoded = Uri.decodeFull(value);
    if (decoded == value) return null;
    return decoded;
  } catch (_) {
    return null;
  }
}
