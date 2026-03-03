import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

class IncomingShareFile {
  final String pathValue;
  final String name;
  final String mimeType;
  final int sizeBytes;

  const IncomingShareFile({
    required this.pathValue,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
  });

  static const Set<String> _stickerExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.gif',
  };

  static const Set<String> _resourceExtensions = {
    '.pdf',
    '.doc',
    '.docx',
    '.ppt',
    '.pptx',
    '.odt',
    '.odp',
    '.txt',
  };

  String get extension {
    final baseName = name.isEmpty ? path.basename(pathValue) : name;
    return path.extension(baseName).toLowerCase();
  }

  bool get isStickerCandidate =>
      _stickerExtensions.contains(extension) || mimeType.startsWith('image/');

  bool get isResourceCandidate =>
      _resourceExtensions.contains(extension) ||
      mimeType.contains('pdf') ||
      mimeType.contains('msword') ||
      mimeType.contains('officedocument');
}

class IncomingSharePayload {
  final String action;
  final String mimeType;
  final String? text;
  final DateTime? receivedAt;
  final List<IncomingShareFile> files;

  const IncomingSharePayload({
    required this.action,
    required this.mimeType,
    required this.text,
    required this.receivedAt,
    required this.files,
  });

  bool get hasFiles => files.isNotEmpty;

  List<IncomingShareFile> get stickerFiles =>
      files.where((file) => file.isStickerCandidate).toList();

  IncomingShareFile? get resourceFile {
    for (final file in files) {
      if (file.isResourceCandidate) return file;
    }
    return null;
  }

  bool get isStickerPackCandidate {
    if (files.length < 2) return false;
    return files.every((file) => file.isStickerCandidate);
  }
}

class IncomingShareService {
  IncomingShareService._();

  static final IncomingShareService instance = IncomingShareService._();

  static const MethodChannel _methodChannel = MethodChannel(
    'me.studyshare.android/share_intent',
  );
  static const EventChannel _eventChannel = EventChannel(
    'me.studyshare.android/share_intent_events',
  );

  final StreamController<IncomingSharePayload> _controller =
      StreamController<IncomingSharePayload>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  bool _isStarted = false;

  Stream<IncomingSharePayload> get stream => _controller.stream;

  Future<void> start() async {
    if (_isStarted) return;
    _isStarted = true;

    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic payload) {
        final parsed = _parsePayload(payload);
        if (parsed != null) {
          _controller.add(parsed);
        }
      },
      onError: (_) {
        // Ignore transient channel errors.
      },
    );
  }

  Future<IncomingSharePayload?> consumeInitialShare() async {
    try {
      final raw = await _methodChannel.invokeMethod<dynamic>('getInitialShare');
      final parsed = _parsePayload(raw);
      if (parsed == null) return null;
      await _methodChannel.invokeMethod<void>('clearInitialShare');
      return parsed;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _isStarted = false;
  }

  IncomingSharePayload? _parsePayload(dynamic raw) {
    if (raw == null) return null;

    Map<String, dynamic> map;
    if (raw is String) {
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      map = decoded.cast<String, dynamic>();
    } else if (raw is Map) {
      map = raw.cast<String, dynamic>();
    } else {
      return null;
    }

    final files = <IncomingShareFile>[];
    final rawFiles = map['files'];
    if (rawFiles is List) {
      for (final item in rawFiles) {
        if (item is! Map) continue;
        final fileMap = item.cast<dynamic, dynamic>();
        final pathValue = fileMap['path']?.toString() ?? '';
        if (pathValue.isEmpty) continue;
        final name = fileMap['name']?.toString() ?? path.basename(pathValue);
        final mimeType = fileMap['mimeType']?.toString() ?? '';
        final rawSize = fileMap['sizeBytes'];
        final size = rawSize is int
            ? rawSize
            : int.tryParse(rawSize?.toString() ?? '') ?? 0;
        files.add(
          IncomingShareFile(
            pathValue: pathValue,
            name: name,
            mimeType: mimeType,
            sizeBytes: size,
          ),
        );
      }
    }

    final text = map['text']?.toString();
    if (files.isEmpty && (text == null || text.trim().isEmpty)) {
      return null;
    }

    DateTime? receivedAt;
    final rawReceivedAt = map['receivedAt'];
    if (rawReceivedAt is int) {
      receivedAt = DateTime.fromMillisecondsSinceEpoch(rawReceivedAt);
    } else if (rawReceivedAt is String) {
      final parsedInt = int.tryParse(rawReceivedAt);
      if (parsedInt != null) {
        receivedAt = DateTime.fromMillisecondsSinceEpoch(parsedInt);
      }
    }

    return IncomingSharePayload(
      action: map['action']?.toString() ?? '',
      mimeType: map['mimeType']?.toString() ?? '',
      text: text,
      receivedAt: receivedAt,
      files: files,
    );
  }
}



