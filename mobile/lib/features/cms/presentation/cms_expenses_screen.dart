import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart' show AppRadii, AppSpacing;
import '../../../core/api/hydration_service.dart';
import '../../../core/fake/demo_store.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../expenses/domain/expense.dart';
import '../../trips/domain/trip.dart';
import 'admin_expense_comment_dialog.dart';
import 'cms_dashboard.dart' show dashboardDataProvider, DashboardData;
import 'widgets/cms_layout.dart';
import 'widgets/cms_theme.dart';

/// Admin-only "all expenses" screen — every expense logged across every
/// trip with filter chips up top and a chat affordance per row that opens
/// the existing AdminExpenseCommentDialog so the admin can question the
/// submitter via @mention.
class CmsExpensesScreen extends ConsumerStatefulWidget {
  const CmsExpensesScreen({super.key});

  @override
  ConsumerState<CmsExpensesScreen> createState() => _CmsExpensesScreenState();
}

class _CmsExpensesScreenState extends ConsumerState<CmsExpensesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  String? _tripFilter;
  String? _userFilter;
  String? _categoryFilter;
  String? _sourceFilter;
  DateTimeRange? _dateRange;
  bool _missingReceiptOnly = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (_searchCtrl.text != _search) {
        setState(() => _search = _searchCtrl.text);
      }
    });
    // Honour `?missingReceipt=1` on first load so /cms/receipts can
    // redirect here with the right filter pre-applied. Run on the next
    // frame so context-driven routing is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final String? mr = GoRouterState.of(context)
          .uri.queryParameters['missingReceipt'];
      if (mr == '1' || mr == 'true') {
        setState(() => _missingReceiptOnly = true);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearAll() => setState(() {
        _searchCtrl.clear();
        _search = '';
        _tripFilter = null;
        _userFilter = null;
        _categoryFilter = null;
        _sourceFilter = null;
        _dateRange = null;
        _missingReceiptOnly = false;
      });

  bool _hasAnyFilter() =>
      _search.trim().isNotEmpty ||
      _tripFilter != null ||
      _userFilter != null ||
      _categoryFilter != null ||
      _sourceFilter != null ||
      _dateRange != null ||
      _missingReceiptOnly;

  bool _passes(Expense e) {
    if (_tripFilter != null && e.tripId != _tripFilter) return false;
    if (_userFilter != null && e.userId != _userFilter) return false;
    if (_categoryFilter != null && e.categoryCode != _categoryFilter) {
      return false;
    }
    if (_sourceFilter != null && e.sourceId != _sourceFilter) return false;
    if (_missingReceiptOnly && e.receiptObjectKey != null) return false;
    if (_dateRange != null) {
      if (e.occurredAt.isBefore(_dateRange!.start) ||
          e.occurredAt.isAfter(_dateRange!.end.add(const Duration(days: 1)))) {
        return false;
      }
    }
    if (_search.trim().isNotEmpty) {
      final String q = _search.trim().toLowerCase();
      if (!e.details.toLowerCase().contains(q)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    if (me == null ||
        (me.role != UserRole.admin && me.role != UserRole.superAdmin)) {
      return const CmsLayout(
        active: CmsNavItem.expenses,
        title: 'Expenses',
        child: Center(child: Text('Admin only.')),
      );
    }
    final AsyncValue<bool> hydration =
        ref.watch(authenticatedHydrationProvider);
    final AsyncValue<DashboardData> dataAsync =
        ref.watch(dashboardDataProvider);

    return CmsLayout(
      active: CmsNavItem.expenses,
      title: 'Expenses',
      titleSubtitle:
          'Every expense logged across every trip — filter, inspect, query.',
      child: hydration.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (bool _) => dataAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, _) => Center(child: Text('Error: $e')),
          data: (DashboardData d) {
            final List<Expense> sorted = <Expense>[...d.expenses]
              ..sort((Expense a, Expense b) =>
                  b.occurredAt.compareTo(a.occurredAt));
            final List<Expense> filtered =
                sorted.where(_passes).toList(growable: false);
            return _Body(
              data: d,
              filtered: filtered,
              total: sorted.length,
              searchCtrl: _searchCtrl,
              tripFilter: _tripFilter,
              userFilter: _userFilter,
              categoryFilter: _categoryFilter,
              sourceFilter: _sourceFilter,
              dateRange: _dateRange,
              missingReceiptOnly: _missingReceiptOnly,
              onTripChange: (String? v) => setState(() => _tripFilter = v),
              onUserChange: (String? v) => setState(() => _userFilter = v),
              onCategoryChange: (String? v) =>
                  setState(() => _categoryFilter = v),
              onSourceChange: (String? v) =>
                  setState(() => _sourceFilter = v),
              onDateChange: (DateTimeRange? r) =>
                  setState(() => _dateRange = r),
              onMissingReceiptToggle: () => setState(
                () => _missingReceiptOnly = !_missingReceiptOnly,
              ),
              onClearAll: _clearAll,
              hasAnyFilter: _hasAnyFilter(),
            );
          },
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.data,
    required this.filtered,
    required this.total,
    required this.searchCtrl,
    required this.tripFilter,
    required this.userFilter,
    required this.categoryFilter,
    required this.sourceFilter,
    required this.dateRange,
    required this.missingReceiptOnly,
    required this.onTripChange,
    required this.onUserChange,
    required this.onCategoryChange,
    required this.onSourceChange,
    required this.onDateChange,
    required this.onMissingReceiptToggle,
    required this.onClearAll,
    required this.hasAnyFilter,
  });

  final DashboardData data;
  final List<Expense> filtered;
  final int total;
  final TextEditingController searchCtrl;
  final String? tripFilter;
  final String? userFilter;
  final String? categoryFilter;
  final String? sourceFilter;
  final DateTimeRange? dateRange;
  final bool missingReceiptOnly;
  final ValueChanged<String?> onTripChange;
  final ValueChanged<String?> onUserChange;
  final ValueChanged<String?> onCategoryChange;
  final ValueChanged<String?> onSourceChange;
  final ValueChanged<DateTimeRange?> onDateChange;
  final VoidCallback onMissingReceiptToggle;
  final VoidCallback onClearAll;
  final bool hasAnyFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DemoStore store = ref.read(demoStoreProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _FilterBar(
            searchCtrl: searchCtrl,
            tripFilter: tripFilter,
            userFilter: userFilter,
            categoryFilter: categoryFilter,
            sourceFilter: sourceFilter,
            dateRange: dateRange,
            missingReceiptOnly: missingReceiptOnly,
            data: data,
            store: store,
            onTripChange: onTripChange,
            onUserChange: onUserChange,
            onCategoryChange: onCategoryChange,
            onSourceChange: onSourceChange,
            onDateChange: onDateChange,
            onMissingReceiptToggle: onMissingReceiptToggle,
            onClearAll: onClearAll,
            hasAnyFilter: hasAnyFilter,
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              'Showing ${filtered.length} of $total '
              'expense${total == 1 ? '' : 's'}'
              '${hasAnyFilter ? ' (filtered)' : ''}',
              style: const TextStyle(
                color: CmsColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: CmsColors.surfaceCard,
              borderRadius: const BorderRadius.all(AppRadii.card),
              border: Border.all(color: CmsColors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (BuildContext _, BoxConstraints c) {
                const double minTableWidth = 1080.0;
                final double tableWidth =
                    c.maxWidth >= minTableWidth ? c.maxWidth : minTableWidth;
                final Widget table = SizedBox(
                  width: tableWidth,
                  child: Column(
                    children: <Widget>[
                      _Header(),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              'No expenses match the current filters.',
                              style:
                                  TextStyle(color: CmsColors.textSecondary),
                            ),
                          ),
                        )
                      else
                        for (int i = 0; i < filtered.length; i++) ...<Widget>[
                          if (i > 0)
                            const Divider(
                              height: 1, color: CmsColors.divider,
                            ),
                          _Row(expense: filtered[i], store: store),
                        ],
                    ],
                  ),
                );
                if (tableWidth <= c.maxWidth) return table;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: table,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Filter bar
// ============================================================================

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchCtrl,
    required this.tripFilter,
    required this.userFilter,
    required this.categoryFilter,
    required this.sourceFilter,
    required this.dateRange,
    required this.missingReceiptOnly,
    required this.data,
    required this.store,
    required this.onTripChange,
    required this.onUserChange,
    required this.onCategoryChange,
    required this.onSourceChange,
    required this.onDateChange,
    required this.onMissingReceiptToggle,
    required this.onClearAll,
    required this.hasAnyFilter,
  });

  final TextEditingController searchCtrl;
  final String? tripFilter;
  final String? userFilter;
  final String? categoryFilter;
  final String? sourceFilter;
  final DateTimeRange? dateRange;
  final bool missingReceiptOnly;
  final DashboardData data;
  final DemoStore store;
  final ValueChanged<String?> onTripChange;
  final ValueChanged<String?> onUserChange;
  final ValueChanged<String?> onCategoryChange;
  final ValueChanged<String?> onSourceChange;
  final ValueChanged<DateTimeRange?> onDateChange;
  final VoidCallback onMissingReceiptToggle;
  final VoidCallback onClearAll;
  final bool hasAnyFilter;

  @override
  Widget build(BuildContext context) {
    // Pull unique users referenced by the loaded expenses (any user who
    // logged at least one expense is searchable). Trips/categories/sources
    // come straight from the dashboard aggregate which already has them.
    final Map<String, String> usersById = <String, String>{};
    for (final Expense e in data.expenses) {
      if (usersById.containsKey(e.userId)) continue;
      try {
        usersById[e.userId] = store.userById(e.userId).displayName;
      } catch (_) {
        usersById[e.userId] = e.userId;
      }
    }
    final List<MapEntry<String, String>> userOptions =
        usersById.entries.toList()
          ..sort((MapEntry<String, String> a, MapEntry<String, String> b) =>
              a.value.compareTo(b.value));

    final List<Trip> trips = <Trip>[...data.trips]
      ..sort((Trip a, Trip b) => a.name.compareTo(b.name));

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          SizedBox(width: 240, child: _SearchInput(ctrl: searchCtrl)),
          SizedBox(
            width: 200,
            child: _DropdownField(
              value: tripFilter,
              hint: 'All trips',
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  value: null, child: Text('All trips'),
                ),
                for (final Trip t in trips)
                  DropdownMenuItem<String?>(
                    value: t.id, child: Text(t.name),
                  ),
              ],
              onChanged: onTripChange,
            ),
          ),
          SizedBox(
            width: 180,
            child: _DropdownField(
              value: userFilter,
              hint: 'All users',
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  value: null, child: Text('All users'),
                ),
                for (final MapEntry<String, String> u in userOptions)
                  DropdownMenuItem<String?>(
                    value: u.key, child: Text(u.value),
                  ),
              ],
              onChanged: onUserChange,
            ),
          ),
          SizedBox(
            width: 160,
            child: _DropdownField(
              value: categoryFilter,
              hint: 'All categories',
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  value: null, child: Text('All categories'),
                ),
                for (final c in data.expenses
                    .map((Expense e) => e.categoryCode)
                    .toSet()
                    .toList()
                  ..sort())
                  DropdownMenuItem<String?>(
                    value: c, child: Text(c),
                  ),
              ],
              onChanged: onCategoryChange,
            ),
          ),
          SizedBox(
            width: 180,
            child: _DropdownField(
              value: sourceFilter,
              hint: 'All sources',
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  value: null, child: Text('All sources'),
                ),
                for (final src in data.sources)
                  DropdownMenuItem<String?>(
                    value: src.id, child: Text(src.name),
                  ),
              ],
              onChanged: onSourceChange,
            ),
          ),
          _DateRangeButton(range: dateRange, onChange: onDateChange),
          FilterChip(
            label: const Text('Missing receipt'),
            selected: missingReceiptOnly,
            onSelected: (_) => onMissingReceiptToggle(),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: missingReceiptOnly
                  ? CmsColors.outflow
                  : CmsColors.textBody,
            ),
            backgroundColor: CmsColors.surfaceCard,
            selectedColor: CmsColors.redSoft,
            side: BorderSide(
              color: missingReceiptOnly
                  ? CmsColors.outflow
                  : CmsColors.divider,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            visualDensity: VisualDensity.compact,
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
                hintText: 'Search vendor or note…',
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

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });
  final String? value;
  final String hint;
  final List<DropdownMenuItem<String?>> items;
  final ValueChanged<String?> onChanged;

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
        child: DropdownButton<String?>(
          value: value,
          isExpanded: true,
          hint: Text(
            hint,
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

// ============================================================================
// Table
// ============================================================================

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    TextStyle h() => const TextStyle(
          color: CmsColors.textTertiary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: const BoxDecoration(
        color: CmsColors.bgElev,
        border: Border(bottom: BorderSide(color: CmsColors.divider)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(width: 80, child: Text('DATE', style: h())),
          Expanded(flex: 3, child: Text('USER', style: h())),
          Expanded(flex: 3, child: Text('TRIP', style: h())),
          Expanded(flex: 2, child: Text('CATEGORY', style: h())),
          Expanded(flex: 3, child: Text('SOURCE', style: h())),
          Expanded(flex: 4, child: Text('VENDOR / NOTE', style: h())),
          SizedBox(
            width: 100,
            child: Text('AMOUNT', style: h(), textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 130,
            child: Text('ACTIONS', style: h(), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.expense, required this.store});
  final Expense expense;
  final DemoStore store;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String userName;
    try {
      userName = store.userById(expense.userId).displayName;
    } catch (_) {
      userName = '—';
    }
    String tripName;
    String tripCountry;
    try {
      final Trip t = store.tripById(expense.tripId);
      tripName = t.name;
      tripCountry = t.countryCode.toUpperCase();
    } catch (_) {
      tripName = expense.tripId;
      tripCountry = '';
    }
    String categoryName;
    try {
      categoryName = store.categoryByCode(expense.categoryCode).nameEn;
    } catch (_) {
      categoryName = expense.categoryCode;
    }
    String sourceName;
    try {
      sourceName = store.sourceById(expense.sourceId).name;
    } catch (_) {
      sourceName = expense.sourceId;
    }
    final bool hasReceipt = expense.receiptObjectKey != null;
    return InkWell(
      onTap: () => context.go('/cms/expenses/${expense.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 80,
              child: Text(
                DateFormat('d MMM').format(expense.occurredAt.toLocal()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CmsColors.textBody, fontSize: 12,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CmsColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                tripCountry.isEmpty ? tripName : '$tripCountry · $tripName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CmsColors.textBody, fontSize: 12,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                categoryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CmsColors.textBody, fontSize: 12,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                sourceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CmsColors.textBody, fontSize: 12,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: <Widget>[
                  if (!hasReceipt) ...<Widget>[
                    Icon(
                      Icons.report_problem_outlined,
                      size: 13,
                      color: CmsColors.outflow,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      expense.details.isEmpty ? '—' : expense.details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CmsColors.textBody, fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 100,
              child: Text(
                expense.amount.format(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: CmsColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            SizedBox(
              width: 130,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  // Labeled "Ask" button — the bare icon was easy to miss.
                  // Stops row-tap propagation by wrapping in its own GestureDetector
                  // so the chat button doesn't double-fire the row's
                  // "open trip detail" handler.
                  OutlinedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          AdminExpenseCommentDialog(expense: expense),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline, size: 13),
                    label: const Text('Ask'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CmsColors.brand,
                      side: BorderSide(
                        color: CmsColors.brand.withValues(alpha: 0.5),
                      ),
                      minimumSize: const Size(0, 28),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_forward,
                    size: 13, color: CmsColors.textTertiary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
