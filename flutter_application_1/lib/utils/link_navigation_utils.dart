import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../screens/viewer/youtube_player_screen.dart';
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

/// Opens a StudyShare link, routing YouTube URLs to [YoutubePlayerScreen]
/// and all other URLs to an external browser.
///
/// [rawUrl] is the raw link string (absolute or relative).
/// [title] is used as the screen title for YouTube links.
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
  return launchExternalUri(uri);
}
