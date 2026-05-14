import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/expenses_providers.dart';
import '../data/expense_repository.dart';
import '../domain/expense.dart';

/// Screen-inventory #9 — Expense detail (read).
class ExpenseDetailScreen extends ConsumerWidget {
  const ExpenseDetailScreen({
    super.key,
    required this.tripId,
    required this.expenseId,
  });
  final String tripId;
  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExpenseRepository repo = ref.watch(expenseRepositoryProvider);
    final AsyncValue<Trip> tripAsync = ref.watch(tripDetailProvider(tripId));
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    final DemoStore store = ref.read(demoStoreProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/m/trips/$tripId/expenses/mine'),
        ),
        title: const Text('EXPENSE'),
      ),
      body: FutureBuilder<Expense>(
        future: repo.byId(expenseId),
        builder: (BuildContext context, AsyncSnapshot<Expense> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          final Expense e = snap.data!;
          final bool canEdit =
              me?.id == e.userId &&
              tripAsync.maybeWhen(
                data: (Trip t) => t.status != TripStatus.closed,
                orElse: () => false,
              );
          final String sourceName = store.sourceById(e.sourceId).name;
          final String categoryName = store
              .categoryByCode(e.categoryCode)
              .nameEn;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: <Widget>[
                Align(
                  alignment: Alignment.centerRight,
                  child: canEdit
                      ? IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Inline editing lands in Milestone A slice 4.',
                                ),
                              ),
                            );
                          },
                        )
                      : const SizedBox.shrink(),
                ),
                Text(
                  '${_pad(e.occurredAt.hour)}:${_pad(e.occurredAt.minute)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  _longDate(e.occurredAt),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.goldOlive.withValues(alpha: 0.15),
                    border: Border.all(color: AppColors.goldOlive, width: 3),
                  ),
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: FittedBox(
                      child: Text(
                        e.amount.format(),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: AppColors.brandBrown,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                _DetailRow(
                  icon: _iconForCategory(e.categoryCode),
                  label: 'CATEGORY',
                  value: categoryName,
                  color: AppColors.forCategory(e.categoryCode),
                ),
                const SizedBox(height: AppSpacing.md),
                _DetailRow(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'SOURCE',
                  value: sourceName,
                  color: AppColors.brandBrown,
                ),
                const SizedBox(height: AppSpacing.md),
                _DetailRow(
                  icon: Icons.notes_outlined,
                  label: 'DETAILS',
                  value: e.details.isEmpty ? '—' : e.details,
                  color: AppColors.brandBrown,
                ),
                const SizedBox(height: AppSpacing.xl),
                if (e.receiptObjectKey != null)
                  _ReceiptViewer(objectKey: e.receiptObjectKey!),
                if (e.pendingSync) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: const BorderRadius.all(AppRadii.card),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.cloud_off, color: AppColors.warning),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'This expense is queued and will sync when you return online.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.warning),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
  String _longDate(DateTime d) {
    const List<String> days = <String>[
      'MON',
      'TUE',
      'WED',
      'THU',
      'FRI',
      'SAT',
      'SUN',
    ];
    const List<String> months = <String>[
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  IconData _iconForCategory(String code) {
    switch (code) {
      case 'FOOD':
        return Icons.restaurant;
      case 'TRANSPORT':
        return Icons.directions_car_outlined;
      case 'HOTEL':
        return Icons.hotel_outlined;
      case 'PHONE':
        return Icons.phone_outlined;
      case 'ENTERTAINMENT':
        return Icons.local_activity_outlined;
      case 'TIPS':
        return Icons.payments_outlined;
      case 'TRAVEL':
        return Icons.flight_outlined;
      default:
        return Icons.label_outline;
    }
  }
}

class _ReceiptViewer extends StatelessWidget {
  const _ReceiptViewer({required this.objectKey});

  /// `objectKey` is either a `blob:` URL (uploaded via image_picker in the
  /// demo) or a server-side S3 key in production. The placeholder card is
  /// what seed expenses get since their pointers don't resolve.
  final String objectKey;

  bool get _isBlobUrl => objectKey.startsWith('blob:') || objectKey.startsWith('http');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'RECEIPT',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_isBlobUrl)
          ClipRRect(
            borderRadius: const BorderRadius.all(AppRadii.card),
            child: GestureDetector(
              onTap: () => _showFullscreen(context),
              child: Image.network(
                objectKey,
                fit: BoxFit.cover,
                width: double.infinity,
                height: 220,
                errorBuilder: (_, __, ___) => _placeholder(context),
              ),
            ),
          )
        else
          _placeholder(context),
      ],
    );
  }

  Widget _placeholder(BuildContext context) => Container(
    height: 120,
    decoration: BoxDecoration(
      color: AppColors.cream,
      borderRadius: const BorderRadius.all(AppRadii.card),
      border: Border.all(color: AppColors.divider),
    ),
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.image_outlined, size: 32, color: AppColors.textSecondary),
          SizedBox(height: 6),
          Text(
            'Receipt on file',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
  );

  void _showFullscreen(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: <Widget>[
            InteractiveViewer(
              child: Image.network(objectKey),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.12),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}
