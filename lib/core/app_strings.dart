import 'package:flutter/widgets.dart';

import 'enums.dart';

/// Lightweight localization catalog used by the shipping app.
///
/// GasLeft v1 ships in English, but widgets read user-facing copy through this
/// catalog so adding another locale does not require redesigning screen logic.
/// A future locale only needs another catalog map plus a supported locale.
class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  static const supportedLocales = <Locale>[Locale('en')];
  static const AppStrings english = AppStrings(Locale('en'));

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings) ??
        const AppStrings(Locale('en'));
  }

  String get appName => text('appName');

  String useCaseLabel(CylinderUseCase value) => text(switch (value) {
    CylinderUseCase.bbq => 'useCaseBbq',
    CylinderUseCase.rvCaravan => 'useCaseRvCaravan',
    CylinderUseCase.camping => 'useCaseCamping',
    CylinderUseCase.patioHeater => 'useCasePatioHeater',
    CylinderUseCase.outdoorCooking => 'useCaseOutdoorCooking',
    CylinderUseCase.other => 'useCaseOther',
  });

  String text(String key, [Map<String, Object?> values = const {}]) {
    // English is the v1 fallback for every locale until another vetted catalog
    // is intentionally added.
    var value = _english[key] ?? key;
    for (final entry in values.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return value;
  }

  static const Map<String, String> englishCatalog = _english;

  static const Map<String, String> _english = {
    'appName': 'GasLeft',
    'continueAction': 'Continue',
    'pageOf': 'Page {current} of {total}',
    'cancelAction': 'Cancel',
    'deleteAction': 'Delete',
    'editAction': 'Edit',
    'saveAction': 'Save',
    'doneAction': 'Done',
    'tryAgainAction': 'Try again',
    'openSettingsAction': 'Open Settings',
    'notNowAction': 'Not now',
    'gotItAction': 'Got it',
    'settingsTitle': 'Settings',
    'settingsTooltip': 'Settings',
    'addCylinder': 'Add Cylinder',
    'addCylinderTitle': 'Add cylinder',
    'editCylinderTitle': 'Edit cylinder',
    'replaceCylinderTitle': 'Replace cylinder',
    'replacePhysicalCylinder': 'Replace physical cylinder',
    'addReading': 'Add Reading',
    'editReading': 'Edit reading',
    'saveReading': 'Save Reading',
    'saveChanges': 'Save changes',
    'measureLater': 'Measure later',
    'viewHistory': 'View history',
    'historyTitle': 'History',
    'noReading': 'No reading',
    'statusGood': 'Good',
    'statusLow': 'Low',
    'statusVeryLow': 'Very Low',
    'statusCheckInput': 'Check input',
    'statusSemantics': 'Status: {status}',
    'useCaseBbq': 'BBQ / Grill',
    'useCaseRvCaravan': 'RV / Caravan',
    'useCaseCamping': 'Camping',
    'useCasePatioHeater': 'Patio heater',
    'useCaseOutdoorCooking': 'Outdoor cooking',
    'useCaseOther': 'Other',
    'cylinderDetails': 'Cylinder details',
    'cylinderWeights': 'Cylinder weights',
    'planningAlert': 'Planning alert',
    'weighCylinder': 'Weigh cylinder',
    'readingResultTitle': 'Reading saved',
    'themeSystem': 'System',
    'themeLight': 'Light',
    'themeDark': 'Dark',

    'onboardingNoSensorTitle': 'No sensor required.',
    'onboardingNoSensorBody': 'Just weigh your propane or LPG cylinder.',
    'onboardingTareTitle': 'Find the tare weight.',
    'onboardingTareBody':
        'Use the TW, TARE, or empty-weight marking on your own cylinder. WC is not tare weight.',
    'onboardingResultTitle': "See what's left.",
    'onboardingResultBody':
        'Enter the current total weight and GasLeft estimates the remaining fuel.',
    'onboardingWhereTare': 'Where do I find it?',
    'onboardingAddFirst': 'Add my first cylinder',
    'onboardingSaveError': 'Could not finish setup. Please try again.',
    'planningEstimateShort':
        'Planning estimate only. Not a leak detector or cylinder safety check.',
    'tareHelpTitle': 'Where do I find the tare weight?',
    'tareHelpBody':
        'Look for TW, TARE, or Empty Weight near the collar, handle, or valve area. On some bottles, tare is shown on a tag or disc near the valve.',
    'tareHelpWc': 'WC / Water Capacity is NOT the tare weight.',
    'tareHelpActualCylinder':
        'Use the marking on your actual cylinder. Two cylinders with the same nominal size can have different tare weights.',

    'homeTitle': 'My Cylinders',
    'homeLoadError': 'Could not load your cylinders.',
    'homeEmptyTitle': 'No cylinders yet',
    'homeEmptyBody': "Add a cylinder to calculate and track what's left.",
    'homeWeighNewCylinder': 'Weigh the new cylinder',
    'homeAddFirstReading': 'Add your first reading',
    'homeReplacementBody':
        'The cylinder details changed. Add a new weight before GasLeft shows a current level.',
    'homeTareCapacity': 'Tare {tare} · Capacity {capacity}',
    'gasPercentSemantics': '{percent} percent gas remaining',
    'gasRemainingSemantics': 'Gas remaining',
    'percentSemantics': '{percent} percent',
    'massLeft': '{mass} left',
    'checkedAgo': 'Checked {time}',
    'timeJustNow': 'Just now',
    'timeMinutesAgo': '{minutes}m ago',
    'timeHoursAgo': '{hours}h ago',
    'timeYesterday': 'Yesterday',
    'timeDaysAgo': '{days} days ago',

    'bootstrapErrorTitle': 'GasLeft could not finish starting.',
    'bootstrapErrorBody': 'Your local data has not been deleted. Try again.',
    'pageNotFound': 'Page not found.',

    'cylinderNotFound': 'Cylinder not found.',
    'readingNotFound': 'Reading not found.',
    'loadAgain': 'Try loading again',
    'cylinderNameLabel': 'Cylinder name',
    'cylinderNameHint': 'BBQ Tank',
    'enterName': 'Enter a name.',
    'nameMax40': 'Use 40 characters or fewer.',
    'useCaseLabel': 'Use case',
    'commonFuelCapacity': 'Common fuel capacity',
    'capacityPresetHelp':
        'Cylinder sizes vary by brand and region. Confirm the rated fuel capacity.',
    'fuelCapacityLabel': 'Fuel capacity ({unit})',
    'fuelCapacityHelper':
        'Use the rated propane/LPG fuel amount — not WC / Water Capacity.',
    'tareWeightLabel': 'Tare weight ({unit})',
    'tareWeightHelper': 'Use the actual TW/TARE on this cylinder.',
    'wcNotTareInline': 'WC means water capacity — do not enter it as tare.',
    'helpAction': 'Help',
    'lowThresholdLabel': 'Low threshold: {percent}%',
    'lowThresholdPlanning':
        'This is a planning preference, not a safety limit.',
    'continueToWeighing': 'Continue to weighing',
    'positiveValueError': 'Enter a value greater than 0.',
    'checkUnitValue': 'Check the unit and value.',
    'newCylinderInfo':
        'Enter the tare and fuel capacity for the new physical cylinder. Your earlier history will stay unchanged.',
    'tareMarkingGood': 'Use this type of empty-weight marking.',
    'tareMarkingBad': 'Water Capacity — NOT the tare weight.',
    'specChangedTitle': 'Tare or capacity changed',
    'specChangedBody':
        'If you are correcting the saved details for the same physical cylinder, choose Correct details. If this is a different physical cylinder, choose Replace cylinder so future readings start a new revision.',
    'correctDetails': 'Correct details',
    'replaceCylinder': 'Replace cylinder',
    'saveCylinderError': 'Could not save the cylinder. Please try again.',
    'cylinderChangedWhileEditing':
        'This cylinder changed while you were editing. Reopen it and try again.',
    'readingChangedWhileEditing':
        'This reading changed while you were editing. Reopen it and try again.',
    'checkValues': 'Check the values.',
    'validationSpecsPositive':
        'Tare weight and fuel capacity must be greater than zero.',
    'validationPortableWeight': 'Enter a valid portable-cylinder weight.',
    'validationBelowTare':
        'Current weight is below the tare weight. Check the unit and the TW/TARE value.',
    'validationNearTare':
        'This is within normal scale variation around the tare weight.',
    'validationAboveNominalFull':
        'This weight is above the nominal full weight. Check the tare, fuel capacity, unit, and any attached accessories.',
    'validationPortableFullMass':
        'The tare plus fuel capacity is outside GasLeft’s portable-cylinder range. Check the unit and values.',
    'correctionExistingBelowTare':
        'Those corrected values would make an existing reading fall below the tare weight. Check the values, or use Replace cylinder if this is a different physical cylinder.',

    'currentTotalWeight': 'Current total weight',
    'currentWeightHelper': 'Enter the weight shown on your scale.',
    'previousReading': 'Previous: {value} · {time}',
    'tareCapacitySummary': 'Tare {tare} · Capacity {capacity}',
    'measuredAt': 'Measured at',
    'readingType': 'Reading type',
    'normalReading': 'Normal reading',
    'refillReading': 'Refill',
    'replacementHistory': 'Cylinder replaced',
    'newCylinderFirstReading':
        'This first reading will mark the new physical cylinder in your history.',
    'enterValidWeight': 'Enter a valid weight.',
    'checkInputGeneric': 'Check your input.',
    'checkWeightTitle': 'Check this weight',
    'goBack': 'Go back',
    'saveAnyway': 'Save anyway',
    'refillLooksTitle': 'This looks like a refill.',
    'refillLooksBody':
        'The weight is higher than the previous reading in this cylinder revision. Mark it as a refill?',
    'keepNormal': 'Keep as Normal',
    'markRefill': 'Mark as Refill',
    'readingSaveError': 'Could not save the reading. Please try again.',
    'readingUpdateError': 'Could not update the reading. Please try again.',
    'measurementFutureError': 'Measurement time cannot be in the future.',
    'weightEstimateDisclaimer':
        'GasLeft estimates remaining fuel from the weights you enter. It does not detect gas leaks or determine whether a cylinder is safe to use.',

    'gasRemaining': 'Gas remaining',
    'usedSinceLast': 'Used {mass} since last check',
    'aboveNominalResult':
        'This reading is above the nominal full weight. Check the tare, capacity, unit, and attached accessories before relying on it.',
    'lowPlanning': 'Low — consider planning a refill before your next use.',
    'veryLowPlanning': 'Very Low — check the cylinder before your next use.',

    'couldNotLoadCylinder': 'Could not load cylinder.',
    'editCylinder': 'Edit cylinder',
    'deleteReadingTitle': 'Delete this reading?',
    'deleteReadingBody': 'The current status and history will be recalculated.',
    'deleteReadingError': 'Could not delete the reading.',
    'deleteCylinderTitle': 'Delete {name}?',
    'deleteCylinderBody':
        'This deletes the cylinder and all of its local reading history.',
    'deleteCylinderError': 'Could not delete the cylinder.',
    'noReadingsHistory':
        'Your measurements will appear here after you add a reading.',
    'noReadingsYet': 'No readings yet',
    'replacementNoLevelBody':
        'Your earlier history is preserved. Add a reading for the replacement cylinder to show a current level.',
    'tareLabel': 'Tare',
    'fuelCapacityTitle': 'Fuel capacity',
    'lowThresholdTitle': 'Low threshold',
    'totalReadingLine': 'Total {total} · {date}',
    'recheckReminder': 'Recheck reminder',
    'recheckEnabledSubtitle': 'Remind me {days} days after the latest reading.',
    'recheckDisabledSubtitle':
        'Optional. GasLeft will remind you to weigh again.',
    'recheckNeedsReading': 'Add a reading before turning on recheck reminders.',
    'recheckWaitingForReading':
        'Waiting for a new reading. The reminder will resume from that measurement.',
    'notificationsOffTitle': 'Notifications are off',
    'notificationsOffBody':
        'GasLeft cannot schedule a recheck reminder until notifications are allowed in iOS Settings.',
    'notificationsOffSettings': 'Notifications are off in iOS Settings.',
    'reminderUpdateError': 'Could not update the reminder.',
    'afterLabel': 'After',
    'daysLabel': '{days} days',
    'notificationRecheckTitle': 'Time to recheck {name}',
    'notificationRecheckBody':
        'It’s been {days} days since your last weight check. Add a new reading for an updated estimate.',

    'settingsGeneral': 'General',
    'defaultUnit': 'Default unit',
    'appearance': 'Appearance',
    'privacyAds': 'Privacy & Ads',
    'privacyOptions': 'Privacy Options',
    'privacyPolicy': 'Privacy Policy',
    'reportAd': 'Report an ad',
    'aboutSafety': 'About & Safety',
    'versionLabel': 'Version',
    'settingsLoadError': 'Could not load settings.',
    'defaultUnitSaveError': 'Could not save the default unit.',
    'appearanceSaveError': 'Could not save the appearance setting.',
    'privacyOpenError': 'Could not open the privacy policy.',
    'adReportUnconfigured':
        'Use the AdChoices/report control shown on the ad when available. The developer support email still needs to be configured before release.',
    'emailOpenError': 'Could not open the email app.',
    'configRequired': '{key} must be configured for the release build.',
    'adReportSubject': 'GasLeft ad report',
    'adReportBody':
        'Please describe the ad and when you saw it. Do not include sensitive personal information.',

    'safetyHowTitle': 'How GasLeft works',
    'safetyHowBody':
        'GasLeft subtracts the tare (empty-cylinder) weight from the total weight you enter, then compares the remaining fuel mass with the nominal fuel capacity.',
    'safetyTareWcTitle': 'Tare vs. WC',
    'safetyTareWcBody':
        'Tare weight is the empty cylinder weight. Look for TW, TARE, or an empty-weight marking on your actual cylinder.\n\nWC means Water Capacity. It is not the tare weight and it is not the nominal fuel mass you should enter as capacity.',
    'safetyBoundaryTitle': 'Safety boundary',
    'safetyBoundaryBody':
        'GasLeft estimates remaining fuel from the weights you enter. It does not detect gas leaks, measure pressure, inspect or certify a cylinder, determine fill compliance, or determine whether a cylinder is safe to use.\n\nUse GasLeft only as a planning estimate. Follow the instructions and safety guidance provided by your cylinder, appliance, supplier, and local authorities.',
    'privacyLocalBody':
        'Your cylinder records are stored locally on your device. GasLeft has no account or cloud sync. Advertising may involve data processing by Google AdMob as described in the privacy policy.',
  };
}

extension AppStringsBuildContext on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';

  @override
  Future<AppStrings> load(Locale locale) async => AppStrings(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppStrings> old) => false;
}
