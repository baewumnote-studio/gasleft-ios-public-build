import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/app_strings.dart';
import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../domain/models/cylinder.dart';
import '../../domain/models/view_models.dart';
import '../../shared/camp_utility_ui.dart';
import '../../shared/section_card.dart';
import '../../shared/use_case_ui.dart';
import '../../shared/status_ui.dart';

class ReadingResultArgs {
  const ReadingResultArgs({
    required this.cylinder,
    required this.calculation,
    required this.status,
    required this.validationFlag,
    this.deltaGrams,
  });

  final Cylinder cylinder;
  final GasCalculation calculation;
  final CylinderStatus status;
  final ReadingValidationFlag validationFlag;
  final int? deltaGrams;
}

class ReadingResultScreen extends ConsumerStatefulWidget {
  const ReadingResultScreen({super.key, required this.args});

  final ReadingResultArgs args;

  @override
  ConsumerState<ReadingResultScreen> createState() =>
      _ReadingResultScreenState();
}

class _ReadingResultScreenState extends ConsumerState<ReadingResultScreen> {
  bool _finishing = false;

  Future<void> _done() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await ref.read(adServiceProvider).showIfEligibleAfterResult();
      if (mounted) context.go('/home');
    } catch (_) {
      // Ads are optional. A local/network ad failure must never trap the user
      // on the result screen.
      if (mounted) context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final args = widget.args;
    final c = args.cylinder;
    final calc = args.calculation;
    final statusUi = StatusUi.resolve(context, args.status);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(strings.text('readingResultTitle')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            SectionCard(
              emphasized: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stack =
                          constraints.maxWidth < 315 ||
                          MediaQuery.textScalerOf(context).scale(1) >= 1.5;
                      final identity = CylinderIdentity(
                        name: c.name,
                        useCase: c.useCase,
                        maxNameLines: 2,
                      );
                      final badge = StatusBadge(status: args.status);
                      if (stack) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            identity,
                            const SizedBox(height: 10),
                            badge,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: identity),
                          const SizedBox(width: 12),
                          badge,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    strings.text('gasRemaining'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stack =
                          constraints.maxWidth < 300 ||
                          MediaQuery.textScalerOf(context).scale(1) >= 1.6;
                      final percent = Semantics(
                        label: strings.text('gasPercentSemantics', {
                          'percent': calc.displayPercent.round(),
                        }),
                        excludeSemantics: true,
                        child: Text(
                          AppFormatters.percent(calc.displayPercent),
                          style: theme.textTheme.displayLarge,
                        ),
                      );
                      final mass = Text(
                        strings.text('massLeft', {
                          'mass': AppFormatters.mass(
                            calc.displayRemainingGrams,
                            c.preferredUnit,
                          ),
                        }),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      );
                      if (stack) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [percent, const SizedBox(height: 4), mass],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(child: percent),
                          const SizedBox(width: 12),
                          Flexible(child: mass),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: calc.displayPercent / 100,
                        minHeight: 12,
                        color: statusUi.color,
                        backgroundColor: statusUi.color.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (args.deltaGrams != null && args.deltaGrams! > 0) ...[
              const SizedBox(height: 14),
              CampNoticeCard(
                icon: Icons.trending_down_rounded,
                text: strings.text('usedSinceLast', {
                  'mass': AppFormatters.mass(args.deltaGrams!, c.preferredUnit),
                }),
              ),
            ],
            if (args.validationFlag ==
                ReadingValidationFlag.aboveNominalFull) ...[
              const SizedBox(height: 14),
              CampNoticeCard(
                icon: Icons.fact_check_outlined,
                text: strings.text('aboveNominalResult'),
                tone: CampNoticeTone.danger,
              ),
            ],
            if (args.status == CylinderStatus.low ||
                args.status == CylinderStatus.veryLow) ...[
              const SizedBox(height: 14),
              CampNoticeCard(
                icon: args.status == CylinderStatus.veryLow
                    ? Icons.error_outline_rounded
                    : Icons.warning_amber_rounded,
                text: args.status == CylinderStatus.veryLow
                    ? strings.text('veryLowPlanning')
                    : strings.text('lowPlanning'),
                tone: args.status == CylinderStatus.veryLow
                    ? CampNoticeTone.danger
                    : CampNoticeTone.warning,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _finishing ? null : _done,
              icon: _finishing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(strings.text('doneAction')),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _finishing
                  ? null
                  : () => context.go('/cylinder/${c.id}'),
              icon: const Icon(Icons.history_rounded),
              label: Text(strings.text('viewHistory')),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    strings.text('weightEstimateDisclaimer'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
