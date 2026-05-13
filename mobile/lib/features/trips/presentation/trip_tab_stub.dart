import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../shared/widgets/trip_bottom_nav.dart';

/// Placeholder for bottom-nav tabs that land in later Milestone A slices:
/// /transfer, /profile, /chat, /manage-funds.
class TripTabStub extends StatelessWidget {
  const TripTabStub({
    super.key,
    required this.tripId,
    required this.title,
    required this.icon,
    required this.message,
  });

  final String tripId;
  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 56, color: AppColors.goldOlive),
              const SizedBox(height: AppSpacing.md),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: TripBottomNav(
        tripId: tripId,
        currentLocation: GoRouterState.of(context).matchedLocation,
      ),
    );
  }
}
