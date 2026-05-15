import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory locale override.
///
/// `null` means "follow the system locale" — that's the default at boot, so
/// a UAE device set to Arabic still opens the app in Arabic without an
/// explicit toggle. As soon as the user picks EN or AR from the language
/// toggle, this notifier holds onto the choice for the rest of the session.
/// We don't persist to shared_preferences here: per the build-order project
/// memory, the demo deliberately resets state across restarts.
class LocalePreference extends StateNotifier<Locale?> {
  LocalePreference() : super(null);

  void useEnglish() => state = const Locale('en');
  void useArabic() => state = const Locale('ar');
  void useSystem() => state = null;

  /// Convenience for the language-toggle row.
  bool get isArabic => state?.languageCode == 'ar';
}

final StateNotifierProvider<LocalePreference, Locale?> localePreferenceProvider =
    StateNotifierProvider<LocalePreference, Locale?>(
      (Ref ref) => LocalePreference(),
    );
