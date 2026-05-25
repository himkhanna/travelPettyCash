import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import 'widgets/cms_theme.dart';
import '../../auth/domain/user.dart';
import '../../expenses/application/expenses_providers.dart';
import '../../expenses/domain/expense.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/data/trip_repository.dart';
import '../../trips/domain/trip.dart';

/// Admin-only dialog for editing an existing trip's name, leader, and
/// member roster. Country + currency are immutable post-create because the
/// money math on existing rows is denormalised against them.
///
/// Member removals cascade-decline the removed user's pending allocations
/// and transfers on this trip (handled server-side; the client just POSTs
/// the new memberIds list).
class EditTripDialog extends ConsumerStatefulWidget {
  const EditTripDialog({super.key, required this.trip});

  final Trip trip;

  @override
  ConsumerState<EditTripDialog> createState() => _EditTripDialogState();
}

class _EditTripDialogState extends ConsumerState<EditTripDialog> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.trip.name);
  late String _leaderId = widget.trip.leaderId;
  late final Set<String> _memberIds = <String>{...widget.trip.memberIds};
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  /// Delete is only meaningful for trips with no expenses logged. We do a
  /// belt-and-braces check here too; the server enforces the same rule.
  bool get _canDelete {
    final List<Expense> expenses =
        ref.read(tripExpensesProvider(widget.trip.id)).valueOrNull ??
            const <Expense>[];
    return expenses.isEmpty && widget.trip.status != TripStatus.closed;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DemoStore store = ref.read(demoStoreProvider);
    final List<User> assignableUsers = store.users
        .where((User u) =>
            u.role == UserRole.member || u.role == UserRole.leader)
        .toList()
      ..sort((User a, User b) => a.displayName.compareTo(b.displayName));

    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.edit_outlined, color: CmsColors.brandBrown),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Edit Trip',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _section('1. TRIP NAME'),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Trip name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '${widget.trip.countryName} · ${widget.trip.currency} — '
                      'country and currency are locked after creation.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: CmsColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _section('2. LEADER'),
                    _LeaderPicker(
                      users: assignableUsers,
                      selected: _leaderId,
                      onPick: (String id) => setState(() {
                        _leaderId = id;
                        _memberIds.remove(id);
                      }),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _section('3. MEMBERS'),
                    Text(
                      'Removing a member auto-declines their pending '
                      'allocations and transfers on this trip. Already-accepted '
                      'rows are kept for audit.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: CmsColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
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
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: CmsColors.outflow.withValues(alpha: 0.1),
                          borderRadius: const BorderRadius.all(AppRadii.chip),
                          border: Border.all(
                            color: CmsColors.outflow.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.error_outline,
                                color: CmsColors.outflow, size: 18),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(color: CmsColors.outflow),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: <Widget>[
                  // Delete affordance — only when the trip has no expenses.
                  // Server enforces the same rule; rendering conditionally
                  // here is just so admins don't see a button that always
                  // fails on active/closed trips.
                  if (_canDelete)
                    OutlinedButton.icon(
                      onPressed: _saving || _deleting
                          ? null
                          : _confirmDelete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CmsColors.outflow,
                        side: BorderSide(
                          color: CmsColors.outflow.withValues(alpha: 0.5),
                        ),
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: _deleting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: CmsColors.outflow,
                              ),
                            )
                          : const Icon(
                              Icons.delete_outline,
                              size: 16,
                            ),
                      label: const Text(
                        'DELETE',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.only(
                      left: _canDelete ? AppSpacing.sm : 0,
                    ),
                    child: Text(
                      '${_memberIds.length} member(s)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: CmsColors.textSecondary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Compact styles override the global theme's
                  // Size(double.infinity, 52) — without these, CANCEL
                  // claims full width and pushes SAVE off the right edge.
                  OutlinedButton(
                    onPressed: _saving || _deleting
                        ? null
                        : () => Navigator.of(context).pop(false),
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
                    onPressed: _saving || _deleting ? null : _save,
                    icon: _saving
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
                      'SAVE',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final String trimmed = _nameCtrl.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _error = 'Trip name cannot be empty.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final TripRepository repo = ref.read(tripRepositoryProvider);
      await repo.updateTrip(
        tripId: widget.trip.id,
        name: trimmed == widget.trip.name ? null : trimmed,
        leaderId: _leaderId == widget.trip.leaderId ? null : _leaderId,
        memberIds: _memberIds.toList(),
      );

      // Provider invalidation is enough — the canonical row comes back from
      // the next /trips/{id} fetch. Writing to DemoStore here would race the
      // refetch and risked staleness.
      ref.invalidate(tripDetailProvider(widget.trip.id));
      ref.invalidate(activeTripsProvider);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not save: $e';
        _saving = false;
      });
    }
  }

  Future<void> _confirmDelete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(AppRadii.card),
        ),
        title: const Text('Delete this trip?'),
        content: Text(
          'This permanently removes "${widget.trip.name}" along with its '
          'allocations and transfers. The trip has no expenses logged, so '
          'no financial record will be lost. This action cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('CANCEL'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: CmsColors.outflow,
              foregroundColor: CmsColors.cream,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text(
              'DELETE',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _delete();
    }
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ref.read(tripRepositoryProvider).deleteTrip(widget.trip.id);
      // Drop the trip from every list that could still show it. The list
      // providers fetch fresh /trips on next watch.
      ref.invalidate(activeTripsProvider);
      ref.invalidate(tripDetailProvider(widget.trip.id));
      if (!mounted) return;
      // pop with the sentinel string `'deleted'` so the caller can route
      // away from the now-gone trip detail page; `true` is reserved for
      // edits and just triggers a refresh.
      Navigator.of(context).pop('deleted');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "${widget.trip.name}".')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Server returns 409 trips/has-expenses if anything was logged
        // between the time we opened the dialog and now — surface the
        // server message verbatim so the admin sees the real reason.
        _error = 'Could not delete: $e';
        _deleting = false;
      });
    }
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
}

class _LeaderPicker extends StatelessWidget {
  const _LeaderPicker({
    required this.users,
    required this.selected,
    required this.onPick,
  });

  final List<User> users;
  final String selected;
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
            selected: u.id == selected,
            onSelected: (_) => onPick(u.id),
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
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final User u in users)
          FilterChip(
            label: Text(u.displayName),
            selected: selected.contains(u.id),
            onSelected: (bool v) => onToggle(u.id, v),
          ),
      ],
    );
  }
}
