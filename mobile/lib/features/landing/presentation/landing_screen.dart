import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/fake/fake_config.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';

/// Landing page at "/" — picks a role and routes into either the mobile UI
/// (rendered inside a phone frame) or the CMS web UI.
class LandingScreen extends ConsumerStatefulWidget {
  const LandingScreen({super.key});

  @override
  ConsumerState<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends ConsumerState<LandingScreen> {
  bool _signingIn = false;
  String? _signInError;

  @override
  Widget build(BuildContext context) {
    final FakeConfig cfg = ref.watch(fakeConfigProvider);

    return Scaffold(
      backgroundColor: AppColors.brandBrownDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _LandingHeader(),
                  const SizedBox(height: AppSpacing.lg),
                  _BackendToggle(
                    cfg: cfg,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _SectionLabel(text: 'Mobile App'.toUpperCase()),
                  const SizedBox(height: AppSpacing.md),
                  _RoleGrid(
                    onPick: (FakeRole r) => _enter(r, '/m/trips'),
                    roles: const <FakeRole>[
                      FakeRole.member,
                      FakeRole.leader,
                      FakeRole.admin,
                      FakeRole.superAdmin,
                    ],
                    target: _RoleTarget.mobile,
                    busy: _signingIn,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _SectionLabel(text: 'Admin Console (Web)'.toUpperCase()),
                  const SizedBox(height: AppSpacing.md),
                  _RoleGrid(
                    onPick: (FakeRole r) => _enter(
                      r,
                      r == FakeRole.superAdmin ? '/cms/dg' : '/cms',
                    ),
                    roles: const <FakeRole>[
                      FakeRole.admin,
                      FakeRole.superAdmin,
                    ],
                    target: _RoleTarget.cms,
                    busy: _signingIn,
                  ),
                  if (_signInError != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.outflow.withValues(alpha: 0.15),
                        borderRadius: const BorderRadius.all(AppRadii.chip),
                      ),
                      child: Text(
                        _signInError!,
                        style: const TextStyle(color: AppColors.cream),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  _DemoNotice(mode: cfg.backendMode),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _enter(FakeRole r, String path) async {
    final FakeConfig cfg = ref.read(fakeConfigProvider);
    setState(() {
      _signingIn = true;
      _signInError = null;
    });
    try {
      if (cfg.backendMode == BackendMode.http) {
        final UserRole role = switch (r) {
          FakeRole.member => UserRole.member,
          FakeRole.leader => UserRole.leader,
          FakeRole.admin => UserRole.admin,
          FakeRole.superAdmin => UserRole.superAdmin,
          FakeRole.unset => UserRole.member,
        };
        await ref.read(authRepositoryProvider).loginAsRole(role);
      } else {
        cfg.setRole(r);
      }
      if (!mounted) return;
      context.go(path);
    } catch (e) {
      setState(() {
        _signInError = 'Backend login failed: $e\n'
            'Is the Spring backend running at ${cfg.backendBaseUrl}? '
            'Switch to FAKE to use the in-memory demo instead.';
      });
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }
}

class _LandingHeader extends StatelessWidget {
  const _LandingHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'PDD Petty Cash',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: AppColors.cream,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Demo Console — pick a role to enter the prototype',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.cream.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: AppColors.goldOlive,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

enum _RoleTarget { mobile, cms }

class _RoleGrid extends StatelessWidget {
  const _RoleGrid({
    required this.roles,
    required this.onPick,
    required this.target,
    this.busy = false,
  });

  final List<FakeRole> roles;
  final ValueChanged<FakeRole> onPick;
  final _RoleTarget target;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: <Widget>[
        for (final FakeRole r in roles)
          _RoleCard(
            role: r,
            target: target,
            onTap: busy ? null : () => onPick(r),
          ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.target,
    required this.onTap,
  });
  final FakeRole role;
  final _RoleTarget target;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Material(
        color: AppColors.cream,
        borderRadius: const BorderRadius.all(AppRadii.card),
        child: InkWell(
          borderRadius: const BorderRadius.all(AppRadii.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(_iconFor(role), color: AppColors.brandBrown, size: 32),
                const SizedBox(height: AppSpacing.md),
                Text(
                  _roleLabel(role),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _seedNameFor(role),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  target == _RoleTarget.mobile
                      ? 'Mobile UI →'
                      : 'Admin Console →',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.brandBrown,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(FakeRole r) {
    switch (r) {
      case FakeRole.member:
        return Icons.person_outline;
      case FakeRole.leader:
        return Icons.workspace_premium_outlined;
      case FakeRole.admin:
        return Icons.admin_panel_settings_outlined;
      case FakeRole.superAdmin:
        return Icons.shield_outlined;
      case FakeRole.unset:
        return Icons.help_outline;
    }
  }

  String _roleLabel(FakeRole r) {
    switch (r) {
      case FakeRole.member:
        return 'Team Member';
      case FakeRole.leader:
        return 'Team Leader';
      case FakeRole.admin:
        return 'Admin';
      case FakeRole.superAdmin:
        return 'Director General';
      case FakeRole.unset:
        return '';
    }
  }

  String _seedNameFor(FakeRole r) {
    switch (r) {
      case FakeRole.member:
        return 'Ahmed Al Maktoum';
      case FakeRole.leader:
        return 'Fatima Al Hashimi';
      case FakeRole.admin:
        return 'Khalid Al Suwaidi';
      case FakeRole.superAdmin:
        return 'Noura Al Falasi';
      case FakeRole.unset:
        return '';
    }
  }
}

class _DemoNotice extends StatelessWidget {
  const _DemoNotice({required this.mode});
  final BackendMode mode;

  @override
  Widget build(BuildContext context) {
    final bool live = mode == BackendMode.http;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: AppColors.goldOlive.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            live ? Icons.cloud_done_outlined : Icons.info_outline,
            color: AppColors.goldOlive,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              live
                  ? 'Connected to the Spring backend. Trips, expenses, users, '
                      'and reports are read and written against PostgreSQL. '
                      'Chat, notifications, and offline queue still run on '
                      'in-memory mock data — those land in follow-up slices.'
                  : 'Running on in-memory mock data. Use the toggle above to '
                      'point the app at the Spring backend once it is running '
                      'locally (default http://localhost:8080).',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.cream,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackendToggle extends StatefulWidget {
  const _BackendToggle({required this.cfg, required this.onChanged});
  final FakeConfig cfg;
  final VoidCallback onChanged;

  @override
  State<_BackendToggle> createState() => _BackendToggleState();
}

class _BackendToggleState extends State<_BackendToggle> {
  late final TextEditingController _urlCtrl =
      TextEditingController(text: widget.cfg.backendBaseUrl);

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool live = widget.cfg.backendMode == BackendMode.http;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: AppColors.cream.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'BACKEND',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.goldOlive,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SegmentedButton<BackendMode>(
                segments: const <ButtonSegment<BackendMode>>[
                  ButtonSegment<BackendMode>(
                    value: BackendMode.fake,
                    label: Text('FAKE'),
                    icon: Icon(Icons.memory),
                  ),
                  ButtonSegment<BackendMode>(
                    value: BackendMode.http,
                    label: Text('HTTP'),
                    icon: Icon(Icons.cloud),
                  ),
                ],
                selected: <BackendMode>{widget.cfg.backendMode},
                onSelectionChanged: (Set<BackendMode> s) {
                  widget.cfg.setBackendMode(s.first);
                  widget.onChanged();
                },
              ),
            ],
          ),
          if (live) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    style: const TextStyle(color: AppColors.cream),
                    decoration: InputDecoration(
                      labelText: 'Backend base URL',
                      labelStyle: const TextStyle(color: AppColors.cream),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.cream.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    onSubmitted: (String v) {
                      widget.cfg.setBackendBaseUrl(v);
                      widget.onChanged();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(
                  onPressed: () {
                    widget.cfg.setBackendBaseUrl(_urlCtrl.text);
                    widget.onChanged();
                  },
                  child: const Text('APPLY'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
