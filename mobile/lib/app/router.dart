import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/cms/presentation/cms_dashboard.dart';
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
import '../features/trips/presentation/trip_tab_stub.dart';
import '../features/trips/presentation/trips_home_screen.dart';
import '../shared/widgets/phone_viewport.dart';

GoRouter buildAppRouter() {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, __) => const LandingScreen()),

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
            builder: (BuildContext context, GoRouterState state) => TripTabStub(
              tripId: state.pathParameters['id']!,
              title: 'Profile',
              icon: Icons.account_circle_outlined,
              message: 'Profile + all-trips view lands in Milestone B.',
            ),
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
        ],
      ),

      // CMS — full-width Flutter Web UI for Admin / Super Admin.
      GoRoute(path: '/cms', builder: (_, __) => const CmsDashboard()),
    ],
    errorBuilder: (_, GoRouterState state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.matchedLocation}')),
    ),
  );
}
