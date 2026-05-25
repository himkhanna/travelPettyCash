import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import 'widgets/cms_theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../auth/domain/user.dart';
import '../../funds/application/funds_providers.dart';
import '../../funds/data/funds_repository.dart';
import '../../funds/domain/funding.dart';
import '../../missions/application/mission_providers.dart';
import '../../missions/domain/mission.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/data/trip_repository.dart';
import '../../trips/domain/trip.dart';

/// Admin-only dialog for creating a trip end-to-end:
/// 1. Trip metadata (name + country + currency)
/// 2. Assign Leader from the user pool
/// 3. Pick Members (multi-select)
/// 4. Initial budget per source (creates an Allocation per source, assigned
///    to the Leader, so the Leader can sub-allocate to Members later)
///
/// Writes directly to DemoStore. Returns `true` on confirm, `null` on cancel.
class CreateTripDialog extends ConsumerStatefulWidget {
  const CreateTripDialog({super.key});

  @override
  ConsumerState<CreateTripDialog> createState() => _CreateTripDialogState();
}

class _CreateTripDialogState extends ConsumerState<CreateTripDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  String _country = 'SA';
  String _currency = 'SAR';
  String? _leaderId;
  String? _missionId;
  final Set<String> _memberIds = <String>{};
  final Map<String, TextEditingController> _sourceAmounts =
      <String, TextEditingController>{};
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final TextEditingController c in _sourceAmounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DemoStore store = ref.read(demoStoreProvider);
    final List<User> assignableUsers = store.users
        .where((User u) => u.role == UserRole.member || u.role == UserRole.leader)
        .toList();
    final List<Source> sources = store.sources;

    for (final Source s in sources) {
      _sourceAmounts.putIfAbsent(s.id, () {
        // Rebuild on every keystroke so the TOTAL BUDGET line at the
        // bottom of the dialog recomputes live as the admin types.
        final TextEditingController c = TextEditingController();
        c.addListener(() {
          if (mounted) setState(() {});
        });
        return c;
      });
    }

    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _Header(onClose: () => Navigator.of(context).pop()),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _section('1. MISSION'),
                    _MissionPicker(
                      selected: _missionId,
                      onPick: (String? id) =>
                          setState(() => _missionId = id),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _section('2. TRIP DETAILS'),
                    _TripMetaFields(
                      nameCtrl: _nameCtrl,
                      country: _country,
                      currency: _currency,
                      onCountry: (String c) => setState(() {
                        _country = c;
                        _currency = _suggestedCurrency(c);
                      }),
                      onCurrency: (String c) => setState(() => _currency = c),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _section('3. ASSIGN LEADER'),
                    _LeaderPicker(
                      users: assignableUsers,
                      selected: _leaderId,
                      onPick: (String id) => setState(() {
                        _leaderId = id;
                        _memberIds.remove(id);
                      }),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _section('4. PICK MEMBERS'),
                    _MembersPicker(
                      users: assignableUsers
                          .where((User u) => u.id != _leaderId)
                          .toList(),
                      selected: _memberIds,
                      onToggle: (String id, bool selected) => setState(() {
                        if (selected) {
                          _memberIds.add(id);
                        } else {
                          _memberIds.remove(id);
                        }
                      }),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _section('5. INITIAL BUDGET PER SOURCE'),
                    Text(
                      'Funds are credited to the Leader, who can sub-allocate '
                      'to Members from the Manage Funds screen.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: CmsColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (final Source s in sources)
                      _SourceBudgetRow(
                        source: s,
                        currency: _currency,
                        controller: _sourceAmounts[s.id]!,
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _Footer(
              saving: _saving,
              onCancel: () => Navigator.of(context).pop(),
              onConfirm: _save,
              totalLabel: _totalLabel(),
            ),
          ],
        ),
      ),
    );
  }

  String _totalLabel() {
    final int total = _sourceAmounts.values.fold<int>(
      0,
      (int sum, TextEditingController c) =>
          sum + _amountToMinor(c.text, _currency),
    );
    return Money(total, _currency).format();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _toast('Trip name is required');
      return;
    }
    if (_missionId == null) {
      _toast('Please pick a mission for this trip');
      return;
    }
    if (_leaderId == null) {
      _toast('Please assign a leader');
      return;
    }
    if (_memberIds.isEmpty) {
      _toast('Please pick at least one member');
      return;
    }

    setState(() => _saving = true);
    try {
      // Sources are read from DemoStore here as reference data (Source list
      // is seeded and rarely changes). The trip + allocations themselves are
      // persisted through the API repositories below.
      final DemoStore store = ref.read(demoStoreProvider);

      // Sum the per-source amounts into one totalBudget and prepare the
      // initial allocations list for the bulk-create call.
      int totalBudgetMinor = 0;
      final List<AllocationDraftRow> draftRows = <AllocationDraftRow>[];
      for (final Source s in store.sources) {
        final int minor = _amountToMinor(
          _sourceAmounts[s.id]?.text ?? '',
          _currency,
        );
        if (minor <= 0) continue;
        totalBudgetMinor += minor;
        draftRows.add(AllocationDraftRow(
          toUserId: _leaderId!,
          sourceId: s.id,
          amount: Money(minor, _currency),
        ));
      }

      // 1. Create the trip via the trip repo (in API mode this POSTs to
      //    /api/v1/trips; in fake mode it mutates DemoStore).
      final TripRepository trips = ref.read(tripRepositoryProvider);
      final Trip trip = await trips.createTrip(
        name: _nameCtrl.text.trim(),
        countryCode: _country,
        countryName: _countryName(_country),
        currency: _currency,
        leaderId: _leaderId!,
        memberIds: _memberIds.toList(),
        totalBudget: Money(totalBudgetMinor, _currency),
        missionId: _missionId,
      );

      // 2. Initial admin-pool allocations per source. The server returns
      //    the canonical rows; we don't write them to DemoStore — the
      //    tripAllocationsProvider invalidation below refetches them.
      if (draftRows.isNotEmpty) {
        final AllocationRepository allocs =
            ref.read(allocationRepositoryProvider);
        await allocs.createMany(
          tripId: trip.id,
          rows: draftRows,
          idempotencyKey: 'trip-create-${trip.id}',
        );
      }

      // 3. Invalidate providers so the CMS list and any open trip detail
      //    re-fetch from the server. Avoids the race where a local cache
      //    write disagrees with the next list response.
      ref.invalidate(activeTripsProvider);
      ref.invalidate(tripAllocationsProvider(trip.id));

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        _toast('Could not create trip: $e');
        setState(() => _saving = false);
      }
      return;
    }
    if (mounted) setState(() => _saving = false);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: CmsColors.brandBrown,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  String _suggestedCurrency(String country) {
    switch (country) {
      case 'SA':
        return 'SAR';
      case 'AE':
        return 'AED';
      case 'EG':
        return 'EGP';
      case 'JO':
        return 'JOD';
      case 'KW':
        return 'KWD';
      case 'BH':
        return 'BHD';
      case 'OM':
        return 'OMR';
      case 'QA':
        return 'QAR';
      case 'GB':
        return 'GBP';
      case 'US':
        return 'USD';
      case 'FR':
      case 'DE':
      case 'IT':
        return 'EUR';
      case 'JP':
        return 'JPY';
      default:
        return 'USD';
    }
  }

  String _countryName(String code) {
    const Map<String, String> map = <String, String>{
      'SA': 'Saudi Arabia',
      'AE': 'United Arab Emirates',
      'EG': 'Egypt',
      'JO': 'Jordan',
      'KW': 'Kuwait',
      'BH': 'Bahrain',
      'OM': 'Oman',
      'QA': 'Qatar',
      'GB': 'United Kingdom',
      'US': 'United States',
      'FR': 'France',
      'DE': 'Germany',
      'IT': 'Italy',
      'JP': 'Japan',
    };
    return map[code] ?? code;
  }

  int _amountToMinor(String text, String currency) {
    final String cleaned = text.replaceAll(',', '').trim();
    if (cleaned.isEmpty) return 0;
    final double major = double.tryParse(cleaned) ?? 0;
    if (major <= 0) return 0;
    return Money.fromMajor(major, currency).amountMinor;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.flight, color: CmsColors.brandBrown),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Create Trip',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Spacer(),
          IconButton(icon: const Icon(Icons.close), onPressed: onClose),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.saving,
    required this.onCancel,
    required this.onConfirm,
    required this.totalLabel,
  });

  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String totalLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'TOTAL BUDGET',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: CmsColors.textSecondary,
                ),
              ),
              Text(
                totalLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: CmsColors.brandBrown,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Both buttons need explicit compact styles to override the global
          // theme's Size(double.infinity, 52) minimumSize — otherwise Cancel
          // expands and pushes CREATE TRIP off the right edge of the dialog.
          OutlinedButton(
            onPressed: saving ? null : onCancel,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('CANCEL'),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: CmsColors.brandBrown,
              foregroundColor: CmsColors.cream,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              visualDensity: VisualDensity.compact,
            ),
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: CmsColors.cream,
                    ),
                  )
                : const Icon(Icons.check),
            label: const Text(
              'CREATE TRIP',
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.2),
            ),
            onPressed: saving ? null : onConfirm,
          ),
        ],
      ),
    );
  }
}

class _TripMetaFields extends StatelessWidget {
  const _TripMetaFields({
    required this.nameCtrl,
    required this.country,
    required this.currency,
    required this.onCountry,
    required this.onCurrency,
  });

  final TextEditingController nameCtrl;
  final String country;
  final String currency;
  final ValueChanged<String> onCountry;
  final ValueChanged<String> onCurrency;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Trip name',
            border: OutlineInputBorder(),
            hintText: 'e.g. KSA State Visit',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: country,
                decoration: const InputDecoration(
                  labelText: 'Country',
                  border: OutlineInputBorder(),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'SA', child: Text('🇸🇦 Saudi Arabia')),
                  DropdownMenuItem(value: 'AE', child: Text('🇦🇪 UAE')),
                  DropdownMenuItem(value: 'EG', child: Text('🇪🇬 Egypt')),
                  DropdownMenuItem(value: 'JO', child: Text('🇯🇴 Jordan')),
                  DropdownMenuItem(value: 'KW', child: Text('🇰🇼 Kuwait')),
                  DropdownMenuItem(value: 'BH', child: Text('🇧🇭 Bahrain')),
                  DropdownMenuItem(value: 'OM', child: Text('🇴🇲 Oman')),
                  DropdownMenuItem(value: 'QA', child: Text('🇶🇦 Qatar')),
                  DropdownMenuItem(value: 'GB', child: Text('🇬🇧 UK')),
                  DropdownMenuItem(value: 'US', child: Text('🇺🇸 USA')),
                  DropdownMenuItem(value: 'FR', child: Text('🇫🇷 France')),
                  DropdownMenuItem(value: 'DE', child: Text('🇩🇪 Germany')),
                  DropdownMenuItem(value: 'JP', child: Text('🇯🇵 Japan')),
                ],
                onChanged: (String? v) {
                  if (v != null) onCountry(v);
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: currency,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  border: OutlineInputBorder(),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                  DropdownMenuItem(value: 'AED', child: Text('AED')),
                  DropdownMenuItem(value: 'EGP', child: Text('EGP')),
                  DropdownMenuItem(value: 'JOD', child: Text('JOD')),
                  DropdownMenuItem(value: 'KWD', child: Text('KWD')),
                  DropdownMenuItem(value: 'BHD', child: Text('BHD')),
                  DropdownMenuItem(value: 'OMR', child: Text('OMR')),
                  DropdownMenuItem(value: 'QAR', child: Text('QAR')),
                  DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                  DropdownMenuItem(value: 'USD', child: Text('USD')),
                  DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                  DropdownMenuItem(value: 'JPY', child: Text('JPY')),
                ],
                onChanged: (String? v) {
                  if (v != null) onCurrency(v);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LeaderPicker extends StatelessWidget {
  const _LeaderPicker({
    required this.users,
    required this.selected,
    required this.onPick,
  });

  final List<User> users;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final User u in users)
          ChoiceChip(
            label: Text(u.displayName),
            selected: selected == u.id,
            onSelected: (_) => onPick(u.id),
            selectedColor: CmsColors.brandBrown,
            labelStyle: TextStyle(
              color: selected == u.id ? CmsColors.cream : CmsColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _MembersPicker extends StatelessWidget {
  const _MembersPicker({
    required this.users,
    required this.selected,
    required this.onToggle,
  });

  final List<User> users;
  final Set<String> selected;
  final void Function(String id, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return Text(
        'Assign a leader first; remaining users will appear here.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: CmsColors.textSecondary,
        ),
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final User u in users)
          FilterChip(
            label: Text(u.displayName),
            selected: selected.contains(u.id),
            onSelected: (bool v) => onToggle(u.id, v),
            selectedColor: CmsColors.goldOlive,
            checkmarkColor: Colors.white,
            labelStyle: TextStyle(
              color: selected.contains(u.id)
                  ? Colors.white
                  : CmsColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _SourceBudgetRow extends StatelessWidget {
  const _SourceBudgetRow({
    required this.source,
    required this.currency,
    required this.controller,
  });

  final Source source;
  final String currency;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  source.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  source.nameAr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CmsColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                prefixText: '$currency  ',
                hintText: '0',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mission selector — required for new trips. Pulls the live list from the
/// backend; an inline "+ New mission" tile opens a tiny dialog to create
/// one without leaving the trip wizard.
class _MissionPicker extends ConsumerWidget {
  const _MissionPicker({required this.selected, required this.onPick});

  final String? selected;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Mission>> async = ref.watch(missionsProvider);
    return async.when(
      loading: () => const LinearProgressIndicator(),
      error: (Object e, _) => Text('Could not load missions: $e'),
      data: (List<Mission> missions) {
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final Mission m in missions)
              ChoiceChip(
                label: Text(
                  m.code,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                avatar: const Icon(
                  Icons.flag_outlined,
                  size: 16,
                  color: CmsColors.brandBrown,
                ),
                tooltip: m.name,
                selected: selected == m.id,
                onSelected: (_) => onPick(m.id),
                selectedColor: CmsColors.brandBrown,
                labelStyle: TextStyle(
                  color: selected == m.id
                      ? CmsColors.cream
                      : CmsColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ActionChip(
              avatar: const Icon(
                Icons.add,
                size: 16,
                color: CmsColors.brandBrown,
              ),
              label: const Text('New mission'),
              onPressed: () async {
                final Mission? created =
                    await _openCreateMissionDialog(context, ref);
                if (created != null) {
                  ref.invalidate(missionsProvider);
                  onPick(created.id);
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<Mission?> _openCreateMissionDialog(
    BuildContext context,
    WidgetRef ref,
  ) {
    return showDialog<Mission>(
      context: context,
      builder: (BuildContext ctx) => const _NewMissionDialog(),
    );
  }
}

class _NewMissionDialog extends ConsumerStatefulWidget {
  const _NewMissionDialog();

  @override
  ConsumerState<_NewMissionDialog> createState() => _NewMissionDialogState();
}

class _NewMissionDialogState extends ConsumerState<_NewMissionDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      title: const Text('New mission'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Mission name',
                hintText: 'e.g. Gulf State Tour 2026',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Code (optional)',
                hintText: 'auto-generated if blank',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: CmsColors.outflow)),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: CmsColors.brandBrown,
            foregroundColor: CmsColors.cream,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: CmsColors.cream,
                  ),
                )
              : const Text('CREATE'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Mission name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final Mission m = await ref.read(missionRepositoryProvider).create(
            name: _nameCtrl.text.trim(),
            code: _codeCtrl.text.trim().isEmpty
                ? null
                : _codeCtrl.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(m);
    } catch (e) {
      setState(() {
        _error = 'Could not save: $e';
        _saving = false;
      });
    }
  }
}
