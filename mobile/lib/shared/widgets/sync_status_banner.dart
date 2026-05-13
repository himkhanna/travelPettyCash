import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/fake/fake_config.dart';
import '../../core/sync/sync_coordinator.dart';

/// Thin colored strip surfaced on dashboard + expenses screens to signal
/// offline mode and active sync. Sits above the bottom nav.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FakeConfig cfg = ref.watch(fakeConfigProvider);
    final SyncState s = ref.watch(syncStateProvider);

    if (cfg.offlineMode) {
      return _Banner(
        color: AppColors.warning,
        icon: Icons.cloud_off,
        label: s.pendingCount > 0
            ? 'Offline — ${s.pendingCount} pending'
            : 'Offline mode',
      );
    }

    if (s.isSyncing) {
      return _Banner(
        color: AppColors.brandBrown,
        icon: Icons.sync,
        label:
            'Syncing ${s.pendingCount} expense${s.pendingCount == 1 ? '' : 's'}…',
      );
    }

    if (s.lastError != null) {
      return _Banner(
        color: AppColors.outflow,
        icon: Icons.error_outline,
        label: 'Sync failed — ${s.lastError}',
      );
    }

    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.label});

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      color: color.withValues(alpha: 0.12),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
