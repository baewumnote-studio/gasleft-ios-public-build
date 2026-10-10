import '../../core/enums.dart';

class Cylinder {
  const Cylinder({
    required this.id,
    required this.name,
    required this.useCase,
    required this.preferredUnit,
    required this.tareGrams,
    required this.capacityGrams,
    required this.lowThresholdPct,
    required this.currentRevision,
    required this.sortOrder,
    required this.createdAtEpochMs,
    required this.updatedAtEpochMs,
  });

  final String id;
  final String name;
  final CylinderUseCase useCase;
  final MassUnit preferredUnit;
  final int tareGrams;
  final int capacityGrams;
  final double lowThresholdPct;
  final int currentRevision;
  final int sortOrder;
  final int createdAtEpochMs;
  final int updatedAtEpochMs;

  factory Cylinder.fromMap(Map<String, Object?> map) => Cylinder(
    id: map['id']! as String,
    name: map['name']! as String,
    useCase: CylinderUseCase.fromDb(map['use_case']! as String),
    preferredUnit: MassUnit.fromDb(map['preferred_unit']! as String),
    tareGrams: map['tare_grams']! as int,
    capacityGrams: map['capacity_grams']! as int,
    lowThresholdPct: (map['low_threshold_pct']! as num).toDouble(),
    currentRevision: map['current_revision']! as int,
    sortOrder: map['sort_order']! as int,
    createdAtEpochMs: map['created_at_ms']! as int,
    updatedAtEpochMs: map['updated_at_ms']! as int,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'use_case': useCase.name,
    'preferred_unit': preferredUnit.name,
    'tare_grams': tareGrams,
    'capacity_grams': capacityGrams,
    'low_threshold_pct': lowThresholdPct,
    'current_revision': currentRevision,
    'sort_order': sortOrder,
    'created_at_ms': createdAtEpochMs,
    'updated_at_ms': updatedAtEpochMs,
  };

  Cylinder copyWith({
    String? name,
    CylinderUseCase? useCase,
    MassUnit? preferredUnit,
    int? tareGrams,
    int? capacityGrams,
    double? lowThresholdPct,
    int? currentRevision,
    int? sortOrder,
    int? updatedAtEpochMs,
  }) {
    return Cylinder(
      id: id,
      name: name ?? this.name,
      useCase: useCase ?? this.useCase,
      preferredUnit: preferredUnit ?? this.preferredUnit,
      tareGrams: tareGrams ?? this.tareGrams,
      capacityGrams: capacityGrams ?? this.capacityGrams,
      lowThresholdPct: lowThresholdPct ?? this.lowThresholdPct,
      currentRevision: currentRevision ?? this.currentRevision,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAtEpochMs: createdAtEpochMs,
      updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
    );
  }
}
