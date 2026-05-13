import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/money/money.dart';

/// Dashboard donut per screen-inventory.md #3 — green arc = remaining balance,
/// brown arc = total spent. Negative balance renders as a full brown ring with
/// the center label showing the overspend.
class DualArcDonut extends StatelessWidget {
  const DualArcDonut({
    super.key,
    required this.balance,
    required this.spent,
    this.size = 220,
    this.thickness = 22,
    this.centerLabel,
    this.centerSublabel,
  });

  final Money balance;
  final Money spent;
  final double size;
  final double thickness;
  final String? centerLabel;
  final String? centerSublabel;

  @override
  Widget build(BuildContext context) {
    final double balanceVal = balance.amountMinor.toDouble();
    final double spentVal = spent.amountMinor.toDouble();
    final bool negative = balance.isNegative;

    final List<PieChartSectionData> sections = <PieChartSectionData>[];
    if (negative) {
      sections.add(
        PieChartSectionData(
          value: spentVal == 0 ? 1 : spentVal,
          color: AppColors.brandBrown,
          radius: thickness,
          showTitle: false,
        ),
      );
    } else if (balanceVal == 0 && spentVal == 0) {
      sections.add(
        PieChartSectionData(
          value: 1,
          color: AppColors.cream,
          radius: thickness,
          showTitle: false,
        ),
      );
    } else {
      if (balanceVal > 0) {
        sections.add(
          PieChartSectionData(
            value: balanceVal,
            color: AppColors.success,
            radius: thickness,
            showTitle: false,
          ),
        );
      }
      if (spentVal > 0) {
        sections.add(
          PieChartSectionData(
            value: spentVal,
            color: AppColors.brandBrown,
            radius: thickness,
            showTitle: false,
          ),
        );
      }
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          PieChart(
            PieChartData(
              sectionsSpace: 0,
              centerSpaceRadius: (size / 2) - thickness,
              startDegreeOffset: -90,
              sections: sections,
            ),
          ),
          Padding(
            padding: EdgeInsets.all(thickness + 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  'BALANCE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  centerLabel ?? balance.format(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: negative ? AppColors.outflow : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  centerSublabel ?? 'SPENT  ${spent.format()}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
