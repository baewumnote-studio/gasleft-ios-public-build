import 'package:flutter/material.dart';

import '../core/theme/design_tokens.dart';

enum CampNoticeTone { info, warning, danger }

class CampSectionHeader extends StatelessWidget {
  const CampSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CampNoticeCard extends StatelessWidget {
  const CampNoticeCard({
    super.key,
    required this.icon,
    required this.text,
    this.tone = CampNoticeTone.info,
    this.action,
  });

  final IconData icon;
  final String text;
  final CampNoticeTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    final color = switch (tone) {
      CampNoticeTone.info => scheme.primary,
      CampNoticeTone.warning =>
        dark ? DesignTokens.amberDark : DesignTokens.amber,
      CampNoticeTone.danger => scheme.error,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        border: Border.all(color: color.withValues(alpha: dark ? 0.30 : 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: dark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

class CampMetricPill extends StatelessWidget {
  const CampMetricPill({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(DesignTokens.radiusChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
