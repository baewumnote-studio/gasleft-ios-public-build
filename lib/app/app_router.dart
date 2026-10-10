import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_strings.dart';
import '../features/add_reading/add_reading_screen.dart';
import '../features/add_reading/reading_result_screen.dart';
import '../features/bootstrap/bootstrap_screen.dart';
import '../features/cylinder_detail/cylinder_detail_screen.dart';
import '../features/cylinder_form/cylinder_form_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/safety/safety_screen.dart';
import '../features/settings/settings_screen.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/bootstrap',
    routes: [
      GoRoute(path: '/bootstrap', builder: (_, _) => const BootstrapScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/cylinder/new',
        builder: (_, state) => CylinderFormScreen(
          first: state.uri.queryParameters['first'] == '1',
        ),
      ),
      GoRoute(
        path: '/cylinder/:id',
        builder: (_, state) =>
            CylinderDetailScreen(cylinderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/cylinder/:id/edit',
        builder: (_, state) =>
            CylinderFormScreen(cylinderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/cylinder/:id/replace',
        builder: (_, state) => CylinderFormScreen(
          cylinderId: state.pathParameters['id']!,
          replace: true,
        ),
      ),
      GoRoute(
        path: '/cylinder/:id/read',
        builder: (_, state) => AddReadingScreen(
          cylinderId: state.pathParameters['id']!,
          readingId: state.uri.queryParameters['readingId'],
          first: state.uri.queryParameters['first'] == '1',
          replacement: state.uri.queryParameters['replacement'] == '1',
        ),
      ),
      GoRoute(
        path: '/reading-result',
        builder: (_, state) {
          final extra = state.extra;
          return extra is ReadingResultArgs
              ? ReadingResultScreen(args: extra)
              : const HomeScreen();
        },
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/safety', builder: (_, _) => const SafetyScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: Center(child: Text(context.strings.text('pageNotFound'))),
    ),
  );
}
