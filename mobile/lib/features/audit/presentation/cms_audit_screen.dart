import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart' show AppRadii, AppSpacing;
import '../../cms/presentation/widgets/cms_layout.dart';
import '../../cms/presentation/widgets/cms_theme.dart';
import '../application/audit_providers.dart';
import '../domain/audit_entry.dart';

/// Admin-only "who did what, when" feed. Reached from the dashboard's
/// Recent activity → View log link.
///
/// Filters are applied client-side because the entire audit response is
/// already loaded for the dashboard rail — a server query per filter
/// change would be unnecessary chatter. When the dataset grows, swap to
/// server-side pagination + filter params on the same UI.
class CmsAuditScreen extends ConsumerStatefulWidget {
  const CmsAuditScreen({super.key});

  @override
  ConsumerState<CmsAuditScreen> createState() => _CmsAuditScreenState();
}

class _CmsAuditScreenState extends ConsumerState<CmsAuditScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  Set<AuditAction> _actionFilter = <AuditAction>{};
  String? _actorFilter; // actor user id
  String? _tripFilter; // trip id
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (_searchCtrl.text != _search) {
        setState(() => _search = _searchCtrl.text);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearAll() {
    setState(() {
      _searchCtrl.clear();
      _search = '';
      _actionFilter = <AuditAction>{};
      _actorFilter = null;
      _tripFilter = null;
      _dateRange = null;
    });
  }

  bool _passes(AuditEntry e) {
    if (_actionFilter.isNotEmpty && !_actionFilter.contains(e.action)) {
      return false;
    }
    if (_actorFilter != null && e.actorId != _actorFilter) return false;
    if (_tripFilter != null && e.tripId != _tripFilter) return false;
    if (_dateRange != null) {
      if (e.at.isBefore(_dateRange!.start) ||
          e.at.isAfter(_dateRange!.end.add(const Duration(days: 1)))) {
        return false;
      }
    }
    if (_search.trim().isNotEmpty) {
      final String q = _search.trim().toLowerCase();
      final bool hit = e.summary.toLowerCase().contains(q) ||
          e.actorName.toLowerCase().contains(q) ||
          (e.tripName?.toLowerCase().contains(q) ?? false);
      if (!hit) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<AuditEntry>> async = ref.watch(auditFeedProvider);

    return CmsLayout(
      active: CmsNavItem.audit,
      title: 'Audit log',
      titleSubtitle:
          'Every financial mutation and lifecycle event, in chronological order.',
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load audit feed: $e',
              style: const TextStyle(color: CmsColors.outflow),
            ),
          ),
        ),
        data: (List<AuditEntry> entries) {
          final List<AuditEntry> filtered =
              entries.where(_passes).toList(growable: false);
          final List<({String id, String name})> actors =
              _uniqueActors(entries);
          final List<({String id, String name})> trips =
              _uniqueTrips(entries);

          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _FilterBar(
                  searchCtrl: _searchCtrl,
                  actionFilter: _actionFilter,
                  actorFilter: _actorFilter,
                  tripFilter: _tripFilter,
                  dateRange: _dateRange,
                  actors: actors,
                  trips: trips,
                  onActionToggle: (AuditAction a) => setState(() {
                    if (_actionFilter.contains(a)) {
                      _actionFilter = <AuditAction>{..._actionFilter}
                        ..remove(a);
                    } else {
                      _actionFilter = <AuditAction>{..._actionFilter, a};
                    }
                  }),
                  onActorChange: (String? v) =>
                      setState(() => _actorFilter = v),
                  onTripChange: (String? v) =>
                      setState(() => _tripFilter = v),
                  onDateChange: (DateTimeRange? r) =>
                      setState(() => _dateRange = r),
                  onClearAll: _clearAll,
                  hasAnyFilter: _hasAnyFilter(),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 4,
                  ),
                  child: Text(
                    'Showing ${filtered.length} of ${entries.length} '
                    'entr${entries.length == 1 ? 'y' : 'ies'}'
                    '${_hasAnyFilter() ? ' (filtered)' : ''}',
                    style: const TextStyle(
                      color: CmsColors.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(child: _AuditTable(entries: filtered)),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _hasAnyFilter() =>
      _search.trim().isNotEmpty ||
      _actionFilter.isNotEmpty ||
      _actorFilter != null ||
      _tripFilter != null ||
      _dateRange != null;

  List<({String id, String name})> _uniqueActors(List<AuditEntry> entries) {
    final Map<String, String> map = <String, String>{};
    for (final AuditEntry e in entries) {
      if (e.actorId != null && !map.containsKey(e.actorId)) {
        map[e.actorId!] = e.actorName;
      }
    }
    final List<({String id, String name})> list =
        map.entries.map((MapEntry<String, String> e) =>
            (id: e.key, name: e.value)).toList();
    list.sort((({String id, String name}) a, ({String id, String name}) b) =>
        a.name.compareTo(b.name));
    return list;
  }

  List<({String id, String name})> _uniqueTrips(List<AuditEntry> entries) {
    final Map<String, String> map = <String, String>{};
    for (final AuditEntry e in entries) {
      if (e.tripId != null && e.tripName != null && !map.containsKey(e.tripId)) {
        map[e.tripId!] = e.tripName!;
      }
    }
    final List<({String id, String name})> list =
        map.entries.map((MapEntry<String, String> e) =>
            (id: e.key, name: e.value)).toList();
    list.sort((({String id, String name}) a, ({String id, String name}) b) =>
        a.name.compareTo(b.name));
    return list;
  }
}

// ============================================================================
// Filter bar
// ============================================================================

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchCtrl,
    required this.actionFilter,
    required this.actorFilter,
    required this.tripFilter,
    required this.dateRange,
    required this.actors,
    required this.trips,
    required this.onActionToggle,
    required this.onActorChange,
    required this.onTripChange,
    required this.onDateChange,
    required this.onClearAll,
    required this.hasAnyFilter,
  });

  final TextEditingController searchCtrl;
  final Set<AuditAction> actionFilter;
  final String? actorFilter;
  final String? tripFilter;
  final DateTimeRange? dateRange;
  final List<({String id, String name})> actors;
  final List<({String id, String name})> trips;
  final ValueChanged<AuditAction> onActionToggle;
  final ValueChanged<String?> onActorChange;
  final ValueChanged<String?> onTripChange;
  final ValueChanged<DateTimeRange?> onDateChange;
  final VoidCallback onClearAll;
  final bool hasAnyFilter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Top row: search + actor + trip + date + clear
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(width: 240, child: _SearchInput(ctrl: searchCtrl)),
              SizedBox(
                width: 200,
                child: _DropdownField<String>(
                  label: 'Actor',
                  value: actorFilter,
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null, child: Text('All actors'),
                    ),
                    for (final ({String id, String name}) a in actors)
                      DropdownMenuItem<String?>(
                        value: a.id, child: Text(a.name),
                      ),
                  ],
                  onChanged: onActorChange,
                ),
              ),
              SizedBox(
                width: 200,
                child: _DropdownField<String>(
                  label: 'Trip',
                  value: tripFilter,
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null, child: Text('All trips'),
                    ),
                    for (final ({String id, String name}) t in trips)
                      DropdownMenuItem<String?>(
                        value: t.id, child: Text(t.name),
                      ),
                  ],
                  onChanged: onTripChange,
                ),
              ),
              _DateRangeButton(
                range: dateRange,
                onChange: onDateChange,
              ),
              if (hasAnyFilter)
                TextButton.icon(
                  onPressed: onClearAll,
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Clear all'),
                  style: TextButton.styleFrom(
                    foregroundColor: CmsColors.textSecondary,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Action-type chips
          Row(
            children: <Widget>[
              const Text(
                'ACTION',
                style: TextStyle(
                  color: CmsColors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final AuditAction a in AuditAction.values)
                      _ActionFilterChip(
                        action: a,
                        selected: actionFilter.contains(a),
                        onTap: () => onActionToggle(a),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchInput extends StatelessWidget {
  const _SearchInput({required this.ctrl});
  final TextEditingController ctrl;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CmsColors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: <Widget>[
          const Icon(Icons.search, size: 14, color: CmsColors.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search summary, actor, trip…',
                hintStyle: TextStyle(
                  color: CmsColors.textTertiary, fontSize: 12,
                ),
              ),
              style: const TextStyle(
                color: CmsColors.textPrimary, fontSize: 12,
              ),
            ),
          ),
          if (ctrl.text.isNotEmpty)
            InkWell(
              onTap: () => ctrl.clear(),
              child: const Icon(
                Icons.close, size: 14, color: CmsColors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final T? value;
  final List<DropdownMenuItem<T?>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CmsColors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isExpanded: true,
          hint: Text(
            'All ${label.toLowerCase()}s',
            style: const TextStyle(
              color: CmsColors.textTertiary, fontSize: 12,
            ),
          ),
          icon: const Icon(
            Icons.expand_more, size: 16, color: CmsColors.textSecondary,
          ),
          style: const TextStyle(
            color: CmsColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DateRangeButton extends StatelessWidget {
  const _DateRangeButton({required this.range, required this.onChange});
  final DateTimeRange? range;
  final ValueChanged<DateTimeRange?> onChange;
  @override
  Widget build(BuildContext context) {
    final String label = range == null
        ? 'Any date'
        : '${DateFormat('MMM d').format(range!.start)} — '
            '${DateFormat('MMM d').format(range!.end)}';
    return OutlinedButton.icon(
      onPressed: () async {
        final DateTimeRange? picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2024),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          initialDateRange: range,
        );
        if (picked != null) onChange(picked);
      },
      icon: const Icon(Icons.event_outlined, size: 14),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: CmsColors.divider),
        foregroundColor: CmsColors.textBody,
        backgroundColor: CmsColors.surfaceCard,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _ActionFilterChip extends StatelessWidget {
  const _ActionFilterChip({
    required this.action,
    required this.selected,
    required this.onTap,
  });
  final AuditAction action;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final ({String label, Color color, Color bg, IconData icon}) cfg =
        _ActionChip._cfgFor(action);
    return Material(
      color: selected ? cfg.bg : CmsColors.surfaceCard,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? cfg.color : CmsColors.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(cfg.icon, size: 11, color: cfg.color),
              const SizedBox(width: 4),
              Text(
                cfg.label,
                style: TextStyle(
                  color: selected ? cfg.color : CmsColors.textBody,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Table
// ============================================================================

class _AuditTable extends StatelessWidget {
  const _AuditTable({required this.entries});
  final List<AuditEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: CmsColors.surfaceCard,
          borderRadius: const BorderRadius.all(AppRadii.card),
          border: Border.all(color: CmsColors.divider),
        ),
        alignment: Alignment.center,
        child: const Text(
          'No entries match the current filters.',
          style: TextStyle(color: CmsColors.textSecondary),
        ),
      );
    }
    final DateFormat dateFmt = DateFormat('d MMM yyyy · HH:mm');
    // No horizontal scroll wrapping here — the previous Flexible(ListView)
    // inside ConstrainedBox(minWidth) inside SingleChildScrollView caused
    // a layout deadlock that locked up the page. Columns are flex-sized
    // and every Text has maxLines + ellipsis instead.
    return Container(
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              color: CmsColors.bgElev,
              border: Border(
                bottom: BorderSide(color: CmsColors.divider),
              ),
            ),
            child: Row(
              children: const <Widget>[
                Expanded(flex: 3, child: _Th(label: 'WHEN')),
                Expanded(flex: 3, child: _Th(label: 'WHO')),
                Expanded(flex: 3, child: _Th(label: 'ACTION')),
                Expanded(flex: 4, child: _Th(label: 'SUMMARY')),
                Expanded(flex: 2, child: _Th(label: 'TRIP')),
                Expanded(
                  flex: 2,
                  child: _Th(label: 'AMOUNT', align: TextAlign.right),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: CmsColors.divider),
              itemBuilder: (BuildContext context, int i) {
                final AuditEntry e = entries[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        flex: 3,
                        child: Text(
                          dateFmt.format(e.at.toLocal()),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: CmsColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: _WhoCell(
                            name: e.actorName, role: e.actorRole),
                      ),
                      Expanded(
                        flex: 3,
                        child: _ActionChip(action: e.action),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          e.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          e.tripName ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: CmsColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          e.amount?.format() ?? '',
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Th extends StatelessWidget {
  const _Th({required this.label, this.align = TextAlign.left});
  final String label;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: align,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: CmsColors.textSecondary,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _WhoCell extends StatelessWidget {
  const _WhoCell({required this.name, required this.role});
  final String name;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          _roleLabel(role),
          style: const TextStyle(fontSize: 11, color: CmsColors.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _roleLabel(String r) {
    switch (r) {
      case 'ADMIN':
        return 'Admin';
      case 'SUPER_ADMIN':
        return 'Director General';
      case 'LEADER':
        return 'Trip Leader';
      case 'MEMBER':
        return 'Team Member';
      default:
        return r;
    }
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.action});
  final AuditAction action;

  @override
  Widget build(BuildContext context) {
    final ({String label, Color color, Color bg, IconData icon}) cfg =
        _cfgFor(action);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cfg.bg,
          borderRadius: const BorderRadius.all(AppRadii.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(cfg.icon, size: 12, color: cfg.color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                cfg.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cfg.color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Style config per action. Public to the file so `_ActionFilterChip`
  /// can reuse the same icon/color set when building the filter row.
  static ({String label, Color color, Color bg, IconData icon}) _cfgFor(
    AuditAction a,
  ) {
    switch (a) {
      case AuditAction.tripCreated:
        return (
          label: 'TRIP CREATED',
          color: CmsColors.brand,
          bg: CmsColors.brandTint,
          icon: Icons.flight_takeoff_outlined,
        );
      case AuditAction.tripClosed:
        return (
          label: 'TRIP CLOSED',
          color: CmsColors.textSecondary,
          bg: CmsColors.bgInset,
          icon: Icons.lock_outline,
        );
      case AuditAction.allocationFromAdmin:
        return (
          label: 'ADMIN ALLOC',
          color: CmsColors.brand,
          bg: CmsColors.brandTint,
          icon: Icons.account_balance_outlined,
        );
      case AuditAction.allocationFromLeader:
        return (
          label: 'LEADER ALLOC',
          color: CmsColors.goldDeep,
          bg: CmsColors.goldSoft,
          icon: Icons.swap_calls_outlined,
        );
      case AuditAction.allocationAccepted:
        return (
          label: 'ACCEPTED',
          color: CmsColors.green,
          bg: CmsColors.greenSoft,
          icon: Icons.check_circle_outline,
        );
      case AuditAction.allocationDeclined:
        return (
          label: 'DECLINED',
          color: CmsColors.red,
          bg: CmsColors.redSoft,
          icon: Icons.cancel_outlined,
        );
      case AuditAction.transferSent:
        return (
          label: 'TRANSFER',
          color: CmsColors.blue,
          bg: CmsColors.blueSoft,
          icon: Icons.compare_arrows,
        );
      case AuditAction.transferAccepted:
        return (
          label: 'XFER ACCEPTED',
          color: CmsColors.green,
          bg: CmsColors.greenSoft,
          icon: Icons.check_circle_outline,
        );
      case AuditAction.transferDeclined:
        return (
          label: 'XFER DECLINED',
          color: CmsColors.red,
          bg: CmsColors.redSoft,
          icon: Icons.cancel_outlined,
        );
      case AuditAction.expenseLogged:
        return (
          label: 'EXPENSE',
          color: CmsColors.amber,
          bg: CmsColors.amberSoft,
          icon: Icons.receipt_long_outlined,
        );
      case AuditAction.userSignedIn:
        return (
          label: 'SIGN IN',
          color: CmsColors.textSecondary,
          bg: CmsColors.bgInset,
          icon: Icons.login,
        );
      case AuditAction.userCreated:
        return (
          label: 'USER CREATED',
          color: CmsColors.brand,
          bg: CmsColors.brandTint,
          icon: Icons.person_add_alt_1,
        );
      case AuditAction.userUpdated:
        return (
          label: 'USER UPDATED',
          color: CmsColors.brand,
          bg: CmsColors.brandTint,
          icon: Icons.edit_outlined,
        );
    }
  }
}
