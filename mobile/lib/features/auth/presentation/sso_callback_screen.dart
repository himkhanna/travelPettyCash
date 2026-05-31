import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/auth/token_store.dart';
import '../application/auth_providers.dart';
import '../domain/user.dart';
import 'login_screen.dart';

/// Landing page for the OIDC round-trip from Dubai-Gov / Smart Dubai.
///
/// The backend's `/api/v1/auth/sso/callback` exchanges the IdP code,
/// mints our own JWT pair, and 302s the browser here with a
/// short-lived one-time `code` query param. This screen:
///
///   1. Reads the code from the URL.
///   2. POSTs to `/api/v1/auth/sso/exchange` to swap it for the JWTs.
///   3. Stows them via [tokenStoreProvider].
///   4. Invalidates [currentUserProvider] and routes to the audience's
///      home path.
///
/// Mounted at `/app/auth/callback` (mobile audience) and
/// `/portal/auth/callback` (admin audience). See ADR-001.
class SsoCallbackScreen extends ConsumerStatefulWidget {
  const SsoCallbackScreen({super.key, required this.audience});
  final PortalAudience audience;

  @override
  ConsumerState<SsoCallbackScreen> createState() =>
      _SsoCallbackScreenState();
}

class _SsoCallbackScreenState extends ConsumerState<SsoCallbackScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final String? code = GoRouterState.of(context).uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      setState(() => _error = 'Missing exchange code in the callback URL.');
      return;
    }
    try {
      final Dio dio = ref.read(dioProvider);
      final Response<dynamic> resp = await dio.post<dynamic>(
        '/api/v1/auth/sso/exchange',
        data: <String, dynamic>{'code': code},
      );
      final Map<String, dynamic> body =
          resp.data as Map<String, dynamic>;
      final Map<String, dynamic> tokens =
          body['tokens'] as Map<String, dynamic>;
      final Map<String, dynamic> me =
          body['user'] as Map<String, dynamic>;

      // Stow tokens via the existing TokenStore so the rest of the app
      // is unaware that auth happened via SSO instead of password.
      final TokenStore store = ref.read(tokenStoreProvider);
      await store.write(AuthTokens(
        accessToken: tokens['accessToken'] as String,
        refreshToken: tokens['refreshToken'] as String,
      ));

      // Refresh /me-derived providers so downstream watchers see the
      // freshly minted session.
      ref.invalidate(currentUserProvider);

      // Land the user on the right home for their portal. Honour the
      // wrong-portal guard: if a Member tries to land at /portal we
      // bounce them to /app and vice versa.
      if (!mounted) return;
      final UserRole role = UserRole.fromApiCode(me['role'] as String);
      final PortalAudience effective = widget.audience.accepts(role)
          ? widget.audience
          : widget.audience.other;
      GoRouter.of(context).go(effective.homePath);
    } on DioException catch (e) {
      setState(() => _error =
          'Exchange failed (${e.response?.statusCode ?? 'no response'}): '
          '${e.message ?? 'unknown error'}.');
    } catch (e) {
      setState(() => _error = 'Unexpected error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _error == null
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircularProgressIndicator(),
                      SizedBox(height: 18),
                      Text(
                        'Signing you in via Dubai Gov…',
                        style: TextStyle(
                          color: AppColors.ink2,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Icon(
                        Icons.error_outline,
                        size: 44,
                        color: AppColors.red,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sign-in did not complete',
                        textAlign: TextAlign.center,
                        style: AppTypography.geist(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: AppTypography.geist(
                          fontSize: 12,
                          color: AppColors.ink3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => GoRouter.of(context)
                            .go(widget.audience.loginPath),
                        child: const Text('BACK TO SIGN IN'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
