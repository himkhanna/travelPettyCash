import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../auth/domain/user.dart';
import '../../funds/domain/funding.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';

/// Admin-only dialog for editing a trip's name, leader, and member roster.
/// Country/currency are immutable once a trip has expenses — those edits are
/// out of scope to avoid corrupting historical money.
/// Total budget is changed via "Assign Additional Funds" (separate dialog).
class EditTripDialog extends ConsumerStatefulWidget {
  const EditTripDialog({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<EditTripDialog> createState() => _EditTripDialogState();
}

class _EditTripDialogState extends ConsumerState<EditTripDialog> {
  late final TextEditingController _nameCtrl;
  late String _leaderId;
  late Set<String> _memberIds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final Trip t = ref.read(demoStoreProvider).tripById(widget.tripId);
    _nameCtrl = TextEditingController(text: t.name);
    _leaderId = t.leaderId;
    _memberIds = <String>{...t.memberIds};
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DemoStore store = ref.read(demoStoreProvider);
    final Trip trip = store.tripById(widget.tripId);
    final bool locked = trip.status == TripStatus.closed;
    final List<User> assignable = store.users
        .where(
          (User u) => u.role == UserRole.member || u.role == UserRole.leader,
        )
        .toList();
    final bool leaderHasAllocations = store.allocations.any(
      (Allocation a) =>
          a.tripId == widget.tripId &&
          a.toUserId == trip.leaderId &&
          a.fromUserId == null,
    );

    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _header(context),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (locked)
                      _LockedBanner()
                    else
                      _ReadOnlyMetaBanner(trip: trip),
                    const SizedBox(height: AppSpacing.lg),
                    _section('TRIP NAME'),
                    TextField(
                      controller: _nameCtrl,
                      enabled: !locked,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _section('LEADER'),
                    if (leaderHasAllocations && _leaderId != trip.leaderId)
                      _Warning(
                        text:
                            'Current leader already received initial funds. '
                            'Swapping leaders in the demo does not migrate '
                            'those allocations — the new leader will start '
                            'with an empty pool.',
                      ),
                    _LeaderChoice(
                      users: assignable,
                      selectedId: _leaderId,
                      enabled: !locked,
                      onPick: (String id) => setState(() {
                        _leaderId = id;
                        _memberIds.remove(id);
                      }),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _section('MEMBERS'),
                    _MembersChoice(
                      users: assignable
                          .where((User u) => u.id != _leaderId)
                          .toList(),
                      selected: _memberIds,
                      enabled: !locked,
                      onToggle: (String id, bool sel) => setState(() {
                        if (sel) {
                          _memberIds.add(id);
                        } else {
                          _memberIds.remove(id);
                        }
                      }),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _footer(locked: locked),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.edit, color: AppColors.brandBrown),
          const SizedBox(width: AppSpacing.sm),
          Text('Edit Trip', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _footer({required bool locked}) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.cream,
                    ),
                  )
                : const Icon(Icons.check),
            label: const Text('SAVE'),
            onPressed: _saving || locked ? null : _save,
          ),
        ],
      ),
    );
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

  Future<void> _save() async {
    final String name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip name is required.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final DemoStore store = ref.read(demoStoreProvider);
      final int i = store.trips.indexWhere(
        (Trip t) => t.id == widget.tripId,
      );
      if (i < 0) throw StateError('Trip not found: ${widget.tripId}');
      final Trip old = store.trips[i];
      store.trips[i] = Trip(
        id: old.id,
        name: name,
        countryCode: old.countryCode,
        countryName: old.countryName,
        currency: old.currency,
        status: old.status,
        createdBy: old.createdBy,
        leaderId: _leaderId,
        memberIds: _memberIds.toList(),
        totalBudget: old.totalBudget,
        createdAt: old.createdAt,
        closedAt: old.closedAt,
      );
      store.emit(DemoStoreEvent.tripsChanged);
      ref.invalidate(tripDetailProvider(widget.tripId));
      ref.invalidate(activeTripsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved changes to "$name".')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _LockedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.all(AppRadii.card),
      ),
      child: Row(
        children: const <Widget>[
          Icon(Icons.lock_outline, color: AppColors.textSecondary),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'This trip is closed. Editing is disabled.',
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyMetaBanner extends StatelessWidget {
  const _ReadOnlyMetaBanner({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: const BorderRadius.all(AppRadii.card),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline, color: AppColors.goldOlive),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Country (${trip.countryName}) and currency (${trip.currency}) '
              'are locked after creation. Change the total budget via '
              '"Assign Additional Funds".',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: const BorderRadius.all(AppRadii.chip),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.warning_amber_outlined,
              color: AppColors.warning,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderChoice extends StatelessWidget {
  const _LeaderChoice({
    required this.users,
    required this.selectedId,
    required this.enabled,
    required this.onPick,
  });
  final List<User> users;
  final String selectedId;
  final bool enabled;
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
            selected: selectedId == u.id,
            onSelected: enabled ? (_) => onPick(u.id) : null,
            selectedColor: AppColors.brandBrown,
            labelStyle: TextStyle(
              color: selectedId == u.id
                  ? AppColors.cream
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _MembersChoice extends StatelessWidget {
  const _MembersChoice({
    required this.users,
    required this.selected,
    required this.enabled,
    required this.onToggle,
  });
  final List<User> users;
  final Set<String> selected;
  final bool enabled;
  final void Function(String, bool) onToggle;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return Text(
        'No members available — assign more users to be members first.',
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
            onSelected: enabled ? (bool v) => onToggle(u.id, v) : null,
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
