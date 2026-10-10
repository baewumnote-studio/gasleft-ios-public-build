import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/gas_repository.dart';
import '../../core/app_config.dart';
import '../../core/app_strings.dart';
import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../domain/models/cylinder.dart';
import '../../domain/services/mass_converter.dart';
import '../../domain/services/cylinder_spec_validation_service.dart';
import '../../shared/camp_utility_ui.dart';
import '../../shared/section_card.dart';
import '../../shared/use_case_ui.dart';

class CylinderFormScreen extends ConsumerStatefulWidget {
  const CylinderFormScreen({
    super.key,
    this.cylinderId,
    this.first = false,
    this.replace = false,
  });

  final String? cylinderId;
  final bool first;
  final bool replace;

  @override
  ConsumerState<CylinderFormScreen> createState() => _CylinderFormScreenState();
}

class _CylinderFormScreenState extends ConsumerState<CylinderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _tare = TextEditingController();
  final _capacity = TextEditingController();

  CylinderUseCase _useCase = CylinderUseCase.bbq;
  MassUnit _unit = MassUnit.kg;
  double _lowThreshold = AppConfig.defaultLowThresholdPct.toDouble();
  Cylinder? _existing;
  bool _loading = true;
  bool _saving = false;
  bool _missingCylinder = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.cylinderId != null) {
        final cylinder = await ref
            .read(repositoryProvider)
            .getCylinder(widget.cylinderId!);
        if (cylinder != null) {
          _existing = cylinder;
          _name.text = cylinder.name;
          _useCase = cylinder.useCase;
          _unit = cylinder.preferredUnit;
          _lowThreshold = cylinder.lowThresholdPct;
          _tare.text = AppFormatters.massInputValue(
            cylinder.tareGrams,
            cylinder.preferredUnit,
          );
          _capacity.text = AppFormatters.massInputValue(
            cylinder.capacityGrams,
            cylinder.preferredUnit,
          );
        } else {
          _missingCylinder = true;
        }
      } else {
        _unit =
            (await ref.read(repositoryProvider).getAppSettings()).defaultUnit;
      }
    } catch (error) {
      _loadError = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _retryLoad() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
      _missingCylinder = false;
    });
    await _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _tare.dispose();
    _capacity.dispose();
    super.dispose();
  }

  List<double> get _presets =>
      _unit == MassUnit.lb ? const [20, 30, 40] : const [4.5, 5, 9, 11, 13];

  Future<void> _syncReminderBestEffort(
    ProviderContainer container,
    String cylinderId,
  ) async {
    try {
      await container.read(reminderCoordinatorProvider).sync(cylinderId);
    } catch (_) {
      // The cylinder change has already committed. A local-notification failure
      // must not invite the user to repeat the replacement and increment the
      // cylinder revision again. Launch/resume synchronization retries later.
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    final strings = context.strings;

    final tareValue = AppFormatters.parseDecimal(_tare.text);
    final capacityValue = AppFormatters.parseDecimal(_capacity.text);
    if (tareValue == null || capacityValue == null) return;

    setState(() => _saving = true);
    final container = ref.container;
    final repo = container.read(repositoryProvider);

    try {
      var tareGrams = MassConverter.toGrams(tareValue, _unit);
      var capacityGrams = MassConverter.toGrams(capacityValue, _unit);

      // A display-unit round trip can differ by a gram due to decimal
      // formatting. Preserve the original physical values so merely switching
      // kg/lb never looks like a cylinder-spec correction.
      if (_existing != null) {
        if ((tareGrams - _existing!.tareGrams).abs() <= 1) {
          tareGrams = _existing!.tareGrams;
        }
        if ((capacityGrams - _existing!.capacityGrams).abs() <= 1) {
          capacityGrams = _existing!.capacityGrams;
        }
      }

      final specValidation = CylinderSpecValidationService.validate(
        tareGrams: tareGrams,
        capacityGrams: capacityGrams,
      );
      if (!specValidation.isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                specValidation.messageKey == null
                    ? strings.text('checkValues')
                    : strings.text(specValidation.messageKey!),
              ),
            ),
          );
        }
        return;
      }

      if (_existing == null) {
        final id = await repo.createCylinder(
          name: _name.text,
          useCase: _useCase,
          preferredUnit: _unit,
          tareGrams: tareGrams,
          capacityGrams: capacityGrams,
          lowThresholdPct: _lowThreshold,
        );
        container.invalidate(cylinderSummariesProvider);
        if (mounted) {
          if (widget.first) {
            context.go('/cylinder/$id/read?first=1');
          } else {
            context.pushReplacement('/cylinder/$id/read');
          }
        }
      } else if (widget.replace) {
        await repo.replaceCylinder(
          cylinder: _existing!,
          newTareGrams: tareGrams,
          newCapacityGrams: capacityGrams,
          unit: _unit,
        );
        await _syncReminderBestEffort(container, _existing!.id);
        container.invalidate(cylinderSummariesProvider);
        container.invalidate(cylinderDetailProvider(_existing!.id));
        if (mounted) {
          context.pushReplacement(
            '/cylinder/${_existing!.id}/read?replacement=1',
          );
        }
      } else {
        final existing = _existing!;
        final specsChanged =
            tareGrams != existing.tareGrams ||
            capacityGrams != existing.capacityGrams;

        if (specsChanged) {
          final decision = await _askSpecChangeDecision();
          if (!mounted || decision == _SpecChangeDecision.cancel) return;

          if (decision == _SpecChangeDecision.replacePhysicalCylinder) {
            final base = existing.copyWith(
              name: _name.text.trim(),
              useCase: _useCase,
              lowThresholdPct: _lowThreshold,
              updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
            );
            await repo.replaceCylinder(
              cylinder: base,
              newTareGrams: tareGrams,
              newCapacityGrams: capacityGrams,
              unit: _unit,
            );
            await _syncReminderBestEffort(container, existing.id);
            container.invalidate(cylinderSummariesProvider);
            container.invalidate(cylinderDetailProvider(existing.id));
            if (mounted) {
              context.pushReplacement(
                '/cylinder/${existing.id}/read?replacement=1',
              );
            }
            return;
          }
        }

        final updated = existing.copyWith(
          name: _name.text.trim(),
          useCase: _useCase,
          preferredUnit: _unit,
          tareGrams: tareGrams,
          capacityGrams: capacityGrams,
          lowThresholdPct: _lowThreshold,
          updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        );
        if (specsChanged) {
          await repo.correctCylinderSpecs(
            cylinder: updated,
            newTareGrams: tareGrams,
            newCapacityGrams: capacityGrams,
            unit: _unit,
          );
          await _syncReminderBestEffort(container, updated.id);
        } else {
          await repo.updateCylinder(updated);
        }
        container.invalidate(cylinderSummariesProvider);
        container.invalidate(cylinderDetailProvider(updated.id));
        if (mounted) context.pop();
      }
    } on CylinderSpecCorrectionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.text(error.messageKey))));
      }
    } on CylinderStateConflictException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.text(error.messageKey))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.text('saveCylinderError'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<_SpecChangeDecision> _askSpecChangeDecision() async {
    if (!mounted) return _SpecChangeDecision.cancel;
    final strings = context.strings;
    return await showDialog<_SpecChangeDecision>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(strings.text('specChangedTitle')),
            content: Text(strings.text('specChangedBody')),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _SpecChangeDecision.cancel),
                child: Text(strings.text('cancelAction')),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _SpecChangeDecision.correctDetails),
                child: Text(strings.text('correctDetails')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _SpecChangeDecision.replacePhysicalCylinder,
                ),
                child: Text(strings.text('replaceCylinder')),
              ),
            ],
          ),
        ) ??
        _SpecChangeDecision.cancel;
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
    if (_missingCylinder) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(strings.text('cylinderNotFound'))),
      );
    }

    final editing = _existing != null;
    final title = widget.replace
        ? strings.text('replaceCylinderTitle')
        : editing
        ? strings.text('editCylinderTitle')
        : strings.text('addCylinderTitle');

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
            children: [
              if (widget.replace) ...[
                CampNoticeCard(
                  icon: Icons.swap_horiz_rounded,
                  text: strings.text('newCylinderInfo'),
                ),
                const SizedBox(height: 18),
              ],
              CampSectionHeader(
                icon: cylinderUseCaseIcon(_useCase),
                title: strings.text('cylinderDetails'),
                subtitle: strings.useCaseLabel(_useCase),
              ),
              SectionCard(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _name,
                      enabled: !widget.replace,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: strings.text('cylinderNameLabel'),
                        hintText: strings.text('cylinderNameHint'),
                        prefixIcon: const Icon(Icons.label_outline_rounded),
                      ),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return strings.text('enterName');
                        if (v.length > 40) return strings.text('nameMax40');
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<CylinderUseCase>(
                      initialValue: _useCase,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: strings.text('useCaseLabel'),
                        prefixIcon: Icon(cylinderUseCaseIcon(_useCase)),
                      ),
                      items: CylinderUseCase.values
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(
                                strings.useCaseLabel(e),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: widget.replace
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _useCase = value);
                              }
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              CampSectionHeader(
                icon: Icons.scale_outlined,
                title: strings.text('cylinderWeights'),
                subtitle: strings.text('capacityPresetHelp'),
              ),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<MassUnit>(
                      segments: const [
                        ButtonSegment(
                          value: MassUnit.kg,
                          label: Text('kg'),
                          icon: Icon(Icons.straighten_outlined),
                        ),
                        ButtonSegment(
                          value: MassUnit.lb,
                          label: Text('lb'),
                          icon: Icon(Icons.straighten_outlined),
                        ),
                      ],
                      selected: {_unit},
                      showSelectedIcon: false,
                      onSelectionChanged: (values) {
                        final next = values.first;
                        if (next == _unit) return;
                        final tareCurrent = AppFormatters.parseDecimal(
                          _tare.text,
                        );
                        final capCurrent = AppFormatters.parseDecimal(
                          _capacity.text,
                        );
                        setState(() {
                          if (tareCurrent != null) {
                            final grams = MassConverter.toGrams(
                              tareCurrent,
                              _unit,
                            );
                            _tare.text = AppFormatters.massInputValue(
                              grams,
                              next,
                            );
                          }
                          if (capCurrent != null) {
                            final grams = MassConverter.toGrams(
                              capCurrent,
                              _unit,
                            );
                            _capacity.text = AppFormatters.massInputValue(
                              grams,
                              next,
                            );
                          }
                          _unit = next;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      strings.text('commonFuelCapacity'),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _presets.map((value) {
                        final digits = value % 1 == 0 ? 0 : 1;
                        return ActionChip(
                          avatar: const Icon(Icons.bolt_outlined, size: 17),
                          label: Text(
                            '${value.toStringAsFixed(digits)} ${_unit.label}',
                          ),
                          onPressed: () =>
                              setState(() => _capacity.text = value.toString()),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.text('capacityPresetHelp'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _capacity,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [DecimalTextInputFormatter()],
                      decoration: InputDecoration(
                        labelText: strings.text('fuelCapacityLabel', {
                          'unit': _unit.label,
                        }),
                        suffixText: _unit.label,
                        prefixIcon: const Icon(Icons.battery_full_outlined),
                        helperText: strings.text('fuelCapacityHelper'),
                        helperMaxLines: 8,
                      ),
                      validator: (value) =>
                          _positiveNumberValidator(value, strings),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _tare,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [DecimalTextInputFormatter()],
                      decoration: InputDecoration(
                        labelText: strings.text('tareWeightLabel', {
                          'unit': _unit.label,
                        }),
                        suffixText: _unit.label,
                        prefixIcon: const Icon(Icons.scale_outlined),
                        helperText: strings.text('tareWeightHelper'),
                        helperMaxLines: 8,
                      ),
                      validator: (value) =>
                          _positiveNumberValidator(value, strings),
                    ),
                    const SizedBox(height: 12),
                    CampNoticeCard(
                      icon: Icons.info_outline_rounded,
                      text: strings.text('wcNotTareInline'),
                      tone: CampNoticeTone.danger,
                      action: IconButton(
                        tooltip: strings.text('helpAction'),
                        onPressed: () => _showTareHelp(context),
                        icon: const Icon(Icons.help_outline_rounded),
                        color: scheme.error,
                      ),
                    ),
                  ],
                ),
              ),
              if (!widget.replace) ...[
                const SizedBox(height: 20),
                CampSectionHeader(
                  icon: Icons.notifications_none_rounded,
                  title: strings.text('planningAlert'),
                  subtitle: strings.text('lowThresholdPlanning'),
                ),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              strings.text('lowThresholdTitle'),
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${_lowThreshold.round()}%',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        min: 5,
                        max: 50,
                        divisions: 9,
                        label: '${_lowThreshold.round()}%',
                        value: _lowThreshold,
                        onChanged: (value) =>
                            setState(() => _lowThreshold = value),
                      ),
                      Text(
                        strings.text('lowThresholdPlanning'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        widget.replace
                            ? Icons.arrow_forward_rounded
                            : Icons.check_rounded,
                      ),
                label: Text(
                  widget.replace
                      ? strings.text('continueToWeighing')
                      : strings.text('saveAction'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _positiveNumberValidator(String? value, AppStrings strings) {
    final parsed = AppFormatters.parseDecimal(value ?? '');
    if (parsed == null || parsed <= 0 || !parsed.isFinite) {
      return strings.text('positiveValueError');
    }
    final grams = MassConverter.toGrams(parsed, _unit);
    if (grams > 500000) return strings.text('checkUnitValue');
    return null;
  }

  Future<void> _showTareHelp(BuildContext context) {
    final strings = context.strings;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.text('tareHelpTitle'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              Text(strings.text('tareHelpBody')),
              const SizedBox(height: 16),
              _MarkingExample(
                label: 'TW 17.2 lb',
                description: strings.text('tareMarkingGood'),
                good: true,
              ),
              const SizedBox(height: 10),
              _MarkingExample(
                label: 'WC 47.8 lb',
                description: strings.text('tareMarkingBad'),
                good: false,
              ),
              const SizedBox(height: 16),
              Text(strings.text('tareHelpActualCylinder')),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkingExample extends StatelessWidget {
  const _MarkingExample({
    required this.label,
    required this.description,
    required this.good,
  });

  final String label;
  final String description;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good
        ? const Color(0xFF2E7D52)
        : Theme.of(context).colorScheme.error;
    return Row(
      children: [
        Icon(
          good ? Icons.check_circle_outline : Icons.cancel_outlined,
          color: color,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [
                TextSpan(
                  text: '$label\n',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _SpecChangeDecision { cancel, correctDetails, replacePhysicalCylinder }
