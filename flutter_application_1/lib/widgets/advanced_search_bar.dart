import 'package:flutter/material.dart';

class AdvancedSearchBar extends StatelessWidget {
  final VoidCallback onTap;
  final String hintText;

  const AdvancedSearchBar({
    super.key,
    required this.onTap,
    this.hintText = 'Search rooms, tags...',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Hero(
      tag: 'search_bar',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.transparent,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: isDark ? Colors.grey : Colors.amber.shade700,
                ),
                const SizedBox(width: 12),
                Text(
                  hintText,
                  style: TextStyle(
                    color: isDark ? Colors.grey : Colors.black54,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.keyboard_command_key,
                        size: 12,
                        color: isDark ? Colors.grey : Colors.black45,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'K',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey : Colors.black45,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
