import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/app_strings.dart';
import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../data/gas_repository.dart';
import '../../domain/models/cylinder.dart';
import '../../domain/models/weight_reading.dart';
import '../../domain/services/gas_calculation_service.dart';
import '../../domain/services/mass_converter.dart';
import '../../domain/services/reading_validation_service.dart';
import '../../domain/services/reading_sequence_service.dart';
import '../../shared/camp_utility_ui.dart';
import '../../shared/section_card.dart';
import '../../shared/use_case_ui.dart';
import 'reading_result_screen.dart';

class AddReadingScreen extends ConsumerStatefulWidget {
  const AddReadingScreen({
    super.key,
    required this.cylinderId,
    this.readingId,
    this.first = false,
    this.replacement = false,
  });

  final String cylinderId;
  final String? readingId;
  final bool first;
  final bool replacement;

  @override
  ConsumerState<AddReadingScreen> createState() => _AddReadingScreenState();
}

class _AddReadingScreenState extends ConsumerState<AddReadingScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  Cylinder? _cylinder;
  WeightReading? _latest;
  WeightReading? _editing;
  bool _loading = true;
  bool _saving = false;
  bool _missingRequestedReading = false;
  Object? _loadError;
  DateTime _measuredAt = DateTime.now();
  ReadingEventType _editEventType = ReadingEventType.normal;

  bool get _isEditing => _editing != null;

  bool get _startsNewCylinderRevision =>
      !_isEditing &&
      _cylinder != null &&
      ReadingSequenceService.startsNewRevision(
        cylinder: _cylinder!,
        latest: _latest,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(repositoryProvider);
      final c = await repo.getCylinder(widget.cylinderId);
      final latest = c == null
          ? null
          : await repo.getLatestReadingForRevision(
              widget.cylinderId,
              c.currentRevision,
            );
      WeightReading? editing;
      if (widget.readingId != null) {
        editing = await repo.getReading(widget.readingId!);
        if (editing == null || editing.cylinderId != widget.cylinderId) {
          editing = null;
          _missingRequestedReading = true;
        }
      }
      if (c != null && editing != null) {
        _controller.text = AppFormatters.massInputValue(
          editing.totalWeightGrams,
          c.preferredUnit,
        );
        _measuredAt = DateTime.fromMillisecondsSinceEpoch(
          editing.measuredAtEpochMs,
        );
        _editEventType = editing.eventType;
      }
      if (mounted) {
        setState(() {
          _cylinder = c;
          _latest = latest;
          _editing = editing;
          _loading = false;
        });
        if (!_isEditing) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focus.requestFocus();
          });
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _retryLoad() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
      _missingRequestedReading = false;
    });
    await _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _syncReminderBestEffort(ProviderContainer container) async {
    try {
      await container.read(reminderCoordinatorProvider).sync(widget.cylinderId);
    } catch (_) {
      // The reading is already safely persisted at this point. Notification
      // scheduling must never make the UI claim that the reading failed to save.
      // Launch/resume reminder repair retries this best-effort maintenance.
    }
  }

  Future<void> _save() async {
    if (_saving || _cylinder == null) return;
    final strings = context.strings;
    final value = AppFormatters.parseDecimal(_controller.text);
    if (value == null || value <= 0) {
      _snack(strings.text('enterValidWeight'));
      return;
    }

    final c = _cylinder!;
    final totalGrams = MassConverter.toGrams(value, c.preferredUnit);
    final validation = ReadingValidationService.validate(
      tareGrams: _editing?.tareGramsSnapshot ?? c.tareGrams,
      capacityGrams: _editing?.capacityGramsSnapshot ?? c.capacityGrams,
      currentTotalGrams: totalGrams,
      inputUnit: c.preferredUnit,
    );

    if (!validation.canSave) {
      _snack(
        validation.messageKey == null
            ? strings.text('checkInputGeneric')
            : strings.text(validation.messageKey!),
      );
      return;
    }

    if (validation.requiresExplicitConfirmation) {
      final proceed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(strings.text('checkWeightTitle')),
              content: Text(
                validation.messageKey == null
                    ? ''
                    : strings.text(validation.messageKey!),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(strings.text('goBack')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(strings.text('saveAnyway')),
                ),
              ],
            ),
          ) ??
          false;
      if (!mounted || !proceed) return;
    }

    final isReplacementReading =
        widget.replacement || _startsNewCylinderRevision;
    var eventType = isReplacementReading
        ? ReadingEventType.replacement
        : (_isEditing ? _editEventType : ReadingEventType.normal);
    var excluded = validation.flag == ReadingValidationFlag.aboveNominalFull;
    final container = ref.container;
    final repo = container.read(repositoryProvider);

    WeightReading? refillComparison;
    if (!isReplacementReading && eventType == ReadingEventType.normal) {
      if (_isEditing) {
        refillComparison = await repo.getPreviousReadingBefore(
          cylinderId: c.id,
          revision: _editing!.cylinderRevision,
          measuredAtEpochMs: _measuredAt.millisecondsSinceEpoch,
          createdAtEpochMs: _editing!.createdAtEpochMs,
          excludingReadingId: _editing!.id,
        );
        if (!mounted) return;
      } else {
        refillComparison = _latest;
      }
    }

    if (refillComparison != null &&
        ReadingValidationService.looksLikeRefill(
          previousTotalGrams: refillComparison.totalWeightGrams,
          newTotalGrams: totalGrams,
          capacityGrams: _editing?.capacityGramsSnapshot ?? c.capacityGrams,
          unit: c.preferredUnit,
        )) {
      final refill =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(strings.text('refillLooksTitle')),
              content: Text(strings.text('refillLooksBody')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(strings.text('keepNormal')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(strings.text('markRefill')),
                ),
              ],
            ),
          ) ??
          false;
      if (!mounted) return;
      if (refill) {
        eventType = ReadingEventType.refill;
        if (_isEditing) _editEventType = ReadingEventType.refill;
      } else {
        // An unexplained increase is still stored when the user explicitly
        // chooses Normal, but it must stay out of any future prediction model.
        excluded = true;
      }
    }

    setState(() => _saving = true);

    try {
      if (_isEditing) {
        await repo.updateReading(
          reading: _editing!,
          measuredAtEpochMs: _measuredAt.millisecondsSinceEpoch,
          totalWeightGrams: totalGrams,
          eventType: eventType,
          validationFlag: validation.flag,
          excludedFromPrediction: excluded,
        );
        await _syncReminderBestEffort(container);
        container.invalidate(cylinderSummariesProvider);
        container.invalidate(cylinderDetailProvider(widget.cylinderId));
        if (mounted) context.pop();
        return;
      }

      final previous = _latest;
      await repo.addReading(
        cylinder: c,
        measuredAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        totalWeightGrams: totalGrams,
        eventType: eventType,
        validationFlag: validation.flag,
        excludedFromPrediction: excluded,
      );

      await _syncReminderBestEffort(container);
      container.invalidate(cylinderSummariesProvider);
      container.invalidate(cylinderDetailProvider(widget.cylinderId));

      final calc = GasCalculationService.calculate(
        tareGrams: c.tareGrams,
        capacityGrams: c.capacityGrams,
        currentTotalGrams: totalGrams,
      );
      final status = ReadingValidationService.status(
        displayPercent: calc.displayPercent,
        lowThresholdPct: c.lowThresholdPct,
        flag: validation.flag,
      );

      final delta = ReadingSequenceService.consumedSincePrevious(
        cylinder: c,
        previous: previous,
        current: calc,
        currentEventType: eventType,
        currentValidationFlag: validation.flag,
      );

      if (!mounted) return;
      context.go(
        '/reading-result',
        extra: ReadingResultArgs(
          cylinder: c,
          calculation: calc,
          status: status,
          validationFlag: validation.flag,
          deltaGrams: delta,
        ),
      );
    } on CylinderStateConflictException catch (error) {
      _snack(strings.text(error.messageKey));
    } on ReadingStateConflictException catch (error) {
      _snack(strings.text(error.messageKey));
    } catch (_) {
      _snack(
        _isEditing
            ? strings.text('readingUpdateError')
            : strings.text('readingSaveError'),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickMeasuredAt() async {
    final strings = context.strings;
    final date = await showDatePicker(
      context: context,
      initialDate: _measuredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_measuredAt),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (selected.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      _snack(strings.text('measurementFutureError'));
      return;
    }
    setState(() => _measuredAt = selected);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: FilledButton.tonal(
            onPressed: _retryLoad,
            child: Text(strings.text('loadAgain')),
          ),
        ),
      );
    }
    if (_cylinder == null) {
      return Scaffold(
        body: Center(child: Text(strings.text('cylinderNotFound'))),
      );
    }
    if (_missingRequestedReading) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(strings.text('readingNotFound'))),
      );
    }

    final c = _cylinder!;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.first,
        leading: widget.first
            ? IconButton(
                tooltip: strings.text('measureLater'),
                onPressed: _saving ? null : () => context.go('/home'),
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: Text(
          _isEditing ? strings.text('editReading') : strings.text('addReading'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CylinderIdentity(
                    name: c.name,
                    useCase: c.useCase,
                    maxNameLines: 2,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      CampMetricPill(
                        icon: Icons.scale_outlined,
                        label:
                            '${strings.text('tareLabel')} ${AppFormatters.mass(c.tareGrams, c.preferredUnit)}',
                      ),
                      CampMetricPill(
                        icon: Icons.battery_full_outlined,
                        label:
                            '${strings.text('fuelCapacityTitle')} ${AppFormatters.mass(c.capacityGrams, c.preferredUnit)}',
                      ),
                    ],
                  ),
                  if (!_isEditing &&
                      _latest != null &&
                      !_startsNewCylinderRevision) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 17,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            strings.text('previousReading', {
                              'value': AppFormatters.mass(
                                _latest!.totalWeightGrams,
                                c.preferredUnit,
                              ),
                              'time': AppFormatters.timeAgo(
                                _latest!.measuredAtEpochMs,
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
                ],
              ),
            ),
            const SizedBox(height: 20),
            CampSectionHeader(
              icon: Icons.scale_rounded,
              title: strings.text('weighCylinder'),
              subtitle: strings.text('currentWeightHelper'),
            ),
            SectionCard(
              emphasized: true,
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.monitor_weight_outlined,
                      color: scheme.onPrimaryContainer,
                      size: 27,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    strings.text('currentTotalWeight'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _controller,
                    focusNode: _focus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [DecimalTextInputFormatter()],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: '0.0',
                      suffixText: c.preferredUnit.label,
                      helperText: strings.text('currentWeightHelper'),
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ],
              ),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 20),
              CampSectionHeader(
                icon: Icons.edit_calendar_outlined,
                title: strings.text('editReading'),
              ),
              SectionCard(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.schedule_outlined, size: 20),
                      ),
                      title: Text(strings.text('measuredAt')),
                      subtitle: Text(
                        AppFormatters.dateTime(
                          _measuredAt.millisecondsSinceEpoch,
                          strings,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _pickMeasuredAt,
                    ),
                    if (_editing!.eventType !=
                        ReadingEventType.replacement) ...[
                      const Divider(),
                      DropdownButtonFormField<ReadingEventType>(
                        initialValue: _editEventType,
                        decoration: InputDecoration(
                          labelText: strings.text('readingType'),
                          prefixIcon: const Icon(
                            Icons.bookmark_outline_rounded,
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: ReadingEventType.normal,
                            child: Text(strings.text('normalReading')),
                          ),
                          DropdownMenuItem(
                            value: ReadingEventType.refill,
                            child: Text(strings.text('refillReading')),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _editEventType = value);
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (widget.replacement || _startsNewCylinderRevision) ...[
              const SizedBox(height: 16),
              CampNoticeCard(
                icon: Icons.autorenew_rounded,
                text: strings.text('newCylinderFirstReading'),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _isEditing
                          ? Icons.check_rounded
                          : Icons.calculate_outlined,
                    ),
              label: Text(
                _isEditing
                    ? strings.text('saveChanges')
                    : strings.text('saveReading'),
              ),
            ),
            const SizedBox(height: 16),
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
