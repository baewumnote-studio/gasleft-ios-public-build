import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/app_config.dart';
import '../../core/app_strings.dart';
import '../../core/enums.dart';
import '../../core/url_utils.dart';
import '../../shared/section_card.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _savingGeneral = false;
  bool _privacyBusy = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final settingsAsync = ref.watch(appSettingsProvider);
    final privacyOptionsAsync = ref.watch(privacyOptionsRequiredProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.text('settingsTitle'))),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(strings.text('settingsLoadError')),
                const SizedBox(height: 14),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(appSettingsProvider),
                  child: Text(strings.text('tryAgainAction')),
                ),
              ],
            ),
          ),
        ),
        data: (settings) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.text('settingsGeneral'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.text('defaultUnit')),
                    trailing: DropdownButton<MassUnit>(
                      value: settings.defaultUnit,
                      items: MassUnit.values
                          .map(
                            (unit) => DropdownMenuItem(
                              value: unit,
                              child: Text(unit.label),
                            ),
                          )
                          .toList(),
                      onChanged: _savingGeneral
                          ? null
                          : (value) {
                              if (value != null) {
                                _saveDefaultUnit(value);
                              }
                            },
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.text('appearance')),
                    trailing: DropdownButton<AppThemeMode>(
                      value: settings.themeMode,
                      items: AppThemeMode.values
                          .map(
                            (mode) => DropdownMenuItem(
                              value: mode,
                              child: Text(switch (mode) {
                                AppThemeMode.system => strings.text(
                                  'themeSystem',
                                ),
                                AppThemeMode.light => strings.text(
                                  'themeLight',
                                ),
                                AppThemeMode.dark => strings.text('themeDark'),
                              }),
                            ),
                          )
                          .toList(),
                      onChanged: _savingGeneral
                          ? null
                          : (value) {
                              if (value != null) {
                                _saveThemeMode(value);
                              }
                            },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.text('privacyAds'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  privacyOptionsAsync.maybeWhen(
                    data: (required) {
                      if (!required) return const SizedBox.shrink();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: Text(strings.text('privacyOptions')),
                        enabled: !_privacyBusy,
                        onTap: _privacyBusy ? null : _presentPrivacyOptions,
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.policy_outlined),
                    title: Text(strings.text('privacyPolicy')),
                    onTap: () => _openPrivacy(context),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(strings.text('reportAd')),
                    onTap: () => _reportAd(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info_outline),
                    title: Text(strings.text('aboutSafety')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/safety'),
                  ),
                  const Divider(),
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('versionLabel')),
                      trailing: Text(
                        snapshot.hasData
                            ? '${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                            : '—',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveDefaultUnit(MassUnit value) async {
    if (_savingGeneral) return;
    setState(() => _savingGeneral = true);
    try {
      await ref.read(repositoryProvider).updateDefaultUnit(value);
      if (!mounted) return;
      ref.invalidate(appSettingsProvider);
    } catch (_) {
      if (mounted) {
        _snack(context, context.strings.text('defaultUnitSaveError'));
      }
    } finally {
      if (mounted) setState(() => _savingGeneral = false);
    }
  }

  Future<void> _saveThemeMode(AppThemeMode value) async {
    if (_savingGeneral) return;
    setState(() => _savingGeneral = true);
    try {
      await ref.read(repositoryProvider).updateThemeMode(value);
      if (!mounted) return;
      ref.invalidate(appSettingsProvider);
    } catch (_) {
      if (mounted) _snack(context, context.strings.text('appearanceSaveError'));
    } finally {
      if (mounted) setState(() => _savingGeneral = false);
    }
  }

  Future<void> _presentPrivacyOptions() async {
    if (_privacyBusy) return;
    setState(() => _privacyBusy = true);
    try {
      await ref.read(adServiceProvider).presentPrivacyOptions();
      if (!mounted) return;
      ref.invalidate(privacyOptionsRequiredProvider);
    } finally {
      if (mounted) setState(() => _privacyBusy = false);
    }
  }

  Future<void> _openPrivacy(BuildContext context) async {
    if (AppConfig.privacyPolicyUrl.isEmpty) {
      _missingConfig(context, 'PRIVACY_POLICY_URL');
      return;
    }
    final uri = Uri.tryParse(AppConfig.privacyPolicyUrl);
    if (uri == null || !await launchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.text('privacyOpenError'))),
        );
      }
    }
  }

  Future<void> _reportAd(BuildContext context) async {
    if (AppConfig.supportEmail.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.strings.text('reportAd')),
          content: Text(context.strings.text('adReportUnconfigured')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.strings.text('gotItAction')),
            ),
          ],
        ),
      );
      return;
    }
    final uri = Uri(
      scheme: 'mailto',
      path: AppConfig.supportEmail,
      query: encodeNonHttpQueryParameters({
        'subject': context.strings.text('adReportSubject'),
        'body': context.strings.text('adReportBody'),
      }),
    );
    if (!await launchUrl(uri) && context.mounted) {
      _snack(context, context.strings.text('emailOpenError'));
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _missingConfig(BuildContext context, String key) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.strings.text('configRequired', {'key': key})),
      ),
    );
  }
}
