import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_config.dart';

/// Hidden in production. Reachable via a long-press on the brand logo or
/// the corner of the phone-frame chrome in the web demo.
class DevMenu extends ConsumerWidget {
  const DevMenu({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext _) => const DevMenu(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FakeConfig cfg = ref.watch(fakeConfigProvider);
    return AnimatedBuilder(
      animation: cfg,
      builder: (BuildContext context, _) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Demo controls',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'These knobs simulate network conditions and role switching '
                  'while the backend is mocked.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Divider(height: 32),
                _LatencyControl(cfg: cfg),
                const SizedBox(height: 16),
                _FailureRateControl(cfg: cfg),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Offline mode'),
                  subtitle: const Text(
                    'Writes queue locally; sync resumes when toggled off.',
                  ),
                  value: cfg.offlineMode,
                  onChanged: (bool v) => cfg.setOfflineMode(value: v),
                ),
                const SizedBox(height: 16),
                _RoleControl(cfg: cfg),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LatencyControl extends StatelessWidget {
  const _LatencyControl({required this.cfg});
  final FakeConfig cfg;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Latency: ${cfg.latency.inMilliseconds}ms'),
        Slider(
          value: cfg.latency.inMilliseconds.toDouble(),
          min: 0,
          max: 2000,
          divisions: 20,
          label: '${cfg.latency.inMilliseconds}ms',
          onChanged: (double v) =>
              cfg.setLatency(Duration(milliseconds: v.round())),
        ),
      ],
    );
  }
}

class _FailureRateControl extends StatelessWidget {
  const _FailureRateControl({required this.cfg});
  final FakeConfig cfg;

  @override
  Widget build(BuildContext context) {
    final int percent = (cfg.failureRate * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Failure injection: $percent% of writes'),
        Slider(
          value: cfg.failureRate,
          min: 0,
          max: 1,
          divisions: 20,
          label: '$percent%',
          onChanged: cfg.setFailureRate,
        ),
      ],
    );
  }
}

class _RoleControl extends StatelessWidget {
  const _RoleControl({required this.cfg});
  final FakeConfig cfg;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Role'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final FakeRole r in FakeRole.values)
              if (r != FakeRole.unset)
                ChoiceChip(
                  label: Text(_roleLabel(r)),
                  selected: cfg.role == r,
                  onSelected: (_) => cfg.setRole(r),
                ),
          ],
        ),
      ],
    );
  }

  String _roleLabel(FakeRole r) {
    switch (r) {
      case FakeRole.member:
        return 'Member';
      case FakeRole.leader:
        return 'Leader';
      case FakeRole.admin:
        return 'Admin';
      case FakeRole.superAdmin:
        return 'DG';
      case FakeRole.unset:
        return 'Unset';
    }
  }
}
