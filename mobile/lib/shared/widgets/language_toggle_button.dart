import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/l10n/locale_provider.dart';
import '../../l10n/generated/app_localizations.dart';

/// Compact EN / AR switcher. Shows the currently active code and opens a
/// popup menu to flip languages.
///
/// Lives in [TripDrawer], the [LandingScreen] header strip, and the CMS
/// [AppBar] so the customer demo can switch directionality from any surface.
class LanguageToggleButton extends ConsumerWidget {
  const LanguageToggleButton({
    super.key,
    this.foregroundColor,
    this.compact = true,
  });

  /// Tints the chip text/border. Defaults to brand brown when unset.
  final Color? foregroundColor;

  /// When true (default) renders as a small chip — fits in AppBars / SafeAreas.
  /// When false, renders as a full ListTile for the side menu.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Locale? current = ref.watch(localePreferenceProvider);
    final AppLocalizations l = AppLocalizations.of(context);
    final bool isAr = (current ?? Localizations.localeOf(context)).languageCode == 'ar';
    final Color fg = foregroundColor ?? AppColors.brandBrown;

    if (compact) {
      return _CompactChip(
        isAr: isAr,
        foreground: fg,
        onSelect: (Locale loc) => _apply(ref, loc),
      );
    }

    return ListTile(
      leading: Icon(Icons.translate, color: fg),
      title: Text(
        l.drawer_language,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          fontSize: 13,
        ),
      ),
      trailing: SegmentedButton<String>(
        segments: <ButtonSegment<String>>[
          ButtonSegment<String>(
            value: 'en',
            label: Text(l.language_english),
          ),
          ButtonSegment<String>(
            value: 'ar',
            label: Text(l.language_arabic),
          ),
        ],
        selected: <String>{isAr ? 'ar' : 'en'},
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onSelectionChanged: (Set<String> sel) {
          _apply(ref, sel.first == 'ar' ? const Locale('ar') : const Locale('en'));
        },
      ),
    );
  }

  void _apply(WidgetRef ref, Locale loc) {
    final LocalePreference notifier =
        ref.read(localePreferenceProvider.notifier);
    if (loc.languageCode == 'ar') {
      notifier.useArabic();
    } else {
      notifier.useEnglish();
    }
  }
}

class _CompactChip extends StatelessWidget {
  const _CompactChip({
    required this.isAr,
    required this.foreground,
    required this.onSelect,
  });

  final bool isAr;
  final Color foreground;
  final ValueChanged<Locale> onSelect;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Locale>(
      tooltip: 'Language',
      onSelected: onSelect,
      itemBuilder: (BuildContext _) => const <PopupMenuEntry<Locale>>[
        PopupMenuItem<Locale>(
          value: Locale('en'),
          child: Text('English'),
        ),
        PopupMenuItem<Locale>(
          value: Locale('ar'),
          child: Text('العربية'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: const BorderRadius.all(AppRadii.chip),
          border: Border.all(color: foreground.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.translate, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(
              isAr ? 'AR' : 'EN',
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
