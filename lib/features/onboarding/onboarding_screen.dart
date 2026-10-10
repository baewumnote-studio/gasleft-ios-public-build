import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/app_strings.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      final repo = ref.read(repositoryProvider);
      await repo.markOnboardingComplete();
      ref.invalidate(appSettingsProvider);
      if (mounted) context.go('/cylinder/new?first=1');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.text('onboardingSaveError'))),
        );
        setState(() => _finishing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final pages = <({String asset, String title, String body})>[
      (
        asset: 'assets/illustrations/onboarding_welcome.png',
        title: strings.text('onboardingNoSensorTitle'),
        body: strings.text('onboardingNoSensorBody'),
      ),
      (
        asset: 'assets/illustrations/onboarding_weigh.png',
        title: strings.text('onboardingTareTitle'),
        body: strings.text('onboardingTareBody'),
      ),
      (
        asset: 'assets/illustrations/onboarding_plan.png',
        title: strings.text('onboardingResultTitle'),
        body: strings.text('onboardingResultBody'),
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, index) {
                  final page = pages[index];
                  return LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight > 56
                              ? constraints.maxHeight - 56
                              : 0.0,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Semantics(
                              image: true,
                              label: page.title,
                              child: ExcludeSemantics(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(28),
                                  child: AspectRatio(
                                    aspectRatio: 5 / 3,
                                    child: Image.asset(
                                      page.asset,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 30),
                            Text(
                              page.title,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              page.body,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.45,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (index == 1) ...[
                              const SizedBox(height: 20),
                              FilledButton.tonalIcon(
                                onPressed: () => _showTareHelp(context),
                                icon: const Icon(Icons.help_outline),
                                label: Text(
                                  strings.text('onboardingWhereTare'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Semantics(
              container: true,
              label: strings.text('pageOf', {
                'current': _page + 1,
                'total': pages.length,
              }),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    pages.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: index == _page ? 22 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: index == _page
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: FilledButton(
                onPressed: _finishing
                    ? null
                    : () async {
                        if (_page < pages.length - 1) {
                          await _controller.nextPage(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOut,
                          );
                        } else {
                          await _finish();
                        }
                      },
                child: _finishing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _page == pages.length - 1
                            ? strings.text('onboardingAddFirst')
                            : strings.text('continueAction'),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 22),
              child: Text(
                strings.text('planningEstimateShort'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTareHelp(BuildContext context) {
    final strings = context.strings;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.text('tareHelpTitle')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/illustrations/tare_weight_guide.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '${strings.text('tareHelpBody')}\n\n'
                '${strings.text('tareHelpWc')}\n\n'
                '${strings.text('tareHelpActualCylinder')}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(strings.text('gotItAction')),
          ),
        ],
      ),
    );
  }
}
