class SecurityValidators {
  static final RegExp _emailPattern = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );
  static final RegExp _containsUppercase = RegExp(r'[A-Z]');
  static final RegExp _containsLowercase = RegExp(r'[a-z]');
  static final RegExp _containsDigit = RegExp(r'\d');
  static final RegExp _horizontalWhitespace = RegExp(r'[ \t]+');
  static final RegExp _anyWhitespace = RegExp(r'\s+');
  static final RegExp _unsafeControlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');
  static final RegExp _unsafeIdentifierChars = RegExp(r'[^A-Za-z0-9_.:@/\- ]');
  static final RegExp _unsafeFilenameChars = RegExp(r'[^A-Za-z0-9._-]');
  static const int kMaxPasswordLength = 256;
  static const Set<String> defaultUploadExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.pdf',
    '.mp4',
    '.mov',
    '.webm',
  };

  static String normalizeEmail(String? email) => email?.trim().toLowerCase() ?? '';

  static String? emailError(String? email) {
    final normalized = normalizeEmail(email);
    if (normalized.isEmpty) {
      return 'Please enter your email';
    }
    if (!_emailPattern.hasMatch(normalized)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  static String? passwordError(String? password) {
    final value = password ?? '';
    if (value.isEmpty) {
      return 'Please enter your password';
    }
    if (value.length > kMaxPasswordLength) {
      return 'Password must be between 12 and 256 characters and include upper-case, lower-case, and a number.';
    }
    if (value.length < 12 ||
        !_containsUppercase.hasMatch(value) ||
        !_containsLowercase.hasMatch(value) ||
        !_containsDigit.hasMatch(value)) {
      return 'Password must be at least 12 characters and include upper-case, lower-case, and a number.';
    }
    return null;
  }

  static String sanitizeDisplayName(
    String value, {
    int maxLength = 80,
  }) {
    final normalized = sanitizeFreeText(
      value,
      fieldName: 'Display name',
      maxLength: maxLength,
      allowNewlines: false,
    );
    if (normalized.length < 2) {
      throw ArgumentError('Display name must be at least 2 characters.');
    }
    return normalized;
  }

  static String sanitizeFreeText(
    String value, {
    required String fieldName,
    int maxLength = 4000,
    bool allowNewlines = true,
  }) {
    var normalized = value.replaceAll(_unsafeControlChars, '');
    normalized = allowNewlines
      ? normalized.replaceAll(_horizontalWhitespace, ' ')
      : normalized.replaceAll(_anyWhitespace, ' ');
    normalized = normalized.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('$fieldName is required.');
    }
    if (normalized.length > maxLength) {
      throw ArgumentError('$fieldName exceeds the allowed length.');
    }
    return normalized;
  }

  static String sanitizeIdentifier(
    String value, {
    required String fieldName,
    int maxLength = 128,
  }) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('$fieldName is required.');
    }
    if (normalized.length > maxLength) {
      throw ArgumentError('$fieldName exceeds the allowed length.');
    }
    if (_unsafeIdentifierChars.hasMatch(normalized)) {
      throw ArgumentError('$fieldName contains invalid characters.');
    }
    return normalized;
  }

  static String sanitizeUrl(
    String value, {
    required String fieldName,
    bool requireHttps = true,
    Set<String> allowedSchemes = const <String>{'http', 'https'},
  }) {
    final normalized = value.trim();
    final normalizedAllowedSchemes = allowedSchemes
        .map((scheme) => scheme.trim().toLowerCase())
        .where((scheme) => scheme.isNotEmpty)
        .toSet();
    if (requireHttps && !normalizedAllowedSchemes.contains('https')) {
      throw ArgumentError.value(
        allowedSchemes,
        'allowedSchemes',
        'requireHttps=true requires allowedSchemes to include "https".',
      );
    }
    if (normalized.isEmpty) {
      throw ArgumentError('$fieldName is required.');
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      throw ArgumentError('$fieldName is not a valid URL.');
    }
    final scheme = uri.scheme.toLowerCase();
    if (requireHttps && scheme != 'https') {
      throw ArgumentError('$fieldName must use HTTPS.');
    }
    if (!requireHttps && !normalizedAllowedSchemes.contains(scheme)) {
      throw ArgumentError('$fieldName uses an unsupported URL scheme.');
    }
    return normalized;
  }

  static String sanitizeFilename(
    String filename, {
    Set<String> allowedExtensions = defaultUploadExtensions,
    int maxLength = 120,
  }) {
    final normalized = filename.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('Filename is required.');
    }
    if (normalized.length > maxLength) {
      throw ArgumentError('Filename is too long.');
    }
    if (_unsafeFilenameChars.hasMatch(normalized) ||
        normalized.contains('..')) {
      throw ArgumentError('Filename contains invalid characters.');
    }
    final lastDot = normalized.lastIndexOf('.');
    final extension = lastDot == -1 ? '' : normalized.substring(lastDot).toLowerCase();
    if (!allowedExtensions.contains(extension)) {
      throw ArgumentError('Unsupported upload type.');
    }
    return normalized;
  }

  static void ensureUploadAllowed({
    required String filename,
    required int sizeBytes,
    Set<String> allowedExtensions = defaultUploadExtensions,
    int maxBytes = 25 * 1024 * 1024,
  }) {
    sanitizeFilename(filename, allowedExtensions: allowedExtensions);
    if (sizeBytes <= 0) {
      throw ArgumentError('Uploaded file is empty.');
    }
    if (sizeBytes > maxBytes) {
      throw ArgumentError('Uploaded file exceeds the maximum size.');
    }
  }
}
