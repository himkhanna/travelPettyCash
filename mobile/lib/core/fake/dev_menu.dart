import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_config.dart';
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
    final ApiConfig api = ref.watch(apiConfigProvider);
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[cfg, api]),
      builder: (BuildContext context, _) {
        return SafeArea(
          child: SingleChildScrollView(
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
                  'These knobs simulate network conditions, switch between '
                  'fake and real backends, and let you change role on the fly.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Divider(height: 32),
                _BackendControl(api: api),
                const SizedBox(height: 16),
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

class _BackendControl extends StatefulWidget {
  const _BackendControl({required this.api});
  final ApiConfig api;

  @override
  State<_BackendControl> createState() => _BackendControlState();
}

class _BackendControlState extends State<_BackendControl> {
  late final TextEditingController _baseUrl =
      TextEditingController(text: widget.api.baseUrl);

  @override
  void dispose() {
    _baseUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Backend'),
        const SizedBox(height: 8),
        SegmentedButton<BackendMode>(
          segments: const <ButtonSegment<BackendMode>>[
            ButtonSegment<BackendMode>(
              value: BackendMode.fake,
              label: Text('Fake'),
              icon: Icon(Icons.dataset_outlined),
            ),
            ButtonSegment<BackendMode>(
              value: BackendMode.api,
              label: Text('API'),
              icon: Icon(Icons.cloud_outlined),
            ),
          ],
          selected: <BackendMode>{widget.api.mode},
          onSelectionChanged: (Set<BackendMode> set) =>
              widget.api.setMode(set.first),
        ),
        if (widget.api.mode == BackendMode.api) ...<Widget>[
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrl,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Base URL',
              hintText: 'http://localhost:8080',
            ),
            onSubmitted: widget.api.setBaseUrl,
          ),
          const SizedBox(height: 4),
          Text(
            'Press enter to save. /api/v1/* paths are appended automatically.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
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
