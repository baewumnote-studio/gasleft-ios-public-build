enum MassUnit {
  kg,
  lb;

  String get label => switch (this) {
    MassUnit.kg => 'kg',
    MassUnit.lb => 'lb',
  };

  static MassUnit fromDb(String value) =>
      value == 'lb' ? MassUnit.lb : MassUnit.kg;
}

enum CylinderUseCase {
  bbq,
  rvCaravan,
  camping,
  patioHeater,
  outdoorCooking,
  other;

  static CylinderUseCase fromDb(String value) {
    return CylinderUseCase.values.firstWhere(
      (e) => e.name == value,
      orElse: () => CylinderUseCase.other,
    );
  }
}

enum ReadingEventType {
  normal,
  refill,
  replacement;

  static ReadingEventType fromDb(String value) {
    return ReadingEventType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ReadingEventType.normal,
    );
  }
}

enum ReadingValidationFlag {
  normal,
  nearTare,
  aboveNominalFull;

  static ReadingValidationFlag fromDb(String value) {
    return ReadingValidationFlag.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ReadingValidationFlag.normal,
    );
  }
}

enum PredictionExclusionReason {
  none,
  sequenceIncrease,
  validation,
  manual;

  static PredictionExclusionReason fromDb(String? value) {
    return PredictionExclusionReason.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PredictionExclusionReason.none,
    );
  }
}

enum CylinderStatus { noReading, good, low, veryLow, checkInput }

enum AppThemeMode {
  system,
  light,
  dark;

  static AppThemeMode fromDb(String value) {
    return AppThemeMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AppThemeMode.system,
    );
  }
}
