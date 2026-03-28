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
  final String? actorEmail;
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
    this.actorEmail,
    this.actorAvatar,
    this.followRequestId,
    this.actionTaken = false,
    this.data,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final data = _mapFromDynamic(json['data']);
    final requester = _mapFromDynamic(data?['requester']);
    final actor = _mapFromDynamic(data?['actor']);
    final user = _mapFromDynamic(data?['user']);

    final rawCreatedAt = _firstNonNull([
      json['created_at'],
      json['createdAt'],
      data?['created_at'],
      data?['createdAt'],
    ]);

    return NotificationModel(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id'].toString()) ?? 0,
      userId: _stringFromCandidates([
        json['user_id'],
        json['userId'],
        data?['user_id'],
        data?['userId'],
      ]),
      type: _stringFromCandidates([json['type'], data?['type']], fallback: 'unknown'),
      title: _stringFromCandidates([json['title'], data?['title']], fallback: 'Notification'),
      message: _stringFromCandidates([json['message'], data?['message']]),
      isRead: _boolFromCandidates([
        json['is_read'],
        json['isRead'],
        json['read'],
        data?['is_read'],
        data?['isRead'],
      ]),
      createdAt: () {
        if (rawCreatedAt == null) return DateTime.now();
        final parsed = DateTime.tryParse(rawCreatedAt.toString());
        if (parsed == null) {
          debugPrint(
            'Failed to parse created_at: "$rawCreatedAt" for notification id: ${json['id']}',
          );
          return DateTime.now();
        }
        return parsed;
      }(),
      data: data,
      actionUrl: _stringFromCandidates([
        json['action_url'],
        json['actionUrl'],
        data?['action_url'],
        data?['actionUrl'],
      ]),
      actorId: _stringFromCandidates([
        json['actor_id'],
        json['actorId'],
        data?['actor_id'],
        data?['actorId'],
        actor?['id'],
        actor?['user_id'],
        user?['id'],
      ]),
      actorName: _stringFromCandidates([
        json['actor_name'],
        json['actorName'],
        data?['actor_name'],
        data?['actorName'],
        requester?['display_name'],
        requester?['name'],
        actor?['display_name'],
        actor?['name'],
        user?['display_name'],
        user?['name'],
      ]),
      actorEmail: _stringFromCandidates([
        json['actor_email'],
        json['actorEmail'],
        data?['actor_email'],
        data?['actorEmail'],
        data?['requester_email'],
        data?['requesterEmail'],
        data?['user_email'],
        data?['userEmail'],
        data?['follower_email'],
        data?['followerEmail'],
        data?['following_email'],
        data?['followingEmail'],
        data?['target_email'],
        data?['targetEmail'],
        requester?['email'],
        actor?['email'],
        user?['email'],
        json['email'],
      ]),
      actorAvatar: _stringFromCandidates([
        json['actor_avatar'],
        json['actorAvatar'],
        data?['actor_avatar'],
        data?['actorAvatar'],
        data?['requester_avatar'],
        data?['requesterAvatar'],
        data?['requester_photo_url'],
        data?['requesterPhotoUrl'],
        requester?['profile_photo_url'],
        requester?['photo_url'],
        actor?['profile_photo_url'],
        actor?['photo_url'],
        user?['profile_photo_url'],
        user?['photo_url'],
      ]),
      followRequestId: _stringFromCandidates([
        json['follow_request_id'],
        json['followRequestId'],
        data?['follow_request_id'],
        data?['followRequestId'],
        data?['request_id'],
        data?['requestId'],
      ]),
      actionTaken: _boolFromCandidates([
        json['action_taken'],
        json['actionTaken'],
        data?['action_taken'],
        data?['actionTaken'],
      ]),
    );
  }

  NotificationModel copyWith({bool? isRead, bool? actionTaken}) {
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
      actorEmail: actorEmail,
      actorAvatar: actorAvatar,
      followRequestId: followRequestId,
      actionTaken: actionTaken ?? this.actionTaken,
      data: data,
    );
  }

  static Map<String, dynamic>? _mapFromDynamic(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static Object? _firstNonNull(List<Object?> values) {
    for (final value in values) {
      if (value != null) return value;
    }
    return null;
  }

  static String _stringFromCandidates(
    List<Object?> values, {
    String fallback = '',
  }) {
    for (final value in values) {
      if (value == null) continue;
      final normalized = value.toString().trim();
      if (normalized.isNotEmpty) return normalized;
    }
    return fallback;
  }

  static bool _boolFromCandidates(List<Object?> values) {
    for (final value in values) {
      if (value is bool) return value;
      final normalized = value?.toString().trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return false;
  }
}
