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
  await ref.read(authRepositoryProvider).logout();
  // Navigate FIRST. Both `context.go` and `ref.invalidate` schedule
  // work for the next frame, and Riverpod typically wins the race —
  // which rebuilds the current /m/trips screen with a null user
  // before GoRouter unmounts it, leaving the URL stuck at /m/trips.
  // Defer the invalidate to a post-frame callback so it only fires
  // after the new route (LoginScreen at /app) has rendered.
  if (context.mounted) {
    context.go(redirect);
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Drop the cached User so any inflight watcher sees null;
    // downstream providers (trips, notifications, balances) re-fetch
    // and short-circuit when the user comes back as null. Safe to
    // call from a callback — Riverpod tolerates async invalidate.
    ref.invalidate(currentUserProvider);
  });
  return true;
}
