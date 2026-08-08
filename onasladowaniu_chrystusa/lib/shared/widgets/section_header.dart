import 'package:flutter/material.dart';

import '../layout/responsive_layout.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool showBackButton;
  final VoidCallback? onBack;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.showBackButton = false,
    this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCompact = context.isCompactAndroid;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.layoutValue(20, compact: 14),
        context.layoutValue(20, compact: 16),
        context.layoutValue(20, compact: 14),
        context.layoutValue(12, compact: 10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showBackButton) ...[
            IconButton(
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_back, size: isCompact ? 22 : 24),
              tooltip: 'Wstecz',
              constraints: BoxConstraints(
                minWidth: isCompact ? 40 : 48,
                minHeight: 48,
              ),
              padding: EdgeInsets.zero,
            ),
            SizedBox(width: context.layoutValue(4, compact: 2)),
          ],
          Icon(
            icon,
            size: context.layoutValue(30, compact: 26),
            color: colorScheme.primary,
          ),
          SizedBox(width: context.layoutValue(12, compact: 8)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: context.layoutValue(24, compact: 21),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: context.layoutValue(4, compact: 3)),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: context.layoutValue(14, compact: 13),
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: context.layoutValue(12, compact: 8)),
            trailing!,
          ],
        ],
      ),
    );
  }
}
