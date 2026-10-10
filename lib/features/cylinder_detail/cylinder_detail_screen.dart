import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/gas_repository.dart';
import '../../core/app_strings.dart';
import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/weight_reading.dart';
import '../../shared/section_card.dart';
import '../../shared/status_ui.dart';
import '../../shared/use_case_ui.dart';

class CylinderDetailScreen extends ConsumerWidget {
  const CylinderDetailScreen({super.key, required this.cylinderId});

  final String cylinderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final detail = ref.watch(cylinderDetailProvider(cylinderId));

    return detail.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(strings.text('couldNotLoadCylinder')),
                const SizedBox(height: 14),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.invalidate(cylinderDetailProvider(cylinderId)),
                  child: Text(strings.text('tryAgainAction')),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (data) {
        if (data == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(strings.text('cylinderNotFound'))),
          );
        }

        final c = data.cylinder;
        final calc = data.summary.calculation;
        return Scaffold(
          appBar: AppBar(
            title: Text(c.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') {
                    context.push('/cylinder/${c.id}/edit');
                  } else if (value == 'replace') {
                    context.push('/cylinder/${c.id}/replace');
                  } else if (value == 'delete') {
                    await _deleteCylinder(
                      context,
                      ref,
                      c.id,
                      c.name,
                      c.currentRevision,
                    );
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(strings.text('editCylinder')),
                  ),
                  PopupMenuItem(
                    value: 'replace',
                    child: Text(strings.text('replacePhysicalCylinder')),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(strings.text('deleteAction')),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 34),
              children: [
                SectionCard(
                  emphasized: true,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CylinderUseCaseMark(useCase: c.useCase, size: 40),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              strings.useCaseLabel(c.useCase),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                          StatusBadge(status: data.summary.status),
                        ],
                      ),
                      const SizedBox(height: 22),
                      if (calc == null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.summary.awaitingReplacementReading
                                  ? strings.text('homeWeighNewCylinder')
                                  : strings.text('noReadingsYet'),
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            if (data.summary.awaitingReplacementReading) ...[
                              const SizedBox(height: 8),
                              Text(
                                strings.text('replacementNoLevelBody'),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                              ),
                            ],
                          ],
                        )
                      else ...[
                        Text(
                          strings.text('gasRemaining'),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Semantics(
                          label: strings.text('gasPercentSemantics', {
                            'percent': calc.displayPercent.round(),
                          }),
                          excludeSemantics: true,
                          child: Text(
                            AppFormatters.percent(calc.displayPercent),
                            style: Theme.of(context).textTheme.displayLarge,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.text('massLeft', {
                            'mass': AppFormatters.mass(
                              calc.displayRemainingGrams,
                              c.preferredUnit,
                            ),
                          }),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 15),
                        ExcludeSemantics(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusChip,
                            ),
                            child: LinearProgressIndicator(
                              value: calc.displayPercent / 100,
                              minHeight: 9,
                              color: StatusUi.resolve(
                                context,
                                data.summary.status,
                              ).color,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainer,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () =>
                              context.push('/cylinder/${c.id}/read'),
                          icon: const Icon(Icons.scale_outlined),
                          label: Text(strings.text('addReading')),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  child: Column(
                    children: [
                      _SpecRow(
                        label: strings.text('tareLabel'),
                        value: AppFormatters.mass(c.tareGrams, c.preferredUnit),
                      ),
                      const Divider(),
                      _SpecRow(
                        label: strings.text('fuelCapacityTitle'),
                        value: AppFormatters.mass(
                          c.capacityGrams,
                          c.preferredUnit,
                        ),
                      ),
                      const Divider(),
                      _SpecRow(
                        label: strings.text('lowThresholdTitle'),
                        value: '${c.lowThresholdPct.round()}%',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _ReminderCard(
                  cylinderId: c.id,
                  enabled: data.reminder.recheckEnabled,
                  days: data.reminder.recheckDays,
                  hasCurrentReading: data.summary.latestReading != null,
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Text(
                      strings.text('historyTitle'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text('${data.readings.length}'),
                  ],
                ),
                const SizedBox(height: 10),
                if (data.readings.isEmpty)
                  SectionCard(child: Text(strings.text('noReadingsHistory')))
                else
                  ...data.readings.map(
                    (reading) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ReadingTile(
                        reading: reading,
                        unit: c.preferredUnit,
                        onEdit: () => context.push(
                          '/cylinder/${c.id}/read?readingId=${reading.id}',
                        ),
                        onDelete: () =>
                            _deleteReading(context, ref, reading.id),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteReading(
    BuildContext context,
    WidgetRef ref,
    String readingId,
  ) async {
    final strings = context.strings;
    final container = ref.container;
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(strings.text('deleteReadingTitle')),
            content: Text(strings.text('deleteReadingBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(strings.text('cancelAction')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(strings.text('deleteAction')),
              ),
            ],
          ),
        ) ??
        false;
    if (!context.mounted || !yes) return;

    try {
      await container.read(repositoryProvider).deleteReading(readingId);
      try {
        await container.read(reminderCoordinatorProvider).sync(cylinderId);
      } catch (_) {
        // Deletion already succeeded. Do not tell the user that it failed just
        // because notification maintenance had a transient problem. Launch/resume
        // reminder repair retries this best-effort maintenance.
      }
      container.invalidate(cylinderDetailProvider(cylinderId));
      container.invalidate(cylinderSummariesProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.text('deleteReadingError'))),
        );
      }
    }
  }

  Future<void> _deleteCylinder(
    BuildContext context,
    WidgetRef ref,
    String id,
    String name,
    int expectedRevision,
  ) async {
    final strings = context.strings;
    final container = ref.container;
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(strings.text('deleteCylinderTitle', {'name': name})),
            content: Text(strings.text('deleteCylinderBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(strings.text('cancelAction')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(strings.text('deleteAction')),
              ),
            ],
          ),
        ) ??
        false;
    if (!context.mounted || !yes) return;

    try {
      final notificationId = await container
          .read(repositoryProvider)
          .deleteCylinder(id, expectedRevision: expectedRevision);
      // Cancel only after the guarded DB delete commits. If the screen was
      // stale and the delete is rejected, a valid reminder for the newer
      // physical-cylinder revision remains untouched.
      if (notificationId != null) {
        try {
          await container
              .read(notificationServiceProvider)
              .cancel(notificationId);
        } catch (_) {
          // Local data is already deleted. The serialized repair below (or the
          // next launch/resume) gets another chance to remove the orphan.
        }
      }
      try {
        // If an app-resume repair was already scheduling this cylinder while
        // deletion committed, this waits behind it and then removes any orphan
        // request that the older operation may have just recreated.
        await container.read(reminderCoordinatorProvider).repairAll();
      } catch (_) {}
      container.invalidate(cylinderSummariesProvider);
      if (context.mounted) context.go('/home');
    } on CylinderStateConflictException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.text(error.messageKey))));
        container.invalidate(cylinderDetailProvider(id));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.text('deleteCylinderError'))),
        );
      }
    }
  }
}

class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack =
            constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.5;
        final valueText = Text(
          value,
          textAlign: stack ? TextAlign.start : TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w700),
        );
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(label), const SizedBox(height: 4), valueText],
          );
        }
        return Row(
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Flexible(child: valueText),
          ],
        );
      },
    );
  }
}

class _ReminderCard extends ConsumerStatefulWidget {
  const _ReminderCard({
    required this.cylinderId,
    required this.enabled,
    required this.days,
    required this.hasCurrentReading,
  });

  final String cylinderId;
  final bool enabled;
  final int days;
  final bool hasCurrentReading;

  @override
  ConsumerState<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends ConsumerState<_ReminderCard>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool? _notificationsEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissionStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionStatus();
    }
  }

  Future<void> _refreshPermissionStatus() async {
    if (!mounted) return;
    final notifications = ref.read(notificationServiceProvider);
    final enabled = await notifications.notificationsEnabled();
    if (mounted) setState(() => _notificationsEnabled = enabled);
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    final strings = context.strings;
    final container = ref.container;
    final coordinator = container.read(reminderCoordinatorProvider);
    final notifications = container.read(notificationServiceProvider);
    setState(() => _busy = true);
    try {
      if (value) {
        final granted = await coordinator.enable(
          cylinderId: widget.cylinderId,
          days: widget.days,
        );
        if (!granted && mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(strings.text('notificationsOffTitle')),
              content: Text(strings.text('notificationsOffBody')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(strings.text('notNowAction')),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await notifications.openNotificationSettings();
                  },
                  child: Text(strings.text('openSettingsAction')),
                ),
              ],
            ),
          );
          if (!mounted) return;
        }
      } else {
        await coordinator.disable(widget.cylinderId);
      }
      container.invalidate(cylinderDetailProvider(widget.cylinderId));
      if (!mounted) return;
      await _refreshPermissionStatus();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.text('reminderUpdateError'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeDays(int days) async {
    if (_busy) return;
    final strings = context.strings;
    final container = ref.container;
    final coordinator = container.read(reminderCoordinatorProvider);
    setState(() => _busy = true);
    try {
      await coordinator.changeDays(widget.cylinderId, days);
      container.invalidate(cylinderDetailProvider(widget.cylinderId));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.text('reminderUpdateError'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              strings.text('recheckReminder'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              widget.enabled
                  ? (widget.hasCurrentReading
                        ? strings.text('recheckEnabledSubtitle', {
                            'days': widget.days,
                          })
                        : strings.text('recheckWaitingForReading'))
                  : (widget.hasCurrentReading
                        ? strings.text('recheckDisabledSubtitle')
                        : strings.text('recheckNeedsReading')),
            ),
            value: widget.enabled,
            onChanged: _busy || (!widget.enabled && !widget.hasCurrentReading)
                ? null
                : _toggle,
          ),
          if (widget.enabled && _notificationsEnabled == false) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.text('notificationsOffSettings'),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  await ref
                                      .read(notificationServiceProvider)
                                      .openNotificationSettings();
                                },
                          child: Text(strings.text('openSettingsAction')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (widget.enabled)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(strings.text('afterLabel')),
                DropdownButton<int>(
                  value: widget.days,
                  items: const [3, 7, 14, 21, 30, 60, 90]
                      .map(
                        (days) => DropdownMenuItem(
                          value: days,
                          child: Text(
                            strings.text('daysLabel', {'days': days}),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (days) {
                          if (days != null) _changeDays(days);
                        },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ReadingTile extends StatelessWidget {
  const _ReadingTile({
    required this.reading,
    required this.unit,
    required this.onEdit,
    required this.onDelete,
  });

  final WeightReading reading;
  final MassUnit unit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final remaining = (reading.totalWeightGrams - reading.tareGramsSnapshot)
        .clamp(0, reading.capacityGramsSnapshot)
        .toInt();
    final pct = (remaining / reading.capacityGramsSnapshot * 100)
        .clamp(0, 100)
        .toDouble();

    final eventLabel = switch (reading.eventType) {
      ReadingEventType.refill => strings.text('refillReading'),
      ReadingEventType.replacement => strings.text('replacementHistory'),
      ReadingEventType.normal => null,
    };

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      '${pct.round()}% · ${strings.text('massLeft', {'mass': AppFormatters.mass(remaining, unit)})}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (eventLabel != null)
                      Chip(
                        label: Text(eventLabel),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (reading.validationFlag ==
                        ReadingValidationFlag.aboveNominalFull)
                      Chip(
                        avatar: const Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                        ),
                        label: Text(strings.text('statusCheckInput')),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  strings.text('totalReadingLine', {
                    'total': AppFormatters.mass(reading.totalWeightGrams, unit),
                    'date': AppFormatters.dateTime(
                      reading.measuredAtEpochMs,
                      strings,
                    ),
                  }),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(strings.text('editAction')),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(strings.text('deleteAction')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
