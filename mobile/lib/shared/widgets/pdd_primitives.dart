import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../features/auth/domain/user.dart';

/// Shared primitives matching the design handoff at
/// `docs/design/design_handoff_petty_cash/ui.jsx`.
///
/// Every widget here is layout-only: no Riverpod, no API calls, no
/// repository lookups. Pass it primitive data (a User, a Money, etc.) so it
/// can be reused on every surface (mobile screens, admin CMS panels, dialog
/// previews, golden tests) without dragging providers along.
///
/// **When to add a primitive here:** any visual that recurs in the prototype
/// across at least two screens. Single-use widgets stay co-located with the
/// screen that uses them.

// ────────────────────────────────────────────────────────────────────
// Avatar
// ────────────────────────────────────────────────────────────────────

/// Circular initials avatar. Background color is derived from the user's
/// id hash so the same user has a stable color across sessions — matches
/// the prototype's per-user color assignment without storing it on the row.
class PddAvatar extends StatelessWidget {
  const PddAvatar({super.key, required this.user, this.size = 36});
  final User? user;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return SizedBox(width: size, height: size);
    }
    final Color bg = _colorFor(user!.id);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(user!.displayName),
        style: AppTypography.geist(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          color: AppColors.bgCard,
          letterSpacing: 0.02,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final List<String> parts =
        name.trim().split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Stable-but-varied palette. Hashes the user id into a fixed 8-color
  /// rota so we don't store a `color` column on the user row. Public so
  /// other widgets (Team activity progress bars, member chips) can use the
  /// same color for the same user.
  static Color colorFor(String id) => _colorFor(id);

  static Color _colorFor(String id) {
    const List<Color> palette = <Color>[
      AppColors.brand,
      AppColors.amber,
      AppColors.blue,
      Color(0xFF7E4B2E),
      Color(0xFF7B5BA8),
      AppColors.red,
      AppColors.green,
      AppColors.goldDeep,
    ];
    if (id.isEmpty) return palette.first;
    int h = 0;
    for (final int code in id.codeUnits) {
      h = (h * 31 + code) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }
}

// ────────────────────────────────────────────────────────────────────
// Top bar
// ────────────────────────────────────────────────────────────────────

/// In-app header — avatar + greeting/name on the left, optional bell on
/// the right. On top-level screens [leadingBack] is false and the avatar
/// is shown; on sub-screens (trip dashboard, detail) set [leadingBack] +
/// [onBack] to swap the avatar for a back arrow.
///
/// [actions] inserts extra icon buttons to the *left* of the notifications
/// bell — used to surface things like a trip-scoped chat shortcut from the
/// dashboard without dragging the user through a drawer.
class PddTopBar extends StatelessWidget {
  const PddTopBar({
    super.key,
    required this.user,
    this.subtitle,
    this.title,
    this.onNotifs,
    this.hasNotif = false,
    this.leadingBack = false,
    this.onBack,
    this.actions = const <Widget>[],
  });

  final User? user;
  final String? subtitle;
  final String? title;
  final VoidCallback? onNotifs;
  final bool hasNotif;

  /// When true, render a back arrow instead of the avatar on the left.
  final bool leadingBack;
  final VoidCallback? onBack;

  /// Extra icon buttons rendered between the title block and the bell.
  /// Use [PddTopBarIconButton] for visual consistency.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: <Widget>[
          if (leadingBack)
            _IconBtn(
              icon: Icons.arrow_back,
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
            )
          else
            PddAvatar(user: user, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  subtitle ?? (user != null ? 'Welcome back' : ''),
                  style: AppTypography.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink3,
                    letterSpacing: 0.02,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title ?? (user?.displayName.split(' ').first ?? ''),
                  style: AppTypography.geist(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          for (final Widget a in actions) ...<Widget>[
            a,
            const SizedBox(width: 6),
          ],
          if (onNotifs != null)
            PddTopBarIconButton(
              icon: Icons.notifications_none_outlined,
              onTap: onNotifs!,
              dot: hasNotif,
            ),
        ],
      ),
    );
  }
}

/// Square 40×40 icon button styled to match [PddTopBar]'s right-side
/// affordances (notifications bell, chat shortcut, etc.). Exposed publicly
/// so feature code can compose [PddTopBar.actions] without rebuilding the
/// visual style each time.
class PddTopBarIconButton extends StatelessWidget {
  const PddTopBarIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.dot = false,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool dot;
  final String? tooltip;

  @override
  Widget build(BuildContext context) =>
      _IconBtn(icon: icon, onTap: onTap, dot: dot, tooltip: tooltip);
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.dot = false,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool dot;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget btn = Material(
      color: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Icon(icon, size: 18, color: AppColors.ink1),
              if (dot)
                const Positioned(
                  top: 10,
                  right: 11,
                  child: SizedBox(
                    width: 8,
                    height: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

// ────────────────────────────────────────────────────────────────────
// Balance card (hero)
// ────────────────────────────────────────────────────────────────────

/// Deep-forest-green hero card. Used as the active-trip hero on Home and
/// (a slimmer variant) as the trip balance on Trip Dashboard.
class PddBalanceCard extends StatelessWidget {
  const PddBalanceCard({
    super.key,
    required this.tripCode,
    required this.tripName,
    required this.dates,
    required this.flagEmoji,
    required this.balanceLabel,
    required this.balanceText,
    required this.currency,
    required this.spentPct,
    this.onTap,
  });

  final String tripCode;
  final String tripName;
  final String dates;
  final String flagEmoji;
  final String balanceLabel;
  final String balanceText;
  final String currency;

  /// 0.0 to 1.0 — drives the "Spent X%" right column.
  final double spentPct;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final int pct = (spentPct.clamp(0.0, 1.0) * 100).round();
    final Widget card = Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: kBrandGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Active trip · $tripCode',
                      style: AppTypography.geist(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.06 * 11,
                        color: AppColors.bgCard.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tripName,
                      style: AppTypography.geist(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.bgCard,
                        letterSpacing: -0.02 * 20,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 13,
                          color: AppColors.bgCard.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          dates,
                          style: AppTypography.geist(
                            fontSize: 13,
                            color: AppColors.bgCard.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(flagEmoji, style: const TextStyle(fontSize: 28, height: 1)),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                flex: 6,
                child: _kvBlock(
                  k: balanceLabel,
                  vText: balanceText,
                  vCurrency: currency,
                ),
              ),
              Expanded(
                flex: 5,
                child: _kvBlock(
                  k: 'Spent',
                  vText: '$pct',
                  vCurrency: '%',
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: card,
      ),
    );
  }

  Widget _kvBlock({
    required String k,
    required String vText,
    required String vCurrency,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          k,
          style: AppTypography.geist(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.06 * 11,
            color: AppColors.bgCard.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: Text(
                vText,
                style: AppTypography.geistMono(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: AppColors.bgCard,
                  letterSpacing: -0.02 * 32,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              vCurrency,
              style: AppTypography.geist(
                fontSize: 11,
                color: AppColors.bgCard.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Action tile (4-up grid on Home)
// ────────────────────────────────────────────────────────────────────

class PddActionTile extends StatelessWidget {
  const PddActionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgCard,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.brandTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: AppColors.brand),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: AppTypography.geist(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Donut chart
// ────────────────────────────────────────────────────────────────────

/// Pure-Flutter donut. Centered % label + sub-text. The handoff spec calls
/// for `var(--brand)` as the arc color and `var(--bg-inset)` as the track —
/// we mirror that. Use this on Trip Dashboard + DG overview.
class PddDonut extends StatelessWidget {
  const PddDonut({
    super.key,
    required this.spent,
    required this.allocated,
    this.size = 144,
    this.strokeWidth = 14,
    this.label = 'spent',
  });

  final double spent;
  final double allocated;
  final double size;
  final double strokeWidth;
  final String label;

  @override
  Widget build(BuildContext context) {
    final double pct =
        allocated <= 0 ? 0 : (spent / allocated).clamp(0.0, 1.0);
    final int pctInt = (pct * 100).round();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: Size.square(size),
            painter: _DonutPainter(
              progress: pct,
              strokeWidth: strokeWidth,
              trackColor: AppColors.bgInset,
              arcColor: AppColors.brand,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '$pctInt%',
                style: AppTypography.geistMono(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink1,
                  letterSpacing: -0.02 * 24,
                ),
              ),
              Text(
                label,
                style: AppTypography.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.06 * 11,
                  color: AppColors.ink3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.progress,
    required this.strokeWidth,
    required this.trackColor,
    required this.arcColor,
  });

  final double progress;
  final double strokeWidth;
  final Color trackColor;
  final Color arcColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double r = (size.width - strokeWidth) / 2;
    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawCircle(c, r, track);
    if (progress <= 0) return;
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = arcColor;
    final Rect rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, arc);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress ||
      old.strokeWidth != strokeWidth ||
      old.arcColor != arcColor ||
      old.trackColor != trackColor;
}

// ────────────────────────────────────────────────────────────────────
// Expense row
// ────────────────────────────────────────────────────────────────────

class PddExpenseRow extends StatelessWidget {
  const PddExpenseRow({
    super.key,
    required this.categoryCode,
    required this.categoryLabel,
    required this.vendor,
    required this.timeLabel,
    required this.amountFormatted,
    required this.currency,
    this.userInitials,
    this.hasReceipt = false,
    this.onTap,
  });

  final String categoryCode;
  final String categoryLabel;
  final String vendor;
  final String timeLabel;
  final String amountFormatted;
  final String currency;
  final String? userInitials;
  final bool hasReceipt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color catColor = AppColors.forCategory(categoryCode);
    final Color catBg = AppColors.forCategoryBg(categoryCode);
    return Material(
      color: AppColors.bgCard,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: catBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _iconForCategory(categoryCode),
                  size: 20,
                  color: catColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      vendor.isEmpty ? '—' : vendor,
                      style: AppTypography.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        categoryLabel,
                        timeLabel,
                        if (userInitials != null) userInitials!,
                      ].join(' · '),
                      style: AppTypography.geist(
                        fontSize: 12,
                        color: AppColors.ink3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  RichText(
                    text: TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: amountFormatted,
                          style: AppTypography.geistMono(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink1,
                          ),
                        ),
                        TextSpan(
                          text: '  $currency',
                          style: AppTypography.geist(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.ink3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (hasReceipt)
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 12,
                      color: AppColors.ink3,
                    )
                  else
                    Text(
                      'no invoice',
                      style: AppTypography.geist(
                        fontSize: 11,
                        color: AppColors.ink4,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconForCategory(String code) {
    switch (code.toUpperCase()) {
      case 'FOOD':
        return Icons.local_cafe_outlined;
      case 'TRANSPORT':
        return Icons.directions_car_outlined;
      case 'HOTEL':
        return Icons.bed_outlined;
      case 'PHONE':
        return Icons.phone_outlined;
      case 'ENTERTAINMENT':
        return Icons.celebration_outlined;
      case 'TIPS':
        return Icons.card_giftcard_outlined;
      case 'TRAVEL':
        return Icons.flight_takeoff_outlined;
      case 'OTHERS':
      default:
        return Icons.more_horiz_outlined;
    }
  }
}

// ────────────────────────────────────────────────────────────────────
// Day separator
// ────────────────────────────────────────────────────────────────────

class PddDaySeparator extends StatelessWidget {
  const PddDaySeparator({
    super.key,
    required this.label,
    required this.totalFormatted,
    required this.currency,
  });

  final String label;
  final String totalFormatted;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: AppTypography.microLabel(),
            ),
          ),
          RichText(
            text: TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: totalFormatted,
                  style: AppTypography.geistMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink2,
                  ),
                ),
                TextSpan(
                  text: ' $currency',
                  style: AppTypography.geist(
                    fontSize: 12,
                    color: AppColors.ink2,
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

// ────────────────────────────────────────────────────────────────────
// Empty state
// ────────────────────────────────────────────────────────────────────

class PddEmptyState extends StatelessWidget {
  const PddEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.bgInset,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 26, color: AppColors.ink3),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.geist(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.ink1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTypography.geist(
              fontSize: 13,
              color: AppColors.ink3,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Toast (snack-bar replacement matching the prototype's float style)
// ────────────────────────────────────────────────────────────────────

void showPddToast(BuildContext context, String message, {bool info = false}) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(milliseconds: 2400),
      behavior: SnackBarBehavior.floating,
      backgroundColor: info ? AppColors.blue : AppColors.brand,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      content: Row(
        children: <Widget>[
          Icon(
            info ? Icons.info_outline : Icons.check_circle_outline,
            color: AppColors.bgCard,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.geist(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.bgCard,
              ),
            ),
          ),
        ],
      ),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 92),
    ),
  );
}

// ────────────────────────────────────────────────────────────────────
// Section header (used a lot on Home + Trip Dashboard)
// ────────────────────────────────────────────────────────────────────

class PddSectionLabel extends StatelessWidget {
  const PddSectionLabel({
    super.key,
    required this.label,
    this.trailing,
  });
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label.toUpperCase(), style: AppTypography.microLabel())),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
