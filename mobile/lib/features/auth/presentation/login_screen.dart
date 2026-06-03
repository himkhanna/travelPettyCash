// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/api/api_config.dart';
import '../../../core/api/api_error.dart';
import '../../../core/api/hydration_service.dart';
import '../../../core/fake/fake_config.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/language_toggle_button.dart';
import '../application/auth_providers.dart';
import '../data/auth_config_repository.dart';
import '../data/auth_repository.dart';
import '../domain/user.dart';

/// Which portal the user is signing into. Each portal accepts a different
/// subset of roles; cross-portal sign-in (e.g. an Admin logging in at /app)
/// is rejected with a hint that points to the right portal.
enum PortalAudience {
  /// Phone app for field officers — Member + Leader only.
  mobileApp,

  /// Web admin console for HQ staff — Admin + Super Admin only.
  webAdmin,
}

extension PortalAudienceX on PortalAudience {
  bool accepts(UserRole r) {
    switch (this) {
      case PortalAudience.mobileApp:
        return r == UserRole.member || r == UserRole.leader;
      case PortalAudience.webAdmin:
        return r == UserRole.admin || r == UserRole.superAdmin;
    }
  }

  String get homePath {
    switch (this) {
      case PortalAudience.mobileApp:
        return '/m/trips';
      case PortalAudience.webAdmin:
        return '/cms';
    }
  }

  PortalAudience get other => this == PortalAudience.mobileApp
      ? PortalAudience.webAdmin
      : PortalAudience.mobileApp;

  String get loginPath => switch (this) {
        PortalAudience.mobileApp => '/app',
        PortalAudience.webAdmin => '/portal',
      };
}

/// Real-backend login screen. Two entry points: `/portal` (admin console)
/// and `/app` (phone app for field officers). Each only accepts the role
/// subset its portal serves — see [PortalAudience].
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    this.audience = PortalAudience.mobileApp,
    this.prefillUsername,
  });

  final PortalAudience audience;

  /// Optional username to seed the form with. Used when the other portal
  /// redirects a wrong-portal sign-in attempt so the user doesn't have to
  /// retype it.
  final String? prefillUsername;

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

  /// When non-null, the credentials matched a valid user whose role belongs
  /// to the *other* portal. The error panel then renders a one-tap button
  /// that navigates to the correct portal.
  PortalAudience? _redirectTo;

  @override
  void initState() {
    super.initState();
    if (widget.prefillUsername != null &&
        widget.prefillUsername!.trim().isNotEmpty) {
      _username.text = widget.prefillUsername!.trim();
    }
  }

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
      _redirectTo = null;
    });
    try {
      final AuthRepository repo = ref.read(authRepositoryProvider);
      final AuthSession session = await repo.login(
        username: _username.text.trim(),
        password: _password.text,
      );
      // Role gate: each portal only accepts its audience. If a Member signs
      // in at /portal or an Admin at /app, drop the session and surface a
      // pointer to the right portal — never silently bounce them.
      if (!widget.audience.accepts(session.user.role)) {
        await repo.logout();
        if (!mounted) return;
        final bool roleIsAdmin =
            session.user.role == UserRole.admin ||
                session.user.role == UserRole.superAdmin;
        setState(() {
          _redirectTo = roleIsAdmin
              ? PortalAudience.webAdmin
              : PortalAudience.mobileApp;
          _error = _wrongPortalMessage(session.user.role);
          _submitting = false;
        });
        return;
      }
      // Mirror the FakeConfig.role so the existing routing reads the
      // user's role from the same place regardless of backend mode.
      ref.read(fakeConfigProvider).setRole(_roleFor(session.user.role));
      // Pull every dataset the UI reads from DemoStore into the cache so
      // post-login screens (trip list, dashboards, allocate/transfer
      // pickers, chat, notifications) all render against backend data.
      await ref.read(hydrationServiceProvider).hydrateAll();
      // Refresh /me-derived providers.
      ref.invalidate(currentUserProvider);
      if (!mounted) return;
      // Director General lands on the DG read-only view; everyone else goes
      // to their portal's default home.
      final String dest = session.user.role == UserRole.superAdmin
          ? '/cms/dg'
          : widget.audience.homePath;
      context.go(dest);
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

  String _wrongPortalMessage(UserRole role) {
    final String roleName = switch (role) {
      UserRole.member => 'Team Member',
      UserRole.leader => 'Team Leader',
      UserRole.admin => 'Admin',
      UserRole.superAdmin => 'Director General',
    };
    final bool roleIsAdmin =
        role == UserRole.admin || role == UserRole.superAdmin;
    if (roleIsAdmin) {
      return 'This account ($roleName) belongs to the Admin Portal. '
          'Tap below to switch.';
    }
    return 'This account ($roleName) belongs to the Mobile App. '
        'Tap below to switch.';
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
                          widget.audience == PortalAudience.webAdmin
                              ? 'Admin Portal · لوحة الإدارة'
                              : 'Mobile App · تطبيق الميدان',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.goldOlive,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
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
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  decoration: BoxDecoration(
                                    color: _redirectTo != null
                                        ? AppColors.warning.withValues(alpha: 0.12)
                                        : AppColors.outflow.withValues(alpha: 0.1),
                                    borderRadius:
                                        const BorderRadius.all(AppRadii.chip),
                                    border: Border.all(
                                      color: _redirectTo != null
                                          ? AppColors.warning.withValues(alpha: 0.5)
                                          : AppColors.outflow.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Icon(
                                            _redirectTo != null
                                                ? Icons.swap_horiz_outlined
                                                : Icons.error_outline,
                                            color: _redirectTo != null
                                                ? AppColors.brandBrownDark
                                                : AppColors.outflow,
                                            size: 18,
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          Expanded(
                                            child: Text(
                                              _error!,
                                              style: TextStyle(
                                                color: _redirectTo != null
                                                    ? AppColors.brandBrownDark
                                                    : AppColors.outflow,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_redirectTo != null) ...<Widget>[
                                        const SizedBox(height: AppSpacing.sm),
                                        FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                AppColors.brandBrown,
                                            foregroundColor: AppColors.cream,
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    vertical: 12),
                                          ),
                                          icon: const Icon(Icons.arrow_forward),
                                          label: Text(
                                            _redirectTo == PortalAudience.webAdmin
                                                ? 'GO TO ADMIN PORTAL'
                                                : 'GO TO MOBILE APP',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                          onPressed: () {
                                            // Pre-fill the username so the
                                            // user doesn't retype it on the
                                            // correct portal.
                                            final String u = _username.text.trim();
                                            context.go(
                                              '${_redirectTo!.loginPath}'
                                              '${u.isEmpty ? '' : '?u=$u'}',
                                            );
                                          },
                                        ),
                                      ],
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
                              // "Sign in with Dubai Gov" — rendered
                              // only when the backend's /auth/config
                              // probe says SSO is wired up. See
                              // docs/architecture/ADR-001-dda-sso.md.
                              _DubaiGovSsoButton(
                                audience: widget.audience,
                                disabled: _submitting,
                              ),
                              _UaePassSsoButton(
                                audience: widget.audience,
                                disabled: _submitting,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextButton(
                                onPressed: _submitting
                                    ? null
                                    : () => context.go(widget.audience.other.loginPath),
                                child: Text(
                                  widget.audience == PortalAudience.mobileApp
                                      ? 'Switch to Admin Portal'
                                      : 'Switch to Mobile App',
                                ),
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

/// "Sign in with Dubai Gov" button. Watches [authConfigProvider]; if the
/// backend reports SSO is disabled (or the probe failed), renders an
/// empty SizedBox. Otherwise opens a top-level navigation to the
/// backend's `/auth/sso/start` URL, which 302s to Smart Dubai's
/// authorize page and (on success) bounces back to the SsoCallbackScreen
/// route for the matching audience.
class _DubaiGovSsoButton extends ConsumerWidget {
  const _DubaiGovSsoButton({
    required this.audience,
    required this.disabled,
  });
  final PortalAudience audience;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AuthConfig> cfg = ref.watch(authConfigProvider);
    final bool show = cfg.maybeWhen(
      data: (AuthConfig c) => c.dubaiGovSsoEnabled,
      orElse: () => false,
    );
    if (!show) return const SizedBox.shrink();

    final String audienceParam = switch (audience) {
      PortalAudience.mobileApp => 'mobileWeb',
      PortalAudience.webAdmin => 'portal',
    };
    // Same-origin navigation so the cookies / redirect state stay
    // attached. On Flutter Web `context.go` would try to handle the
    // /api path inside the SPA router — which has no match — so we
    // use a hard window-location nav via the platform's URL launcher.
    // For now the simplest approach: build the absolute URL and use
    // `window.location.assign` via a tiny dart:html shim. The API
    // base is configured in ApiConfig so it picks up overrides.
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: OutlinedButton.icon(
        onPressed: disabled
            ? null
            : () => _navigateToStart(ref, audienceParam),
        icon: const Icon(Icons.shield_outlined, size: 18),
        label: const Text('SIGN IN WITH DUBAI GOV'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brand,
          side: const BorderSide(color: AppColors.brand),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  void _navigateToStart(WidgetRef ref, String audienceParam) {
    final String base = ref.read(apiConfigProvider).baseUrl;
    final String url =
        '$base/api/v1/auth/sso/start?audience=$audienceParam';
    // Hard navigation — let the browser follow the IdP redirect chain.
    // Web-only path; see ADR-001 + the v1 PWA-only decision.
    html.window.location.href = url;
  }
}

/// "Sign in with UAE Pass" button. Same shape as [_DubaiGovSsoButton] but
/// probes [authConfigProvider].uaePassSsoEnabled and starts the UAE Pass
/// flow at `/auth/sso/uaepass/start`. See ADR-002.
class _UaePassSsoButton extends ConsumerWidget {
  const _UaePassSsoButton({
    required this.audience,
    required this.disabled,
  });
  final PortalAudience audience;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AuthConfig> cfg = ref.watch(authConfigProvider);
    final bool show = cfg.maybeWhen(
      data: (AuthConfig c) => c.uaePassSsoEnabled,
      orElse: () => false,
    );
    if (!show) return const SizedBox.shrink();

    final String audienceParam = switch (audience) {
      PortalAudience.mobileApp => 'mobileWeb',
      PortalAudience.webAdmin => 'portal',
    };
    // Official UAE PASS sign-in button — the exact "Outline Pill" artwork
    // used on sso.dubai.gov.ae (TDRA brand asset). Rendering the official
    // image guarantees brand compliance. AR variant swaps in for Arabic.
    final bool isArabic = Directionality.of(context) == TextDirection.rtl;
    final String asset = isArabic
        ? 'assets/uaepass/uaepass_signin_ar.png'
        : 'assets/uaepass/uaepass_signin.png';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Center(
        child: Semantics(
          button: true,
          label: 'Sign in with UAE PASS',
          child: Opacity(
            opacity: disabled ? 0.5 : 1.0,
            child: InkWell(
              onTap:
                  disabled ? null : () => _navigateToStart(ref, audienceParam),
              borderRadius: BorderRadius.circular(27),
              child: Image.asset(
                asset,
                height: 48,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToStart(WidgetRef ref, String audienceParam) {
    final String base = ref.read(apiConfigProvider).baseUrl;
    final String url =
        '$base/api/v1/auth/sso/uaepass/start?audience=$audienceParam';
    html.window.location.href = url;
  }
}

