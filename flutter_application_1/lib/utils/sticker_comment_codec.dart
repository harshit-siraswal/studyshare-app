class StickerCommentCodec {
  static const String marker = '[mss-sticker]';

  static String encode(String url) {
    return '$marker${url.trim()}';
  }

  static String? extractUrl(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith(marker)) {
      final raw = trimmed.substring(marker.length).trim();
      return _cleanupUrl(raw.isEmpty ? '' : raw);
    }

    final patterns = <RegExp>[
      RegExp(r'^!\[Sticker\]\((https?://[^)]+)\)$', caseSensitive: false),
      RegExp(r'^sticker!(https?://\S+)$', caseSensitive: false),
      RegExp(
        r'^(https?://\S+\.(png|jpg|jpeg|webp|gif)(\?\S*)?)$',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(trimmed);
      if (match == null) continue;
      final raw = match.group(1) ?? '';
      final cleaned = _cleanupUrl(raw);
      if (cleaned != null) return cleaned;
    }

    return null;
  }

  static String? _cleanupUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return null;

    if (url.startsWith('{') && url.endsWith('}')) {
      url = url.substring(1, url.length - 1).trim();
    }

    if (url.startsWith('asset://')) {
      return url;
    }

    if (!(url.startsWith('http://') || url.startsWith('https://'))) {
      return null;
    }

    return url;
  }
}
