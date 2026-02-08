import 'package:flutter/foundation.dart';

class NotificationModel {
  final int id;

  final String userId;
  final String type; // 'follow_request', 'resource_posted', etc.
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic>? data;
  final String? actionUrl;
  final String? actorId;
  final String? actorName;
  final String? actorAvatar;
  final String? followRequestId;
  final bool actionTaken;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.actionUrl,
    this.actorId,
    this.actorName,
    this.actorAvatar,
    this.followRequestId,
    this.actionTaken = false,
    this.data,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      userId: json['user_id']?.toString() ?? '',
      type: json['type'] ?? 'unknown',
      title: json['title'] ?? 'Notification',
      message: json['message'] ?? '',
      isRead: json['is_read'] ?? false,
      createdAt: () {
        if (json['created_at'] == null) return DateTime.now();
        final parsed = DateTime.tryParse(json['created_at'].toString());
        if (parsed == null) {
          debugPrint('Failed to parse created_at: "${json['created_at']}" for notification id: ${json['id']}');
          return DateTime.now();
        }
        return parsed;
      }(),
      data: json['data'] is Map<String, dynamic> ? json['data'] as Map<String, dynamic> : null,
      actionUrl: json['action_url'],
      actorId: json['actor_id']?.toString(),
      actorName: json['actor_name'],
      actorAvatar: json['actor_avatar'],
      followRequestId: json['follow_request_id']?.toString(),
      actionTaken: json['action_taken'] ?? false,    );
  }

  NotificationModel copyWith({
    bool? isRead,
    bool? actionTaken,
  }) {
    return NotificationModel(
      id: id,
      userId: userId,
      type: type,
      title: title,
      message: message,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      actionUrl: actionUrl,
      actorId: actorId,
      actorName: actorName,
      actorAvatar: actorAvatar,
      followRequestId: followRequestId,
      actionTaken: actionTaken ?? this.actionTaken,
      data: data,
    );
  }
}
