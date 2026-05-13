import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../features/trips/domain/trip.dart';

/// Per-source card under the dashboard donut. Olive-gold balance ring,
/// green-down inflow, red-up outflow. Matches screen-inventory #3.
class SourceBalanceCard extends StatelessWidget {
  const SourceBalanceCard({super.key, required this.balance});

  final SourceBalance balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            balance.sourceName.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              _Ring(amount: balance.balance.format()),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _Flow(
                      label: 'RECEIVED',
                      amount: balance.received.format(),
                      icon: Icons.arrow_downward,
                      color: AppColors.inflow,
                    ),
                    const SizedBox(height: 4),
                    _Flow(
                      label: 'SPENT',
                      amount: balance.spent.format(),
                      icon: Icons.arrow_upward,
                      color: AppColors.outflow,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.amount});
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.goldOlive, width: 4),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: FittedBox(
          child: Text(
            amount,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.brandBrown,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _Flow extends StatelessWidget {
  const _Flow({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  final String label;
  final String amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(
          amount,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
