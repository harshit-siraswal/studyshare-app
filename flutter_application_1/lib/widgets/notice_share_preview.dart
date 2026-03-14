import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';
import '../models/department_account.dart';

class NoticeSharePreview extends StatelessWidget {
  final Map<String, dynamic> notice;
  final DepartmentAccount account;
  final String brandLabel;
  final String timestampLabel;

  const NoticeSharePreview({
    super.key,
    required this.notice,
    required this.account,
    required this.brandLabel,
    required this.timestampLabel,
  });

  @override
  Widget build(BuildContext context) {
    final title = (notice['title'] ?? 'Untitled').toString().trim();
    final content = (notice['content'] ?? '').toString().trim();
    final mediaCount = _mediaUrls.length;
    final hasPdf = _documentUrl.isNotEmpty;
    final hasAttachments = mediaCount > 0 || hasPdf;

    return Material(
      color: Colors.white,
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: account.color,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      account.avatarLetter,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                account.name,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.verified_rounded,
                              size: 16,
                              color: const Color(0xFF8B5CF6),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${account.handle} \u00b7 $timestampLabel',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 22,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
              if (content.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  content,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    height: 1.5,
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
              if (hasAttachments) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (mediaCount > 0)
                      _buildAttachmentChip(
                        icon: Icons.image_rounded,
                        color: const Color(0xFF38BDF8),
                        label: mediaCount == 1
                            ? '1 image'
                            : '$mediaCount images',
                      ),
                    if (hasPdf)
                      _buildAttachmentChip(
                        icon: Icons.picture_as_pdf_rounded,
                        color: const Color(0xFFF97316),
                        label: 'PDF attached',
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'via $brandLabel',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> get _mediaUrls {
    final values = <String>[];
    final seen = <String>{};
    final raw = notice['media_urls'];
    if (raw is List) {
      for (final value in raw) {
        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty && seen.add(text)) values.add(text);
      }
    }

    final legacyImage = notice['image_url']?.toString().trim() ?? '';
    if (legacyImage.isNotEmpty && seen.add(legacyImage)) {
      values.add(legacyImage);
    }
    return values;
  }

  String get _documentUrl {
    final candidates = <String?>[
      notice['document_url']?.toString(),
      notice['pdf_url']?.toString(),
      notice['attachment_url']?.toString(),
    ];

    for (final candidate in candidates) {
      final trimmed = candidate?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  Widget _buildAttachmentChip({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
