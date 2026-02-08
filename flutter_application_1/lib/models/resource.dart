import 'package:flutter/foundation.dart';

class Resource {
  final String id;
  final String title;
  final String type; // notes, video, pyq
  final String fileUrl;
  final String? thumbnailUrl;
  final String? semester;
  final String? branch;
  final String? subject;
  final String? chapter;
  final String? topic;
  final String? description; // Added for notices
  final int upvotes;
  final int downvotes;
  final String uploadedByEmail;
  final String? uploadedByName;
  final String collegeId;
  final bool isApproved;
  final DateTime createdAt;

  Resource({
    required this.id,
    required this.title,
    required this.type,
    required this.fileUrl,
    this.thumbnailUrl,
    this.semester,
    this.branch,
    this.subject,
    this.chapter,
    this.topic,
    this.description,
    this.upvotes = 0,
    this.downvotes = 0,
    required this.uploadedByEmail,
    this.uploadedByName,
    required this.collegeId,
    this.isApproved = true,
    required this.createdAt,
  });

  factory Resource.fromJson(Map<String, dynamic> json) {
    return Resource(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      type: json['type'] ?? 'notes',
      fileUrl: json['file_url'] ?? '',
      thumbnailUrl: json['thumbnail_url'],
      semester: json['semester'],
      branch: json['branch'],
      subject: json['subject'],
      chapter: json['chapter'],
      topic: json['topic'],
      description: json['description'] ?? json['content'], // Map content to description for flexibility
      upvotes: json['upvotes'] ?? 0,
      downvotes: json['downvotes'] ?? 0,
      uploadedByEmail: json['uploaded_by_email'] ?? '',
      uploadedByName: json['uploaded_by_name'],
      collegeId: json['college_id'] ?? '',
      isApproved: json['status'] == 'approved' || json['is_approved'] == true,
      createdAt: _parseCreatedAt(json),
    );
  }

  static DateTime _parseCreatedAt(Map<String, dynamic> json) {
    final raw = json['created_at'];
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) {
      debugPrint('Resource Warning: Invalid created_at "$raw" for ID ${json['id']}. Fallback to epoch.');
      return DateTime.utc(1970, 1, 1);
    }
    return parsed;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'file_url': fileUrl,
      'thumbnail_url': thumbnailUrl,
      'semester': semester,
      'branch': branch,
      'subject': subject,
      'chapter': chapter,
      'topic': topic,
      'description': description,
      'content': description, // Ensure content mirrors description
      'upvotes': upvotes,
      'downvotes': downvotes,
      'uploaded_by_email': uploadedByEmail,
      'uploaded_by_name': uploadedByName,
      'college_id': collegeId,
      'is_approved': isApproved,
      'status': isApproved ? 'approved' : 'pending', // Ensure status mirrors isApproved
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Get vote score
  int get score => upvotes - downvotes;

  /// Check if resource is a PDF
  bool get isPdf => fileUrl.toLowerCase().endsWith('.pdf');

  /// Check if resource is a video
  bool get isVideo {
    final url = fileUrl.toLowerCase();
    return url.endsWith('.mp4') || 
           url.endsWith('.mov') || 
           url.endsWith('.webm') ||
           url.contains('youtube.com') ||
           url.contains('youtu.be');
  }

  /// Get resource type icon name
  String get iconName {
    switch (type.toLowerCase()) {
      case 'video':
        return 'video';
      case 'pyq':
        return 'quiz';
      case 'notes':
      default:
        return 'description';
    }
  }

  /// Get formatted date
  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    
    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes <= 0) {
          return 'just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()}w ago';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }
}
