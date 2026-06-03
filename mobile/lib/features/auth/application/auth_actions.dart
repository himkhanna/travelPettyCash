import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import 'auth_providers.dart';

/// Clears the auth tokens, drops cached user state, and routes the user
/// back to the login screen.
///
/// [redirect] is the path to land on after sign-out. Defaults to `/app`
/// for the mobile flow; pass `/portal` for the admin CMS so the admin
/// doesn't bounce through the role-picker landing page.
///
/// Returns the choice the user made — null if they dismissed the dialog.
Future<bool?> confirmAndSignOut(
  BuildContext context,
  WidgetRef ref, {
  String redirect = '/app',
}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext _) => AlertDialog(
      title: const Text('Sign out?'),
      content: const Text(
        'You will need to sign in again to access trips and balances.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('SIGN OUT'),
        ),
      ],
    ),
  );
  if (ok != true) return ok;
  // Always navigate, even if the server-side logout fails. The local
  // token store and provider cache are still wiped in the finally
  // block, so the user is functionally signed out regardless. The
  // earlier code awaited the network call first — when CORS, a 401,
  // or a flaky LAN connection threw, the await aborted and
  // context.go never ran, leaving the user stuck on /m/trips.
  try {
    await ref.read(authRepositoryProvider).logout();
  } catch (_) {
    // Best-effort: token revocation on the server failed but we're
    // signing out locally regardless. Surfacing the error would
    // require keeping the user on the screen — that's worse UX.
  }
  // Clear the cached user FIRST, while this widget's ref is still alive.
  // The previous version deferred this to a post-frame callback that ran
  // after navigation — but by then the calling widget (and its ref) was
  // often already disposed, so the invalidate silently no-op'd and
  // currentUserProvider stayed cached as the signed-out user. With the
  // user cleared here, the router's auth gate redirects any /m/* route to
  // /app, so logout lands on the login screen even if the context.go
  // below is skipped on an unmounted context (the bug that left the user
  // stranded on a stale /m/trips). Home screens read the user null-safely,
  // so an extra null frame before navigation is harmless.
  ref.invalidate(currentUserProvider);
  if (context.mounted) {
    GoRouter.of(context).go(redirect);
  }
  return true;
}
