import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/connectivity/offline_screen.dart';
import '../core/connectivity/offline_status_provider.dart';
import '../features/auth/application/auth_providers.dart';
import '../features/auth/domain/user.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/sso_callback_screen.dart';
import '../features/audit/presentation/cms_audit_screen.dart';
import '../features/auth/presentation/wrong_portal_screen.dart';
import '../features/cms/presentation/cms_dashboard.dart';
import '../features/cms/presentation/cms_expenses_screen.dart';
import '../features/cms/presentation/cms_missions_screen.dart';
import '../features/cms/presentation/cms_expense_detail_screen.dart';
import '../features/cms/presentation/cms_reports_screen.dart';
import '../features/cms/presentation/cms_settings_screen.dart';
import '../features/cms/presentation/cms_trip_detail_screen.dart';
import '../features/cms/presentation/cms_trips_screen.dart';
import '../features/cms/presentation/dg_dashboard.dart';
import '../features/cms/presentation/users_screen.dart';
import '../features/expenses/presentation/add_expense_screen.dart';
import '../features/expenses/presentation/expense_breakdown_screen.dart';
import '../features/expenses/presentation/expense_detail_screen.dart';
import '../features/chat/presentation/chat_thread_screen.dart';
import '../features/chat/presentation/chats_list_screen.dart';
import '../features/expenses/presentation/my_expenses_screen.dart';
import '../features/expenses/presentation/trip_expense_breakdown_screen.dart';
import '../features/expenses/presentation/trip_expenses_screen.dart';
import '../features/funds/presentation/allocate_funds_screen.dart';
import '../features/funds/presentation/manage_funds_screen.dart';
import '../features/funds/presentation/transfer_screen.dart';
import '../features/landing/presentation/landing_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/trips/presentation/trip_dashboard_screen.dart';
import '../features/trips/presentation/trip_profile_screen.dart';
import '../features/trips/presentation/trips_home_screen.dart';
import '../features/trips/presentation/trips_list_screen.dart';
import '../features/cms/presentation/cms_mission_detail_screen.dart';
import '../shared/widgets/phone_viewport.dart';

/// Listens to [offlineStatusProvider] so GoRouter can re-evaluate its
/// redirect when the device goes online / offline (or the Demo Controls
/// toggle flips). Without this the redirect would only fire on
/// navigation, so a user already sitting on /m/trips when the network
/// dies would just see stale cached data instead of the offline screen.
class _RouterRefreshNotifier extends ChangeNotifier {
  void poke() => notifyListeners();
}

final _RouterRefreshNotifier _routerRefreshNotifier =
    _RouterRefreshNotifier();

/// Public hook the PddApp widget uses to plumb the offline-status
/// stream + the current-user stream into GoRouter. Called from
/// `app.dart`'s build. Both signals re-evaluate the redirect: the
/// offline one for connectivity gating, the auth one so logout
/// bounces /m/* routes to /app even if the caller forgot to navigate.
void wireOfflineRefresh(WidgetRef ref) {
  ref.listen<AsyncValue<bool>>(
    offlineStatusProvider,
    (_, __) => _routerRefreshNotifier.poke(),
  );
  ref.listen<AsyncValue<User?>>(
    currentUserProvider,
    (_, __) => _routerRefreshNotifier.poke(),
  );
}

/// Path patterns that stay accessible even while offline:
///   - `/`, `/login`, `/portal`, `/app`, `/wrong-portal` — auth surfaces
///   - `/m/offline` itself
///   - `/m/trips/:id/expenses/new` — Add Expense queues drafts locally
///   - every `/cms/...` route — CMS is admin-only and runs in the same
///     bundle but on a different network context; gating it here would
///     be aggressive.
bool _routeAllowedOffline(String location) {
  if (location == '/' ||
      location == '/login' ||
      location.startsWith('/portal') ||
      location.startsWith('/app') ||
      location.startsWith('/wrong-portal')) {
    return true;
  }
  if (location.startsWith('/m/offline')) return true;
  if (location.startsWith('/cms/') || location == '/cms') return true;
  // Add Expense — match `/m/trips/:tripId/expenses/new` with optional
  // trailing query.
  if (RegExp(r'^/m/trips/[^/]+/expenses/new(\?.*)?$')
      .hasMatch(location)) {
    return true;
  }
  return false;
}

GoRouter buildAppRouter(WidgetRef ref) {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    refreshListenable: _routerRefreshNotifier,
    redirect: (BuildContext context, GoRouterState state) {
      final String loc = state.uri.toString();
      if (_routeAllowedOffline(loc)) return null;
      // Only mobile (`/m/...`) routes are gated. CMS already exits via
      // the allow-list above.
      if (!loc.startsWith('/m/')) return null;
      // Auth gate — if currentUserProvider has settled and we have no
      // user, bounce to /app. Catches the case where the logout
      // helper's context.go didn't fire (race or thrown exception)
      // and the user would otherwise sit on a /m/* page with no user.
      final AsyncValue<User?> userAsync = ref.read(currentUserProvider);
      if (userAsync is AsyncData<User?> && userAsync.value == null) {
        return '/app';
      }
      // Offline gate.
      final bool offline = ref.read(isOfflineProvider);
      return offline ? '/m/offline' : null;
    },
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, __) => const LandingScreen()),

      // Dedicated entry paths — each only accepts a specific role audience.
      // Optional ?u=<username> query param pre-fills the username field, used
      // when the other portal redirects a wrong-portal sign-in attempt.
      GoRoute(
        path: '/app',
        builder: (BuildContext context, GoRouterState state) => LoginScreen(
          audience: PortalAudience.mobileApp,
          prefillUsername: state.uri.queryParameters['u'],
        ),
      ),
      GoRoute(
        path: '/portal',
        builder: (BuildContext context, GoRouterState state) => LoginScreen(
          audience: PortalAudience.webAdmin,
          prefillUsername: state.uri.queryParameters['u'],
        ),
      ),
      // OIDC callbacks — the backend 302s the browser here after the
      // user finishes signing in with Dubai-Gov. The screen reads the
      // one-time `code` query param and swaps it for our own JWT pair.
      // ADR-001 (docs/architecture/ADR-001-dda-sso.md).
      GoRoute(
        path: '/app/auth/callback',
        builder: (BuildContext context, GoRouterState state) =>
            const SsoCallbackScreen(audience: PortalAudience.mobileApp),
      ),
      GoRoute(
        path: '/portal/auth/callback',
        builder: (BuildContext context, GoRouterState state) =>
            const SsoCallbackScreen(audience: PortalAudience.webAdmin),
      ),
      // UAE Pass callbacks (ADR-002) — same screen, but the exchange hits
      // the UAE-Pass-specific endpoint.
      GoRoute(
        path: '/app/auth/uaepass/callback',
        builder: (BuildContext context, GoRouterState state) =>
            const SsoCallbackScreen(
          audience: PortalAudience.mobileApp,
          exchangePath: '/api/v1/auth/sso/uaepass/exchange',
        ),
      ),
      GoRoute(
        path: '/portal/auth/uaepass/callback',
        builder: (BuildContext context, GoRouterState state) =>
            const SsoCallbackScreen(
          audience: PortalAudience.webAdmin,
          exchangePath: '/api/v1/auth/sso/uaepass/exchange',
        ),
      ),
      // Back-compat: the old single /login URL bounces to /portal (the more
      // common reason to hit this route directly is bookmarked admin links).
      GoRoute(
        path: '/login',
        redirect: (_, __) => '/portal',
      ),
      // 403-style page when role doesn't match portal — see WrongPortalScreen.
      GoRoute(
        path: '/wrong-portal',
        builder: (BuildContext context, GoRouterState state) =>
            WrongPortalScreen(
          expected: state.uri.queryParameters['expected'] == 'mobileApp'
              ? PortalAudience.mobileApp
              : PortalAudience.webAdmin,
        ),
      ),

      // Mobile UI — rendered inside a phone-frame on web (>=600px).
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) =>
            PhoneViewport(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: '/m/trips',
            builder: (_, __) => const TripsHomeScreen(),
          ),
          GoRoute(
            path: '/m/all-trips',
            builder: (_, __) => const TripsListScreen(),
          ),
          GoRoute(
            path: '/m/trips/:id/dashboard',
            builder: (BuildContext context, GoRouterState state) =>
                TripDashboardScreen(tripId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/m/trips/:id/expenses/mine',
            builder: (BuildContext context, GoRouterState state) =>
                MyExpensesScreen(tripId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/m/trips/:id/expenses/mine/chart',
            builder: (BuildContext context, GoRouterState state) =>
                ExpenseBreakdownScreen(tripId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/m/trips/:id/expenses/all',
            builder: (BuildContext context, GoRouterState state) =>
                TripExpensesScreen(tripId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/m/trips/:id/expenses/all/chart',
            builder: (BuildContext context, GoRouterState state) =>
                TripExpenseBreakdownScreen(
                  tripId: state.pathParameters['id']!,
                ),
          ),
          GoRoute(
            path: '/m/trips/:id/expenses/new',
            builder: (BuildContext context, GoRouterState state) =>
                AddExpenseScreen(tripId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/m/trips/:tripId/expenses/:expenseId',
            builder: (BuildContext context, GoRouterState state) =>
                ExpenseDetailScreen(
                  tripId: state.pathParameters['tripId']!,
                  expenseId: state.pathParameters['expenseId']!,
                ),
          ),
          GoRoute(
            path: '/m/trips/:id/transfer',
            builder: (BuildContext context, GoRouterState state) =>
                TransferScreen(tripId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/m/trips/:id/profile',
            builder: (BuildContext context, GoRouterState state) =>
                TripProfileScreen(tripId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/m/trips/:id/chat',
            builder: (BuildContext context, GoRouterState state) =>
                ChatsListScreen(tripId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/m/trips/:tripId/chat/:threadId',
            builder: (BuildContext context, GoRouterState state) =>
                ChatThreadScreen(
                  tripId: state.pathParameters['tripId']!,
                  threadId: state.pathParameters['threadId']!,
                ),
          ),
          GoRoute(
            path: '/m/trips/:id/manage-funds',
            builder: (BuildContext context, GoRouterState state) =>
                ManageFundsScreen(tripId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/m/trips/:id/allocate',
            builder: (BuildContext context, GoRouterState state) =>
                AllocateFundsScreen(tripId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/m/notifications',
            builder: (_, __) => const NotificationsScreen(),
          ),
          // Global chat list — every thread for the current user across all
          // trips. Reached from the Profile menu; trip-scoped chat still
          // lives under /m/trips/:id/chat.
          GoRoute(
            path: '/m/chat',
            builder: (_, __) => const ChatsListScreen(),
          ),
          // Offline destination — every gated /m route redirects here
          // when isOfflineProvider returns true. Stays inside the
          // PhoneViewport so it reads as part of the same shell.
          GoRoute(
            path: '/m/offline',
            builder: (_, __) => const OfflineScreen(),
          ),
        ],
      ),

      // CMS — full-width Flutter Web UI for Admin / Super Admin.
      GoRoute(path: '/cms', builder: (_, __) => const CmsDashboard()),
      GoRoute(
        path: '/cms/trips',
        builder: (_, __) => const CmsTripsScreen(),
      ),
      GoRoute(
        path: '/cms/trips/:id',
        builder: (BuildContext context, GoRouterState state) =>
            CmsTripDetailScreen(tripId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/cms/missions',
        builder: (_, __) => const CmsMissionsScreen(),
      ),
      GoRoute(
        path: '/cms/missions/:id',
        builder: (BuildContext context, GoRouterState state) =>
            CmsMissionDetailScreen(
              missionId: state.pathParameters['id']!,
            ),
      ),
      GoRoute(
        path: '/cms/expenses',
        builder: (_, __) => const CmsExpensesScreen(),
      ),
      GoRoute(
        path: '/cms/expenses/:id',
        builder: (BuildContext context, GoRouterState state) =>
            CmsExpenseDetailScreen(
              expenseId: state.pathParameters['id']!,
            ),
      ),
      GoRoute(path: '/cms/users', builder: (_, __) => const CmsUsersScreen()),
      GoRoute(path: '/cms/audit', builder: (_, __) => const CmsAuditScreen()),
      // /cms/receipts was a standalone "missing-receipt" view. The Expenses
      // screen now carries the same data via its "Missing receipt" filter
      // chip, so this URL redirects there with the filter pre-selected.
      GoRoute(
        path: '/cms/receipts',
        redirect: (_, __) => '/cms/expenses?missingReceipt=1',
      ),
      GoRoute(path: '/cms/dg', builder: (_, __) => const DgDashboard()),
      GoRoute(
        path: '/cms/settings',
        builder: (_, __) => const CmsSettingsScreen(),
      ),
      GoRoute(
        path: '/cms/reports',
        builder: (_, __) => const CmsReportsScreen(),
      ),
    ],
    errorBuilder: (_, GoRouterState state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.matchedLocation}')),
    ),
  );
}
