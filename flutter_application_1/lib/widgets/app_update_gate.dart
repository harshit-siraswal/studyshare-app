import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_service.dart';
import '../utils/app_snack_bar.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child, this.service});

  final Widget child;
  final AppUpdateService? service;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  static const Duration _resumeCheckThrottle = Duration(hours: 6);

  late final AppUpdateService _service = widget.service ?? AppUpdateService();
  DateTime? _lastCheckAt;
  AndroidReleaseInfo? _availableRelease;
  bool _checkInFlight = false;
  bool _dialogVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForUpdate());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final lastCheckAt = _lastCheckAt;
    if (lastCheckAt != null &&
        DateTime.now().difference(lastCheckAt) < _resumeCheckThrottle) {
      return;
    }
    unawaited(_checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    if (!mounted || _checkInFlight || _dialogVisible) return;
    _checkInFlight = true;
    _lastCheckAt = DateTime.now();

    try {
      final release = await _service.checkForUpdate(includeDismissed: true);
      if (!mounted || release == null) return;
      setState(() => _availableRelease = release);
      if (!await _service.isReleaseDismissed(release)) {
        await _showUpdateDialog(release);
      }
    } catch (error) {
      debugPrint('App update prompt failed: $error');
    } finally {
      _checkInFlight = false;
    }
  }

  Future<void> _showUpdateDialog(AndroidReleaseInfo release) async {
    if (_dialogVisible) return;
    _dialogVisible = true;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !release.mandatory,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          return AlertDialog(
            icon: Icon(
              Icons.system_update_rounded,
              color: theme.colorScheme.primary,
            ),
            title: Text('Update available: v${release.version}'),
            content: _UpdateDialogContent(release: release),
            actions: [
              if (!release.mandatory)
                TextButton(
                  onPressed: () async {
                    await _service.dismissRelease(release);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: const Text('Later'),
                ),
              FilledButton.icon(
                onPressed: () async {
                  await _service.dismissRelease(release);
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  if (mounted) {
                    await _openDownload(release);
                  }
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download'),
              ),
            ],
          );
        },
      );
    } finally {
      _dialogVisible = false;
    }
  }

  Future<void> _openDownload(AndroidReleaseInfo release) async {
    final uri = Uri.parse(release.apkUrl);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      AppSnackBar.error(
        context,
        'Could not open the APK download. Please try again later.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = _availableRelease;
    if (release == null) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 12,
          right: 12,
          top: MediaQuery.paddingOf(context).top + 10,
          child: _UpdateBanner(
            release: release,
            onDownload: () => unawaited(_openDownload(release)),
          ),
        ),
      ],
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.release, required this.onDownload});

  final AndroidReleaseInfo release;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SafeArea(
      bottom: false,
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.primary.withValues(alpha: 0.22)),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: colors.primary.withValues(alpha: 0.12),
                  foregroundColor: colors.primary,
                  child: const Icon(Icons.system_update_rounded, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New version ${release.version} available',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Download the latest StudyShare APK.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateDialogContent extends StatelessWidget {
  const _UpdateDialogContent({required this.release});

  final AndroidReleaseInfo release;

  @override
  Widget build(BuildContext context) {
    final notes = release.releaseNotes.take(3).toList(growable: false);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A newer StudyShare Android build is ready. Download it to get '
          'the latest fixes and features.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('- '),
                  Expanded(child: Text(note)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
