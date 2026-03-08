String? normalizeProfilePhotoUrl(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;

  const nullLikeValues = <String>{'null', 'undefined', 'n/a', '-'};
  if (nullLikeValues.contains(trimmed.toLowerCase())) {
    return null;
  }

  if (trimmed.startsWith('//')) {
    return 'https:$trimmed';
  }

  return trimmed;
}

String? resolveProfilePhotoUrl(
  dynamic source, {
  List<String> preferredKeys = const <String>[],
}) {
  final candidates = <String?>[];

  void addCandidate(dynamic value) {
    if (value == null) return;
    candidates.add(value.toString());
  }

  void addFromMap(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (!map.containsKey(key)) continue;
      addCandidate(map[key]);
    }
  }

  if (source is Map) {
    final map = <String, dynamic>{
      for (final entry in source.entries)
        entry.key.toString(): entry.value,
    };
    const defaultKeys = <String>[
      'profile_photo_url',
      'photo_url',
      'avatar_url',
      'author_photo_url',
      'user_photo_url',
    ];

    addFromMap(map, preferredKeys);
    addFromMap(map, defaultKeys);

    const nestedKeys = <String>['user', 'author', 'profile'];
    for (final nestedKey in nestedKeys) {
      final nested = map[nestedKey];
      if (nested is Map) {
        final nestedMap = <String, dynamic>{
          for (final entry in nested.entries)
            entry.key.toString(): entry.value,
        };
        addFromMap(nestedMap, defaultKeys);
      }
    }
  } else {
    addCandidate(source);
  }

  for (final candidate in candidates) {
    final normalized = normalizeProfilePhotoUrl(candidate);
    if (normalized != null) {
      return normalized;
    }
  }

  return null;
}
