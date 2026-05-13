import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/cms/presentation/cms_placeholder.dart';
import '../features/landing/presentation/landing_screen.dart';
import '../features/trips/presentation/trip_dashboard_screen.dart';
import '../features/trips/presentation/trip_tab_stub.dart';
import '../features/trips/presentation/trips_home_screen.dart';
import '../shared/widgets/phone_viewport.dart';

GoRouter buildAppRouter() {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, __) => const LandingScreen(),
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
            path: '/m/trips/:id/dashboard',
            builder: (BuildContext context, GoRouterState state) =>
                TripDashboardScreen(tripId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/m/trips/:id/expenses/mine',
            builder: (BuildContext context, GoRouterState state) => TripTabStub(
              tripId: state.pathParameters['id']!,
              title: 'My Expenses',
              icon: Icons.receipt_long_outlined,
              message: 'List view + filter + chart toggle lands in the next slice.',
            ),
          ),
          GoRoute(
            path: '/m/trips/:id/expenses/new',
            builder: (BuildContext context, GoRouterState state) => TripTabStub(
              tripId: state.pathParameters['id']!,
              title: 'Add Expense',
              icon: Icons.add_circle_outline,
              message: 'Form + receipt + offline queue lands in the next slice.',
            ),
          ),
          GoRoute(
            path: '/m/trips/:id/transfer',
            builder: (BuildContext context, GoRouterState state) => TripTabStub(
              tripId: state.pathParameters['id']!,
              title: 'Transfer',
              icon: Icons.swap_horiz,
              message: 'Peer-to-peer transfer lands in Milestone B.',
            ),
          ),
          GoRoute(
            path: '/m/trips/:id/profile',
            builder: (BuildContext context, GoRouterState state) => TripTabStub(
              tripId: state.pathParameters['id']!,
              title: 'Profile',
              icon: Icons.account_circle_outlined,
              message: 'Profile + all-trips view lands later in Milestone A.',
            ),
          ),
          GoRoute(
            path: '/m/trips/:id/chat',
            builder: (BuildContext context, GoRouterState state) => TripTabStub(
              tripId: state.pathParameters['id']!,
              title: 'Chats',
              icon: Icons.chat_bubble_outline,
              message: 'Chat threads + per-thread view lands in Milestone B.',
            ),
          ),
          GoRoute(
            path: '/m/trips/:id/manage-funds',
            builder: (BuildContext context, GoRouterState state) => TripTabStub(
              tripId: state.pathParameters['id']!,
              title: 'Manage Funds',
              icon: Icons.account_balance_wallet_outlined,
              message: 'Allocate Funds (Leader) lands in Milestone C.',
            ),
          ),
          GoRoute(
            path: '/m/notifications',
            builder: (_, __) => Scaffold(
              appBar: AppBar(title: const Text('Notifications')),
              body: const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Notifications list lands in Milestone B.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      // CMS — full-width Flutter Web UI for Admin / Super Admin.
      GoRoute(
        path: '/cms',
        builder: (_, __) => const CmsPlaceholder(),
      ),
    ],
    errorBuilder: (_, GoRouterState state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.matchedLocation}')),
    ),
  );
}
