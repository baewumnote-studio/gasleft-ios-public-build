import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../shared/section_card.dart';

class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('aboutSafety'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.text('safetyHowTitle'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(strings.text('safetyHowBody')),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.text('safetyTareWcTitle'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(strings.text('safetyTareWcBody')),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.text('safetyBoundaryTitle'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(strings.text('safetyBoundaryBody')),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              strings.text('privacyLocalBody'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
