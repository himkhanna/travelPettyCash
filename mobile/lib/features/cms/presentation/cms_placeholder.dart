import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/fake/fake_config.dart';

class CmsPlaceholder extends ConsumerWidget {
  const CmsPlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FakeConfig cfg = ref.watch(fakeConfigProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: Row(
          children: <Widget>[
            const Icon(Icons.shield_outlined, color: AppColors.brandBrown),
            const SizedBox(width: AppSpacing.sm),
            Text('PDD Petty Cash — Admin Console',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Center(
              child: Chip(label: Text(_roleLabel(cfg.role))),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.dashboard_customize_outlined,
                    size: 72, color: AppColors.goldOlive),
                const SizedBox(height: AppSpacing.md),
                Text('Admin Console',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Create trips, assign funds from source pools, generate signed '
                  'reports, and view the Director General overview. '
                  'Milestone D in the build plan.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _roleLabel(FakeRole r) =>
      r == FakeRole.superAdmin ? 'Director General' : 'Admin';
}
