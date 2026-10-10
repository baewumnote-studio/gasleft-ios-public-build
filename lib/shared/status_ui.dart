import 'package:flutter/material.dart';

import '../core/app_strings.dart';
import '../core/enums.dart';
import '../core/theme/design_tokens.dart';

class StatusUi {
  const StatusUi({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  static StatusUi resolve(BuildContext context, CylinderStatus status) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    return switch (status) {
      CylinderStatus.noReading => StatusUi(
        label: strings.text('noReading'),
        icon: Icons.scale_outlined,
        color: scheme.onSurfaceVariant,
      ),
      CylinderStatus.good => StatusUi(
        label: strings.text('statusGood'),
        icon: Icons.check_circle_outline,
        color: dark ? const Color(0xFF84D8AE) : DesignTokens.pineBright,
      ),
      CylinderStatus.low => StatusUi(
        label: strings.text('statusLow'),
        icon: Icons.warning_amber_rounded,
        color: dark ? DesignTokens.amberDark : DesignTokens.amber,
      ),
      CylinderStatus.veryLow => StatusUi(
        label: strings.text('statusVeryLow'),
        icon: Icons.error_outline,
        color: dark ? DesignTokens.dangerDark : DesignTokens.danger,
      ),
      CylinderStatus.checkInput => StatusUi(
        label: strings.text('statusCheckInput'),
        icon: Icons.fact_check_outlined,
        color: scheme.error,
      ),
    };
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});
  final CylinderStatus status;

  @override
  Widget build(BuildContext context) {
    final ui = StatusUi.resolve(context, status);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: context.strings.text('statusSemantics', {'status': ui.label}),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: ui.color.withValues(alpha: dark ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(DesignTokens.radiusChip),
          border: Border.all(
            color: ui.color.withValues(alpha: dark ? 0.34 : 0.22),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ui.icon, size: 15, color: ui.color),
            const SizedBox(width: 5),
            Text(
              ui.label,
              style: TextStyle(
                color: ui.color,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
