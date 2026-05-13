import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/fake/dev_menu.dart';
import '../../../core/fake/fake_config.dart';

/// Phase 0 placeholder. Real Trips Home (screen-inventory #2) lands in
/// Milestone A.
class TripsHomePlaceholder extends ConsumerWidget {
  const TripsHomePlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FakeConfig cfg = ref.watch(fakeConfigProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: const Text('PDD Petty Cash'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Demo controls',
            onPressed: () => DevMenu.show(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Hello',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              _greetingName(cfg.role),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Active Trips',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    letterSpacing: 1.4,
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Expanded(
              child: Center(
                child: _MilestoneAComingSoon(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _greetingName(FakeRole role) {
    switch (role) {
      case FakeRole.member:
        return 'AHMED';
      case FakeRole.leader:
        return 'FATIMA';
      case FakeRole.admin:
        return 'KHALID';
      case FakeRole.superAdmin:
        return 'NOURA';
      case FakeRole.unset:
        return 'DEMO';
    }
  }
}

class _MilestoneAComingSoon extends StatelessWidget {
  const _MilestoneAComingSoon();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.flight_takeoff, size: 64, color: AppColors.goldOlive),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Trips Home',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            'Milestone A lands the real trip cards + dashboard. '
            'Phase 0 verifies the shell boots, role switching works, '
            'and demo controls open.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ),
      ],
    );
  }
}
