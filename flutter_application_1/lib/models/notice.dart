import 'package:flutter/foundation.dart';

@immutable
class Notice {
  final String title;

  const Notice({required this.title});

  factory Notice.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('title') || json['title'] == null || json['title'].toString().trim().isEmpty) {
      throw const FormatException("Notice.fromJson: Missing or empty required 'title' field");
    }
    return Notice(
      title: json['title'].toString(),
    );
  }

  /// Attempts to parse a Notice from JSON, returning null on failure.
  static Notice? tryFromJson(Map<String, dynamic> json) {
    try {
      return Notice.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'title': title,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Notice && other.title == title;
  }

  @override
  int get hashCode => title.hashCode;

  @override
  String toString() => 'Notice(title: $title)';
}
