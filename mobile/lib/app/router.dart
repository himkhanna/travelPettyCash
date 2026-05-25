import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/login_screen.dart';
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

GoRouter buildAppRouter() {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
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
