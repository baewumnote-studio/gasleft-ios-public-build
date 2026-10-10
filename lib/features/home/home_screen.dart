import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/app_strings.dart';
import '../../core/formatters.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/view_models.dart';
import '../../shared/section_card.dart';
import '../../shared/status_ui.dart';
import '../../shared/use_case_ui.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final summaries = ref.watch(cylinderSummariesProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 66,
        title: Text(strings.text('homeTitle')),
        actions: [
          IconButton(
            tooltip: strings.text('settingsTooltip'),
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/cylinder/new'),
        icon: const Icon(Icons.add_rounded),
        label: Text(strings.text('addCylinder')),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(cylinderSummariesProvider);
            await ref.read(cylinderSummariesProvider.future);
          },
          child: summaries.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 100),
                const Icon(Icons.error_outline_rounded, size: 48),
                const SizedBox(height: 12),
                Text(
                  strings.text('homeLoadError'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(cylinderSummariesProvider),
                  child: Text(strings.text('tryAgainAction')),
                ),
              ],
            ),
            data: (items) {
              if (items.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  children: [
                    const SizedBox(height: 70),
                    Center(
                      child: Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.local_fire_department_outlined,
                          size: 44,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      strings.text('homeEmptyTitle'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      strings.text('homeEmptyBody'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 26),
                    FilledButton.icon(
                      onPressed: () => context.push('/cylinder/new'),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(strings.text('addCylinder')),
                    ),
                  ],
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.pageHorizontal,
                  10,
                  DesignTokens.pageHorizontal,
                  100,
                ),
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: DesignTokens.sectionGap),
                itemBuilder: (context, index) =>
                    _CylinderCard(summary: items[index]),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CylinderCard extends StatelessWidget {
  const _CylinderCard({required this.summary});

  final CylinderSummary summary;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final c = summary.cylinder;
    final calc = summary.calculation;
    final latest = summary.latestReading;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusUi = StatusUi.resolve(context, summary.status);

    return Semantics(
      button: true,
      label: c.name,
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusHero),
        onTap: () => context.push('/cylinder/${c.id}'),
        child: SectionCard(
          emphasized: true,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CylinderIdentity(name: c.name, useCase: c.useCase),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge(status: summary.status),
                ],
              ),
              const SizedBox(height: 22),
              if (calc == null) ...[
                Text(
                  summary.awaitingReplacementReading
                      ? strings.text('homeWeighNewCylinder')
                      : strings.text('homeAddFirstReading'),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  summary.awaitingReplacementReading
                      ? strings.text('homeReplacementBody')
                      : strings.text('homeTareCapacity', {
                          'tare': AppFormatters.mass(
                            c.tareGrams,
                            c.preferredUnit,
                          ),
                          'capacity': AppFormatters.mass(
                            c.capacityGrams,
                            c.preferredUnit,
                          ),
                        }),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ] else ...[
                Text(
                  strings.text('gasRemaining'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 12,
                  runSpacing: 5,
                  children: [
                    Semantics(
                      label: strings.text('gasPercentSemantics', {
                        'percent': calc.displayPercent.round(),
                      }),
                      excludeSemantics: true,
                      child: Text(
                        AppFormatters.percent(calc.displayPercent),
                        style: theme.textTheme.displaySmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        strings.text('massLeft', {
                          'mass': AppFormatters.mass(
                            calc.displayRemainingGrams,
                            c.preferredUnit,
                          ),
                        }),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: calc.displayPercent / 100,
                      minHeight: 8,
                      color: statusUi.color,
                      backgroundColor: scheme.surfaceContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                if (latest != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          strings.text('checkedAgo', {
                            'time': AppFormatters.timeAgo(
                              latest.measuredAtEpochMs,
                              strings,
                            ),
                          }),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => context.push('/cylinder/${c.id}/read'),
                  icon: const Icon(Icons.scale_outlined),
                  label: Text(strings.text('addReading')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
