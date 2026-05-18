import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../features/trips/domain/trip.dart';
import '../../l10n/generated/app_localizations.dart';

/// Compact status chip used on All Trips cards and trip detail headers.
/// Color mapping per design notes:
///  - ACTIVE  -> green / inflow
///  - CLOSED  -> grey / textSecondary
///  - DRAFT   -> amber / warning
class TripStatusChip extends StatelessWidget {
  const TripStatusChip({super.key, required this.status});

  final TripStatus status;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final (Color bg, Color fg, String label) = switch (status) {
      TripStatus.active => (
        AppColors.inflow.withValues(alpha: 0.15),
        AppColors.inflow,
        l.trip_status_active,
      ),
      TripStatus.closed => (
        AppColors.textSecondary.withValues(alpha: 0.15),
        AppColors.textSecondary,
        l.trip_status_closed,
      ),
      TripStatus.draft => (
        AppColors.warning.withValues(alpha: 0.18),
        AppColors.warning,
        l.trip_status_draft,
      ),
    };

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 10,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(AppRadii.chip),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
