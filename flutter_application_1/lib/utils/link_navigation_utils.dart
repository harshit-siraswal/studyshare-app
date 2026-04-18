import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../screens/viewer/pdf_viewer_screen.dart';
import '../screens/viewer/web_source_viewer_screen.dart';
import '../screens/viewer/youtube_player_screen.dart';
import '../screens/viewer/video_player_screen.dart';
import '../widgets/full_screen_image_viewer.dart';
import 'youtube_link_utils.dart';

/// Builds an absolute [Uri] for a StudyShare resource link.
///
/// If [rawUrl] is already an absolute URL, it is returned directly. If it is
/// a relative path (e.g. `/resource/123`), it is resolved against
/// [fallbackBaseUrl] (defaults to [AppConfig.apiUrl]).
///
/// Returns `null` when [rawUrl] is empty, malformed, or cannot be resolved.
Uri? buildStudyShareExternalUri(String rawUrl, {String? fallbackBaseUrl}) {
  final direct = buildExternalUri(rawUrl);
  if (direct != null) return direct;

  final trimmed = rawUrl.trim();
  if (!trimmed.startsWith('/')) return null;

  final base = Uri.tryParse(fallbackBaseUrl ?? AppConfig.apiUrl);
  if (base == null || base.host.isEmpty) return null;
  return buildExternalUri(base.resolve(trimmed).toString());
}

/// Opens a StudyShare link inside the app whenever possible.
/// YouTube, video, PDF, Office documents, and images stay in-app.
/// Generic web pages fall back to the in-app web viewer on mobile/desktop.
///
/// [rawUrl] is the raw link string (absolute or relative).
/// [title] is used as the screen title for in-app viewers.
/// [resourceId], [collegeId], [subject], [semester], and [branch] provide
/// optional metadata forwarded to the player screen.
/// [fallbackBaseUrl] is used to resolve relative URLs (see
/// [buildStudyShareExternalUri]).
///
/// Returns `true` if the link was opened successfully, `false` otherwise.
/// Does not throw; failures are returned as `false`.
Future<bool> openStudyShareLink(
  BuildContext context, {
  required String rawUrl,
  required String title,
  String? resourceId,
  String? collegeId,
  String? collegeName,
  String? subject,
  String? semester,
  String? branch,
  String? fallbackBaseUrl,
}) async {
  final youtubeLink = parseYoutubeLink(rawUrl);
  if (youtubeLink != null) {
    if (!context.mounted) return false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => YoutubePlayerScreen(
          youtubeLink: youtubeLink,
          title: title,
          resourceId: resourceId,
          collegeId: collegeId,
          subject: subject,
          semester: semester,
          branch: branch,
          collegeName: collegeName,
        ),
      ),
    );
    return true;
  }

  final uri = buildStudyShareExternalUri(
    rawUrl,
    fallbackBaseUrl: fallbackBaseUrl,
  );
  if (uri == null) return false;

  if (_isDirectVideoUrl(uri)) {
    if (!context.mounted) return false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerScreen(
          videoUrl: uri.toString(),
          title: title,
          resourceId: resourceId,
          collegeId: collegeId,
          collegeName: collegeName,
          subject: subject,
          semester: semester,
          branch: branch,
        ),
      ),
    );
    return true;
  }

  // Route PDF links to in-app viewer instead of the system browser.
  if (_isPdfUrl(uri) || _isOfficeDocumentUrl(uri)) {
    if (!context.mounted) return false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfViewerScreen(
          pdfUrl: uri.toString(),
          title: title,
          resourceId: resourceId,
          collegeId: collegeId,
        ),
      ),
    );
    return true;
  }

  if (_isImageUrl(uri)) {
    if (!context.mounted) return false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullScreenImageViewer(
          imageUrl: uri.toString(),
          heroTag: 'source_image_${uri.toString().hashCode}',
        ),
      ),
    );
    return true;
  }

  if (kIsWeb) {
    return launchExternalUri(uri);
  }

  if (!context.mounted) return false;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => WebSourceViewerScreen(
        initialUrl: uri.toString(),
        title: title,
      ),
    ),
  );
  return true;
}

bool _isDirectVideoUrl(Uri uri) {
  final lower = uri.path.toLowerCase();
  const extensions = <String>{'.mp4', '.mov', '.m4v', '.webm', '.mkv', '.m3u8'};
  return extensions.any(lower.endsWith);
}

bool _isPdfUrl(Uri uri) {
  final lower = uri.path.toLowerCase();
  final query = uri.query.toLowerCase();
  return lower.endsWith('.pdf') || lower.contains('.pdf?') || lower.contains('/pdf') || query.contains('.pdf');
}

bool _isOfficeDocumentUrl(Uri uri) {
  final lower = uri.path.toLowerCase();
  const extensions = <String>{
    '.doc',
    '.docx',
    '.ppt',
    '.pptx',
    '.xls',
    '.xlsx',
  };
  return extensions.any(lower.endsWith);
}

bool _isImageUrl(Uri uri) {
  final lower = uri.path.toLowerCase();
  const extensions = <String>{'.png', '.jpg', '.jpeg', '.gif', '.webp'};
  return extensions.any(lower.endsWith);
}
