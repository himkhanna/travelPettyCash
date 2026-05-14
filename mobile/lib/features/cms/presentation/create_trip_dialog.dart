import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../auth/domain/user.dart';
import '../../funds/domain/funding.dart';
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
  static const Uuid _uuid = Uuid();

  final TextEditingController _nameCtrl = TextEditingController();
  String _country = 'SA';
  String _currency = 'SAR';
  String? _leaderId;
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
      _sourceAmounts.putIfAbsent(s.id, () => TextEditingController());
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
                    _section('1. TRIP DETAILS'),
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
                    _section('2. ASSIGN LEADER'),
                    _LeaderPicker(
                      users: assignableUsers,
                      selected: _leaderId,
                      onPick: (String id) => setState(() {
                        _leaderId = id;
                        _memberIds.remove(id);
                      }),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _section('3. PICK MEMBERS'),
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
                    _section('4. INITIAL BUDGET PER SOURCE'),
                    Text(
                      'Funds are credited to the Leader, who can sub-allocate '
                      'to Members from the Manage Funds screen.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
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
      final DemoStore store = ref.read(demoStoreProvider);
      final String tripId = 'trip-${_uuid.v4().substring(0, 8)}';
      final DateTime now = DateTime.now();

      int totalBudgetMinor = 0;
      final List<Allocation> initialAllocations = <Allocation>[];
      for (final Source s in store.sources) {
        final int minor = _amountToMinor(
          _sourceAmounts[s.id]?.text ?? '',
          _currency,
        );
        if (minor <= 0) continue;
        totalBudgetMinor += minor;
        initialAllocations.add(
          Allocation(
            id: 'alloc-${_uuid.v4().substring(0, 8)}',
            tripId: tripId,
            fromUserId: null,
            toUserId: _leaderId!,
            sourceId: s.id,
            amount: Money(minor, _currency),
            status: AllocationStatus.accepted,
            createdAt: now,
            respondedAt: now,
          ),
        );
      }

      final Trip trip = Trip(
        id: tripId,
        name: _nameCtrl.text.trim(),
        countryCode: _country,
        countryName: _countryName(_country),
        currency: _currency,
        status: TripStatus.active,
        createdBy: 'u-khalid',
        leaderId: _leaderId!,
        memberIds: _memberIds.toList(),
        totalBudget: Money(totalBudgetMinor, _currency),
        createdAt: now,
      );
      store.trips.add(trip);
      store.allocations.addAll(initialAllocations);
      store.emit(DemoStoreEvent.tripsChanged);
      store.emit(DemoStoreEvent.allocationsChanged);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: AppColors.brandBrown,
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
          const Icon(Icons.flight, color: AppColors.brandBrown),
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
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                totalLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.brandBrown,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: saving ? null : onCancel,
            child: const Text('CANCEL'),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.cream,
                    ),
                  )
                : const Icon(Icons.check),
            label: const Text('CREATE TRIP'),
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
            selectedColor: AppColors.brandBrown,
            labelStyle: TextStyle(
              color: selected == u.id ? AppColors.cream : AppColors.textPrimary,
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
          color: AppColors.textSecondary,
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
            selectedColor: AppColors.goldOlive,
            checkmarkColor: Colors.white,
            labelStyle: TextStyle(
              color: selected.contains(u.id)
                  ? Colors.white
                  : AppColors.textPrimary,
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
                    color: AppColors.textSecondary,
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
