import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/theme.dart';
import '../utils/profile_photo_utils.dart';

class UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final String displayName;
  final double radius;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    this.photoUrl,
    required this.displayName,
    this.radius = 20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(displayName);
    final normalizedPhotoUrl = normalizeProfilePhotoUrl(photoUrl);
    final hasImage = normalizedPhotoUrl != null;
    
    final avatarWidget = hasImage
        ? CachedNetworkImage(
            imageUrl: normalizedPhotoUrl!,
            imageBuilder: (context, imageProvider) => CircleAvatar(
              radius: radius,
              backgroundImage: imageProvider,
            ),
            placeholder: (context, url) => _buildInitialsAvatar(initials),
            errorWidget: (context, url, error) => _buildInitialsAvatar(initials),
          )
        : _buildInitialsAvatar(initials);

    // Wrap with Semantics for accessibility
    return Semantics(
      button: onTap != null,
      label: 'Avatar for $displayName',
      onTapHint: onTap != null ? 'View profile' : null,
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: avatarWidget,
            )
          : avatarWidget,
    );
  }

  /// Builds a [CircleAvatar] displaying the user's initials as a fallback
  /// when no profile image is available.
  Widget _buildInitialsAvatar(String initials) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.primary,
      child: Text(
        initials,
        style: GoogleFonts.inter(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'U';
    
    final parts = trimmed.split(' ').where((e) => e.isNotEmpty);
    return parts.map((e) => e[0]).take(2).join().toUpperCase();
  }
}
