import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../l10n/generated/app_localizations.dart';

/// Yellow disclaimer card surfaced above the Add Expense form after a
/// successful OCR scan. CLAUDE.md §15 calls OCR an "opt-in enhancement"
/// that must be "deterministic-first" — the banner is the visible
/// guardrail that reminds the user the values are AI-suggested, not
/// authoritative.
///
/// RTL-safe: uses EdgeInsetsDirectional and Directionality-aware icons.
/// Animated slide-in from the top so the user notices it appearing.
class OcrDisclaimerBanner extends StatefulWidget {
  const OcrDisclaimerBanner({
    super.key,
    required this.body,
    required this.onDismiss,
    this.title,
  });

  /// Headline string. Defaults to `ocr_disclaimer_title` when omitted.
  final String? title;

  /// Body text. The Add Expense screen passes the `warning` field from
  /// the receipt scan response so we can A/B the copy server-side later.
  final String body;

  /// Tap handler for the close (×) affordance.
  final VoidCallback onDismiss;

  @override
  State<OcrDisclaimerBanner> createState() => _OcrDisclaimerBannerState();
}

class _OcrDisclaimerBannerState extends State<OcrDisclaimerBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String title = widget.title ?? l.ocr_disclaimer_title;

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.16),
            borderRadius: const BorderRadius.all(AppRadii.card),
            border: Border.all(color: AppColors.warning, width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warning,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.brandBrownDark,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.body,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('ocrDisclaimerDismiss'),
                icon: const Icon(Icons.close, size: 20),
                tooltip: l.common_close,
                color: AppColors.textSecondary,
                onPressed: widget.onDismiss,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
