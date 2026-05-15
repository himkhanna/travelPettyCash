import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/api/api_config.dart';
import '../../../core/api/api_error.dart';
import '../../../core/fake/fake_config.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/language_toggle_button.dart';
import '../application/auth_providers.dart';
import '../data/auth_repository.dart';
import '../domain/user.dart';

/// Real-backend login screen. Lives behind the "Sign in (API)" button on the
/// landing page and `/login`. The fake-mode role picker on the landing page
/// stays as the default demo path — this screen is only reachable once the
/// DevMenu has flipped BackendMode to api.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  bool _submitting = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final AuthRepository repo = ref.read(authRepositoryProvider);
      final AuthSession session = await repo.login(
        username: _username.text.trim(),
        password: _password.text,
      );
      // Mirror the FakeConfig.role so the existing routing reads the
      // user's role from the same place regardless of backend mode.
      ref.read(fakeConfigProvider).setRole(_roleFor(session.user.role));
      // Refresh /me-derived providers.
      ref.invalidate(currentUserProvider);
      if (!mounted) return;
      context.go(
        session.user.role == UserRole.admin || session.user.role == UserRole.superAdmin
            ? (session.user.role == UserRole.superAdmin ? '/cms/dg' : '/cms')
            : '/m/trips',
      );
    } on ApiError catch (e) {
      setState(() {
        _error = _messageFor(e);
        _submitting = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _submitting = false;
      });
    }
  }

  String _messageFor(ApiError e) {
    final AppLocalizations l = AppLocalizations.of(context);
    if (e.code == 'auth/invalid-credentials') {
      return l.auth_login_error_invalid_credentials;
    }
    if (e.code.startsWith('network/')) {
      return l.auth_login_error_network;
    }
    return '${e.title} — ${e.detail}';
  }

  FakeRole _roleFor(UserRole r) {
    switch (r) {
      case UserRole.member:
        return FakeRole.member;
      case UserRole.leader:
        return FakeRole.leader;
      case UserRole.admin:
        return FakeRole.admin;
      case UserRole.superAdmin:
        return FakeRole.superAdmin;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ApiConfig api = ref.watch(apiConfigProvider);

    return Scaffold(
      backgroundColor: AppColors.brandBrownDark,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          l.auth_login_title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            color: AppColors.cream,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          api.baseUrl,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.cream.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: AppColors.cream,
                            borderRadius: const BorderRadius.all(AppRadii.card),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              TextFormField(
                                controller: _username,
                                autofillHints: const <String>[AutofillHints.username],
                                textInputAction: TextInputAction.next,
                                enabled: !_submitting,
                                decoration: InputDecoration(
                                  labelText: l.auth_login_username,
                                  prefixIcon: const Icon(Icons.person_outline),
                                ),
                                validator: (String? v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? l.auth_login_username_required
                                        : null,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                controller: _password,
                                autofillHints: const <String>[AutofillHints.password],
                                obscureText: _obscure,
                                enabled: !_submitting,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: l.auth_login_password,
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (String? v) =>
                                    (v == null || v.isEmpty)
                                        ? l.auth_login_password_required
                                        : null,
                              ),
                              if (_error != null) ...<Widget>[
                                const SizedBox(height: AppSpacing.md),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.sm,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.outflow.withValues(alpha: 0.1),
                                    borderRadius: const BorderRadius.all(AppRadii.chip),
                                    border: Border.all(
                                      color: AppColors.outflow.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      Icon(
                                        Icons.error_outline,
                                        color: AppColors.outflow,
                                        size: 18,
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: TextStyle(color: AppColors.outflow),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.lg),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.brandBrown,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                onPressed: _submitting ? null : _submit,
                                child: _submitting
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.cream,
                                        ),
                                      )
                                    : Text(
                                        l.auth_login_submit,
                                        style: const TextStyle(
                                          color: AppColors.cream,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.4,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextButton(
                                onPressed: _submitting
                                    ? null
                                    : () => context.go('/'),
                                child: Text(l.auth_login_back_to_landing),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const PositionedDirectional(
              top: AppSpacing.md,
              end: AppSpacing.md,
              child: LanguageToggleButton(foregroundColor: AppColors.cream),
            ),
          ],
        ),
      ),
    );
  }
}
