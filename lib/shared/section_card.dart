import 'package:flutter/material.dart';

import '../core/theme/design_tokens.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DesignTokens.cardPadding),
    this.emphasized = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: emphasized ? scheme.surfaceContainerLowest : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          emphasized ? DesignTokens.radiusHero : DesignTokens.radiusCard,
        ),
        side: BorderSide(
          color: emphasized
              ? scheme.primary.withValues(alpha: 0.18)
              : scheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
