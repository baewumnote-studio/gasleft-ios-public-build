import 'package:flutter/material.dart';

import '../core/app_strings.dart';
import '../core/enums.dart';

IconData cylinderUseCaseIcon(CylinderUseCase value) => switch (value) {
  CylinderUseCase.bbq => Icons.outdoor_grill_outlined,
  CylinderUseCase.rvCaravan => Icons.rv_hookup_outlined,
  CylinderUseCase.camping => Icons.park_outlined,
  CylinderUseCase.patioHeater => Icons.local_fire_department_outlined,
  CylinderUseCase.outdoorCooking => Icons.restaurant_outlined,
  CylinderUseCase.other => Icons.category_outlined,
};

class CylinderUseCaseMark extends StatelessWidget {
  const CylinderUseCaseMark({super.key, required this.useCase, this.size = 44});

  final CylinderUseCase useCase;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        alignment: Alignment.center,
        child: Icon(
          cylinderUseCaseIcon(useCase),
          size: size * 0.52,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class CylinderIdentity extends StatelessWidget {
  const CylinderIdentity({
    super.key,
    required this.name,
    required this.useCase,
    this.maxNameLines = 1,
  });

  final String name;
  final CylinderUseCase useCase;
  final int maxNameLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CylinderUseCaseMark(useCase: useCase),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: maxNameLines,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                strings.useCaseLabel(useCase),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
