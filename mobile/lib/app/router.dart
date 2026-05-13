import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/cms/presentation/cms_placeholder.dart';
import '../features/landing/presentation/landing_screen.dart';
import '../features/trips/presentation/trips_home_placeholder.dart';
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

      // Mobile UI — rendered inside a phone-frame on web.
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) =>
            PhoneViewport(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: '/m/trips',
            builder: (_, __) => const TripsHomePlaceholder(),
          ),
          // Future: /m/trips/:id/dashboard, /m/trips/:id/expenses, etc.
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
