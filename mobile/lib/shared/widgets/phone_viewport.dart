import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Renders a child widget at iPhone 13-class proportions (375x812) inside a
/// device chrome bezel. Used on the Flutter Web demo to present the mobile
/// app in a phone-shaped frame at desktop sizes.
///
/// Behaviour:
/// * On narrow viewports (<600 logical px) or non-web targets, the child
///   renders full-screen without the bezel.
/// * Otherwise the frame is rendered at a capped display height (so it
///   visually approximates a real phone on a desk, ~14-15cm tall on a 96dpi
///   monitor) rather than full iPhone-13 logical-pixel size, which on a
///   desktop browser would be more like 21cm. On taller browser windows it
///   stays at the cap; on shorter ones it shrinks further to fit. The inner
///   child still believes it has 375x812 logical pixels — only the visual
///   render is scaled, so layout/breakpoints in the mobile UI are unaffected.
class PhoneViewport extends StatelessWidget {
  const PhoneViewport({super.key, required this.child});

  final Widget child;

  static const double kWidth = 375;
  static const double kHeight = 812;

  // Bezel padding (10 each side) + outer bottom shadow margin.
  static const double kChromeWidth = kWidth + 20;
  static const double kChromeHeight = kHeight + 20;

  /// Target visual height of the device chrome on desktop browsers. We
  /// previously capped at 580 (~15cm) which felt phone-sized but pushed
  /// sticky CTAs off the visible frame on long forms (Add Expense, Transfer,
  /// Allocate). 680 gives ~17cm — still phone-shaped, comfortably fits the
  /// "Record / Continue / Confirm" buttons inside the visible frame.
  static const double kDisplayHeight = 680;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final bool useBezel = kIsWeb && size.width >= 600;

    if (!useBezel) {
      return child;
    }

    // Use up to kDisplayHeight, but shrink further on cramped browser windows
    // so the bottom of the phone never gets clipped. 40px reserves space for
    // the vertical padding we add around the frame.
    final double cap = (size.height - 40).clamp(380.0, kDisplayHeight);

    return ColoredBox(
      color: AppColors.brandBrownDark,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          child: Center(
            child: SizedBox(
              height: cap,
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.center,
                child: _DeviceChrome(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceChrome extends StatelessWidget {
  const _DeviceChrome({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(48),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Colors.black54,
            blurRadius: 32,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: SizedBox(
          width: PhoneViewport.kWidth,
          height: PhoneViewport.kHeight,
          child: child,
        ),
      ),
    );
  }
}
