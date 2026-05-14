import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme.dart';
import '../../../funds/application/funds_providers.dart';
import '../../../funds/domain/funding.dart';
import '../../application/expenses_providers.dart';
import '../../domain/expense.dart';

/// Active filter state per trip. Filter applies to both the My Expenses
/// list view and the breakdown chart.
class ExpenseFilterState {
  const ExpenseFilterState({
    this.categoryCodes = const <String>{},
    this.sourceIds = const <String>{},
    this.from,
    this.to,
  });

  final Set<String> categoryCodes;
  final Set<String> sourceIds;
  final DateTime? from;
  final DateTime? to;

  bool get isEmpty =>
      categoryCodes.isEmpty &&
      sourceIds.isEmpty &&
      from == null &&
      to == null;

  int get count {
    int c = 0;
    if (categoryCodes.isNotEmpty) c++;
    if (sourceIds.isNotEmpty) c++;
    if (from != null || to != null) c++;
    return c;
  }

  ExpenseFilter toRepoFilter() => ExpenseFilter(
    categoryCodes: categoryCodes.isEmpty ? null : categoryCodes.toList(),
    sourceIds: sourceIds.isEmpty ? null : sourceIds.toList(),
    from: from,
    to: to,
  );

  ExpenseFilterState copyWith({
    Set<String>? categoryCodes,
    Set<String>? sourceIds,
    DateTime? from,
    DateTime? to,
    bool clearFrom = false,
    bool clearTo = false,
  }) => ExpenseFilterState(
    categoryCodes: categoryCodes ?? this.categoryCodes,
    sourceIds: sourceIds ?? this.sourceIds,
    from: clearFrom ? null : (from ?? this.from),
    to: clearTo ? null : (to ?? this.to),
  );
}

/// Per-trip filter — preserved as the user navigates between list and chart.
final StateProviderFamily<ExpenseFilterState, String> expenseFilterProvider =
    StateProvider.family<ExpenseFilterState, String>(
      (Ref ref, String tripId) => const ExpenseFilterState(),
    );

Future<void> showExpenseFilterSheet(
  BuildContext context, {
  required String tripId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext _) => _ExpenseFilterSheet(tripId: tripId),
  );
}

class _ExpenseFilterSheet extends ConsumerStatefulWidget {
  const _ExpenseFilterSheet({required this.tripId});
  final String tripId;

  @override
  ConsumerState<_ExpenseFilterSheet> createState() =>
      _ExpenseFilterSheetState();
}

class _ExpenseFilterSheetState extends ConsumerState<_ExpenseFilterSheet> {
  late ExpenseFilterState _draft;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(expenseFilterProvider(widget.tripId));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<ExpenseCategory>> catsAsync = ref.watch(
      categoriesProvider,
    );
    final AsyncValue<List<Source>> sourcesAsync = ref.watch(sourcesProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (BuildContext context, ScrollController scroll) {
        return Column(
          children: <Widget>[
            const _GrabHandle(),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    'FILTER',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(
                      () => _draft = const ExpenseFilterState(),
                    ),
                    child: const Text('CLEAR ALL'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: <Widget>[
                  _section('BY CATEGORY'),
                  catsAsync.maybeWhen(
                    data: (List<ExpenseCategory> cats) => Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: <Widget>[
                        for (final ExpenseCategory c in cats)
                          FilterChip(
                            label: Text(c.nameEn),
                            selected: _draft.categoryCodes.contains(c.code),
                            onSelected: (bool v) => setState(() {
                              final Set<String> next = Set<String>.from(
                                _draft.categoryCodes,
                              );
                              if (v) {
                                next.add(c.code);
                              } else {
                                next.remove(c.code);
                              }
                              _draft = _draft.copyWith(categoryCodes: next);
                            }),
                            selectedColor: AppColors.forCategory(c.code),
                            labelStyle: TextStyle(
                              color: _draft.categoryCodes.contains(c.code)
                                  ? Colors.white
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    orElse: () => const LinearProgressIndicator(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _section('BY SOURCE'),
                  sourcesAsync.maybeWhen(
                    data: (List<Source> sources) => Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: <Widget>[
                        for (final Source s in sources)
                          FilterChip(
                            label: Text(s.name),
                            selected: _draft.sourceIds.contains(s.id),
                            onSelected: (bool v) => setState(() {
                              final Set<String> next = Set<String>.from(
                                _draft.sourceIds,
                              );
                              if (v) {
                                next.add(s.id);
                              } else {
                                next.remove(s.id);
                              }
                              _draft = _draft.copyWith(sourceIds: next);
                            }),
                            selectedColor: AppColors.brandBrown,
                            labelStyle: TextStyle(
                              color: _draft.sourceIds.contains(s.id)
                                  ? AppColors.cream
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    orElse: () => const LinearProgressIndicator(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _section('BY DATE'),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _DateTile(
                          label: 'FROM',
                          value: _draft.from,
                          onPick: (DateTime? d) => setState(
                            () => _draft = _draft.copyWith(
                              from: d,
                              clearFrom: d == null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _DateTile(
                          label: 'TO',
                          value: _draft.to,
                          onPick: (DateTime? d) => setState(
                            () => _draft = _draft.copyWith(
                              to: d,
                              clearTo: d == null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SafeArea(
                top: false,
                child: FilledButton(
                  onPressed: () {
                    ref.read(expenseFilterProvider(widget.tripId).notifier).state =
                        _draft;
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    _draft.isEmpty
                        ? 'APPLY (no filters)'
                        : 'APPLY ${_draft.count} FILTER${_draft.count == 1 ? '' : 'S'}',
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: AppColors.textSecondary,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.cream,
          borderRadius: const BorderRadius.all(AppRadii.chip),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    value == null ? 'Any' : DateFormat.yMMMd().format(value!),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (value != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => onPick(null),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}
