import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Renders a child widget at fixed iPhone 13-class dimensions (375x812) inside
/// a device chrome bezel. Used on the Flutter Web demo to present the mobile
/// app in a phone-shaped frame at desktop sizes.
///
/// On narrow viewports (<600 logical px) or non-web targets, the child
/// renders full-screen without the bezel. On short viewports (height
/// below the bezel + padding) the whole page becomes scrollable so the
/// bottom of the phone never gets clipped.
class PhoneViewport extends StatelessWidget {
  const PhoneViewport({super.key, required this.child});

  final Widget child;

  static const double kWidth = 375;
  static const double kHeight = 812;

  // Bezel padding (10 each side) + outer bottom shadow margin.
  static const double kChromeWidth = kWidth + 20;
  static const double kChromeHeight = kHeight + 20;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final bool useBezel = kIsWeb && size.width >= 600;

    if (!useBezel) {
      return child;
    }

    return ColoredBox(
      color: AppColors.brandBrownDark,
      child: SingleChildScrollView(
        // Page-level scroll so users on browser windows shorter than
        // the phone frame can still reach the bottom.
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: size.height),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: _DeviceChrome(child: child),
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
